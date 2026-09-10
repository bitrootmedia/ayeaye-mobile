import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/api/repo.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/models.dart';
import '../../core/org_controller.dart';
import '../../ui/format.dart';
import '../../ui/theme.dart';
import '../../ui/toast.dart';
import '../../ui/widgets/screen_header.dart';
import '../../ui/widgets/states.dart';
import 'running_timer_bar.dart';
import 'timer_providers.dart';

/// Time logged over the last fortnight.
///
/// Two weeks rather than "everything": on a phone this answers "did I log
/// yesterday?" and "what did this week go on?", and both live inside a
/// fortnight.
final _timeEntriesProvider = FutureProvider<List<TimeEntryOut>>((ref) async {
  final orgId = ref.watch(currentOrgIdProvider);
  if (orgId == null) return const [];
  final now = DateTime.now();
  return ref.watch(repoProvider).timeEntries(
        orgId,
        userId: ref.watch(meProvider)?.userId,
        start: now.subtract(const Duration(days: 14)),
        end: now,
      );
});

class TimeScreen extends ConsumerWidget {
  const TimeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(_timeEntriesProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: const ScreenHeader(
        leading: HeaderBack(),
        title: HeaderTitle('Time', subtitle: 'Your last two weeks'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_timeEntriesProvider);
          ref.invalidate(timerProvider);
        },
        child: AsyncView(
          value: entries,
          onRetry: () => ref.invalidate(_timeEntriesProvider),
          data: (items) {
            final byDay = <String, List<TimeEntryOut>>{};
            for (final entry in items) {
              final day = DateTime(
                entry.startedAt.year,
                entry.startedAt.month,
                entry.startedAt.day,
              );
              byDay.putIfAbsent(day.toIso8601String(), () => []).add(entry);
            }
            final days = byDay.keys.toList()
              ..sort((a, b) => b.compareTo(a));

            return ListView(
              padding: const EdgeInsets.only(bottom: Gap.xxl),
              children: [
                const RunningTimerBar(),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: Gap.xxl),
                    child: EmptyState(
                      icon: LucideIcons.timer,
                      title: 'No time logged',
                      message: 'Start a timer from any task, or log time by '
                          'hand.',
                    ),
                  ),
                for (final day in days) ...[
                  SectionLabel(
                    Fmt.weekday(DateTime.parse(day)),
                    trailing: Text(
                      Fmt.seconds(
                        byDay[day]!.fold(0, (sum, e) => sum + e.seconds),
                      ),
                      style: context.texts.small.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (final entry in byDay[day]!) _EntryRow(entry: entry),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EntryRow extends ConsumerWidget {
  const _EntryRow({required this.entry});

  final TimeEntryOut entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) => InkWell(
        onTap: () => context.push('/task/${entry.taskId}'),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.taskTitle ?? 'Task',
                      maxLines: 2,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      [
                        Fmt.time(entry.startedAt),
                        if (entry.projectName != null) entry.projectName!,
                        if ((entry.note ?? '').isNotEmpty) entry.note!,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.muted,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Gap.sm),
              Text(
                entry.endedAt == null
                    ? 'running'
                    : Fmt.seconds(entry.seconds),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: entry.endedAt == null
                      ? context.colors.primary
                      : context.colors.foreground,
                ),
              ),
              ShadIconButton.ghost(
                width: 28,
                height: 28,
                icon: const Icon(LucideIcons.trash2, size: 13),
                onPressed: () async {
                  final orgId = ref.read(requireOrgIdProvider);
                  await runGuarded(
                    context,
                    () => ref
                        .read(repoProvider)
                        .deleteTimeEntry(orgId, entry.id),
                    success: 'Deleted',
                  );
                  ref.invalidate(_timeEntriesProvider);
                },
              ),
            ],
          ),
        ),
      );
}
