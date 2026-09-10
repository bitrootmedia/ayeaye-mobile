import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../auth/session_tokens.dart';
import 'api_exception.dart';

/// A page of results plus the server's real total, from `X-Total-Count`.
class Paged<T> {
  const Paged(this.items, this.total);
  final List<T> items;
  final int total;

  bool get hasMore => items.length < total;
}

typedef TokensChanged = void Function(SessionTokens tokens);

/// One instance's HTTP client, with the SuperTokens header-mode lifecycle
/// hand-rolled.
///
/// The SDK is built around one `apiDomain` per `init()`, which is exactly what
/// multi-profile breaks — so each profile owns its own [ApiClient] and its own
/// token set, with no shared "current session" anywhere.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    SessionTokens tokens = SessionTokens.empty,
    this.onTokensChanged,
    this.onSessionLost,
    Dio? dio,
    Dio? storageDio,
  })  // The fields are private but the parameters should not be; a caller
      // constructing a client says `tokens:`, not `_tokens:`.
      // ignore: prefer_initializing_formals
      : _tokens = tokens,
        _dio = dio ?? Dio(),
        _bare = storageDio ?? Dio(BaseOptions(validateStatus: (_) => true)) {
    _dio.options = _dio.options.copyWith(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      // We interpret every status ourselves; Dio throwing on 4xx would hide
      // the response headers we must read even on failures.
      validateStatus: (_) => true,
      headers: {'st-auth-mode': 'header'},
    );
  }

  final String baseUrl;
  final Dio _dio;

  /// For presigned storage PUTs and media reads: they must not carry our
  /// Authorization header, and must not be retried by the session logic.
  final Dio _bare;

  final TokensChanged? onTokensChanged;

  /// Called when the refresh token is rejected: the profile needs to sign in
  /// again and the UI should say so rather than silently showing empty lists.
  final void Function()? onSessionLost;

  SessionTokens _tokens;
  SessionTokens get tokens => _tokens;

  Future<void>? _refreshing;

  void adoptTokens(SessionTokens tokens) => _tokens = tokens;

  // ---------------------------------------------------------------- requests

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async =>
      _send('GET', path, query: query).then((r) => r.data);

  Future<dynamic> post(String path, {Object? body, Map<String, dynamic>? query}) async =>
      _send('POST', path, body: body, query: query).then((r) => r.data);

  Future<dynamic> patch(String path, {Object? body}) async =>
      _send('PATCH', path, body: body).then((r) => r.data);

  Future<dynamic> put(String path, {Object? body}) async =>
      _send('PUT', path, body: body).then((r) => r.data);

  Future<dynamic> delete(String path, {Object? body}) async =>
      _send('DELETE', path, body: body).then((r) => r.data);

  /// A list endpoint, decoded with [parse] and paired with `X-Total-Count`.
  Future<Paged<T>> getPaged<T>(
    String path,
    T Function(Map<String, dynamic>) parse, {
    Map<String, dynamic>? query,
  }) async {
    final res = await _send('GET', path, query: query);
    final raw = res.data;
    final items = (raw is List ? raw : const [])
        .whereType<Map>()
        .map((e) => parse(e.cast<String, dynamic>()))
        .toList();
    final header = res.headers.value('x-total-count');
    return Paged(items, int.tryParse(header ?? '') ?? items.length);
  }

  /// A list endpoint with no paging story.
  Future<List<T>> getList<T>(
    String path,
    T Function(Map<String, dynamic>) parse, {
    Map<String, dynamic>? query,
  }) async {
    final raw = await get(path, query: query);
    return (raw is List ? raw : const [])
        .whereType<Map>()
        .map((e) => parse(e.cast<String, dynamic>()))
        .toList();
  }

  Future<Map<String, dynamic>> getObject(String path, {Map<String, dynamic>? query}) async {
    final raw = await get(path, query: query);
    return raw is Map ? raw.cast<String, dynamic>() : <String, dynamic>{};
  }

  // ------------------------------------------------------------------- auth

  /// Registers, or signs in, on the `emailpassword` recipe.
  ///
  /// SuperTokens signals failure in the *body* with a 200, so the caller gets
  /// the decoded body and must check `status` before assuming success.
  Future<Map<String, dynamic>> authenticate({
    required bool register,
    required String email,
    required String password,
  }) async {
    final res = await _dio.request<dynamic>(
      register ? '/api/auth/signup' : '/api/auth/signin',
      data: {
        'formFields': [
          {'id': 'email', 'value': email},
          {'id': 'password', 'value': password},
        ],
      },
      options: Options(
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          // Only the recipe routes need `rid`; /api/* does not.
          'rid': 'emailpassword',
          'st-auth-mode': 'header',
        },
      ),
    );
    _absorbTokens(res);
    final body = res.data;
    if (body is Map) return body.cast<String, dynamic>();
    throw ApiError(
      messageFromBody(body) ?? 'Sign-in failed (${res.statusCode})',
      statusCode: res.statusCode,
    );
  }

  Future<void> signOut() async {
    try {
      await _send('POST', '/api/auth/signout');
    } catch (_) {
      // Best effort: a profile is being removed either way, and a dead network
      // must not block that.
    }
    _tokens = SessionTokens.empty;
  }

  /// Rotates both tokens. Verified: the refresh token goes in the
  /// Authorization header, and the response carries a new pair.
  Future<void> refreshSession() {
    // Collapse concurrent refreshes; a list screen firing five requests at
    // once must not mint five sessions.
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _doRefresh() async {
    final refresh = _tokens.refreshToken;
    if (refresh == null || refresh.isEmpty) {
      _fail();
      throw const SessionExpiredError();
    }
    final res = await _dio.request<dynamic>(
      '/api/auth/session/refresh',
      options: Options(
        method: 'POST',
        headers: {
          'Authorization': 'Bearer $refresh',
          'st-auth-mode': 'header',
        },
      ),
    );
    _absorbTokens(res);
    final code = res.statusCode ?? 0;
    if (code == 401 || code == 403 || !_tokens.hasSession) {
      _fail();
      throw const SessionExpiredError();
    }
    if (code >= 400) {
      throw ApiError(
        messageFromBody(res.data) ?? 'Could not refresh the session',
        statusCode: code,
      );
    }
  }

  void _fail() {
    _tokens = SessionTokens.empty;
    onTokensChanged?.call(_tokens);
    onSessionLost?.call();
  }

  // ---------------------------------------------------------------- plumbing

  Future<Response<dynamic>> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool allowRetry = true,
  }) async {
    // Pre-emptive refresh: cheaper than a round trip that we know will 401.
    if (allowRetry && _tokens.hasSession && _tokens.isStale && _tokens.refreshToken != null) {
      try {
        await refreshSession();
      } on ApiException {
        // Fall through and let the request produce the real error; the token
        // may still have a few seconds on it.
      }
    }

    Response<dynamic> res;
    try {
      res = await _dio.request<dynamic>(
        path,
        data: body,
        queryParameters: _clean(query),
        options: Options(method: method, headers: _authHeader()),
      );
    } on DioException catch (e) {
      throw NetworkError(_networkMessage(e));
    }

    _absorbTokens(res);

    final code = res.statusCode ?? 0;
    if (code == 401 && allowRetry && (_tokens.refreshToken ?? '').isNotEmpty) {
      await refreshSession();
      return _send(method, path, body: body, query: query, allowRetry: false);
    }
    _throwForStatus(res);
    return res;
  }

  Map<String, String> _authHeader() {
    final token = _tokens.accessToken;
    if (token == null || token.isEmpty) return const {};
    return {'Authorization': 'Bearer $token'};
  }

  /// Reads `St-*` / `Front-Token` off **every** response, including 204s.
  ///
  /// This is the expensive gotcha in the whole flow: the 2FA challenge returns
  /// 204 with a new access token, and the old one keeps returning 403 forever.
  /// A client that skips header parsing on a bodyless response completes 2FA
  /// and stays locked out.
  void _absorbTokens(Response<dynamic> res) {
    final incoming = tokensFromHeaders(res.headers.map);
    if (incoming == null) return;
    _tokens = _tokens.merge(incoming);
    onTokensChanged?.call(_tokens);
  }

  void _throwForStatus(Response<dynamic> res) {
    final code = res.statusCode ?? 0;
    if (code >= 200 && code < 300) return;
    final body = res.data;

    if (code == 403) {
      // Gates are matched by shape. An ordinary 403 is just a refusal.
      if (hasClaimError(body, 'st-mfa-ok')) throw const MfaRequiredError();
      if (hasClaimError(body, 'st-ev')) throw const EmailVerificationRequiredError();
      throw ForbiddenError(messageFromBody(body) ?? 'Not allowed');
    }
    if (code == 401) {
      throw SessionExpiredError(messageFromBody(body) ?? 'Your session has expired');
    }
    if (code == 404) {
      throw NotFoundError(messageFromBody(body) ?? 'Not found');
    }
    throw ApiError(
      messageFromBody(body) ?? 'Something went wrong ($code)',
      statusCode: code,
    );
  }

  String _networkMessage(DioException e) => switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          'The server took too long to answer',
        DioExceptionType.badCertificate =>
          'The server\'s certificate could not be verified',
        DioExceptionType.connectionError => 'Could not reach $baseUrl',
        _ => 'Could not reach $baseUrl',
      };

  Map<String, dynamic>? _clean(Map<String, dynamic>? query) {
    if (query == null) return null;
    final out = <String, dynamic>{};
    for (final e in query.entries) {
      if (e.value != null) out[e.key] = e.value;
    }
    return out.isEmpty ? null : out;
  }

  // --------------------------------------------------------------- uploads

  /// Step 2 of an upload: bytes go straight to storage, never through the API.
  ///
  /// [contentType] must be the string the *server* returned with the ticket.
  /// The signature covers it byte for byte, and the platform's own guess
  /// (`audio/webm;codecs=opus`) fails as `SignatureDoesNotMatch`, which says
  /// nothing about content types.
  Future<void> putToStorage({
    required String uploadUrl,
    required List<int> bytes,
    required String contentType,
  }) async {
    final Response<dynamic> res;
    try {
      res = await _bare.put<dynamic>(
        uploadUrl,
        data: Stream.fromIterable([bytes]),
        options: Options(
          headers: {
            'Content-Type': contentType,
            Headers.contentLengthHeader: bytes.length,
          },
        ),
      );
    } on DioException catch (e) {
      throw NetworkError(_networkMessage(e));
    }
    final code = res.statusCode ?? 0;
    if (code < 200 || code >= 300) {
      throw ApiError('Upload failed ($code)', statusCode: code);
    }
  }

  /// Fetches bytes for a presigned read URL (voice-note playback, images).
  ///
  /// Read URLs are minted per read and expire, so nothing here is cached.
  Future<List<int>> fetchBytes(String url) async {
    final res = await _bare.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    return res.data ?? const [];
  }

  String absolute(String pathOrUrl) {
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return pathOrUrl;
    }
    final root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$root${pathOrUrl.startsWith('/') ? '' : '/'}$pathOrUrl';
  }

  /// Presigned media URLs already carry their own credentials, but same-origin
  /// `/media/*` paths need our bearer token.
  Map<String, String> imageHeaders(String url) =>
      url.contains('X-Amz-') || url.contains('Signature=') ? const {} : _authHeader();

  void close() {
    _dio.close(force: true);
    _bare.close(force: true);
  }
}

/// Normalises what a person types into a profile URL.
///
/// Self-hosters run plain `http://localhost`, so http is warned about
/// elsewhere but never blocked here.
String normaliseBaseUrl(String input) {
  var value = input.trim();
  if (value.isEmpty) return value;
  if (!value.startsWith('http://') && !value.startsWith('https://')) {
    value = 'https://$value';
  }
  while (value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}

/// Pretty-prints a body for the debug console without dumping tokens.
String debugBody(dynamic body) {
  try {
    return const JsonEncoder.withIndent('  ').convert(body);
  } catch (_) {
    return '$body';
  }
}
