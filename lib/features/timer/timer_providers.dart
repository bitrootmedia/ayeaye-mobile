import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/repo.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/models.dart';

/// The running timer, across every organisation.
///
/// One of the two things people open the app for daily, so it is app-wide
/// state rather than something a screen fetches for itself.
final timerProvider = FutureProvider<TimerOut>((ref) async {
  ref.watch(activeProfileIdProvider);
  if (ref.watch(authControllerProvider.select((s) => s.me)) == null) {
    return const TimerOut(entry: null);
  }
  return ref.watch(repoProvider).myTimer();
});
