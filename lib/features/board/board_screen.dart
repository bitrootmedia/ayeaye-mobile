import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/api/repo.dart';
import '../../core/models/enums.dart';
import '../../core/models/models.dart';
import '../../core/org_controller.dart';
import '../../ui/theme.dart';
import '../../ui/toast.dart';
import '../../ui/widgets/badges.dart';
import '../../ui/widgets/screen_header.dart';
import '../../ui/widgets/states.dart';
import '../tasks/task_providers.dart';

/// How the board is grouped. Status by default, matching the endpoint's own
/// default and the web app's landing view.
final _boardGroupProvider =
    NotifierProvider<_BoardGroup, String>(_BoardGroup.new);

class _BoardGroup extends Notifier<String> {
  @override
  String build() => 'status';

  void toggle() => state = state == 'status' ? 'priority' : 'status';
}

final boardProvider = FutureProvider<BoardOut>((ref) async {
  final orgId = ref.watch(currentOrgIdProvider);
  final group = ref.watch(_boardGroupProvider);
  if (orgId == null) {
    return const BoardOut(groupBy: 'status', perGroup: 0, columns: []);
  }
  return ref.watch(repoProvider).board(orgId, group: group);
});

/// The board, as horizontally paged columns.
///
/// The board has its own endpoint and **cannot be paged**: rows come back
/// priority-first, so taking the first N of a large set would fill every
/// column with criticals and leave the rest empty. It bounds each column
/// server-side and reports each column's real size — which is why a column
/// header can honestly say "12 of 40".
class BoardScreen extends ConsumerWidget {
  const BoardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(boardProvider);
    final group = ref.watch(_boardGroupProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: ScreenHeader(
        leading: const HeaderBack(),
        title: HeaderTitle(
          'Board',
          subtitle: 'Grouped by ${group == 'status' ? 'status' : 'priority'}',
        ),
        actions: [
          ShadButton.ghost(
            size: ShadButtonSize.sm,
            onPressed: () => ref.read(_boardGroupProvider.notifier).toggle(),
            child: Text(group == 'status' ? 'By priority' : 'By status'),
          ),
        ],
      ),
      body: AsyncView(
        value: board,
        onRetry: () => ref.invalidate(boardProvider),
        data: (data) {
          if (data.columns.isEmpty) {
            return const EmptyState(
              icon: LucideIcons.columns3,
              title: 'Nothing on the board',
              message: 'Open tasks appear here grouped into columns.',
            );
          }
          return ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.md,
              vertical: Gap.md,
            ),
            children: [
              for (final column in data.columns)
                _Column(column: column, groupBy: data.groupBy),
            ],
          );
        },
      ),
    );
  }
}

class _Column extends ConsumerWidget {
  const _Column({required this.column, required this.groupBy});

  final BoardColumn column;
  final String groupBy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (label, color) = groupBy == 'priority'
        ? (
            TaskPriority.of(column.key).label,
            TaskPriority.of(column.key).color,
          )
        : (TaskStatus.of(column.key).label, TaskStatus.of(column.key).color);

    return Container(
      width: 290,
      margin: const EdgeInsets.only(right: Gap.md),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container
          (
            padding: const EdgeInsets.all(Gap.md),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: context.colors.border),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    label,
                    style: context.texts.p.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  // The column reports its real size, so say so when we are
                  // only showing part of it.
                  column.tasks.length < column.total
                      ? '${column.tasks.length} of ${column.total}'
                      : '${column.total}',
                  style: context.texts.small.copyWith(
                    color: context.colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: column.tasks.isEmpty
                ? Center(
                    child: Text('Empty', style: context.texts.muted),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(Gap.sm),
                    itemCount: column.tasks.length,
                    itemBuilder: (context, index) =>
                        _Card(task: column.tasks[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Card extends ConsumerWidget {
  const _Card({required this.task});

  final TaskOut task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waitingOnMe = ref.watch(isMeProvider(task.actionRequired?.id));
    return GestureDetector(
      onTap: () => context.push('/task/${task.id}'),
      onLongPress: () => _quickMove(context, ref),
      child: Container(
        margin: const EdgeInsets.only(bottom: Gap.sm),
        padding: const EdgeInsets.all(Gap.md),
        decoration: BoxDecoration(
          color: context.colors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PriorityDot(task.priority, size: 7),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    task.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.3,
                      fontWeight:
                          waitingOnMe ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            if (task.actionRequired != null || task.dueOn != null) ...[
              const SizedBox(height: Gap.sm),
              Wrap(
                spacing: Gap.sm,
                runSpacing: 4,
                children: [
                  if (task.actionRequired != null)
                    ActionRequiredChip(
                      person: task.actionRequired,
                      isMe: waitingOnMe,
                    ),
                  if (task.dueOn != null) DueChip(task.dueOn!),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Long-press to move a card: dragging between horizontally-scrolling
  /// columns on a phone is a coin toss, so the gesture opens a list instead.
  Future<void> _quickMove(BuildContext context, WidgetRef ref) async {
    final status = await showShadSheet<String>(
      context: context,
      side: ShadSheetSide.bottom,
      builder: (context) => ShadSheet(
        title: Text(task.title),
        description: const Text('Move to status'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final s in TaskStatus.all)
              InkWell(
                onTap: () => Navigator.of(context).pop(s.key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.md),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: s.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: Gap.md),
                      Expanded(child: Text(s.label, style: context.texts.p)),
                      if (s.key == task.status)
                        Icon(
                          LucideIcons.check,
                          size: 16,
                          color: context.colors.primary,
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (status == null || status == task.status || !context.mounted) return;
    final orgId = ref.read(requireOrgIdProvider);
    await runGuarded(
      context,
      () => ref
          .read(repoProvider)
          .updateTask(orgId, task.id, {'status': status}),
      success: 'Moved',
    );
    ref.invalidate(boardProvider);
    ref.invalidate(taskProvider(task.id));
  }
}
