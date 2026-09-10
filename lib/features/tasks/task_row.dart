import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/models/models.dart';
import '../../core/org_controller.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/badges.dart';

/// One task in a list.
///
/// The layout is deliberately three lines at most: a priority rail, the title,
/// and a metadata line that only shows what is actually set. Rows in a task
/// list are scanned, not read, so anything that is merely *available* stays
/// off and only what changes a decision — who it waits on, when it is due,
/// which project — earns a place.
class TaskRow extends ConsumerWidget {
  const TaskRow({
    super.key,
    required this.task,
    required this.onTap,
    this.onToggleClosed,
    this.showProject = true,
    this.trailing,
  });

  final TaskOut task;
  final VoidCallback onTap;
  final VoidCallback? onToggleClosed;
  final bool showProject;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waitingOnMe = ref.watch(isMeProvider(task.actionRequired?.id));
    final closed = !task.isOpen;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.lg,
          vertical: Gap.md,
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.colors.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 34,
              child: PriorityRail(task.priority),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (task.isPinned) ...[
                        Icon(
                          LucideIcons.pin,
                          size: 12,
                          color: context.colors.mutedForeground,
                        ),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          task.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            height: 1.3,
                            fontWeight: waitingOnMe
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: closed
                                ? context.colors.mutedForeground
                                : context.colors.foreground,
                            decoration:
                                closed ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: Gap.md,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusPill(task.status, compact: true),
                      if (task.actionRequired != null || waitingOnMe)
                        ActionRequiredChip(
                          person: task.actionRequired,
                          isMe: waitingOnMe,
                        ),
                      if (task.dueOn != null) DueChip(task.dueOn!),
                      if (showProject && task.projectName != null)
                        _Meta(
                          icon: LucideIcons.folder,
                          text: task.projectName!,
                        ),
                      for (final tag in task.tags.take(2)) TagChip(tag),
                      if (task.tags.length > 2)
                        Text(
                          '+${task.tags.length - 2}',
                          style: context.texts.small.copyWith(
                            color: context.colors.mutedForeground,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: Gap.sm),
              trailing!,
            ] else if (onToggleClosed != null && task.canClose) ...[
              const SizedBox(width: Gap.sm),
              // The flags are resolved server-side; a control the flags deny
              // is hidden rather than shown to 403, which is the product's own
              // rule and saves reimplementing the access model here.
              ShadIconButton.ghost(
                width: 30,
                height: 30,
                icon: Icon(
                  closed ? LucideIcons.rotateCcw : LucideIcons.check,
                  size: 16,
                ),
                onPressed: onToggleClosed,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: context.colors.mutedForeground),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: context.colors.mutedForeground,
              ),
            ),
          ),
        ],
      );
}

/// A compact row for the places that list tasks without the full metadata —
/// dashboards, planner buckets, search results.
class CompactTaskRow extends StatelessWidget {
  const CompactTaskRow({
    super.key,
    required this.title,
    required this.onTap,
    this.status,
    this.priority,
    this.subtitle,
    this.dueOn,
    this.trailing,
    this.dimmed = false,
  });

  final String title;
  final VoidCallback onTap;
  final String? status;
  final String? priority;
  final String? subtitle;
  final DateTime? dueOn;
  final Widget? trailing;
  final bool dimmed;

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
              if (priority != null) ...[
                PriorityDot(priority!, size: 7),
                const SizedBox(width: Gap.sm + 2),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: dimmed
                            ? context.colors.mutedForeground
                            : context.colors.foreground,
                        decoration: dimmed ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (subtitle != null || dueOn != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        // A Wrap: at a large text scale a project name and a
                        // due date will not share one line on a small phone,
                        // and the due date is the half worth keeping visible.
                        child: Wrap(
                          spacing: Gap.sm,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (subtitle != null)
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 190),
                                child: Text(
                                  subtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: context.colors.mutedForeground,
                                  ),
                                ),
                              ),
                            if (dueOn != null) DueChip(dueOn!),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (status != null) ...[
                const SizedBox(width: Gap.sm),
                StatusPill(status!, compact: true),
              ],
              ?trailing,
            ],
          ),
        ),
      );
}
