import 'package:ayeaye_mobile/core/auth/profile.dart';
import 'package:ayeaye_mobile/core/auth/session_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// Every screen the app can navigate to has to exist.
///
/// `context.go('/')` was used as "send me wherever I belong now" after a
/// profile switch, sign-in and each gate — but `/` was never declared as a
/// route, so go_router threw `no routes for location: /` and offered an error
/// page whose only button navigated to `/` again.
void main() {
  Profile profile(String id, String label) => Profile(
        id: id,
        label: label,
        baseUrl: 'https://$label.example.test',
        tokens: SessionTokens(
          accessToken: 'access-$id',
          refreshToken: 'refresh-$id',
          accessExpiry: DateTime.now().add(const Duration(hours: 1)),
          userId: 'user-1',
        ),
        email: 'you@$label.example.test',
        displayName: 'Test Person',
        userId: 'user-1',
        lastOrgId: 'o1',
      );

  testWidgets('switching instance lands on Home, not an error page',
      (tester) async {
    await pumpApp(
      tester,
      routes: {
        ...baseRoutes(),
        '/api/organisations/o1/dashboard': emptyDashboard(),
      },
      profiles: [profile('p1', 'work'), profile('p2', 'personal')],
      activeId: 'p1',
    );

    // Settings → Manage instances is one way in; the switcher sheet is the
    // other. Both land on the same screen.
    await tester.tap(find.text('More'));
    await settle(tester);
    await tester.tap(find.text('Settings'));
    await settle(tester);
    await tester.tap(find.text('Manage instances'));
    await settle(tester);

    expect(find.text('Choose an instance'), findsOneWidget);

    await tester.tap(find.text('personal'));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('no routes for location'), findsNothing);
    expect(find.text('Page Not Found'), findsNothing);
    // Back on the app proper.
    expect(find.text('Mobile Test Co'), findsOneWidget);
  });

  testWidgets('the root location resolves instead of throwing', (tester) async {
    await pumpApp(
      tester,
      routes: {
        ...baseRoutes(),
        '/api/organisations/o1/dashboard': emptyDashboard(),
      },
    );

    // Reproduce the raw failure: navigate to '/' the way the auth screens do.
    final router = routerFor(tester);
    router.go('/');
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(router.state.matchedLocation, '/home');
  });
}
