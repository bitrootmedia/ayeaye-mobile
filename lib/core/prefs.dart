import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small, non-secret UI state that should survive a restart.
///
/// Sorting and filtering are the server's job, but *which* sort and filter a
/// person chose belongs in app state that outlives the process — the web app
/// keeps it in the URL, and losing it on every launch is the kind of thing
/// that makes an app feel disposable.
class Prefs {
  Prefs(this._prefs);

  final SharedPreferences _prefs;

  String? getString(String key) => _prefs.getString(key);
  Future<void> setString(String key, String value) => _prefs.setString(key, value);
  bool getBool(String key, {bool fallback = false}) => _prefs.getBool(key) ?? fallback;
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);
  Future<void> remove(String key) => _prefs.remove(key);
}

/// Resolved once at startup in `main`, so screens can read it synchronously.
final prefsProvider = Provider<Prefs>(
  (ref) => throw StateError('prefsProvider must be overridden in main()'),
);
