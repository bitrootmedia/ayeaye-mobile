import 'package:ayeaye_mobile/core/prefs.dart';
import 'package:ayeaye_mobile/core/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/harness.dart';

void main() {
  testWidgets('the theme choice is offered and takes effect', (tester) async {
    // The phone is light; picking Dark has to override that, not follow it.
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await pumpApp(tester, routes: {
      ...baseRoutes(),
      '/api/organisations/o1/dashboard': emptyDashboard(),
      '/api/me/mfa/status': {'enrolled': false, 'codes_remaining': 0},
    });

    await tester.tap(find.text('More'));
    await settle(tester);
    await tester.tap(find.text('Settings'));
    await settle(tester);

    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.text('Theme')),
    );
    expect(container.read(themeModeProvider), ThemeMode.system);

    await tester.tap(find.text('Dark'));
    await settle(tester);

    expect(container.read(themeModeProvider), ThemeMode.dark);
    // The rendered theme actually flipped, not just the setting.
    expect(
      ShadTheme.of(tester.element(find.text('Theme'))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('the choice survives a restart', (tester) async {
    await pumpApp(tester, routes: {
      ...baseRoutes(),
      '/api/organisations/o1/dashboard': emptyDashboard(),
      '/api/me/mfa/status': {'enrolled': false, 'codes_remaining': 0},
    });
    await tester.tap(find.text('More'));
    await settle(tester);
    await tester.tap(find.text('Settings'));
    await settle(tester);
    await tester.tap(find.text('Light'));
    await settle(tester);

    final prefs = ProviderScope.containerOf(tester.element(find.text('Theme')));
    expect(prefs.read(themeModeProvider), ThemeMode.light);
    // Written through to storage, which is what makes it survive a launch.
    expect(
      prefs.read(prefsProvider).getString('ui.themeMode.v1'),
      'light',
    );
  });
}
