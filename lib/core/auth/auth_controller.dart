import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../models/models.dart';
import 'profile.dart';
import 'profile_store.dart';
import 'session_tokens.dart';

/// Which session claim, if any, is currently making every `/api/*` route 403.
enum SessionGate { none, mfa, emailVerification }

/// The outcome of trying to sign in, so the form can say something useful.
sealed class SignInResult {
  const SignInResult();
}

class SignInOk extends SignInResult {
  const SignInOk(this.profileId);
  final String profileId;
}

/// SuperTokens signals failure in the body with a 200, so this is the ordinary
/// "wrong password" path, not an exception.
class SignInFailed extends SignInResult {
  const SignInFailed(this.message, {this.fieldErrors = const {}});
  final String message;
  final Map<String, String> fieldErrors;
}

class AuthState {
  const AuthState({
    this.bootstrapping = true,
    this.profiles = const [],
    this.activeProfileId,
    this.me,
    this.gate = SessionGate.none,
    this.meLoading = false,
    this.meError,
  });

  final bool bootstrapping;
  final List<Profile> profiles;
  final String? activeProfileId;

  /// `/api/me` for the active profile. The whole UI gates on this: the call
  /// creates the local user row on first sight and binds pending invitations,
  /// so firing anything else before it means firing against a user that does
  /// not exist yet.
  final MeOut? me;

  final SessionGate gate;
  final bool meLoading;
  final String? meError;

  Profile? get activeProfile {
    final id = activeProfileId;
    if (id == null) return null;
    for (final p in profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  bool get isReady =>
      !bootstrapping &&
      activeProfile?.signedIn == true &&
      gate == SessionGate.none &&
      me != null;

  AuthState copyWith({
    bool? bootstrapping,
    List<Profile>? profiles,
    String? activeProfileId,
    MeOut? me,
    SessionGate? gate,
    bool? meLoading,
    String? meError,
    bool clearActive = false,
    bool clearMe = false,
    bool clearMeError = false,
  }) =>
      AuthState(
        bootstrapping: bootstrapping ?? this.bootstrapping,
        profiles: profiles ?? this.profiles,
        activeProfileId: clearActive ? null : (activeProfileId ?? this.activeProfileId),
        me: clearMe ? null : (me ?? this.me),
        gate: gate ?? this.gate,
        meLoading: meLoading ?? this.meLoading,
        meError: clearMeError ? null : (meError ?? this.meError),
      );
}

final profileStoreProvider = Provider<ProfileStore>((ref) => ProfileStore());

/// How a profile's [ApiClient] gets built.
///
/// A seam rather than a `new` buried in the controller: it lets a test drive
/// the whole session lifecycle — sign-in, the gates, token rotation — over a
/// faked transport, which is the only way to exercise this logic without a
/// live instance.
typedef ApiClientFactory = ApiClient Function({
  required String baseUrl,
  required SessionTokens tokens,
  required TokensChanged onTokensChanged,
  required void Function() onSessionLost,
});

final apiClientFactoryProvider = Provider<ApiClientFactory>(
  (ref) => ({
    required String baseUrl,
    required SessionTokens tokens,
    required TokensChanged onTokensChanged,
    required void Function() onSessionLost,
  }) =>
      ApiClient(
        baseUrl: baseUrl,
        tokens: tokens,
        onTokensChanged: onTokensChanged,
        onSessionLost: onSessionLost,
      ),
);

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

/// The active profile's id, on its own, so [apiProvider] and every data
/// provider rebuild on a profile switch but *not* on a token rotation.
final activeProfileIdProvider = Provider<String?>(
  (ref) => ref.watch(authControllerProvider.select((s) => s.activeProfileId)),
);

/// The active profile's client. Throws if there is none — the router keeps the
/// signed-out screens away from anything that reads this.
final apiProvider = Provider<ApiClient>((ref) {
  final id = ref.watch(activeProfileIdProvider);
  if (id == null) {
    throw StateError('apiProvider read with no active profile');
  }
  return ref.read(authControllerProvider.notifier).clientFor(id);
});

final meProvider = Provider<MeOut?>(
  (ref) => ref.watch(authControllerProvider.select((s) => s.me)),
);

class AuthController extends Notifier<AuthState> {
  final Map<String, ApiClient> _clients = {};
  Timer? _saveTimer;

  @override
  AuthState build() {
    ref.onDispose(() {
      _saveTimer?.cancel();
      for (final c in _clients.values) {
        c.close();
      }
    });
    // Fire and forget: the router shows a splash while `bootstrapping` is true.
    Future.microtask(_bootstrap);
    return const AuthState();
  }

  ProfileStore get _store => ref.read(profileStoreProvider);

  // ------------------------------------------------------------- bootstrap

  Future<void> _bootstrap() async {
    final (profiles, activeId) = await _store.load();
    final active = activeId != null && profiles.any((p) => p.id == activeId)
        ? activeId
        : (profiles.isNotEmpty ? profiles.first.id : null);

    state = state.copyWith(
      bootstrapping: false,
      profiles: profiles,
      activeProfileId: active,
      clearActive: active == null,
    );
    if (active != null) {
      await loadMe();
    }
  }

  /// The client for a profile, created on first use and kept alive.
  ///
  /// Long-lived on purpose: it owns the refresh lock, so recreating it on a
  /// rebuild would let concurrent requests each mint their own session.
  ApiClient clientFor(String profileId) {
    final existing = _clients[profileId];
    if (existing != null) return existing;

    final profile = _profile(profileId);
    final client = ref.read(apiClientFactoryProvider)(
      baseUrl: profile?.baseUrl ?? '',
      tokens: profile?.tokens ?? SessionTokens.empty,
      onTokensChanged: (tokens) => _persistTokens(profileId, tokens),
      onSessionLost: () => _onSessionLost(profileId),
    );
    _clients[profileId] = client;
    return client;
  }

  Profile? _profile(String id) {
    for (final p in state.profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  // ------------------------------------------------------------ sign in/up

  /// Adds a profile and signs it in (or registers first).
  ///
  /// The order matters: authenticate, then `GET /api/me` before anything else,
  /// then the timezone, then the socket token.
  Future<SignInResult> addProfile({
    required String label,
    required String baseUrl,
    required String email,
    required String password,
    required bool register,
  }) async {
    final url = normaliseBaseUrl(baseUrl);
    final id = newProfileId();
    final client = ref.read(apiClientFactoryProvider)(
      baseUrl: url,
      tokens: SessionTokens.empty,
      onTokensChanged: (tokens) => _persistTokens(id, tokens),
      onSessionLost: () => _onSessionLost(id),
    );

    final Map<String, dynamic> body;
    try {
      body = await client.authenticate(
        register: register,
        email: email.trim(),
        password: password,
      );
    } on ApiException catch (e) {
      client.close();
      return SignInFailed(e.message);
    }

    final status = body['status'] as String?;
    if (status != 'OK') {
      client.close();
      return SignInFailed(
        _authStatusMessage(status, register: register),
        fieldErrors: _fieldErrors(body),
      );
    }
    if (!client.tokens.hasSession) {
      client.close();
      return const SignInFailed(
        'The server accepted the sign-in but sent no session token. '
        'Check that this is an ayeaye instance.',
      );
    }

    final effectiveLabel = label.trim().isEmpty
        ? (Uri.tryParse(url)?.host ?? 'ayeaye')
        : label.trim();

    var profile = Profile(
      id: id,
      label: effectiveLabel,
      baseUrl: url,
      tokens: client.tokens,
      email: email.trim(),
      userId: client.tokens.userId,
    );

    _clients[id] = client;
    state = state.copyWith(
      profiles: [...state.profiles, profile],
      activeProfileId: id,
      gate: SessionGate.none,
      clearMe: true,
      clearMeError: true,
    );
    await _save();
    await loadMe();
    return SignInOk(id);
  }

  /// Signs an existing profile back in after its session died.
  Future<SignInResult> reauthenticate({
    required String profileId,
    required String email,
    required String password,
  }) async {
    final profile = _profile(profileId);
    if (profile == null) return const SignInFailed('That profile is gone');

    final client = clientFor(profileId);
    final Map<String, dynamic> body;
    try {
      body = await client.authenticate(
        register: false,
        email: email.trim(),
        password: password,
      );
    } on ApiException catch (e) {
      return SignInFailed(e.message);
    }
    if (body['status'] != 'OK') {
      return SignInFailed(
        _authStatusMessage(body['status'] as String?, register: false),
        fieldErrors: _fieldErrors(body),
      );
    }
    _replace(profile.copyWith(
      tokens: client.tokens,
      email: email.trim(),
      userId: client.tokens.userId,
    ));
    state = state.copyWith(
      activeProfileId: profileId,
      gate: SessionGate.none,
      clearMe: true,
      clearMeError: true,
    );
    await _save();
    await loadMe();
    return SignInOk(profileId);
  }

  String _authStatusMessage(String? status, {required bool register}) =>
      switch (status) {
        'WRONG_CREDENTIALS_ERROR' => 'That email and password do not match',
        'SIGN_IN_NOT_ALLOWED' =>
          'This account has been suspended. Ask an administrator to re-enable it.',
        'SIGN_UP_NOT_ALLOWED' => 'Sign-ups are not open on this instance',
        'EMAIL_ALREADY_EXISTS_ERROR' =>
          'An account with that email already exists — sign in instead',
        'FIELD_ERROR' => register
            ? 'Please check the details below'
            : 'Please check your email and password',
        _ => register ? 'Could not create the account' : 'Could not sign in',
      };

  /// Password policy is the server's call (10+ chars, upper, lower, digit) and
  /// it reports rejections per field.
  Map<String, String> _fieldErrors(Map<String, dynamic> body) {
    final fields = body['formFields'];
    if (fields is! List) return const {};
    final out = <String, String>{};
    for (final f in fields) {
      if (f is Map && f['id'] is String && f['error'] is String) {
        out[f['id'] as String] = f['error'] as String;
      }
    }
    return out;
  }

  // ------------------------------------------------------------------- /me

  /// Calls `/api/me` and interprets the session gates.
  ///
  /// Both gates come back as a 403 whose body names the failing claim; an
  /// unrelated 403 must not be mistaken for one, which is why the client
  /// matches by shape.
  Future<void> loadMe() async {
    final id = state.activeProfileId;
    if (id == null) return;
    final profile = _profile(id);
    if (profile == null || !profile.signedIn) return;

    state = state.copyWith(meLoading: true, clearMeError: true);
    final client = clientFor(id);
    try {
      final me = MeOut.fromJson(await client.getObject('/api/me'));
      state = state.copyWith(
        me: me,
        gate: SessionGate.none,
        meLoading: false,
        clearMeError: true,
      );
      _replace(_profile(id)!.copyWith(
        email: me.email,
        displayName: me.displayName,
        userId: me.userId,
      ));
      await _save();

      // Housekeeping that must not block the UI, and must not fail it either.
      await _syncTimezone(me);
      await _ensureSocketToken(id);
    } on MfaRequiredError {
      state = state.copyWith(
        gate: SessionGate.mfa,
        meLoading: false,
        clearMe: true,
      );
    } on EmailVerificationRequiredError {
      state = state.copyWith(
        gate: SessionGate.emailVerification,
        meLoading: false,
        clearMe: true,
      );
    } on SessionExpiredError catch (e) {
      state = state.copyWith(meLoading: false, meError: e.message, clearMe: true);
    } on ApiException catch (e) {
      state = state.copyWith(meLoading: false, meError: e.message);
    }
  }

  /// Sends the device's IANA zone, because reminders, the deadline sweep and
  /// the daily digest all compute "today" per user zone — and a setting nobody
  /// finds stays wrong.
  Future<void> _syncTimezone(MeOut me) async {
    final id = state.activeProfileId;
    if (id == null) return;
    try {
      final tz = (await FlutterTimezone.getLocalTimezone()).identifier;
      if (tz.isEmpty || tz == me.timezone) return;
      final updated = MeOut.fromJson(
        await _asMap(clientFor(id).patch('/api/me', body: {'timezone': tz})),
      );
      state = state.copyWith(me: updated);
    } catch (_) {
      // Not worth surfacing: the account keeps whatever zone it had.
    }
  }

  /// Mints the personal access token the socket needs.
  ///
  /// The socket takes an `sAccessToken` cookie or a PAT; a header-mode client
  /// has neither, and its SuperTokens access token is *not* a PAT. Read scope
  /// is enough — the socket carries no content, only nudges.
  Future<void> _ensureSocketToken(String profileId) async {
    final profile = _profile(profileId);
    if (profile == null || (profile.patForSocket ?? '').isNotEmpty) return;
    try {
      final created = TokenCreated.fromJson(await _asMap(
        clientFor(profileId).post('/api/me/tokens', body: {
          'name': 'Mobile app',
          'scope': 'read',
        }),
      ));
      if (created.token.isEmpty) return;
      _replace(profile.copyWith(
        patForSocket: created.token, // plaintext, returned exactly once
        patId: created.id,
        patPrefix: created.prefix,
      ));
      await _save();
    } catch (_) {
      // Realtime degrades to pull-to-refresh; not worth blocking sign-in.
    }
  }

  // ----------------------------------------------------------------- gates

  /// Completes the 2FA gate with a TOTP code.
  ///
  /// The challenge answers 204 **with a new access token in the headers**, and
  /// the old token keeps returning 403 forever. [ApiClient] reads `St-*` off
  /// every response including 204s, so the rotation lands before we re-check.
  Future<String?> submitTotp(String code) => _unblock(
        () => clientFor(state.activeProfileId!).post(
          '/api/me/mfa/totp/challenge',
          body: {'code': code.trim()},
        ),
        'That code was not accepted',
      );

  Future<String?> redeemBackupCode(String code) => _unblock(
        () => clientFor(state.activeProfileId!).post(
          '/api/me/mfa/backup-codes/redeem',
          body: {'code': code.trim()},
        ),
        'That backup code was not accepted',
      );

  Future<String?> _unblock(Future<void> Function() call, String fallback) async {
    if (state.activeProfileId == null) return 'No active profile';
    try {
      await call();
    } on ApiException catch (e) {
      return e.message.isEmpty ? fallback : e.message;
    }
    await loadMe();
    return state.gate == SessionGate.mfa ? fallback : null;
  }

  /// Re-checks the email-verification gate.
  ///
  /// Verification is recorded against the account, but the access token still
  /// carries the stale `st-ev` claim — so the refresh is what picks up the new
  /// value. Without it, "I've confirmed it" re-checks, gets the same answer,
  /// and loops forever.
  Future<String?> recheckEmailVerification() async {
    final id = state.activeProfileId;
    if (id == null) return 'No active profile';
    try {
      await clientFor(id).refreshSession();
    } on ApiException catch (e) {
      return e.message;
    }
    await loadMe();
    return state.gate == SessionGate.emailVerification
        ? 'Still not confirmed. Open the link in your email, then try again.'
        : null;
  }

  // -------------------------------------------------------------- switching

  Future<void> switchProfile(String profileId) async {
    if (profileId == state.activeProfileId) return;
    if (_profile(profileId) == null) return;
    state = state.copyWith(
      activeProfileId: profileId,
      gate: SessionGate.none,
      clearMe: true,
      clearMeError: true,
    );
    await _save();
    await loadMe();
  }

  /// Signs a profile out and forgets it, revoking the socket token on the way.
  Future<void> removeProfile(String profileId) async {
    final profile = _profile(profileId);
    if (profile == null) return;
    final client = _clients[profileId];

    if (client != null) {
      // Revoke before signing out: afterwards the session cannot authorise it.
      final patId = profile.patId;
      if (patId != null) {
        try {
          await client.delete('/api/me/tokens/$patId');
        } catch (_) {/* the token outliving the profile is a minor leak */}
      }
      await client.signOut();
      client.close();
      _clients.remove(profileId);
    }

    final remaining = state.profiles.where((p) => p.id != profileId).toList();
    final wasActive = state.activeProfileId == profileId;
    final nextActive = wasActive
        ? (remaining.isEmpty ? null : remaining.first.id)
        : state.activeProfileId;

    state = AuthState(
      bootstrapping: false,
      profiles: remaining,
      activeProfileId: nextActive,
      gate: SessionGate.none,
      me: wasActive ? null : state.me,
    );
    await _save();
    if (wasActive && nextActive != null) await loadMe();
  }

  /// Drops the session but keeps the profile, so signing back in is one field.
  Future<void> signOutActive() async {
    final id = state.activeProfileId;
    if (id == null) return;
    final client = _clients[id];
    if (client != null) {
      await client.signOut();
      client.close();
      _clients.remove(id);
    }
    final profile = _profile(id);
    if (profile != null) {
      _replace(profile.copyWith(tokens: SessionTokens.empty, clearPat: true));
    }
    state = state.copyWith(gate: SessionGate.none, clearMe: true, clearMeError: true);
    await _save();
  }

  Future<void> renameProfile(String profileId, String label) async {
    final profile = _profile(profileId);
    if (profile == null || label.trim().isEmpty) return;
    _replace(profile.copyWith(label: label.trim()));
    await _save();
  }

  /// The web app drops you back into the last organisation; we match it.
  Future<void> setLastOrg(String orgId) async {
    final id = state.activeProfileId;
    if (id == null) return;
    final profile = _profile(id);
    if (profile == null || profile.lastOrgId == orgId) return;
    _replace(profile.copyWith(lastOrgId: orgId));
    await _save();
  }

  Future<void> updateMe(MeOut me) async {
    state = state.copyWith(me: me);
    final id = state.activeProfileId;
    final profile = id == null ? null : _profile(id);
    if (profile != null) {
      _replace(profile.copyWith(displayName: me.displayName, email: me.email));
      await _save();
    }
  }

  // ------------------------------------------------------------ persistence

  void _replace(Profile updated) {
    state = state.copyWith(
      profiles: [
        for (final p in state.profiles) p.id == updated.id ? updated : p,
      ],
    );
  }

  /// Tokens rotate on every response, so this runs often and coalesces writes.
  void _persistTokens(String profileId, SessionTokens tokens) {
    final profile = _profile(profileId);
    if (profile == null) return;
    _replace(profile.copyWith(tokens: tokens));
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () => _save());
  }

  void _onSessionLost(String profileId) {
    final profile = _profile(profileId);
    if (profile != null) {
      _replace(profile.copyWith(tokens: SessionTokens.empty, clearPat: true));
    }
    if (state.activeProfileId == profileId) {
      state = state.copyWith(
        clearMe: true,
        gate: SessionGate.none,
        meLoading: false,
      );
    }
    _clients.remove(profileId)?.close();
    _save();
  }

  Future<void> _save() async {
    _saveTimer?.cancel();
    try {
      await _store.save(state.profiles, state.activeProfileId);
    } catch (_) {
      // Nothing useful to do; the in-memory session still works this run.
    }
  }

  Future<Map<String, dynamic>> _asMap(Future<dynamic> call) async {
    final raw = await call;
    return raw is Map ? raw.cast<String, dynamic>() : <String, dynamic>{};
  }
}
