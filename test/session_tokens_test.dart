import 'dart:convert';

import 'package:ayeaye_mobile/core/api/api_exception.dart';
import 'package:ayeaye_mobile/core/auth/session_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Front-Token', () {
    test('reads the access-token expiry and user id', () {
      // Shape captured from a real signup response.
      final token = base64.encode(utf8.encode(jsonEncode({
        'ate': 1788914826000,
        'uid': 'eca7f65a-9c40-4cd5-8e20-ae72076c6162',
        'up': {'st-ev': {'v': false}},
      })));

      final (expiry, userId) = parseFrontToken(token);

      expect(expiry, DateTime.fromMillisecondsSinceEpoch(1788914826000));
      expect(userId, 'eca7f65a-9c40-4cd5-8e20-ae72076c6162');
    });

    test('survives a malformed token rather than failing the request', () {
      expect(parseFrontToken('not base64 at all'), (null, null));
    });

    test('tolerates missing base64 padding', () {
      final raw = base64.encode(utf8.encode(jsonEncode({'ate': 1, 'uid': 'x'})));
      final unpadded = raw.replaceAll('=', '');

      final (_, userId) = parseFrontToken(unpadded);

      expect(userId, 'x');
    });
  });

  group('tokensFromHeaders', () {
    test('is null when a response rotated nothing', () {
      expect(tokensFromHeaders({'content-type': ['application/json']}), isNull);
    });

    test('reads St-* headers regardless of case', () {
      // Rotation arrives on 204s too — the 2FA challenge is exactly that, and
      // missing it leaves a client locked out with a stale token.
      final tokens = tokensFromHeaders({
        'St-Access-Token': ['new-access'],
        'st-refresh-token': ['new-refresh'],
      });

      expect(tokens, isNotNull);
      expect(tokens!.accessToken, 'new-access');
      expect(tokens.refreshToken, 'new-refresh');
    });

    test('treats an empty header value as absent', () {
      expect(tokensFromHeaders({'st-access-token': ['']}), isNull);
    });
  });

  group('SessionTokens', () {
    test('merge keeps what a partial rotation did not replace', () {
      const existing = SessionTokens(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        userId: 'user-1',
      );

      final merged = existing.merge(const SessionTokens(accessToken: 'new'));

      expect(merged.accessToken, 'new');
      expect(merged.refreshToken, 'old-refresh');
      expect(merged.userId, 'user-1');
    });

    test('is stale shortly before the token actually expires', () {
      final almost = SessionTokens(
        accessToken: 'a',
        accessExpiry: DateTime.now().add(const Duration(seconds: 20)),
      );
      final fresh = SessionTokens(
        accessToken: 'a',
        accessExpiry: DateTime.now().add(const Duration(minutes: 30)),
      );

      expect(almost.isStale, isTrue, reason: 'refresh pre-emptively');
      expect(fresh.isStale, isFalse);
    });

    test('an expiry we never learned is not stale', () {
      const tokens = SessionTokens(accessToken: 'a');
      expect(tokens.isStale, isFalse);
    });

    test('round-trips through storage', () {
      final tokens = SessionTokens(
        accessToken: 'a',
        refreshToken: 'r',
        accessExpiry: DateTime.fromMillisecondsSinceEpoch(1788914826000),
        userId: 'u',
      );

      final restored = SessionTokens.fromJson(tokens.toJson());

      expect(restored.accessToken, 'a');
      expect(restored.refreshToken, 'r');
      expect(restored.accessExpiry, tokens.accessExpiry);
      expect(restored.userId, 'u');
    });
  });

  group('the two session gates', () {
    test('recognises the 2FA claim by shape', () {
      // Captured verbatim from the instance.
      const body = {
        'message': 'invalid claim',
        'claimValidationErrors': [
          {
            'id': 'st-mfa-ok',
            'reason': {
              'message': 'wrong value',
              'expectedValue': true,
              'actualValue': false,
            },
          },
        ],
      };

      expect(hasClaimError(body, 'st-mfa-ok'), isTrue);
      expect(hasClaimError(body, 'st-ev'), isFalse);
    });

    test('an ordinary 403 is not mistaken for a gate', () {
      const body = {'detail': 'You cannot edit this task'};

      expect(hasClaimError(body, 'st-mfa-ok'), isFalse);
      expect(hasClaimError(body, 'st-ev'), isFalse);
    });

    test('a 403 mentioning a claim without the wrapper is not a gate', () {
      const body = {'detail': 'st-mfa-ok is required'};

      expect(hasClaimError(body, 'st-mfa-ok'), isFalse);
    });
  });

  group('messageFromBody', () {
    test('prefers FastAPI detail', () {
      expect(messageFromBody({'detail': 'Nope'}), 'Nope');
    });

    test("falls back to SuperTokens' message key", () {
      // The key is `message`, not `detail`, on exactly the auth failures a
      // person most needs explained.
      expect(messageFromBody({'message': 'unauthorised'}), 'unauthorised');
    });

    test('unwraps a validation error list', () {
      expect(
        messageFromBody({
          'detail': [
            {'loc': ['body', 'title'], 'msg': 'field required'},
          ],
        }),
        'title: field required',
      );
    });

    test('returns null when there is nothing worth showing', () {
      expect(messageFromBody({'unexpected': true}), isNull);
    });
  });
}
