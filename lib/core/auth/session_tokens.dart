import 'dart:convert';

/// One profile's SuperTokens session, in header mode.
///
/// Both tokens rotate on every refresh, so this is always replaced wholesale,
/// never mutated in place.
class SessionTokens {
  const SessionTokens({
    this.accessToken,
    this.refreshToken,
    this.accessExpiry,
    this.userId,
  });

  final String? accessToken;
  final String? refreshToken;

  /// `ate` from the Front-Token: when the access token dies. Used to refresh
  /// pre-emptively instead of waiting for a 401.
  final DateTime? accessExpiry;
  final String? userId;

  bool get hasSession => (accessToken ?? '').isNotEmpty;

  /// Refresh a little early — a token that expires mid-flight costs a retry.
  bool get isStale {
    final exp = accessExpiry;
    if (exp == null) return false;
    return DateTime.now().isAfter(exp.subtract(const Duration(seconds: 60)));
  }

  SessionTokens merge(SessionTokens other) => SessionTokens(
        accessToken: other.accessToken ?? accessToken,
        refreshToken: other.refreshToken ?? refreshToken,
        accessExpiry: other.accessExpiry ?? accessExpiry,
        userId: other.userId ?? userId,
      );

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'accessExpiry': accessExpiry?.toIso8601String(),
        'userId': userId,
      };

  factory SessionTokens.fromJson(Map<String, dynamic> j) => SessionTokens(
        accessToken: j['accessToken'] as String?,
        refreshToken: j['refreshToken'] as String?,
        accessExpiry: j['accessExpiry'] == null
            ? null
            : DateTime.tryParse(j['accessExpiry'] as String),
        userId: j['userId'] as String?,
      );

  static const empty = SessionTokens();
}

/// What a response's `St-*` / `Front-Token` headers said.
///
/// Returns null when the response carried none, so callers can tell "no
/// rotation" from "rotated to nothing".
SessionTokens? tokensFromHeaders(Map<String, List<String>> headers) {
  String? one(String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name) {
        final v = entry.value.isEmpty ? null : entry.value.first;
        return (v == null || v.isEmpty) ? null : v;
      }
    }
    return null;
  }

  final access = one('st-access-token');
  final refresh = one('st-refresh-token');
  final front = one('front-token');
  if (access == null && refresh == null && front == null) return null;

  DateTime? expiry;
  String? userId;
  if (front != null) {
    final parsed = parseFrontToken(front);
    expiry = parsed.$1;
    userId = parsed.$2;
  }
  return SessionTokens(
    accessToken: access,
    refreshToken: refresh,
    accessExpiry: expiry,
    userId: userId,
  );
}

/// Front-Token is base64 JSON: `{"ate": <ms>, "uid": "…", "up": {claims}}`.
/// Reading it saves decoding the JWT ourselves.
(DateTime?, String?) parseFrontToken(String value) {
  try {
    final json = jsonDecode(utf8.decode(base64.decode(base64.normalize(value))));
    if (json is! Map) return (null, null);
    final ate = json['ate'];
    final expiry = ate is num
        ? DateTime.fromMillisecondsSinceEpoch(ate.toInt())
        : null;
    return (expiry, json['uid'] as String?);
  } catch (_) {
    // A malformed Front-Token is not worth failing a request over; we just
    // lose pre-emptive refresh and fall back to reacting to the 401.
    return (null, null);
  }
}
