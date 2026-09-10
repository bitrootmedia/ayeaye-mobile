import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/models/enums.dart';
import '../../core/org_controller.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/badges.dart';
import 'task_providers.dart';

/// The filter and sort sheet.
///
/// Every control here maps to one query parameter, because the server does the
/// filtering — so what looks like a lot of options is really just the endpoint
/// made visible.
Future<void> showTaskFilterSheet(BuildContext context) => showShadSheet<void>(
      context: context,
      side: ShadSheetSide.bottom,
      builder: (context) => const _FilterSheet(),
    );

class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(taskFiltersProvider);
    final controller = ref.read(taskFiltersProvider.notifier);
    final projects = ref.watch(projectsProvider).value ?? const [];
    final tags = ref.watch(tagsProvider).value ?? const [];
    final members = ref.watch(membersProvider).value ?? const [];
    final me = ref.watch(meProvider);

    return ShadSheet(
      title: const Text('Filter & sort'),
      actions: [
        if (!filters.isClean)
          ShadButton.ghost(
            onPressed: () => controller.clear(),
            child: const Text('Clear all'),
          ),
        ShadButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.66,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Group(
                label: 'Sort by',
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final sort in TaskSort.all)
                      _Chip(
                        label: sort.label,
                        selected: filters.sortKey == sort.key,
                        // Tapping the active sort flips its direction, which is
                        // the shortest route to "oldest first".
                        trailing: filters.sortKey == sort.key
                            ? Icon(
                                filters.descending
                                    ? LucideIcons.arrowDown
                                    : LucideIcons.arrowUp,
                                size: 12,
                                color: context.colors.primary,
                              )
                            : null,
                        onTap: () => controller.setSort(sort),
                      ),
                  ],
                ),
              ),
              _Group(
                label: 'Status',
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Chip(
                      label: 'Any',
                      selected: filters.status == null,
                      onTap: () =>
                          controller.update(filters.copyWith(clearStatus: true)),
                    ),
                    for (final status in TaskStatus.all)
                      _Chip(
                        label: status.label,
                        selected: filters.status == status.key,
                        dot: status.color,
                        onTap: () => controller.update(
                          filters.copyWith(status: status.key),
                        ),
                      ),
                  ],
                ),
              ),
              _Group(
                label: 'Priority',
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Chip(
                      label: 'Any',
                      selected: filters.priority == null,
                      onTap: () => controller
                          .update(filters.copyWith(clearPriority: true)),
                    ),
                    for (final priority in TaskPriority.all)
                      _Chip(
                        label: priority.label,
                        selected: filters.priority == priority.key,
                        dot: priority.color,
                        onTap: () => controller.update(
                          filters.copyWith(priority: priority.key),
                        ),
                      ),
                  ],
                ),
              ),
              _Group(
                label: 'Waiting on',
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Chip(
                      label: 'Anyone',
                      selected: filters.actionRequiredUserId == null,
                      onTap: () => controller.update(
                        filters.copyWith(clearActionRequired: true),
                      ),
                    ),
                    if (me != null)
                      _Chip(
                        label: 'Me',
                        selected: filters.actionRequiredUserId == me.userId,
                        onTap: () => controller.update(
                          filters.copyWith(actionRequiredUserId: me.userId),
                        ),
                      ),
                    for (final member in members.where(
                      (m) => m.userId != null && m.userId != me?.userId,
                    ))
                      _Chip(
                        label: member.displayName ?? member.email ?? 'Someone',
                        selected: filters.actionRequiredUserId == member.userId,
                        onTap: () => controller.update(
                          filters.copyWith(actionRequiredUserId: member.userId),
                        ),
                      ),
                  ],
                ),
              ),
              if (projects.isNotEmpty)
                _Group(
                  label: 'Project',
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _Chip(
                        label: 'Any',
                        selected: filters.projectId == null && !filters.loose,
                        onTap: () => controller.update(
                          filters.copyWith(clearProject: true, loose: false),
                        ),
                      ),
                      _Chip(
                        label: 'No project',
                        selected: filters.loose,
                        onTap: () => controller.update(
                          filters.copyWith(loose: true, clearProject: true),
                        ),
                      ),
                      for (final project in projects)
                        _Chip(
                          label: project.name,
                          selected: filters.projectId == project.id,
                          onTap: () => controller.update(
                            filters.copyWith(
                              projectId: project.id,
                              loose: false,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (tags.isNotEmpty)
                _Group(
                  label: 'Tag',
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _Chip(
                        label: 'Any',
                        selected: filters.tagId == null,
                        onTap: () =>
                            controller.update(filters.copyWith(clearTag: true)),
                      ),
                      for (final tag in tags)
                        _Chip(
                          label: tag.name,
                          selected: filters.tagId == tag.id,
                          onTap: () => controller
                              .update(filters.copyWith(tagId: tag.id)),
                        ),
                    ],
                  ),
                ),
              _Group(
                label: 'Also show',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShadCheckbox(
                      value: filters.includeClosed,
                      onChanged: (v) =>
                          controller.update(filters.copyWith(includeClosed: v)),
                      label: const Text('Closed tasks'),
                    ),
                    const SizedBox(height: Gap.sm),
                    ShadCheckbox(
                      value: filters.includeOffBoard,
                      onChanged: (v) => controller
                          .update(filters.copyWith(includeOffBoard: v)),
                      label: const Text('Tasks tagged off-board'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
                color: context.colors.mutedForeground,
              ),
            ),
            const SizedBox(height: Gap.sm),
            child,
          ],
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.dot,
    this.trailing,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? dot;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? context.colors.primary.withValues(alpha: 0.1)
                : context.colors.card,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: selected ? context.colors.primary : context.colors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected
                      ? context.colors.primary
                      : context.colors.foreground,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 4),
                trailing!,
              ],
            ],
          ),
        ),
      );
}

/// The filter button, with a count of what is narrowing the list.
class FilterButton extends ConsumerWidget {
  const FilterButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(taskFiltersProvider).activeCount;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ShadIconButton.ghost(
          icon: const Icon(LucideIcons.slidersHorizontal, size: 18),
          onPressed: () => showTaskFilterSheet(context),
        ),
        if (count > 0)
          Positioned(right: 2, top: 2, child: CountBadge(count)),
      ],
    );
  }
}
