/// Errors the app can actually act on.
///
/// The API speaks in two dialects: FastAPI's `{"detail": …}` for the
/// application's own errors and SuperTokens' `{"message": …}` for session
/// ones. A parser that only knows one shows a blank message on exactly the
/// auth failures a person most needs explained, so [messageFromBody] reads
/// both.
sealed class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  /// The HTTP status behind this, where one is fixed by the error's meaning.
  int? get statusCode => null;

  @override
  String toString() => message;
}

/// A 4xx/5xx that carries a human-readable reason.
class ApiError extends ApiException {
  const ApiError(super.message, {this.statusCode});

  @override
  final int? statusCode;
}

/// The resource is gone, or was never visible to us.
///
/// ayeaye reports "no access" as 404, never 403 — so this is the screen for
/// both, and the app must not render a "forbidden" wall for it.
class NotFoundError extends ApiException {
  const NotFoundError([super.message = 'Not found']);

  @override
  int? get statusCode => 404;
}

/// Visible, but not at that level. A real 403 — not one of the session gates.
class ForbiddenError extends ApiException {
  const ForbiddenError([super.message = 'Not allowed']);

  @override
  int? get statusCode => 403;
}

/// The session claim `st-mfa-ok` is false: every `/api/*` route will 403 until
/// a TOTP code or a backup code is redeemed.
class MfaRequiredError extends ApiException {
  const MfaRequiredError() : super('Two-factor authentication required');

  @override
  int? get statusCode => 403;
}

/// The session claim `st-ev` is false: the address needs confirming, and then
/// the session needs *refreshing* — the token carries the stale claim until it
/// is rotated.
class EmailVerificationRequiredError extends ApiException {
  const EmailVerificationRequiredError()
      : super('Please confirm your email address');

  @override
  int? get statusCode => 403;
}

/// Credentials are gone or rejected; the profile has to sign in again.
class SessionExpiredError extends ApiException {
  const SessionExpiredError([super.message = 'Your session has expired']);

  @override
  int? get statusCode => 401;
}

class NetworkError extends ApiException {
  const NetworkError([super.message = 'Could not reach the server']);
}

/// Pulls the best available message out of a response body.
String? messageFromBody(dynamic body) {
  if (body is Map) {
    // FastAPI validation errors put a list under `detail`; take the first
    // field message rather than printing the raw structure.
    final detail = body['detail'];
    if (detail is String && detail.isNotEmpty) return detail;
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map && first['msg'] != null) {
        final loc = first['loc'];
        final field = (loc is List && loc.length > 1) ? '${loc.last}: ' : '';
        return '$field${first['msg']}';
      }
    }
    final msg = body['message'];
    if (msg is String && msg.isNotEmpty) return msg;
  }
  if (body is String && body.isNotEmpty && body.length < 300) return body;
  return null;
}

/// True when a 403 body is the `id` claim gate rather than an ordinary refusal.
///
/// Matched by shape, never by status code alone — an unrelated 403 must not be
/// mistaken for a gate.
bool hasClaimError(dynamic body, String id) {
  if (body is! Map) return false;
  if (body['message'] != 'invalid claim') return false;
  final errors = body['claimValidationErrors'];
  if (errors is! List) return false;
  return errors.any((e) => e is Map && e['id'] == id);
}
