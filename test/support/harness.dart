import 'dart:convert';

import 'package:ayeaye_mobile/app.dart';
import 'package:ayeaye_mobile/core/api/api_client.dart';
import 'package:ayeaye_mobile/core/auth/auth_controller.dart';
import 'package:ayeaye_mobile/core/auth/profile.dart';
import 'package:ayeaye_mobile/core/auth/profile_store.dart';
import 'package:ayeaye_mobile/core/auth/session_tokens.dart';
import 'package:ayeaye_mobile/core/prefs.dart';
import 'package:ayeaye_mobile/core/realtime/ws_client.dart';
import 'package:ayeaye_mobile/router.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A fake instance: routes are answered from a map of path -> JSON.
///
/// Matched on the path alone, ignoring the query string, so a test can stub
/// `/api/organisations/o1/tasks` without restating every filter parameter.
class FakeInstance implements HttpClientAdapter {
  FakeInstance(this.routes);

  final Map<String, Object?> routes;
  final List<RequestOptions> requests = [];

  /// Paths asked for that had no stub — a test can assert this is empty to
  /// catch a screen quietly calling something unexpected.
  final List<String> unmatched = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.path.startsWith('http')
        ? (Uri.tryParse(options.path)?.path ?? options.path)
        : options.path.split('?').first;

    if (!routes.containsKey(path)) {
      unmatched.add('${options.method} $path');
      return ResponseBody.fromString('{"detail":"not stubbed: $path"}', 404,
          headers: _jsonHeaders);
    }
    final value = routes[path];
    return ResponseBody.fromString(
      jsonEncode(value),
      200,
      headers: {
        ..._jsonHeaders,
        if (value is List) 'x-total-count': ['${value.length}'],
      },
    );
  }

  static const _jsonHeaders = {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  };

  @override
  void close({bool force = false}) {}
}

class _FakeStore extends ProfileStore {
  _FakeStore(this.profiles, this.activeId);

  final List<Profile> profiles;
  final String? activeId;

  @override
  Future<(List<Profile>, String?)> load() async => (profiles, activeId);

  @override
  Future<void> save(List<Profile> profiles, String? activeId) async {}

  @override
  Future<void> clear() async {}
}

/// A profile that is already signed in, so tests start past the auth screens.
Profile signedInProfile() => Profile(
      id: 'p1',
      label: 'Test',
      baseUrl: 'https://tasks.example.test',
      tokens: SessionTokens(
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
        accessExpiry: DateTime.now().add(const Duration(hours: 1)),
        userId: 'user-1',
      ),
      email: 'you@example.test',
      displayName: 'Test Person',
      userId: 'user-1',
      patForSocket: null,
      lastOrgId: 'o1',
    );

/// Boots the real app — real router, real providers, real widgets — with only
/// the platform edges faked.
Future<FakeInstance> pumpApp(
  WidgetTester tester, {
  required Map<String, Object?> routes,
  List<Profile>? profiles,
  String? activeId = 'p1',
  Size size = const Size(430, 932),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final instance = FakeInstance(routes);
  mockPlatformChannels(tester);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(Prefs(prefs)),
        profileStoreProvider.overrideWithValue(
          _FakeStore(profiles ?? [signedInProfile()], activeId),
        ),
        // Every request in the app goes through this.
        apiClientFactoryProvider.overrideWithValue(
          ({
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
                dio: Dio()..httpClientAdapter = instance,
                storageDio: Dio(BaseOptions(validateStatus: (_) => true))
                  ..httpClientAdapter = instance,
              ),
        ),
        // No socket in tests: a real one would leave reconnect timers pending.
        realtimeProvider.overrideWithValue(null),
      ],
      child: const AyeayeApp(),
    ),
  );

  await settle(tester);
  return instance;
}

/// The live router, for asserting on locations directly.
GoRouter routerFor(WidgetTester tester) {
  final context = tester.element(find.byType(AyeayeApp));
  return ProviderScope.containerOf(context).read(routerProvider);
}

/// `pumpAndSettle` cannot be used while the running-timer bar is ticking, so
/// this pumps a bounded number of frames instead.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

// ---------------------------------------------------------------- fixtures

Map<String, Object?> me() => {
      'id': 'member-1',
      'user_id': 'user-1',
      'email': 'you@example.test',
      'display_name': 'Test Person',
      'timezone': 'Europe/Lisbon',
      'status_message': null,
      'daily_summary_enabled': true,
    };

List<Object?> organisations() => [
      {
        'id': 'o1',
        'name': 'Mobile Test Co',
        'slug': 'mobile-test-co',
        'role': 'owner',
        'require_mfa': false,
        'created_at': '2026-09-01T10:00:00Z',
      },
    ];

Map<String, Object?> task({
  String id = 't1',
  String title = 'Ship the mobile beta',
  String status = 'in_progress',
  String priority = 'critical',
  bool isOpen = true,
  String? dueOn,
  Map<String, Object?>? actionRequired,
  String? description,
}) =>
    {
      'id': id,
      'title': title,
      'description': description,
      'status': status,
      'priority': priority,
      'is_open': isOpen,
      'closed_at': null,
      'project_id': 'proj-1',
      'project_name': 'Mobile',
      'owner': null,
      'action_required': actionRequired,
      'due_on': dueOn,
      'estimated_start_on': null,
      'estimated_hours': null,
      'position': 0,
      'created_at': '2026-09-01T10:00:00Z',
      'updated_at': '2026-09-08T10:00:00Z',
      'is_hidden': false,
      'is_pinned': false,
      'tags': <Object?>[],
      'access': 'write',
      'can_close': true,
      'can_hide': true,
    };

Map<String, Object?> emptyDashboard() => {
      'announcements': <Object?>[],
      'away': <Object?>[],
      'can_announce': false,
      'critical': <Object?>[],
      'urgent': <Object?>[],
      'high': <Object?>[],
      'due_soon': <Object?>[],
      'pinned': <Object?>[],
      'recent': <Object?>[],
    };

/// The routes every signed-in screen touches on the way in.
Map<String, Object?> baseRoutes() => {
      '/api/me': me(),
      '/api/organisations': organisations(),
      '/api/me/tokens': {
        'id': 'tok-1',
        'name': 'Mobile app',
        'scope': 'read',
        'prefix': 'ayc_test1234',
        'last_used_at': null,
        'created_at': '2026-09-08T10:00:00Z',
        'token': 'ayc_test1234secret',
      },
      '/api/notifications/unread-count': {'unread': 0},
      '/api/me/timer': {'entry': null, 'organisation_id': null},
      '/api/organisations/o1/members': <Object?>[],
      '/api/organisations/o1/projects': <Object?>[],
      '/api/organisations/o1/tags': <Object?>[],
    };

/// Renders the widget tree to text, for diagnosing a failing expectation.
String describeTree(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where((s) => s.isNotEmpty)
    .join(' | ');

/// Answers the plugin channels the app touches on start-up.
///
/// Without this the timezone lookup never completes, and the sign-in
/// housekeeping that follows it never runs — which is a test artefact, not a
/// behaviour worth asserting.
void mockPlatformChannels(WidgetTester tester) {
  final messenger =
      tester.binding.defaultBinaryMessenger;

  messenger.setMockMethodCallHandler(
    const MethodChannel('flutter_timezone'),
    (call) async => call.method == 'getLocalTimezone'
        ? {'identifier': 'Europe/Lisbon'}
        : null,
  );
}

/// A fixture with something in every list, so a layout sweep exercises the
/// wrapping cases rather than a grid of empty states.
Map<String, Object?> richRoutes() => {
      ...baseRoutes(),
      '/api/organisations/o1/dashboard': {
        ...emptyDashboard(),
        'announcements': [
          {
            'id': 'a1',
            'body': 'All hands on Friday, and please log your time before '
                'the end of the month.',
            'sticky': true,
            'expires_on': null,
            'author': null,
            'created_at': '2026-09-08T10:00:00Z',
          },
        ],
        'away': [
          {
            'id': 'ab1',
            'starts_on': '2026-09-08',
            'ends_on': '2026-09-12',
            'note': 'conference',
            'away_now': true,
            'person': {
              'id': 'user-2',
              'email': 'colleague@example.test',
              'display_name': 'A Colleague With A Long Name',
            },
          },
        ],
        'critical': [
          {
            'id': 't1',
            'title': 'An overdue critical task with a fairly long title',
            'status': 'in_progress',
            'project_id': 'p',
            'project_name': 'Mobile',
            'due_on': '2026-09-01',
            'is_owner': true,
            'is_action_required': true,
            'waiting_on': {
              'id': 'user-1',
              'email': 'you@example.test',
              'display_name': 'Test Person',
            },
            'is_overdue': true,
            'is_due_today': false,
          },
        ],
      },
      '/api/organisations/o1/tasks': [
        task(
          title: 'A task with a deliberately long title that has to wrap '
              'onto a second line',
          dueOn: '2026-09-01',
          actionRequired: {
            'id': 'user-1',
            'email': 'you@example.test',
            'display_name': 'Test Person',
          },
        ),
        task(id: 't2', title: 'Short one', status: 'todo', priority: 'low'),
      ],
      '/api/organisations/o1/tasks/t1': task(
        description: 'A plan, written as markdown, with some length to it.',
        dueOn: '2026-12-01',
      ),
      '/api/organisations/o1/tasks/t1/comments': {
        'messages': [
          {
            'id': 'm1',
            'author': {
              'id': 'user-2',
              'email': 'colleague@example.test',
              'display_name': 'A Colleague With A Long Name',
            },
            'body': 'A comment long enough to wrap across several lines on '
                'a narrow screen, which is the point of this fixture.',
            'attachments': [
              {
                'id': 'att1',
                'filename': 'voice-note-20260908-120000.m4a',
                'content_type': 'audio/mp4',
                'size_bytes': 20480,
                'url': 'https://storage.example.test/att1',
                'thumbnail_url': null,
              },
            ],
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
      '/api/organisations/o1/tasks/t1/checklists': [
        {
          'id': 'cl1',
          'title': 'Before release',
          'items': [
            {'id': 'i1', 'text': 'Check the presigned upload path', 'done': true},
            {'id': 'i2', 'text': 'Test the two session gates', 'done': false},
          ],
        },
      ],
      '/api/notifications': [
        {
          'id': 'n1',
          'kind': 'mention',
          'title': 'You were mentioned on a task with a long title',
          'body': 'Have a look when you get a moment.',
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
          'task_id': 't1',
          'task_title': 'Ship the mobile beta',
          'title': 'Chase Acme about the renewal',
          'organisation_id': 'o1',
          'organisation_name': 'Mobile Test Co',
        },
      ],
      '/api/sparks': [
        {
          'id': 's1',
          'body': 'Look into whether the socket can carry bodies after all',
          'created_at': '2026-09-08T08:00:00Z',
          'updated_at': '2026-09-08T08:00:00Z',
        },
      ],
      '/api/organisations/o1/planner': {
        'pool': [
          {
            'id': 't2',
            'title': 'Unplanned but pressing',
            'priority': 'urgent',
            'status': 'todo',
            'is_open': true,
          },
        ],
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
      '/api/organisations/o1/tasks/board': {
        'group_by': 'status',
        'per_group': 50,
        'columns': [
          {'key': 'todo', 'total': 40, 'tasks': [task(id: 'b1', status: 'todo')]},
          {'key': 'blocker', 'total': 1, 'tasks': [task(id: 'b2', status: 'blocker')]},
        ],
      },
      '/api/organisations/o1/calendar': {
        'tasks': [
          {
            'id': 't1',
            'title': 'Ship the mobile beta',
            'due_on': '2026-09-15',
            'status': 'in_progress',
            'priority': 'critical',
            'project_name': 'Mobile',
          },
        ],
        'reminders': [
          {
            'id': 'r1',
            'remind_on': '2026-09-20',
            'note': 'chase',
            'task_id': null,
            'task_title': null,
            'title': 'Chase Acme',
          },
        ],
        'away': [
          {
            'id': 'ab1',
            'person': {
              'id': 'user-2',
              'email': 'c@example.test',
              'display_name': 'A Colleague',
            },
            'starts_on': '2026-09-22',
            'ends_on': '2026-09-26',
            'note': 'conference',
          },
        ],
      },
      '/api/organisations/o1/bookmarks': [
        {
          'id': 'bm1',
          'url': 'https://example.test/a-fairly-long-url/that-keeps-going',
          'description': 'The runbook everyone forgets about',
          'pinned': true,
          'position': 0,
          'added_by': null,
          'created_at': '2026-09-01T10:00:00Z',
          'updated_at': '2026-09-01T10:00:00Z',
          'can_edit': true,
        },
      ],
      '/api/organisations/o1/kb/books': [
        {
          'id': 'bk1',
          'name': 'Operations',
          'description': 'How we run things day to day',
          'owner': null,
          'archived': false,
          'created_at': '2026-09-01T10:00:00Z',
          'access': 'read',
          'article_count': 3,
        },
      ],
      '/api/organisations/o1/kb/books/bk1/articles': [
        {
          'id': 'ar1',
          'book_id': 'bk1',
          'title': 'Restoring from a backup',
          'owner': null,
          'is_private': false,
          'can_make_private': false,
          'created_at': '2026-09-01T10:00:00Z',
          'updated_at': '2026-09-05T10:00:00Z',
          'access': 'read',
        },
      ],
      '/api/organisations/o1/kb/articles/ar1': {
        'id': 'ar1',
        'book_id': 'bk1',
        'title': 'Restoring from a backup',
        'owner': null,
        'is_private': false,
        'can_make_private': false,
        'created_at': '2026-09-01T10:00:00Z',
        'updated_at': '2026-09-05T10:00:00Z',
        'access': 'read',
      },
      '/api/organisations/o1/kb/articles/ar1/revisions': [
        {
          'id': 'rev1',
          'article_id': 'ar1',
          'title': 'Restoring from a backup',
          'body': '<h2>Steps</h2><ul><li>Stop the stack</li>'
              '<li>Restore the volume</li></ul><pre><code>docker compose up'
              '</code></pre>',
          'edited_by': null,
          'created_at': '2026-09-05T10:00:00Z',
          'updated_at': '2026-09-05T10:00:00Z',
          'is_current': true,
        },
      ],
      '/api/organisations/o1/time/entries': [
        {
          'id': 'te1',
          'task_id': 't1',
          'task_title': 'Ship the mobile beta',
          'project_name': 'Mobile',
          'user': null,
          'started_at': '2026-09-08T09:00:00Z',
          'ended_at': '2026-09-08T10:30:00Z',
          'seconds': 5400,
          'note': 'pairing on the auth flow',
          'edited_at': null,
        },
      ],
      '/api/me/mfa/status': {'enrolled': false, 'codes_remaining': 0},
    };
