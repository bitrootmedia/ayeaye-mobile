import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/auth_controller.dart';
import 'features/auth/add_profile_screen.dart';
import 'features/auth/gate_screens.dart';
import 'features/auth/profiles_screen.dart';
import 'features/auth/signin_screen.dart';
import 'features/auth/splash_screen.dart';
import 'features/board/board_screen.dart';
import 'features/bookmarks/bookmarks_screen.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/home/home_screen.dart';
import 'features/inbox/inbox_screen.dart';
import 'features/kb/kb_screen.dart';
import 'features/more/more_screen.dart';
import 'features/planner/planner_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/sparks/sparks_screen.dart';
import 'features/tasks/task_detail_screen.dart';
import 'features/tasks/tasks_screen.dart';
import 'features/tasks/triage_screen.dart';
import 'features/timer/time_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

/// Where the app is allowed to be, given the session.
///
/// The gates are the interesting part: a perfectly valid password can still
/// leave every `/api/*` route returning 403, so "signed in" is not the same as
/// "can use the app" and the router has to model both.
enum _Stage { splash, noProfiles, signedOut, mfa, email, ready }

_Stage _stageOf(AuthState state) {
  if (state.bootstrapping) return _Stage.splash;
  if (state.profiles.isEmpty) return _Stage.noProfiles;
  final active = state.activeProfile;
  if (active == null || !active.signedIn) return _Stage.signedOut;
  return switch (state.gate) {
    SessionGate.mfa => _Stage.mfa,
    SessionGate.emailVerification => _Stage.email,
    SessionGate.none => state.me == null ? _Stage.splash : _Stage.ready,
  };
}

final routerProvider = Provider<GoRouter>((ref) {
  // A plain Listenable bridge: go_router wants change notifications, Riverpod
  // wants a provider, and this is the smallest honest adapter between them.
  final refresh = _AuthRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, routerState) {
      final stage = _stageOf(ref.read(authControllerProvider));
      final path = routerState.matchedLocation;

      // Screens a person can always reach, whatever the session says: adding
      // an instance and signing one back in have to work from a dead session.
      final isAuthRoute = path.startsWith('/profiles') || path.startsWith('/signin');

      return switch (stage) {
        _Stage.splash => path == '/splash' ? null : '/splash',
        _Stage.noProfiles => isAuthRoute ? null : '/profiles',
        _Stage.signedOut => isAuthRoute ? null : '/profiles',
        _Stage.mfa => path == '/gate/mfa' || isAuthRoute ? null : '/gate/mfa',
        _Stage.email => path == '/gate/email' || isAuthRoute ? null : '/gate/email',
        _Stage.ready => (path == '/splash' || path.startsWith('/gate'))
            ? '/home'
            : null,
      };
    },
    routes: [
      // `/` is what the auth screens navigate to when they mean "send me
      // wherever I belong now" — after a profile switch, a sign-in, or a
      // cleared gate. It has to exist as a route, or go_router throws
      // `no routes for location: /` before the redirect above ever runs.
      GoRoute(path: '/', redirect: (_, _) => '/home'),
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/profiles', builder: (_, _) => const ProfilesScreen()),
      GoRoute(
        path: '/profiles/add',
        builder: (_, _) => const AddProfileScreen(),
      ),
      GoRoute(
        path: '/signin/:profileId',
        builder: (_, s) =>
            SignInScreen(profileId: s.pathParameters['profileId']!),
      ),
      GoRoute(path: '/gate/mfa', builder: (_, _) => const MfaGateScreen()),
      GoRoute(path: '/gate/email', builder: (_, _) => const EmailGateScreen()),

      // The tabs. An IndexedStack keeps each tab's scroll position and
      // filters alive, which matters most for the task list.
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _shellKey,
            routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/tasks', builder: (_, _) => const TasksScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/triage', builder: (_, _) => const TriageScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/inbox', builder: (_, _) => const InboxScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/more', builder: (_, _) => const MoreScreen())],
          ),
        ],
      ),

      // Pushed over the tabs, so the bottom bar gets out of the way for the
      // screens where content is the whole point.
      GoRoute(
        path: '/task/:taskId',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => TaskDetailScreen(taskId: s.pathParameters['taskId']!),
      ),
      GoRoute(
        path: '/sparks',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const SparksScreen(),
      ),
      GoRoute(
        path: '/planner',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const PlannerScreen(),
      ),
      GoRoute(
        path: '/board',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const BoardScreen(),
      ),
      GoRoute(
        path: '/calendar',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const CalendarScreen(),
      ),
      GoRoute(
        path: '/bookmarks',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const BookmarksScreen(),
      ),
      GoRoute(
        path: '/kb',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const BooksScreen(),
      ),
      GoRoute(
        path: '/kb/book/:bookId',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => BookScreen(bookId: s.pathParameters['bookId']!),
      ),
      GoRoute(
        path: '/kb/article/:articleId',
        parentNavigatorKey: _rootKey,
        builder: (_, s) =>
            ArticleScreen(articleId: s.pathParameters['articleId']!),
      ),
      GoRoute(
        path: '/time',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const TimeScreen(),
      ),
      GoRoute(
        path: '/settings',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const SettingsScreen(),
      ),
    ],
  );
});

/// Notifies go_router when the session stage changes — and only then, so a
/// token rotation does not bounce the person off the screen they are reading.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(this._ref) {
    _stage = _stageOf(_ref.read(authControllerProvider));
    _sub = _ref.listen<AuthState>(authControllerProvider, (_, next) {
      final stage = _stageOf(next);
      if (stage == _stage) return;
      _stage = stage;
      notifyListeners();
    });
  }

  final Ref _ref;
  late _Stage _stage;
  late final ProviderSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}
