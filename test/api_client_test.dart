import 'dart:convert';
import 'dart:typed_data';

import 'package:ayeaye_mobile/core/api/api_client.dart';
import 'package:ayeaye_mobile/core/api/api_exception.dart';
import 'package:ayeaye_mobile/core/auth/session_tokens.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// One canned reply.
class _Reply {
  _Reply(this.status, {this.body = '{}', this.headers = const {}});

  final int status;
  final String body;
  final Map<String, List<String>> headers;
}

/// A transport that answers from a script and records what it was asked.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.replies);

  /// Path -> queued replies, consumed in order.
  final Map<String, List<_Reply>> replies;
  final List<RequestOptions> requests = [];

  /// A relative request arrives as `/api/me`; an absolute one (a presigned
  /// storage URL) arrives whole, so both are keyed by their path.
  static String pathOf(RequestOptions options) =>
      options.path.startsWith('http')
          ? (Uri.tryParse(options.path)?.path ?? options.path)
          : options.path;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final queue = replies[pathOf(options)];
    if (queue == null || queue.isEmpty) {
      return ResponseBody.fromString('{"detail":"no canned reply"}', 500);
    }
    final reply = queue.length == 1 ? queue.first : queue.removeAt(0);
    return ResponseBody.fromString(
      reply.body,
      reply.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...reply.headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}

  RequestOptions requestTo(String path) =>
      requests.lastWhere((r) => pathOf(r) == path);

  int countTo(String path) => requests.where((r) => pathOf(r) == path).length;
}

ApiClient _client(
  _FakeAdapter adapter, {
  SessionTokens tokens = const SessionTokens(
    accessToken: 'access-1',
    refreshToken: 'refresh-1',
  ),
  void Function(SessionTokens)? onTokensChanged,
  void Function()? onSessionLost,
}) {
  final dio = Dio()..httpClientAdapter = adapter;
  return ApiClient(
    baseUrl: 'https://tasks.example.com',
    tokens: tokens,
    dio: dio,
    onTokensChanged: onTokensChanged,
    onSessionLost: onSessionLost,
  );
}

void main() {
  test('sends the access token as a bearer, with no cookie or CSRF', () async {
    final adapter = _FakeAdapter({
      '/api/me': [_Reply(200, body: '{"id":"1"}')],
    });

    await _client(adapter).get('/api/me');

    final headers = adapter.requestTo('/api/me').headers;
    expect(headers['Authorization'], 'Bearer access-1');
    expect(headers.containsKey('Cookie'), isFalse);
    expect(headers.containsKey('rid'), isFalse, reason: 'only auth routes');
  });

  test('reads X-Total-Count off a paged list', () async {
    final adapter = _FakeAdapter({
      '/api/organisations/o1/tasks': [
        _Reply(
          200,
          body: '[{"id":"t1","title":"One"}]',
          headers: {'x-total-count': ['240']},
        ),
      ],
    });

    final page = await _client(adapter).getPaged(
      '/api/organisations/o1/tasks',
      (json) => json['id'] as String,
    );

    expect(page.items, ['t1']);
    expect(page.total, 240);
    expect(page.hasMore, isTrue);
  });

  test('absorbs rotated tokens from a 204, then uses the new one', () async {
    // The 2FA challenge is the case that matters: it answers 204 with a new
    // access token, and the old one keeps returning 403 forever.
    final adapter = _FakeAdapter({
      '/api/me/mfa/totp/challenge': [
        _Reply(204, body: '', headers: {
          'st-access-token': ['access-2'],
          'st-refresh-token': ['refresh-2'],
        }),
      ],
      '/api/me': [_Reply(200, body: '{"id":"1"}')],
    });
    SessionTokens? persisted;
    final client = _client(adapter, onTokensChanged: (t) => persisted = t);

    await client.post('/api/me/mfa/totp/challenge', body: {'code': '123456'});

    expect(client.tokens.accessToken, 'access-2');
    expect(client.tokens.refreshToken, 'refresh-2');
    expect(persisted?.accessToken, 'access-2',
        reason: 'rotation must reach storage');

    await client.get('/api/me');
    expect(adapter.requestTo('/api/me').headers['Authorization'],
        'Bearer access-2');
  });

  test('refreshes and retries once on a 401', () async {
    final adapter = _FakeAdapter({
      '/api/me': [
        _Reply(401, body: '{"message":"unauthorised"}'),
        _Reply(200, body: '{"id":"1"}'),
      ],
      '/api/auth/session/refresh': [
        _Reply(200, headers: {
          'st-access-token': ['access-2'],
          'st-refresh-token': ['refresh-2'],
        }),
      ],
    });
    final client = _client(adapter);

    final result = await client.get('/api/me');

    expect(result, {'id': '1'});
    expect(adapter.countTo('/api/me'), 2, reason: 'one retry, not a loop');
    expect(
      adapter.requestTo('/api/auth/session/refresh').headers['Authorization'],
      'Bearer refresh-1',
      reason: 'refresh authenticates with the refresh token',
    );
    expect(client.tokens.accessToken, 'access-2');
  });

  test('does not retry forever when the retry also 401s', () async {
    final adapter = _FakeAdapter({
      '/api/me': [_Reply(401, body: '{"message":"unauthorised"}')],
      '/api/auth/session/refresh': [
        _Reply(200, headers: {'st-access-token': ['access-2']}),
      ],
    });
    final client = _client(adapter);

    await expectLater(
      client.get('/api/me'),
      throwsA(isA<SessionExpiredError>()),
    );
    expect(adapter.countTo('/api/me'), 2);
  });

  test('a rejected refresh token reports the session lost, once', () async {
    final adapter = _FakeAdapter({
      '/api/me': [_Reply(401, body: '{"message":"unauthorised"}')],
      '/api/auth/session/refresh': [
        _Reply(401, body: '{"message":"unauthorised"}'),
      ],
    });
    var lost = 0;
    final client = _client(adapter, onSessionLost: () => lost++);

    await expectLater(
      client.get('/api/me'),
      throwsA(isA<SessionExpiredError>()),
    );
    expect(lost, 1);
    expect(client.tokens.hasSession, isFalse);
  });

  test('refreshes pre-emptively when the token is nearly expired', () async {
    final adapter = _FakeAdapter({
      '/api/me': [_Reply(200, body: '{"id":"1"}')],
      '/api/auth/session/refresh': [
        _Reply(200, headers: {
          'st-access-token': ['access-2'],
          'st-refresh-token': ['refresh-2'],
        }),
      ],
    });
    final client = _client(
      adapter,
      tokens: SessionTokens(
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
        accessExpiry: DateTime.now().add(const Duration(seconds: 5)),
      ),
    );

    await client.get('/api/me');

    expect(adapter.countTo('/api/auth/session/refresh'), 1);
    expect(adapter.requestTo('/api/me').headers['Authorization'],
        'Bearer access-2', reason: 'the request used the fresh token');
  });

  test('collapses concurrent refreshes into one', () async {
    final adapter = _FakeAdapter({
      '/api/me': [_Reply(200, body: '{}'), _Reply(200, body: '{}')],
      '/api/organisations': [_Reply(200, body: '[]')],
      '/api/auth/session/refresh': [
        _Reply(200, headers: {'st-access-token': ['access-2']}),
      ],
    });
    final client = _client(
      adapter,
      tokens: SessionTokens(
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
        accessExpiry: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    );

    // A list screen firing several requests at once must not mint several
    // sessions.
    await Future.wait([
      client.get('/api/me'),
      client.get('/api/organisations'),
    ]);

    expect(adapter.countTo('/api/auth/session/refresh'), 1);
  });

  group('the two gates', () {
    test('a 2FA claim error becomes MfaRequiredError', () async {
      final adapter = _FakeAdapter({
        '/api/me': [
          _Reply(403, body: jsonEncode({
            'message': 'invalid claim',
            'claimValidationErrors': [
              {'id': 'st-mfa-ok', 'reason': {'message': 'wrong value'}},
            ],
          })),
        ],
      });

      await expectLater(
        _client(adapter).get('/api/me'),
        throwsA(isA<MfaRequiredError>()),
      );
    });

    test('an email-verification claim error becomes its own type', () async {
      final adapter = _FakeAdapter({
        '/api/me': [
          _Reply(403, body: jsonEncode({
            'message': 'invalid claim',
            'claimValidationErrors': [{'id': 'st-ev'}],
          })),
        ],
      });

      await expectLater(
        _client(adapter).get('/api/me'),
        throwsA(isA<EmailVerificationRequiredError>()),
      );
    });

    test('an unrelated 403 stays an ordinary refusal', () async {
      final adapter = _FakeAdapter({
        '/api/organisations/o1/tasks/t1': [
          _Reply(403, body: '{"detail":"You cannot edit this task"}'),
        ],
      });

      await expectLater(
        _client(adapter).patch('/api/organisations/o1/tasks/t1', body: {}),
        throwsA(
          isA<ForbiddenError>().having(
            (e) => e.message,
            'message',
            'You cannot edit this task',
          ),
        ),
      );
    });
  });

  test('404 is not found, never forbidden', () async {
    // No access reads as 404 on this API, so the two are indistinguishable
    // and both must render as "not found".
    final adapter = _FakeAdapter({
      '/api/organisations/o9': [_Reply(404, body: '{"detail":"Not found"}')],
    });

    await expectLater(
      _client(adapter).get('/api/organisations/o9'),
      throwsA(isA<NotFoundError>()),
    );
  });

  test("shows SuperTokens' message key, not a blank error", () async {
    final adapter = _FakeAdapter({
      '/api/me': [_Reply(500, body: '{"message":"something broke"}')],
    });

    await expectLater(
      _client(adapter).get('/api/me'),
      throwsA(isA<ApiError>().having(
        (e) => e.message,
        'message',
        'something broke',
      )),
    );
  });

  test('authenticate sends the recipe headers and keeps a body failure', () async {
    final adapter = _FakeAdapter({
      '/api/auth/signin': [
        _Reply(200, body: '{"status":"WRONG_CREDENTIALS_ERROR"}'),
      ],
    });
    final client = _client(adapter, tokens: SessionTokens.empty);

    final body = await client.authenticate(
      register: false,
      email: 'a@b.c',
      password: 'secret',
    );

    // SuperTokens signals failure in the body with a 200, so this must come
    // back as data rather than an exception.
    expect(body['status'], 'WRONG_CREDENTIALS_ERROR');
    final headers = adapter.requestTo('/api/auth/signin').headers;
    expect(headers['rid'], 'emailpassword');
    expect(headers['st-auth-mode'], 'header');
  });

  test('a storage PUT echoes the server content type and skips our auth',
      () async {
    final adapter = _FakeAdapter({
      '/upload': [_Reply(200, body: '')],
    });
    // The presigned PUT goes through a separate client that carries none of
    // our session headers, so the fake has to be injected there.
    final client = ApiClient(
      baseUrl: 'https://tasks.example.com',
      tokens: const SessionTokens(accessToken: 'access-1'),
      dio: Dio()..httpClientAdapter = adapter,
      storageDio: Dio(BaseOptions(validateStatus: (_) => true))
        ..httpClientAdapter = adapter,
    );

    await client.putToStorage(
      uploadUrl: 'https://storage.example.com/upload',
      bytes: [1, 2, 3],
      // The signature covers Content-Type byte for byte, so the value the
      // server returned is the only one that works.
      contentType: 'audio/mp4',
    );

    final request = adapter.requestTo('/upload');
    expect(request.headers['Content-Type'], 'audio/mp4');
    expect(request.headers.containsKey('Authorization'), isFalse);
  });

  group('normaliseBaseUrl', () {
    test('adds https when no scheme is given', () {
      expect(normaliseBaseUrl('tasks.example.com'), 'https://tasks.example.com');
    });

    test('keeps http, because self-hosters run it', () {
      expect(normaliseBaseUrl('http://localhost'), 'http://localhost');
    });

    test('trims trailing slashes and whitespace', () {
      expect(normaliseBaseUrl('  https://x.dev///  '), 'https://x.dev');
    });
  });
}
