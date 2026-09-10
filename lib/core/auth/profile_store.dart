import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'profile.dart';

/// Persists profiles — tokens included — in the platform keychain.
///
/// The whole list travels as one JSON blob under one key: profiles are only
/// ever read and written together, and a few kilobytes is well inside what the
/// keychain will hold.
class ProfileStore {
  ProfileStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              // v11 encrypts by default on Android; on Apple platforms
              // `first_unlock` lets a pre-emptive token refresh run while the
              // phone is locked in the user's pocket.
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
              mOptions: MacOsOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _storage;

  static const _profilesKey = 'ayeaye.profiles.v1';
  static const _activeKey = 'ayeaye.activeProfile.v1';

  Future<(List<Profile>, String?)> load() async {
    try {
      final raw = await _storage.read(key: _profilesKey);
      final active = await _storage.read(key: _activeKey);
      if (raw == null || raw.isEmpty) return (<Profile>[], null);
      final decoded = jsonDecode(raw);
      if (decoded is! List) return (<Profile>[], null);
      final profiles = decoded
          .whereType<Map>()
          .map((e) => Profile.fromJson(e.cast<String, dynamic>()))
          .where((p) => p.baseUrl.isNotEmpty)
          .toList();
      return (profiles, active);
    } catch (_) {
      // A corrupt or unreadable keychain entry must not brick the app; the
      // person can sign in again, which is strictly better than a crash loop.
      return (<Profile>[], null);
    }
  }

  Future<void> save(List<Profile> profiles, String? activeId) async {
    await _storage.write(
      key: _profilesKey,
      value: jsonEncode(profiles.map((p) => p.toJson()).toList()),
    );
    if (activeId == null) {
      await _storage.delete(key: _activeKey);
    } else {
      await _storage.write(key: _activeKey, value: activeId);
    }
  }

  Future<void> clear() async {
    await _storage.delete(key: _profilesKey);
    await _storage.delete(key: _activeKey);
  }
}
