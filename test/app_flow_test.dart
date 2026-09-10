import 'package:ayeaye_mobile/core/auth/profile.dart';
import 'package:ayeaye_mobile/core/auth/session_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('with no profiles, it asks you to connect an instance',
      (tester) async {
    await pumpApp(tester, routes: {}, profiles: [], activeId: null);

    expect(find.text('Connect your instance'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    // The localhost hint matters: an emulator cannot reach it.
    expect(find.textContaining('10.0.2.2'), findsOneWidget);
  });

  testWidgets('a signed-out profile is offered a one-field sign-in',
      (tester) async {
    final profile = Profile(
      id: 'p1',
      label: 'Work',
      baseUrl: 'https://tasks.example.test',
      email: 'you@example.test',
      tokens: SessionTokens.empty,
    );

    await pumpApp(tester, routes: {}, profiles: [profile]);

    expect(find.text('Choose an instance'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('signed out'), findsOneWidget);
  });

  testWidgets('a signed-in profile lands on the dashboard', (tester) async {
    await pumpApp(tester, routes: {
      ...baseRoutes(),
      '/api/organisations/o1/dashboard': emptyDashboard(),
    });

    // The greeting only renders once /api/me has answered, so finding it also
    // proves the app gated on it. It greets by first name.
    expect(find.textContaining('Test'), findsWidgets);
    expect(find.text('Mobile Test Co'), findsOneWidget);
    expect(find.text('All clear'), findsOneWidget);
  });

  testWidgets('the dashboard groups overdue work first', (tester) async {
    await pumpApp(tester, routes: {
      ...baseRoutes(),
      '/api/organisations/o1/dashboard': {
        ...emptyDashboard(),
        'critical': [
          {
            'id': 't1',
            'title': 'Overdue critical thing',
            'status': 'in_progress',
            'project_id': 'p',
            'project_name': 'Mobile',
            'due_on': '2026-09-01',
            'is_owner': true,
            'is_action_required': true,
            'waiting_on': null,
            'is_overdue': true,
            'is_due_today': false,
          },
        ],
      },
    });

    expect(find.text('OVERDUE'), findsOneWidget);
    expect(find.text('Overdue critical thing'), findsOneWidget);
  });

  testWidgets('mints a socket token after sign-in', (tester) async {
    // The socket takes a cookie or a PAT, and a header-mode client has
    // neither — so sign-in has to mint one.
    final instance = await pumpApp(tester, routes: {
      ...baseRoutes(),
      '/api/organisations/o1/dashboard': emptyDashboard(),
    });

    expect(
      instance.requests.any(
        (r) => r.path == '/api/me/tokens' && r.method == 'POST',
      ),
      isTrue,
      reason: 'requests were: '
          '${instance.requests.map((r) => '${r.method} ${r.path}').toList()} '
          'unmatched: ${instance.unmatched}',
    );
    final mint = instance.requests
        .lastWhere((r) => r.path == '/api/me/tokens' && r.method == 'POST');
    expect((mint.data as Map)['scope'], 'read',
        reason: 'watching is reading; write scope is not needed');
  });

  testWidgets('sends the device timezone to /api/me', (tester) async {
    // Reminders, the deadline sweep and the daily digest all compute "today"
    // per user zone, so the device's zone has to reach the server.
    final instance = await pumpApp(tester, routes: {
      ...baseRoutes(),
      // Report a different zone so the client has a reason to correct it.
      '/api/me': {...me(), 'timezone': 'UTC'},
      '/api/organisations/o1/dashboard': emptyDashboard(),
    });

    final patch = instance.requests
        .where((r) => r.path == '/api/me' && r.method == 'PATCH')
        .toList();
    expect(patch, hasLength(1), reason: 'corrected once, not on every build');
    expect((patch.single.data as Map)['timezone'], 'Europe/Lisbon');
  });

  testWidgets('an unreachable instance explains itself and offers a retry',
      (tester) async {
    // /api/me is not stubbed, so it 404s: the app must say something useful
    // rather than sitting on a spinner.
    await pumpApp(tester, routes: {});

    expect(find.text('Could not reach your instance'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
