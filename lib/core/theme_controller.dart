import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'prefs.dart';

const _themeKey = 'ui.themeMode.v1';

/// Light, dark, or whatever the phone is doing.
///
/// Following the system is the right default — a task app should match the
/// rest of the phone at 11pm — but it is not sufficient on its own: plenty of
/// people keep the system light and want one dark app, and on Android the
/// system toggle is buried. So the choice is explicit and remembered.
final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final stored = ref.read(prefsProvider).getString(_themeKey);
    return switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  void set(ThemeMode mode) {
    state = mode;
    ref.read(prefsProvider).setString(_themeKey, mode.name);
  }

  String get label => switch (state) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'Match system',
      };
}
