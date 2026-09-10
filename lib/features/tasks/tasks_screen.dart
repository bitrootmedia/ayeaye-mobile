import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/api/repo.dart';
import '../../core/org_controller.dart';
import '../../ui/theme.dart';
import '../../ui/toast.dart';
import '../../ui/widgets/screen_header.dart';
import '../../ui/widgets/states.dart';
import '../shell/org_switcher.dart';
import 'task_editor.dart';
import 'task_filter_sheet.dart';
import 'task_providers.dart';
import 'task_row.dart';
import 'task_search.dart';

/// The task list.
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll.removeListener(_maybeLoadMore);
    _scroll.dispose();
    super.dispose();
  }

  /// Fetch the next page before the person reaches the bottom, so scrolling
  /// never visibly stalls.
  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 600) {
      ref.read(taskListProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final orgId = ref.watch(currentOrgIdProvider);
    final list = ref.watch(taskListProvider);
    final filters = ref.watch(taskFiltersProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: ScreenHeader(
        title: const OrgSwitcherButton(),
        actions: [
          ShadIconButton.ghost(
            icon: const Icon(LucideIcons.search, size: 18),
            onPressed: orgId == null ? null : () => showTaskSearch(context),
          ),
          const FilterButton(),
        ],
      ),
      floatingActionButton: orgId == null
          ? null
          : FloatingActionButton(
              onPressed: () => showTaskEditor(context, ref),
              backgroundColor: context.colors.primary,
              foregroundColor: context.colors.primaryForeground,
              child: const Icon(LucideIcons.plus),
            ),
      body: orgId == null
          ? const _NoOrganisation()
          : RefreshIndicator(
              onRefresh: () => ref.read(taskListProvider.notifier).refresh(),
              child: AsyncView(
                value: list,
                onRetry: () => ref.invalidate(taskListProvider),
                data: (state) {
                  if (state.items.isEmpty) {
                    return CustomScrollView(
                      slivers: [
                        SliverFillRemaining(
                          child: EmptyState(
                            icon: LucideIcons.listTodo,
                            title: filters.isClean
                                ? 'No tasks yet'
                                : 'Nothing matches these filters',
                            message: filters.isClean
                                ? 'Create the first one and it will show up here.'
                                : 'Try clearing a filter or two.',
                            action: filters.isClean
                                ? ShadButton(
                                    onPressed: () => showTaskEditor(context, ref),
                                    leading:
                                        const Icon(LucideIcons.plus, size: 16),
                                    child: const Text('New task'),
                                  )
                                : ShadButton.outline(
                                    onPressed: () => ref
                                        .read(taskFiltersProvider.notifier)
                                        .clear(),
                                    child: const Text('Clear filters'),
                                  ),
                          ),
                        ),
                      ],
                    );
                  }

                  return ListView.builder(
                    controller: _scroll,
                    // One extra row: the count line, or the next-page spinner.
                    itemCount: state.items.length + 1,
                    itemBuilder: (context, index) {
                      if (index == state.items.length) {
                        return _ListFooter(
                          shown: state.items.length,
                          total: state.total,
                          loading: state.loadingMore,
                        );
                      }
                      final task = state.items[index];
                      return TaskRow(
                        task: task,
                        onTap: () => context.push('/task/${task.id}'),
                        onToggleClosed: () => _toggleClosed(orgId, task.id, task.isOpen),
                      );
                    },
                  );
                },
              ),
            ),
    );
  }

  Future<void> _toggleClosed(String orgId, String taskId, bool isOpen) async {
    final notifier = ref.read(taskListProvider.notifier);
    final ok = await runGuarded(
      context,
      () => ref.read(repoProvider).setClosed(orgId, taskId, isOpen),
      success: isOpen ? 'Closed' : 'Reopened',
    );
    if (!ok) return;
    final filters = ref.read(taskFiltersProvider);
    if (isOpen && !filters.includeClosed) {
      // It no longer belongs in this list, so take it out rather than leaving
      // a struck-through row the next refresh would drop anyway.
      notifier.remove(taskId);
    } else {
      await notifier.refresh();
    }
    ref.invalidate(taskProvider(taskId));
  }
}

class _ListFooter extends StatelessWidget {
  const _ListFooter({
    required this.shown,
    required this.total,
    required this.loading,
  });

  final int shown;
  final int total;
  final bool loading;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.xl),
        child: Center(
          child: loading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.colors.mutedForeground,
                  ),
                )
              : Text(
                  shown >= total
                      ? '$total ${total == 1 ? 'task' : 'tasks'}'
                      : '$shown of $total',
                  style: context.texts.muted,
                ),
        ),
      );
}

class _NoOrganisation extends ConsumerWidget {
  const _NoOrganisation();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgs = ref.watch(organisationsProvider);
    return AsyncView(
      value: orgs,
      onRetry: () => ref.invalidate(organisationsProvider),
      data: (list) => EmptyState(
        icon: LucideIcons.building2,
        title: list.isEmpty ? 'No organisations yet' : 'Pick an organisation',
        message: list.isEmpty
            ? 'Tasks live inside an organisation. Create one to get started, '
                'or ask a colleague to invite you.'
            : 'Choose which organisation to work in.',
        action: list.isEmpty
            ? ShadButton(
                onPressed: () => _createOrganisation(context, ref),
                leading: const Icon(LucideIcons.plus, size: 16),
                child: const Text('Create one'),
              )
            : ShadButton.outline(
                onPressed: () => showContextSwitcher(context),
                child: const Text('Choose'),
              ),
      ),
    );
  }

  Future<void> _createOrganisation(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showShadDialog<String>(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('New organisation'),
        description: const Text(
          'Projects, tasks and your knowledge base all live inside an '
          'organisation.',
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ShadButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.md),
          child: ShadInputFormField(
            controller: controller,
            label: const Text('Name'),
            placeholder: const Text('Acme Ltd'),
            autofocus: true,
            onSubmitted: (value) =>
                Navigator.of(context).pop(value.trim()),
          ),
        ),
      ),
    );
    if (name == null || name.isEmpty || !context.mounted) return;
    await runGuarded(
      context,
      () async {
        final org = await ref.read(repoProvider).createOrganisation(name);
        ref.invalidate(organisationsProvider);
        ref.read(currentOrgIdProvider.notifier).select(org.id);
      },
      success: 'Organisation created',
    );
  }
}
