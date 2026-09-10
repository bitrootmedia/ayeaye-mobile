import 'dart:math';

import 'session_tokens.dart';

/// One ayeaye instance a person is signed in to.
///
/// ayeaye is single-origin: the SPA, the API, the auth routes, the socket and
/// media all live behind one hostname. So a profile really is just *one URL
/// plus one credential set* — there is no discovery call and nothing else to
/// configure.
///
/// Two profiles signed in at once is the normal case for anyone with a work
/// instance and a personal one, so each keeps its own fully independent token
/// set. There is no shared "current session" anywhere in the app.
class Profile {
  const Profile({
    required this.id,
    required this.label,
    required this.baseUrl,
    this.tokens = SessionTokens.empty,
    this.patForSocket,
    this.patId,
    this.patPrefix,
    this.userId,
    this.email,
    this.displayName,
    this.lastOrgId,
  });

  /// Local-only identity, so two profiles can share a hostname.
  final String id;

  /// User-chosen; several instances may share a hostname pattern.
  final String label;

  /// Scheme included. `http://` is allowed — self-hosters run plain localhost.
  final String baseUrl;

  final SessionTokens tokens;

  /// A personal access token, minted after sign-in purely to authenticate the
  /// WebSocket: the socket takes a cookie or a PAT, and a header-mode client
  /// has neither. Read scope is enough — watching is reading.
  final String? patForSocket;
  final String? patId;

  /// Shown in the UI so a person can tell which token to revoke.
  final String? patPrefix;

  final String? userId;

  /// Kept so the profile switcher renders offline, before `/api/me` answers.
  final String? email;
  final String? displayName;

  /// The web app drops you back into the last organisation; we match it.
  final String? lastOrgId;

  bool get signedIn => tokens.hasSession;

  String get host {
    final uri = Uri.tryParse(baseUrl);
    return uri?.host.isNotEmpty == true ? uri!.host : baseUrl;
  }

  bool get isInsecure => baseUrl.startsWith('http://');

  String get initials {
    final source = (displayName?.trim().isNotEmpty == true)
        ? displayName!.trim()
        : (email ?? label).trim();
    if (source.isEmpty) return '?';
    final parts = source.split(RegExp(r'[\s@._-]+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return source.substring(0, 1).toUpperCase();
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  Profile copyWith({
    String? label,
    String? baseUrl,
    SessionTokens? tokens,
    String? patForSocket,
    String? patId,
    String? patPrefix,
    String? userId,
    String? email,
    String? displayName,
    String? lastOrgId,
    bool clearPat = false,
  }) =>
      Profile(
        id: id,
        label: label ?? this.label,
        baseUrl: baseUrl ?? this.baseUrl,
        tokens: tokens ?? this.tokens,
        patForSocket: clearPat ? null : (patForSocket ?? this.patForSocket),
        patId: clearPat ? null : (patId ?? this.patId),
        patPrefix: clearPat ? null : (patPrefix ?? this.patPrefix),
        userId: userId ?? this.userId,
        email: email ?? this.email,
        displayName: displayName ?? this.displayName,
        lastOrgId: lastOrgId ?? this.lastOrgId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'baseUrl': baseUrl,
        'tokens': tokens.toJson(),
        'patForSocket': patForSocket,
        'patId': patId,
        'patPrefix': patPrefix,
        'userId': userId,
        'email': email,
        'displayName': displayName,
        'lastOrgId': lastOrgId,
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String? ?? newProfileId(),
        label: j['label'] as String? ?? 'ayeaye',
        baseUrl: j['baseUrl'] as String? ?? '',
        tokens: j['tokens'] is Map
            ? SessionTokens.fromJson((j['tokens'] as Map).cast<String, dynamic>())
            : SessionTokens.empty,
        patForSocket: j['patForSocket'] as String?,
        patId: j['patId'] as String?,
        patPrefix: j['patPrefix'] as String?,
        userId: j['userId'] as String?,
        email: j['email'] as String?,
        displayName: j['displayName'] as String?,
        lastOrgId: j['lastOrgId'] as String?,
      );
}

final _random = Random.secure();

String newProfileId() {
  final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final salt = _random.nextInt(1 << 32).toRadixString(36);
  return 'p_${now}_$salt';
}
