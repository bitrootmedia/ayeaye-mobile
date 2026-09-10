import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/repo.dart';
import '../../core/models/models.dart';
import '../../core/org_controller.dart';

export '../timer/timer_providers.dart' show timerProvider;

/// The dashboard the home screen renders. One request, server-resolved.
final dashboardProvider = FutureProvider<DashboardOut>((ref) async {
  final orgId = ref.watch(currentOrgIdProvider);
  if (orgId == null) {
    return const DashboardOut(
      announcements: [],
      away: [],
      canAnnounce: false,
      critical: [],
      urgent: [],
      high: [],
      dueSoon: [],
      pinned: [],
      recent: [],
    );
  }
  return ref.watch(repoProvider).dashboard(orgId);
});
