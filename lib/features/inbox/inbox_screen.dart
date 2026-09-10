import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/api/repo.dart';
import '../../core/models/models.dart';
import '../../core/org_controller.dart';
import '../../ui/format.dart';
import '../../ui/theme.dart';
import '../../ui/toast.dart';
import '../../ui/widgets/badges.dart';
import '../../ui/widgets/screen_header.dart';
import '../../ui/widgets/states.dart';
import 'inbox_providers.dart';

/// Notifications and reminders, in one place.
///
/// Both are cross-organisation and both mean "look at this" — separating them
/// into two tabs would just make people check two lists.
class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  bool _unreadOnly = false;

  @override
  Widget build(BuildContext context) {
    final notifications = ref.watch(notificationsProvider(_unreadOnly));
    final reminders = ref.watch(remindersProvider);
    final unread = ref.watch(unreadCountProvider).value ?? 0;

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: ScreenHeader(
        title: Padding(
          padding: const EdgeInsets.only(left: Gap.sm),
          child: HeaderTitle(
            'Inbox',
            subtitle: unread == 0 ? 'All read' : '$unread unread',
          ),
        ),
        actions: [
          ShadButton.ghost(
            size: ShadButtonSize.sm,
            onPressed: () => setState(() => _unreadOnly = !_unreadOnly),
            child: Text(_unreadOnly ? 'All' : 'Unread'),
          ),
          if (unread > 0)
            ShadIconButton.ghost(
              icon: const Icon(LucideIcons.mailOpen, size: 17),
              onPressed: _markAllRead,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(notificationsProvider);
          ref.invalidate(remindersProvider);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: Gap.xxl),
          children: [
            _Reminders(reminders: reminders),
            const SectionLabel('Notifications'),
            AsyncView(
              value: notifications,
              onRetry: () => ref.invalidate(notificationsProvider),
              loading: const Padding(
                padding: EdgeInsets.all(Gap.xxl),
                child: LoadingView(),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: Gap.xl),
                    child: EmptyState(
                      icon: LucideIcons.bellOff,
                      title: _unreadOnly ? 'Nothing unread' : 'No notifications',
                      message: _unreadOnly
                          ? 'You are all caught up.'
                          : 'Mentions and assignments will show up here.',
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final item in items) _NotificationRow(item: item),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markAllRead() async {
    await runGuarded(
      context,
      () => ref.read(repoProvider).markAllRead(),
      success: 'Marked all read',
    );
    ref.invalidate(notificationsProvider);
    ref.invalidate(unreadCountProvider);
  }
}

class _NotificationRow extends ConsumerWidget {
  const _NotificationRow({required this.item});

  final NotificationOut item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = item.readAt == null;
    return InkWell(
      onTap: () => _open(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.lg,
          vertical: Gap.md,
        ),
        decoration: BoxDecoration(
          color: unread
              ? context.colors.primary.withValues(alpha: 0.04)
              : Colors.transparent,
          border: Border(bottom: BorderSide(color: context.colors.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: unread ? context.colors.primary : Colors.transparent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.3,
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if ((item.body ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      Fmt.preview(item.body, max: 140),
                      style: context.texts.muted,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    Fmt.ago(item.createdAt),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: context.colors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            ShadIconButton.ghost(
              width: 28,
              height: 28,
              icon: const Icon(LucideIcons.x, size: 13),
              onPressed: () async {
                await runGuarded(
                  context,
                  () => ref.read(repoProvider).deleteNotification(item.id),
                );
                ref.invalidate(notificationsProvider);
                ref.invalidate(unreadCountProvider);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    if (item.readAt == null) {
      try {
        await ref.read(repoProvider).markRead(item.id);
        ref.invalidate(notificationsProvider);
        ref.invalidate(unreadCountProvider);
      } catch (_) {
        // Opening matters more than the read receipt.
      }
    }
    final taskId = _taskIdFrom(item.linkPath);
    if (taskId != null && context.mounted) context.push('/task/$taskId');
  }

  /// Notifications carry a web path like `/o/<slug>/tasks/<id>`; the task id is
  /// the only part this app can route on.
  static String? _taskIdFrom(String? linkPath) {
    if (linkPath == null) return null;
    final match = RegExp(
      r'/tasks?/([0-9a-fA-F-]{16,})',
    ).firstMatch(linkPath);
    return match?.group(1);
  }
}

class _Reminders extends ConsumerWidget {
  const _Reminders({required this.reminders});

  final AsyncValue<List<ReminderOut>> reminders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = reminders.value ?? const <ReminderOut>[];
    if (items.isEmpty) return const SizedBox.shrink();
    final overdue = items.where((r) => r.overdue).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          'Reminders',
          trailing: overdue == 0 ? null : CountBadge(overdue, emphasised: true),
        ),
        for (final reminder in items)
          InkWell(
            onTap: reminder.taskId == null
                ? null
                : () => context.push('/task/${reminder.taskId}'),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.lg,
                vertical: Gap.md,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: context.colors.border),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.alarmClock,
                    size: 15,
                    color: reminder.overdue
                        ? context.colors.destructive
                        : context.colors.mutedForeground,
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reminder.title ?? reminder.taskTitle ?? 'Reminder',
                          maxLines: 2,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if ((reminder.note ?? '').isNotEmpty)
                          Text(reminder.note!, style: context.texts.muted),
                        const SizedBox(height: 3),
                        // A Wrap: reminders are cross-organisation, so the
                        // date and the organisation's name both belong here
                        // and neither fits beside the other on a small phone.
                        Wrap(
                          spacing: Gap.sm,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            DueChip(
                              reminder.remindOn,
                              icon: LucideIcons.bell,
                            ),
                            if (reminder.organisationName != null)
                              Text(
                                reminder.organisationName!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: context.colors.mutedForeground,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  ShadIconButton.ghost(
                    width: 30,
                    height: 30,
                    icon: const Icon(LucideIcons.check, size: 15),
                    onPressed: () async {
                      await runGuarded(
                        context,
                        () => ref.read(repoProvider).updateReminder(
                              reminder.id,
                              const ReminderUpdate(done: true),
                            ),
                        success: 'Done',
                      );
                      ref.invalidate(remindersProvider);
                    },
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, 0),
          child: ShadButton.ghost(
            size: ShadButtonSize.sm,
            onPressed: () => _addReminder(context, ref),
            leading: const Icon(LucideIcons.plus, size: 14),
            child: const Text('New reminder'),
          ),
        ),
      ],
    );
  }

  Future<void> _addReminder(BuildContext context, WidgetRef ref) async {
    final orgId = ref.read(currentOrgIdProvider);
    if (orgId == null) {
      showToast(context, 'Pick an organisation first');
      return;
    }
    final controller = TextEditingController();
    final title = await showShadDialog<String>(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('New reminder'),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ShadButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Next'),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.md),
          child: ShadInputFormField(
            controller: controller,
            label: const Text('Remind me to'),
            autofocus: true,
            onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
          ),
        ),
      ),
    );
    if (title == null || title.isEmpty || !context.mounted) return;

    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: DateTime(now.year + 3),
      helpText: 'Remind me on',
    );
    if (date == null || !context.mounted) return;

    await runGuarded(
      context,
      () => ref.read(repoProvider).createStandaloneReminder(
            orgId,
            StandaloneReminderIn(remindOn: date, title: title),
          ),
      success: 'Reminder set for ${Fmt.date(date)}',
    );
    ref.invalidate(remindersProvider);
  }
}
