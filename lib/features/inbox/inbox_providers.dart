import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/repo.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/models.dart';

/// The inbox badge.
///
/// There are no push notifications on the server — there is a webhook channel
/// and Telegram, but no APNs or FCM — so the count is polled on the same 60s
/// cadence the web app uses for its badge. Failures are swallowed: a badge is
/// not worth an error state.
final unreadCountProvider = StreamProvider<int>((ref) {
  if (ref.watch(authControllerProvider.select((s) => s.me)) == null) {
    return Stream.value(0);
  }
  final repo = ref.watch(repoProvider);
  final controller = StreamController<int>();

  Future<void> tick() async {
    try {
      final count = await repo.unreadCount();
      if (!controller.isClosed) controller.add(count);
    } catch (_) {
      // Leave the last known value in place rather than flashing to zero.
    }
  }

  tick();
  final timer = Timer.periodic(const Duration(seconds: 60), (_) => tick());
  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });
  return controller.stream;
});

final notificationsProvider =
    FutureProvider.family<List<NotificationOut>, bool>((ref, unreadOnly) async {
  ref.watch(activeProfileIdProvider);
  return ref.watch(repoProvider).notifications(unreadOnly: unreadOnly, limit: 100);
});

/// Reminders are cross-organisation, so this is not org-scoped.
final remindersProvider = FutureProvider<List<ReminderOut>>((ref) async {
  ref.watch(activeProfileIdProvider);
  if (ref.watch(authControllerProvider.select((s) => s.me)) == null) {
    return const [];
  }
  return ref.watch(repoProvider).reminders();
});

final sparksProvider = FutureProvider<List<SparkOut>>((ref) async {
  ref.watch(activeProfileIdProvider);
  if (ref.watch(authControllerProvider.select((s) => s.me)) == null) {
    return const [];
  }
  return ref.watch(repoProvider).sparks();
});
