import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/repo.dart';
import 'auth/auth_controller.dart';
import 'models/models.dart';

/// The organisations the active profile can see.
///
/// Rebuilds on a profile switch and on nothing else, so switching instances
/// re-reads the list while a token rotation does not.
final organisationsProvider = FutureProvider<List<OrganisationOut>>((ref) async {
  ref.watch(activeProfileIdProvider);
  // `/api/me` creates the local user row and binds pending invitations, and
  // everything else keys on the id it returns — so nothing is fetched until it
  // has answered.
  if (ref.watch(authControllerProvider.select((s) => s.me)) == null) {
    return const [];
  }
  return ref.watch(repoProvider).organisations();
});

/// The organisation the app is currently looking at.
///
/// The web app drops you back into the last organisation you used; this
/// matches that, falling back to the first one the account can see.
final currentOrgIdProvider =
    NotifierProvider<CurrentOrgController, String?>(CurrentOrgController.new);

class CurrentOrgController extends Notifier<String?> {
  /// An explicit in-session choice, which outranks the remembered one.
  String? _chosen;

  @override
  String? build() {
    final orgs = ref.watch(organisationsProvider).value;
    final remembered = ref.watch(
      authControllerProvider.select((s) => s.activeProfile?.lastOrgId),
    );
    if (orgs == null || orgs.isEmpty) return null;

    bool exists(String? id) => id != null && orgs.any((o) => o.id == id);

    // Each candidate is checked against the list, so a stale id — a profile
    // switch, or an organisation somebody left — falls through instead of
    // pinning the app to something it cannot load.
    if (exists(_chosen)) return _chosen;
    if (exists(remembered)) return remembered;
    return orgs.first.id;
  }

  void select(String orgId) {
    if (orgId == state) return;
    _chosen = orgId;
    state = orgId;
    ref.read(authControllerProvider.notifier).setLastOrg(orgId);
  }
}

final currentOrgProvider = Provider<OrganisationOut?>((ref) {
  final id = ref.watch(currentOrgIdProvider);
  final orgs = ref.watch(organisationsProvider).value;
  if (id == null || orgs == null) return null;
  for (final o in orgs) {
    if (o.id == id) return o;
  }
  return null;
});

/// Screens that cannot render without an organisation read this and are only
/// ever built once one is resolved.
final requireOrgIdProvider = Provider<String>((ref) {
  final id = ref.watch(currentOrgIdProvider);
  if (id == null) throw StateError('No organisation selected');
  return id;
});

/// The members of the current organisation — needed by every assignee picker,
/// so it is fetched once and shared.
final membersProvider = FutureProvider<List<MemberOut>>((ref) async {
  final orgId = ref.watch(currentOrgIdProvider);
  if (orgId == null) return const [];
  return ref.watch(repoProvider).members(orgId);
});

final projectsProvider = FutureProvider<List<ProjectOut>>((ref) async {
  final orgId = ref.watch(currentOrgIdProvider);
  if (orgId == null) return const [];
  return ref.watch(repoProvider).projects(orgId);
});

final tagsProvider = FutureProvider<List<TagOut>>((ref) async {
  final orgId = ref.watch(currentOrgIdProvider);
  if (orgId == null) return const [];
  return ref.watch(repoProvider).tags(orgId);
});

/// True when the given user id is the signed-in person.
///
/// `action_required` pointing at *you* is the product's most important signal,
/// so it is worth having one place that decides it.
final isMeProvider = Provider.family<bool, String?>((ref, userId) {
  if (userId == null) return false;
  final me = ref.watch(meProvider);
  return me != null && (me.userId == userId || me.id == userId);
});
