import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// Renders every screen on a small phone at a large text scale.
///
/// Flutter reports an overflow as a framework error, which fails the test — so
/// simply visiting each screen at the tightest size the app claims to support
/// is a real assertion, not a smoke test. Three genuine overflows turned up
/// this way, all of them in rows of buttons.
void main() {
  const smallPhone = Size(320, 568);


  /// Each tab, reached by tapping the bottom bar.
  for (final tab in ['Home', 'Tasks', 'Triage', 'Inbox', 'More']) {
    testWidgets('$tab fits a small phone at a large text scale',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpApp(tester, routes: richRoutes(), size: smallPhone);
      await tester.tap(find.text(tab));
      await settle(tester);

      expect(tester.takeException(), isNull);
    });
  }

  /// Each pushed screen, reached from the More hub.
  for (final entry in {
        'Sparks': 'Sparks',
        'Planner': 'Planner',
        'Board': 'Board',
        'Calendar': 'Calendar',
        'Time': 'Time',
        'Knowledge base': 'Knowledge base',
        'Bookmarks': 'Bookmarks',
        'Settings': 'Settings',
      }.entries) {
    testWidgets('${entry.key} fits a small phone at a large text scale',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpApp(tester, routes: richRoutes(), size: smallPhone);
      await tester.tap(find.text('More'));
      await settle(tester);

      // On a small phone at this text scale the More list scrolls, and a
      // ListView has not built its lower rows yet — so scroll the plain
      // finder into existence before tapping it.
      final item = find.text(entry.value);
      await tester.scrollUntilVisible(
        item,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester);
      await tester.tap(item.first);
      await settle(tester);

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the task detail screen fits, thread and all', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpApp(tester, routes: richRoutes(), size: smallPhone);
    await tester.tap(find.text('Tasks'));
    await settle(tester);
    await tester.tap(find.textContaining('deliberately long title'));
    await settle(tester);

    expect(tester.takeException(), isNull);

    // The checklist sits below the summary and the description, so it has to
    // be scrolled to on a small phone.
    final checklist = find.text('Before release'.toUpperCase());
    await tester.scrollUntilVisible(
      checklist,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(checklist, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an article renders its sanitised HTML body', (tester) async {
    await pumpApp(tester, routes: richRoutes(), size: smallPhone);
    await tester.tap(find.text('More'));
    await settle(tester);
    final kb = find.text('Knowledge base');
    await tester.scrollUntilVisible(
      kb,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
    await tester.tap(kb.first);
    await settle(tester);
    await tester.tap(find.text('Operations'));
    await settle(tester);
    await tester.tap(find.text('Restoring from a backup'));
    await settle(tester);

    expect(tester.takeException(), isNull);
    // The body renders through an HTML widget, so the text lives in a
    // RichText rather than a plain Text.
    expect(
      find.textContaining('Stop the stack', findRichText: true),
      findsWidgets,
    );
  });

  testWidgets('dark mode renders every tab', (tester) async {
    // The palette defines light and dark separately; a token defined in only
    // one of them shows up as an unreadable screen, not as an error.
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await pumpApp(tester, routes: richRoutes());
    for (final tab in ['Tasks', 'Triage', 'Inbox', 'More', 'Home']) {
      await tester.tap(find.text(tab));
      await settle(tester);
      expect(tester.takeException(), isNull, reason: tab);
    }
  });
}
