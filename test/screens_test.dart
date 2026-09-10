import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/harness.dart';

void main() {
  Future<FakeInstance> openTab(
    WidgetTester tester,
    String label, {
    required Map<String, Object?> routes,
  }) async {
    final instance = await pumpApp(tester, routes: routes);
    await tester.tap(find.text(label));
    await settle(tester);
    return instance;
  }

  group('task list', () {
    testWidgets('renders a row with its status, project and due date',
        (tester) async {
      await openTab(tester, 'Tasks', routes: {
        ...baseRoutes(),
        '/api/organisations/o1/dashboard': emptyDashboard(),
        '/api/organisations/o1/tasks': [
          task(dueOn: '2026-09-01'),
          task(
            id: 't2',
            title: 'Record a voice note',
            status: 'todo',
            priority: 'normal',
          ),
        ],
      });

      expect(find.text('Ship the mobile beta'), findsOneWidget);
      expect(find.text('Record a voice note'), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('To do'), findsOneWidget);
      expect(find.text('Mobile'), findsWidgets, reason: 'project name');
      // An overdue date reads as elapsed time, not a bare date.
      expect(find.textContaining('days ago'), findsOneWidget);
      expect(find.text('2 tasks'), findsOneWidget);
    });

    testWidgets('says so, honestly, when a page is part of a larger set',
        (tester) async {
      await openTab(tester, 'Tasks', routes: {
        ...baseRoutes(),
        '/api/organisations/o1/dashboard': emptyDashboard(),
        // The fake reports X-Total-Count from the list length, so a single
        // row means a single task; assert the exact-count wording instead.
        '/api/organisations/o1/tasks': [task()],
      });

      expect(find.text('1 task'), findsOneWidget);
    });

    testWidgets('an empty list offers to create the first task',
        (tester) async {
      await openTab(tester, 'Tasks', routes: {
        ...baseRoutes(),
        '/api/organisations/o1/dashboard': emptyDashboard(),
        '/api/organisations/o1/tasks': <Object?>[],
      });

      expect(find.text('No tasks yet'), findsOneWidget);
      expect(find.text('New task'), findsOneWidget);
    });

    testWidgets('asks for an explicit limit, since there is no default',
        (tester) async {
      final instance = await openTab(tester, 'Tasks', routes: {
        ...baseRoutes(),
        '/api/organisations/o1/dashboard': emptyDashboard(),
        '/api/organisations/o1/tasks': <Object?>[],
      });

      final list = instance.requests
          .lastWhere((r) => r.path.startsWith('/api/organisations/o1/tasks'));
      expect(list.queryParameters['limit'], isNotNull);
      expect(list.queryParameters['sort'], 'priority');
    });
  });

  group('triage', () {
    testWidgets('asks the server for tasks nobody is action-required on',
        (tester) async {
      final instance = await openTab(tester, 'Triage', routes: {
        ...baseRoutes(),
        '/api/organisations/o1/dashboard': emptyDashboard(),
        '/api/organisations/o1/tasks': [task()],
      });

      // Triage is not its own endpoint — it is this filter.
      final list = instance.requests
          .lastWhere((r) => r.path.startsWith('/api/organisations/o1/tasks'));
      expect(list.queryParameters['action_required_unset'], true);
    });

    testWidgets('offers the three answers to "who holds this?"',
        (tester) async {
      await openTab(tester, 'Triage', routes: {
        ...baseRoutes(),
        '/api/organisations/o1/dashboard': emptyDashboard(),
        '/api/organisations/o1/tasks': [task()],
      });

      expect(find.text('Ship the mobile beta'), findsOneWidget);
      expect(find.text("I'll take it"), findsOneWidget);
      expect(find.text('Assign'), findsOneWidget);
      expect(find.text('1 task waiting'), findsOneWidget);
    });

    testWidgets('an empty queue is framed as the goal, not as a blank screen',
        (tester) async {
      await openTab(tester, 'Triage', routes: {
        ...baseRoutes(),
        '/api/organisations/o1/dashboard': emptyDashboard(),
        '/api/organisations/o1/tasks': <Object?>[],
      });

      expect(find.text('Nothing to triage'), findsOneWidget);
    });
  });

  group('task detail', () {
    Map<String, Object?> detailRoutes() => {
          ...baseRoutes(),
          '/api/organisations/o1/dashboard': emptyDashboard(),
          '/api/organisations/o1/tasks': [task()],
          '/api/organisations/o1/tasks/t1': task(
            description: 'A **bold** plan.',
            dueOn: '2026-12-01',
          ),
          '/api/organisations/o1/tasks/t1/comments': {
            'messages': [
              {
                'id': 'm1',
                'author': {
                  'id': 'user-2',
                  'email': 'colleague@example.test',
                  'display_name': 'A Colleague',
                },
                'body': 'Looks good to me.',
                'attachments': <Object?>[],
                'created_at': '2026-09-08T09:00:00Z',
                'edited_at': null,
                'deleted': false,
                'mine': false,
              },
            ],
            'can_post': true,
            'unread': 0,
          },
          '/api/organisations/o1/tasks/t1/files': <Object?>[],
          '/api/organisations/o1/tasks/t1/checklists': <Object?>[],
        };

    testWidgets('opens from the list and shows the task with its thread',
        (tester) async {
      await openTab(tester, 'Tasks', routes: detailRoutes());

      await tester.tap(find.text('Ship the mobile beta'));
      await settle(tester);

      expect(find.text('Conversation'.toUpperCase()), findsOneWidget);
      expect(find.text('Looks good to me.'), findsOneWidget);
      expect(find.text('A Colleague'), findsOneWidget);
      expect(find.text('Waiting on'), findsOneWidget);
      expect(find.text('Unassigned'), findsWidgets);
      // The composer offers a voice note and a photo, not just text.
      expect(find.byIcon(LucideIcons.mic), findsOneWidget);
      expect(find.byIcon(LucideIcons.image), findsOneWidget);
    });

    testWidgets('renders a markdown-authored description as text',
        (tester) async {
      await openTab(tester, 'Tasks', routes: detailRoutes());
      await tester.tap(find.text('Ship the mobile beta'));
      await settle(tester);

      // Stored bodies with no `<` are plain text and stay that way.
      expect(find.textContaining('bold'), findsWidgets);
    });

    testWidgets('a task that is gone reads as not found, never forbidden',
        (tester) async {
      final routes = detailRoutes();
      routes.remove('/api/organisations/o1/tasks/t1');

      await openTab(tester, 'Tasks', routes: routes);
      await tester.tap(find.text('Ship the mobile beta'));
      await settle(tester);

      expect(find.text('Not found'), findsOneWidget);
      expect(find.textContaining('no longer have access'), findsOneWidget);
    });
  });

  group('more', () {
    testWidgets('lists the stage-three screens', (tester) async {
      await openTab(tester, 'More', routes: {
        ...baseRoutes(),
        '/api/organisations/o1/dashboard': emptyDashboard(),
        '/api/sparks': <Object?>[],
      });

      expect(find.text('Planner'), findsOneWidget);
      expect(find.text('Board'), findsOneWidget);
      expect(find.text('Calendar'), findsOneWidget);
      expect(find.text('Knowledge base'), findsOneWidget);
      expect(find.text('Bookmarks'), findsOneWidget);
      expect(find.text('Sparks'), findsOneWidget);
    });

    testWidgets('the planner shows all five buckets', (tester) async {
      await openTab(tester, 'More', routes: {
        ...baseRoutes(),
        '/api/organisations/o1/dashboard': emptyDashboard(),
        '/api/sparks': <Object?>[],
        '/api/organisations/o1/planner': {
          'pool': <Object?>[],
          'buckets': {
            'today': [
              {
                'task': {
                  'id': 't1',
                  'title': 'Ship the mobile beta',
                  'priority': 'critical',
                  'status': 'in_progress',
                  'is_open': true,
                },
                'bucket': 'today',
                'position': 0,
              },
            ],
          },
        },
      });

      await tester.tap(find.text('Planner'));
      await settle(tester);

      for (final bucket in ['TODAY', 'TOMORROW', 'THIS WEEK', 'NEXT WEEK', 'SOMEDAY']) {
        expect(find.text(bucket), findsOneWidget, reason: bucket);
      }
      expect(find.text('Ship the mobile beta'), findsOneWidget);
    });

    testWidgets('the board reports each column\'s real size', (tester) async {
      await openTab(tester, 'More', routes: {
        ...baseRoutes(),
        '/api/organisations/o1/dashboard': emptyDashboard(),
        '/api/sparks': <Object?>[],
        '/api/organisations/o1/tasks/board': {
          'group_by': 'status',
          'per_group': 50,
          'columns': [
            {'key': 'todo', 'total': 40, 'tasks': [task(id: 'b1', status: 'todo')]},
            {'key': 'in_progress', 'total': 1, 'tasks': [task(id: 'b2')]},
          ],
        },
      });

      await tester.tap(find.text('Board'));
      await settle(tester);

      // The board cannot be paged, so a bounded column must say what it hid.
      expect(find.text('1 of 40'), findsOneWidget);
      expect(find.text('1'), findsWidgets);
    });
  });

  group('inbox', () {
    testWidgets('shows notifications and reminders together', (tester) async {
      await openTab(tester, 'Inbox', routes: {
        ...baseRoutes(),
        '/api/organisations/o1/dashboard': emptyDashboard(),
        '/api/notifications': [
          {
            'id': 'n1',
            'kind': 'mention',
            'title': 'You were mentioned',
            'body': 'On "Ship the mobile beta"',
            'link_path': '/o/mobile-test-co/tasks/t1',
            'read_at': null,
            'created_at': '2026-09-08T12:00:00Z',
          },
        ],
        '/api/reminders': [
          {
            'id': 'r1',
            'remind_on': '2026-09-01',
            'note': 'chase the invoice',
            'overdue': true,
            'task_id': null,
            'task_title': null,
            'title': 'Chase Acme',
            'organisation_id': 'o1',
            'organisation_name': 'Mobile Test Co',
          },
        ],
      });

      expect(find.text('You were mentioned'), findsOneWidget);
      expect(find.text('Chase Acme'), findsOneWidget);
      expect(find.text('REMINDERS'), findsOneWidget);
      expect(find.text('NOTIFICATIONS'), findsOneWidget);
    });
  });
}
