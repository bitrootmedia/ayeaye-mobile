import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/org_controller.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/screen_header.dart';
import '../inbox/inbox_providers.dart';
import '../shell/org_switcher.dart';
import '../sparks/spark_capture.dart';
import '../timer/running_timer_bar.dart';

/// Everything that does not need a permanent tab.
///
/// The web app has roughly thirty screens; these are the ones worth carrying
/// on a phone. Sheets, KB authoring, org settings, working-hours grids,
/// exports and access panels stay on the web, where the density suits them.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sparkCount = ref.watch(sparksProvider).value?.length ?? 0;
    final hasOrg = ref.watch(currentOrgIdProvider) != null;

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: const ScreenHeader(title: OrgSwitcherButton()),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Gap.xxl),
        children: [
          const RunningTimerBar(),
          const SectionLabel('Capture'),
          _Item(
            icon: LucideIcons.zap,
            label: 'Quick capture',
            detail: 'Get a thought out of your head',
            onTap: () => showSparkCapture(context),
          ),
          _Item(
            icon: LucideIcons.sparkles,
            label: 'Sparks',
            detail: sparkCount == 0 ? null : '$sparkCount saved',
            onTap: () => context.push('/sparks'),
          ),
          const SectionLabel('Plan'),
          _Item(
            icon: LucideIcons.calendarRange,
            label: 'Planner',
            detail: 'Today, tomorrow, this week',
            enabled: hasOrg,
            onTap: () => context.push('/planner'),
          ),
          _Item(
            icon: LucideIcons.columns3,
            label: 'Board',
            detail: 'Tasks grouped by status',
            enabled: hasOrg,
            onTap: () => context.push('/board'),
          ),
          _Item(
            icon: LucideIcons.calendar,
            label: 'Calendar',
            detail: 'Due dates, reminders and who is away',
            enabled: hasOrg,
            onTap: () => context.push('/calendar'),
          ),
          _Item(
            icon: LucideIcons.timer,
            label: 'Time',
            detail: 'What you logged, and when',
            enabled: hasOrg,
            onTap: () => context.push('/time'),
          ),
          const SectionLabel('Reference'),
          _Item(
            icon: LucideIcons.bookMarked,
            label: 'Knowledge base',
            detail: 'Books and articles',
            enabled: hasOrg,
            onTap: () => context.push('/kb'),
          ),
          _Item(
            icon: LucideIcons.bookmark,
            label: 'Bookmarks',
            detail: 'Links the team keeps',
            enabled: hasOrg,
            onTap: () => context.push('/bookmarks'),
          ),
          const SectionLabel('You'),
          _Item(
            icon: LucideIcons.settings,
            label: 'Settings',
            detail: 'Profile, instances, two-factor',
            onTap: () => context.push('/settings'),
          ),
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.label,
    required this.onTap,
    this.detail,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.lg,
              vertical: Gap.md,
            ),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: context.colors.border)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: context.colors.foreground),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: context.texts.p.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (detail != null)
                        Text(detail!, style: context.texts.muted),
                    ],
                  ),
                ),
                Icon(
                  LucideIcons.chevronRight,
                  size: 16,
                  color: context.colors.mutedForeground,
                ),
              ],
            ),
          ),
        ),
      );
}
