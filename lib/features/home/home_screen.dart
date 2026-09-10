import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/models/models.dart';
import '../../core/org_controller.dart';
import '../../ui/format.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/badges.dart';
import '../../ui/widgets/screen_header.dart';
import '../../ui/widgets/states.dart';
import '../shell/org_switcher.dart';
import '../sparks/spark_capture.dart';
import '../tasks/task_row.dart';
import '../timer/running_timer_bar.dart';
import 'home_providers.dart';

/// The first screen: what is on fire, what you are holding, what is due.
///
/// Ordered by how urgently it wants a decision rather than by data model —
/// overdue before critical, and the running timer above everything, because a
/// timer left running is the one mistake this app can make on your behalf.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgId = ref.watch(currentOrgIdProvider);
    final dashboard = ref.watch(dashboardProvider);
    final me = ref.watch(meProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: ScreenHeader(
        title: const OrgSwitcherButton(),
        actions: [
          ShadIconButton.ghost(
            icon: const Icon(LucideIcons.zap, size: 18),
            onPressed: () => showSparkCapture(context),
          ),
          ShadIconButton.ghost(
            icon: const Icon(LucideIcons.settings, size: 18),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: orgId == null
          ? EmptyState(
              icon: LucideIcons.building2,
              title: 'Welcome aboard',
              message: 'Pick or create an organisation to see your work.',
              action: ShadButton.outline(
                onPressed: () => showContextSwitcher(context),
                child: const Text('Choose'),
              ),
            )
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(dashboardProvider);
                ref.invalidate(timerProvider);
              },
              child: ListView(
                padding: const EdgeInsets.only(bottom: Gap.xxl),
                children: [
                  const RunningTimerBar(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Gap.lg,
                      Gap.lg,
                      Gap.lg,
                      Gap.sm,
                    ),
                    child: Text(
                      _greeting(me?.displayName),
                      style: context.texts.h3,
                    ),
                  ),
                  AsyncView(
                    value: dashboard,
                    onRetry: () => ref.invalidate(dashboardProvider),
                    loading: const Padding(
                      padding: EdgeInsets.all(Gap.xxl),
                      child: LoadingView(),
                    ),
                    data: (data) => _Dashboard(data: data),
                  ),
                ],
              ),
            ),
    );
  }

  static String _greeting(String? name) {
    final hour = DateTime.now().hour;
    final part = hour < 12
        ? 'Good morning'
        : hour < 18
            ? 'Good afternoon'
            : 'Good evening';
    final first = name?.trim().split(' ').first;
    return first == null || first.isEmpty ? part : '$part, $first';
  }
}

class _Dashboard extends ConsumerWidget {
  const _Dashboard({required this.data});

  final DashboardOut data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overdue = [
      ...data.critical,
      ...data.urgent,
      ...data.high,
      ...data.dueSoon,
    ].where((t) => t.isOverdue).toList();

    final mine = [
      ...data.critical,
      ...data.urgent,
      ...data.high,
    ].where((t) => t.isActionRequired && !t.isOverdue).toList();

    final everythingEmpty = data.announcements.isEmpty &&
        overdue.isEmpty &&
        mine.isEmpty &&
        data.dueSoon.isEmpty &&
        data.pinned.isEmpty &&
        data.recent.isEmpty;

    if (everythingEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Gap.xxl),
        child: EmptyState(
          icon: LucideIcons.coffee,
          title: 'All clear',
          message: 'Nothing is overdue and nothing is waiting on you.',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final announcement in data.announcements)
          _Announcement(announcement: announcement),
        if (data.away.isNotEmpty) _AwayStrip(away: data.away),
        _Group(
          label: 'Overdue',
          tasks: overdue,
          emphasised: true,
          icon: LucideIcons.triangleAlert,
        ),
        _Group(
          label: 'Waiting on you',
          tasks: mine,
          icon: LucideIcons.userCheck,
        ),
        _Group(
          label: 'Due soon',
          tasks: data.dueSoon.where((t) => !t.isOverdue).toList(),
          icon: LucideIcons.calendarClock,
        ),
        _Group(
          label: 'Pinned',
          tasks: data.pinned,
          icon: LucideIcons.pin,
        ),
        if (data.recent.isNotEmpty) ...[
          const SectionLabel('Recently updated'),
          for (final task in data.recent.take(8))
            CompactTaskRow(
              title: task.title,
              status: task.status,
              subtitle: task.projectName,
              dimmed: !task.isOpen,
              onTap: () => context.push('/task/${task.id}'),
            ),
        ],
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.label,
    required this.tasks,
    required this.icon,
    this.emphasised = false,
  });

  final String label;
  final List<DashboardTaskOut> tasks;
  final IconData icon;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: Gap.lg,
            right: Gap.lg,
            top: Gap.lg,
            bottom: Gap.sm,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 13,
                color: emphasised
                    ? context.colors.destructive
                    : context.colors.mutedForeground,
              ),
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                  color: emphasised
                      ? context.colors.destructive
                      : context.colors.mutedForeground,
                ),
              ),
              const SizedBox(width: Gap.sm),
              CountBadge(tasks.length, emphasised: emphasised),
            ],
          ),
        ),
        for (final task in tasks)
          CompactTaskRow(
            title: task.title,
            status: task.status,
            subtitle: task.waitingOn == null
                ? task.projectName
                : 'waiting on ${Fmt.person(task.waitingOn!.displayName, task.waitingOn!.email)}',
            dueOn: task.dueOn,
            onTap: () => context.push('/task/${task.id}'),
          ),
      ],
    );
  }
}

class _Announcement extends StatelessWidget {
  const _Announcement({required this.announcement});

  final AnnouncementOut announcement;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, 0),
        padding: const EdgeInsets.all(Gap.md),
        decoration: BoxDecoration(
          color: context.colors.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: context.colors.primary.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              LucideIcons.megaphone,
              size: 15,
              color: context.colors.primary,
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(
                announcement.body,
                style: context.texts.small.copyWith(height: 1.4),
              ),
            ),
          ],
        ),
      );
}

class _AwayStrip extends StatelessWidget {
  const _AwayStrip({required this.away});

  final List<AbsenceOut> away;

  @override
  Widget build(BuildContext context) {
    final now = away.where((a) => a.awayNow).toList();
    if (now.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 0),
      child: Row(
        children: [
          Icon(
            LucideIcons.palmtree,
            size: 13,
            color: context.colors.mutedForeground,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Away: ${now.map((a) => Fmt.person(a.person?.displayName, a.person?.email)).join(', ')}',
              style: context.texts.small.copyWith(
                color: context.colors.mutedForeground,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
