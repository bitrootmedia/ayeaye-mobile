import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/api/repo.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/models.dart';
import '../../core/org_controller.dart';
import '../../core/realtime/ws_client.dart';
import '../../ui/format.dart';
import '../../ui/theme.dart';
import '../../ui/toast.dart';
import '../../ui/widgets/badges.dart';
import '../../ui/widgets/rich_body.dart';
import '../../ui/widgets/screen_header.dart';
import '../../ui/widgets/states.dart';
import '../comments/comment_thread.dart';
import '../timer/timer_providers.dart';
import 'task_editor.dart';
import 'task_providers.dart';

/// Everything about one task, plus its conversation.
class TaskDetailScreen extends ConsumerStatefulWidget {
  const TaskDetailScreen({super.key, required this.taskId});

  final String taskId;

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  StreamSubscription<Set<String>>? _nudges;
  RealtimeClient? _realtime;
  Watch? _watch;

  @override
  void initState() {
    super.initState();
    // Watch this task on the socket. Events carry no bodies, so a nudge means
    // "refetch over HTTP" — and a 404 on that refetch is how we discover
    // access was revoked.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final realtime = ref.read(realtimeProvider);
      if (realtime == null) return;
      final watch = Watch.task(widget.taskId);
      realtime.watch(watch);
      _realtime = realtime;
      _watch = watch;
      _nudges = realtime.nudges.listen((ids) {
        if (!mounted || !ids.contains(widget.taskId)) return;
        ref.invalidate(taskProvider(widget.taskId));
        ref.invalidate(taskCommentsProvider(widget.taskId));
      });
    });
  }

  @override
  void dispose() {
    _nudges?.cancel();
    final watch = _watch;
    if (watch != null) _realtime?.unwatch(watch);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = ref.watch(taskProvider(widget.taskId));

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: ScreenHeader(
        leading: const HeaderBack(),
        title: task.value == null
            ? const HeaderTitle('Task')
            : HeaderTitle(
                task.value!.title,
                subtitle: task.value!.projectName,
              ),
        actions: [
          if (task.value != null) _TaskMenu(task: task.value!),
        ],
      ),
      body: AsyncView(
        value: task,
        onRetry: () => ref.invalidate(taskProvider(widget.taskId)),
        data: (data) => Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(taskProvider(widget.taskId));
                  ref.invalidate(taskCommentsProvider(widget.taskId));
                  ref.invalidate(taskFilesProvider(widget.taskId));
                  ref.invalidate(taskChecklistsProvider(widget.taskId));
                },
                child: ListView(
                  children: [
                    _Summary(task: data),
                    _Description(task: data),
                    _Checklists(taskId: widget.taskId),
                    _Files(taskId: widget.taskId),
                    const SectionLabel('Conversation'),
                    CommentThread(taskId: widget.taskId),
                    const SizedBox(height: Gap.xl),
                  ],
                ),
              ),
            ),
            _CommentComposerHost(taskId: widget.taskId),
          ],
        ),
      ),
    );
  }
}

/// Pulled out so the composer only rebuilds on the thread's `can_post`, not on
/// every task field.
class _CommentComposerHost extends ConsumerWidget {
  const _CommentComposerHost({required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canPost =
        ref.watch(taskCommentsProvider(taskId)).value?.canPost ?? true;
    return CommentComposer(taskId: taskId, canPost: canPost);
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({required this.task});

  final TaskOut task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waitingOnMe = ref.watch(isMeProvider(task.actionRequired?.id));

    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        color: context.colors.card,
        border: Border(bottom: BorderSide(color: context.colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task.title,
            style: TextStyle(
              fontSize: 19,
              height: 1.28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: context.colors.foreground,
              decoration: task.isOpen ? null : TextDecoration.lineThrough,
            ),
          ),
          const SizedBox(height: Gap.md),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusPill(task.status),
              PriorityLabel(task.priority),
              if (!task.isOpen)
                ShadBadge.secondary(child: const Text('Closed')),
              if (task.isHidden)
                ShadBadge.outline(child: const Text('Hidden')),
              if (task.recurrence?.active == true)
                ShadBadge.outline(
                  child: Text(
                    'Repeats every ${task.recurrence!.intervalCount} '
                    '${task.recurrence!.intervalUnit}',
                  ),
                ),
            ],
          ),
          const SizedBox(height: Gap.lg),
          _Row(
            icon: LucideIcons.userCheck,
            label: 'Waiting on',
            child: ActionRequiredChip(
              person: task.actionRequired,
              isMe: waitingOnMe,
            ),
          ),
          _Row(
            icon: LucideIcons.user,
            label: 'Owner',
            child: Text(
              task.owner == null
                  ? 'Unassigned'
                  : Fmt.person(task.owner!.displayName, task.owner!.email),
              style: context.texts.small,
            ),
          ),
          if (task.dueOn != null)
            _Row(
              icon: LucideIcons.calendar,
              label: 'Due',
              child: DueChip(task.dueOn!),
            ),
          if (task.estimatedHours != null)
            _Row(
              icon: LucideIcons.hourglass,
              label: 'Estimate',
              child: Text(
                '${task.estimatedHours} h',
                style: context.texts.small,
              ),
            ),
          if (task.projectName != null)
            _Row(
              icon: LucideIcons.folder,
              label: 'Project',
              child: Text(task.projectName!, style: context.texts.small),
            ),
          if (task.tags.isNotEmpty)
            _Row(
              icon: LucideIcons.tag,
              label: 'Tags',
              child: Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [for (final tag in task.tags) TagChip(tag)],
              ),
            ),
          _Row(
            icon: LucideIcons.clock,
            label: 'Updated',
            child: Text(Fmt.agoLong(task.updatedAt), style: context.texts.small),
          ),
          const SizedBox(height: Gap.md),
          _QuickActions(task: task),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.child});

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.sm + 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: context.colors.mutedForeground),
            const SizedBox(width: Gap.sm),
            SizedBox(
              width: 82,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: context.colors.mutedForeground,
                ),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      );
}

/// The three things worth doing without opening a menu.
class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.task});

  final TaskOut task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final waitingOnMe = ref.watch(isMeProvider(task.actionRequired?.id));
    final timer = ref.watch(timerProvider).value;
    final runningHere = timer?.entry?.taskId == task.id;

    // A Wrap rather than flexed buttons: ShadButton sizes to its content and
    // ignores a tight slot, so an Expanded one overflows on a narrow screen.
    return Wrap(
      spacing: Gap.sm,
      runSpacing: Gap.sm,
      children: [
        if (!waitingOnMe && me != null)
          ShadButton.secondary(
            size: ShadButtonSize.sm,
            onPressed: () => _take(context, ref, me.userId),
            leading: const Icon(LucideIcons.userCheck, size: 14),
            child: const Text("I'll take it"),
          ),
        if (runningHere)
          ShadButton.destructive(
            size: ShadButtonSize.sm,
            onPressed: () => _stopTimer(context, ref),
            leading: const Icon(LucideIcons.square, size: 13),
            child: const Text('Stop timer'),
          )
        else
          ShadButton.outline(
            size: ShadButtonSize.sm,
            onPressed: () => _startTimer(context, ref),
            leading: const Icon(LucideIcons.play, size: 13),
            child: const Text('Start timer'),
          ),
        if (task.canClose)
          ShadIconButton.outline(
            width: 32,
            height: 32,
            icon: Icon(
              task.isOpen ? LucideIcons.check : LucideIcons.rotateCcw,
              size: 15,
            ),
            onPressed: () => _toggleClosed(context, ref),
          ),
      ],
    );
  }

  Future<void> _take(BuildContext context, WidgetRef ref, String userId) async {
    final orgId = ref.read(requireOrgIdProvider);
    await runGuarded(
      context,
      () => ref
          .read(repoProvider)
          .updateTask(orgId, task.id, {'action_required_user_id': userId}),
      success: 'Yours now',
    );
    ref.invalidate(taskProvider(task.id));
    ref.read(triageListProvider.notifier).remove(task.id);
    ref.read(taskListProvider.notifier).refresh();
  }

  Future<void> _toggleClosed(BuildContext context, WidgetRef ref) async {
    final orgId = ref.read(requireOrgIdProvider);
    await runGuarded(
      context,
      () => ref.read(repoProvider).setClosed(orgId, task.id, task.isOpen),
      success: task.isOpen ? 'Closed' : 'Reopened',
    );
    ref.invalidate(taskProvider(task.id));
    ref.read(taskListProvider.notifier).refresh();
  }

  Future<void> _startTimer(BuildContext context, WidgetRef ref) async {
    final orgId = ref.read(requireOrgIdProvider);
    await runGuarded(
      context,
      () => ref.read(repoProvider).startTimer(orgId, task.id),
      success: 'Timer running',
    );
    ref.invalidate(timerProvider);
    ref.invalidate(taskTimeProvider(task.id));
  }

  Future<void> _stopTimer(BuildContext context, WidgetRef ref) async {
    await runGuarded(
      context,
      () => ref.read(repoProvider).stopTimer(),
      success: 'Timer stopped',
    );
    ref.invalidate(timerProvider);
    ref.invalidate(taskTimeProvider(task.id));
  }
}

class _Description extends ConsumerWidget {
  const _Description({required this.task});

  final TaskOut task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if ((task.description ?? '').trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, 0),
      child: RichBody(
        task.description,
        baseUrl: ref.watch(repoProvider).api.baseUrl,
      ),
    );
  }
}

class _Checklists extends ConsumerWidget {
  const _Checklists({required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checklists = ref.watch(taskChecklistsProvider(taskId)).value;
    if (checklists == null || checklists.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final checklist in checklists) ...[
          SectionLabel(
            checklist.title,
            trailing: Text(
              '${checklist.items.where((i) => i.done).length}'
              '/${checklist.items.length}',
              style: context.texts.small.copyWith(
                color: context.colors.mutedForeground,
              ),
            ),
          ),
          for (final item in checklist.items)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.lg,
                vertical: 3,
              ),
              child: ShadCheckbox(
                value: item.done,
                onChanged: (value) => _toggle(context, ref, checklist, item, value),
                label: Text(
                  item.text,
                  style: TextStyle(
                    fontSize: 13.5,
                    decoration: item.done ? TextDecoration.lineThrough : null,
                    color: item.done
                        ? context.colors.mutedForeground
                        : context.colors.foreground,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    ChecklistOut checklist,
    ChecklistItemOut item,
    bool value,
  ) async {
    final orgId = ref.read(requireOrgIdProvider);
    await runGuarded(
      context,
      () => ref.read(repoProvider).setChecklistItemDone(
            orgId,
            taskId,
            checklist.id,
            item.id,
            value,
          ),
    );
    ref.invalidate(taskChecklistsProvider(taskId));
  }
}

class _Files extends ConsumerWidget {
  const _Files({required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files = ref.watch(taskFilesProvider(taskId)).value;
    if (files == null || files.isEmpty) return const SizedBox.shrink();

    // Files that arrived as comment attachments are already visible in the
    // thread, so listing them twice is just noise.
    final own = files.where((f) => !f.fromComment).toList();
    if (own.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Files'),
        for (final file in own)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.lg,
              vertical: Gap.xs,
            ),
            child: AttachmentTile(
              attachment: AttachmentOut(
                id: file.id,
                filename: file.filename,
                contentType: file.contentType,
                sizeBytes: file.sizeBytes,
                url: file.url,
                thumbnailUrl: file.thumbnailUrl,
              ),
            ),
          ),
      ],
    );
  }
}

/// The overflow menu: everything that is not a daily action.
class _TaskMenu extends ConsumerWidget {
  const _TaskMenu({required this.task});

  final TaskOut task;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ShadIconButton.ghost(
        icon: const Icon(LucideIcons.ellipsisVertical, size: 18),
        onPressed: () => showShadSheet<void>(
          context: context,
          side: ShadSheetSide.bottom,
          builder: (sheetContext) => ShadSheet(
            title: const Text('Task'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _MenuItem(
                  icon: LucideIcons.pencil,
                  label: 'Edit task',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    showTaskEditor(context, ref, task: task);
                  },
                ),
                _MenuItem(
                  icon: task.isPinned ? LucideIcons.pinOff : LucideIcons.pin,
                  label: task.isPinned ? 'Unpin' : 'Pin to dashboard',
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    final orgId = ref.read(requireOrgIdProvider);
                    await runGuarded(
                      context,
                      () => ref
                          .read(repoProvider)
                          .setPinned(orgId, task.id, !task.isPinned),
                      success: task.isPinned ? 'Unpinned' : 'Pinned',
                    );
                    ref.invalidate(taskProvider(task.id));
                  },
                ),
                _MenuItem(
                  icon: LucideIcons.alarmClock,
                  label: 'Add a reminder',
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _addReminder(context, ref);
                  },
                ),
                if (task.canHide)
                  _MenuItem(
                    icon: task.isHidden ? LucideIcons.eye : LucideIcons.eyeOff,
                    label: task.isHidden ? 'Unhide' : 'Hide from the board',
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      final orgId = ref.read(requireOrgIdProvider);
                      await runGuarded(
                        context,
                        () => ref
                            .read(repoProvider)
                            .setHidden(orgId, task.id, !task.isHidden),
                        success: task.isHidden ? 'Visible again' : 'Hidden',
                      );
                      ref.invalidate(taskProvider(task.id));
                    },
                  ),
              ],
            ),
          ),
        ),
      );

  Future<void> _addReminder(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: DateTime(now.year + 3),
      helpText: 'Remind me on',
    );
    if (date == null || !context.mounted) return;
    final orgId = ref.read(requireOrgIdProvider);
    await runGuarded(
      context,
      () => ref
          .read(repoProvider)
          .addTaskReminder(orgId, task.id, ReminderIn(remindOn: date)),
      success: 'Reminder set for ${Fmt.date(date)}',
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.md),
          child: Row(
            children: [
              Icon(icon, size: 17, color: context.colors.foreground),
              const SizedBox(width: Gap.md),
              Text(label, style: context.texts.p),
            ],
          ),
        ),
      );
}
