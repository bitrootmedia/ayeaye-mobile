import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/api/repo.dart';
import '../../core/models/models.dart';
import '../../core/org_controller.dart';
import '../../ui/format.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/screen_header.dart';
import '../../ui/widgets/states.dart';
import '../tasks/task_row.dart';

/// The month being viewed, as a first-of-month date.
final _monthProvider = NotifierProvider<_MonthController, DateTime>(
  _MonthController.new,
);

class _MonthController extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  void shift(int months) =>
      state = DateTime(state.year, state.month + months);

  void reset() {
    final now = DateTime.now();
    state = DateTime(now.year, now.month);
  }
}

final calendarProvider = FutureProvider<CalendarOut>((ref) async {
  final orgId = ref.watch(currentOrgIdProvider);
  final month = ref.watch(_monthProvider);
  if (orgId == null) {
    return const CalendarOut(tasks: [], reminders: [], away: []);
  }
  // The endpoint takes an explicit range, so ask for exactly the month shown.
  final start = DateTime(month.year, month.month);
  final end = DateTime(month.year, month.month + 1, 0);
  return ref.watch(repoProvider).calendar(orgId, start: start, end: end);
});

/// The calendar as an agenda, not a grid.
///
/// A month grid on a phone gives each day about forty pixels, which is enough
/// for a dot and nothing else. An agenda grouped by day shows what is actually
/// happening and still scrolls a month in a couple of flicks.
class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(_monthProvider);
    final calendar = ref.watch(calendarProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: ScreenHeader(
        leading: const HeaderBack(),
        title: HeaderTitle('Calendar', subtitle: Fmt.monthYear(month)),
        actions: [
          ShadIconButton.ghost(
            icon: const Icon(LucideIcons.chevronLeft, size: 18),
            onPressed: () => ref.read(_monthProvider.notifier).shift(-1),
          ),
          ShadButton.ghost(
            size: ShadButtonSize.sm,
            onPressed: () => ref.read(_monthProvider.notifier).reset(),
            child: const Text('Today'),
          ),
          ShadIconButton.ghost(
            icon: const Icon(LucideIcons.chevronRight, size: 18),
            onPressed: () => ref.read(_monthProvider.notifier).shift(1),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(calendarProvider),
        child: AsyncView(
          value: calendar,
          onRetry: () => ref.invalidate(calendarProvider),
          data: (data) => _Agenda(data: data, month: month),
        ),
      ),
    );
  }
}

/// One day's worth of everything.
class _DayEntries {
  _DayEntries(this.day);

  final DateTime day;
  final List<CalendarTaskOut> tasks = [];
  final List<CalendarReminderOut> reminders = [];
  final List<CalendarAbsenceOut> away = [];

  bool get isEmpty => tasks.isEmpty && reminders.isEmpty && away.isEmpty;
}

class _Agenda extends StatelessWidget {
  const _Agenda({required this.data, required this.month});

  final CalendarOut data;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final byDay = <String, _DayEntries>{};

    _DayEntries slot(DateTime date) {
      final key = '${date.year}-${date.month}-${date.day}';
      return byDay.putIfAbsent(
        key,
        () => _DayEntries(DateTime(date.year, date.month, date.day)),
      );
    }

    for (final task in data.tasks) {
      slot(task.dueOn).tasks.add(task);
    }
    for (final reminder in data.reminders) {
      slot(reminder.remindOn).reminders.add(reminder);
    }
    // An absence spans days; showing it on its first day in range is enough to
    // answer "who is out this month" without repeating it fourteen times.
    for (final absence in data.away) {
      slot(absence.startsOn).away.add(absence);
    }

    final days = byDay.values.where((d) => !d.isEmpty).toList()
      ..sort((a, b) => a.day.compareTo(b.day));

    if (days.isEmpty) {
      return CustomScrollView(
        slivers: [
          SliverFillRemaining(
            child: EmptyState(
              icon: LucideIcons.calendar,
              title: 'Nothing in ${Fmt.monthYear(month)}',
              message: 'No due dates, reminders or absences this month.',
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: Gap.xxl),
      children: [
        for (final day in days) _DaySection(entries: day),
      ],
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({required this.entries});

  final _DayEntries entries;

  @override
  Widget build(BuildContext context) {
    final isToday = Fmt.isToday(entries.day);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.sm),
          child: Row(
            children: [
              Text(
                Fmt.weekday(entries.day),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: isToday
                      ? context.colors.primary
                      : context.colors.foreground,
                ),
              ),
              if (isToday) ...[
                const SizedBox(width: Gap.sm),
                ShadBadge(child: const Text('Today')),
              ],
            ],
          ),
        ),
        for (final task in entries.tasks)
          CompactTaskRow(
            title: task.title,
            status: task.status,
            priority: task.priority,
            subtitle: task.projectName,
            onTap: () => context.push('/task/${task.id}'),
          ),
        for (final reminder in entries.reminders)
          _SimpleRow(
            icon: LucideIcons.bell,
            title: reminder.title ?? reminder.taskTitle ?? 'Reminder',
            subtitle: reminder.note,
            onTap: reminder.taskId == null
                ? null
                : () => context.push('/task/${reminder.taskId}'),
          ),
        for (final absence in entries.away)
          _SimpleRow(
            icon: LucideIcons.palmtree,
            title:
                '${Fmt.person(absence.person?.displayName, absence.person?.email)} away',
            subtitle: absence.endsOn == absence.startsOn
                ? absence.note
                : 'until ${Fmt.date(absence.endsOn)}'
                    '${absence.note == null ? '' : ' · ${absence.note}'}',
          ),
      ],
    );
  }
}

class _SimpleRow extends StatelessWidget {
  const _SimpleRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.lg,
            vertical: Gap.sm + 2,
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: context.colors.mutedForeground),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 13.5),
                    ),
                    if ((subtitle ?? '').isNotEmpty)
                      Text(subtitle!, style: context.texts.muted),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
