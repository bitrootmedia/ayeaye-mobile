import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/repo.dart';
import '../../core/models/enums.dart';
import '../../core/models/models.dart';
import '../../core/org_controller.dart';
import '../../core/prefs.dart';

/// What a task list is currently showing.
///
/// Filtering and sorting are the server's job, but the *choice* is app state
/// that has to survive a restart — the web app keeps it in the URL, and losing
/// it on every launch makes the app feel disposable.
class TaskFilters {
  const TaskFilters({
    this.projectId,
    this.status,
    this.priority,
    this.tagId,
    this.ownerUserId,
    this.actionRequiredUserId,
    this.includeClosed = false,
    this.includeOffBoard = false,
    this.loose = false,
    this.sortKey = 'priority',
    this.descending = false,
  });

  final String? projectId;
  final String? status;
  final String? priority;
  final String? tagId;
  final String? ownerUserId;
  final String? actionRequiredUserId;
  final bool includeClosed;
  final bool includeOffBoard;

  /// Tasks with no project.
  final bool loose;

  final String sortKey;
  final bool descending;

  TaskSort get sort => TaskSort.of(sortKey);

  /// How many filters are narrowing the list — drives the badge on the filter
  /// button, so a person can tell at a glance why a list looks short.
  int get activeCount => [
        projectId,
        status,
        priority,
        tagId,
        ownerUserId,
        actionRequiredUserId,
      ].where((v) => v != null).length +
      (includeClosed ? 1 : 0) +
      (loose ? 1 : 0);

  bool get isClean => activeCount == 0;

  TaskFilters copyWith({
    String? projectId,
    String? status,
    String? priority,
    String? tagId,
    String? ownerUserId,
    String? actionRequiredUserId,
    bool? includeClosed,
    bool? includeOffBoard,
    bool? loose,
    String? sortKey,
    bool? descending,
    bool clearProject = false,
    bool clearStatus = false,
    bool clearPriority = false,
    bool clearTag = false,
    bool clearOwner = false,
    bool clearActionRequired = false,
  }) =>
      TaskFilters(
        projectId: clearProject ? null : (projectId ?? this.projectId),
        status: clearStatus ? null : (status ?? this.status),
        priority: clearPriority ? null : (priority ?? this.priority),
        tagId: clearTag ? null : (tagId ?? this.tagId),
        ownerUserId: clearOwner ? null : (ownerUserId ?? this.ownerUserId),
        actionRequiredUserId: clearActionRequired
            ? null
            : (actionRequiredUserId ?? this.actionRequiredUserId),
        includeClosed: includeClosed ?? this.includeClosed,
        includeOffBoard: includeOffBoard ?? this.includeOffBoard,
        loose: loose ?? this.loose,
        sortKey: sortKey ?? this.sortKey,
        descending: descending ?? this.descending,
      );

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        'status': status,
        'priority': priority,
        'tagId': tagId,
        'ownerUserId': ownerUserId,
        'actionRequiredUserId': actionRequiredUserId,
        'includeClosed': includeClosed,
        'includeOffBoard': includeOffBoard,
        'loose': loose,
        'sortKey': sortKey,
        'descending': descending,
      };

  factory TaskFilters.fromJson(Map<String, dynamic> j) => TaskFilters(
        projectId: j['projectId'] as String?,
        status: j['status'] as String?,
        priority: j['priority'] as String?,
        tagId: j['tagId'] as String?,
        ownerUserId: j['ownerUserId'] as String?,
        actionRequiredUserId: j['actionRequiredUserId'] as String?,
        includeClosed: j['includeClosed'] as bool? ?? false,
        includeOffBoard: j['includeOffBoard'] as bool? ?? false,
        loose: j['loose'] as bool? ?? false,
        sortKey: j['sortKey'] as String? ?? 'priority',
        descending: j['descending'] as bool? ?? false,
      );
}

const _filtersKey = 'tasks.filters.v1';

final taskFiltersProvider =
    NotifierProvider<TaskFiltersController, TaskFilters>(TaskFiltersController.new);

class TaskFiltersController extends Notifier<TaskFilters> {
  @override
  TaskFilters build() {
    final raw = ref.read(prefsProvider).getString(_filtersKey);
    if (raw == null) return const TaskFilters();
    try {
      return TaskFilters.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const TaskFilters();
    }
  }

  void update(TaskFilters filters) {
    state = filters;
    ref.read(prefsProvider).setString(_filtersKey, jsonEncode(filters.toJson()));
  }

  void clear() => update(
        TaskFilters(sortKey: state.sortKey, descending: state.descending),
      );

  void setSort(TaskSort sort) {
    // Recently-updated ascending is never what anybody wants, so a fresh sort
    // starts in its own natural direction.
    final flipping = sort.key == state.sortKey;
    update(state.copyWith(
      sortKey: sort.key,
      descending: flipping ? !state.descending : sort.defaultDescending,
    ));
  }
}

/// One page-accumulating task list.
class TaskListState {
  const TaskListState({
    this.items = const [],
    this.total = 0,
    this.loadingMore = false,
  });

  final List<TaskOut> items;

  /// From `X-Total-Count`, so "12 of 240" is honest.
  final int total;

  final bool loadingMore;

  bool get hasMore => items.length < total;

  TaskListState copyWith({
    List<TaskOut>? items,
    int? total,
    bool? loadingMore,
  }) =>
      TaskListState(
        items: items ?? this.items,
        total: total ?? this.total,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

/// Which slice of the org's tasks a list is for.
enum TaskScope {
  /// Everything the filters allow.
  all,

  /// Triage: tasks nobody is action-required on.
  ///
  /// Not its own endpoint — it is the task list with the "nobody
  /// action-required" filter, which is why it shares this controller.
  triage,
}

const _pageSize = 40;

class TaskListController extends AsyncNotifier<TaskListState> {
  TaskListController(this.scope);

  final TaskScope scope;

  String? _orgId;
  late TaskFilters _filters;

  @override
  Future<TaskListState> build() async {
    _orgId = ref.watch(currentOrgIdProvider);
    _filters = ref.watch(taskFiltersProvider);
    final orgId = _orgId;
    if (orgId == null) return const TaskListState();
    final page = await _fetch(offset: 0);
    return TaskListState(items: page.items, total: page.total);
  }

  Future<Paged<TaskOut>> _fetch({required int offset}) {
    final filters = scope == TaskScope.triage
        // Triage deliberately ignores the saved list filters: it is a queue,
        // and a queue that silently hides rows is a queue people stop trusting.
        ? const TaskFilters(sortKey: 'priority')
        : _filters;
    return ref.read(repoProvider).tasks(
          _orgId!,
          projectId: filters.projectId,
          status: filters.status,
          priority: filters.priority,
          tagId: filters.tagId,
          ownerUserId: filters.ownerUserId,
          actionRequiredUserId: filters.actionRequiredUserId,
          actionRequiredUnset: scope == TaskScope.triage,
          includeClosed: filters.includeClosed,
          includeOffBoard: filters.includeOffBoard,
          loose: filters.loose,
          sort: filters.sortKey,
          dir: filters.descending ? 'desc' : 'asc',
          limit: _pageSize,
          offset: offset,
        );
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.loadingMore || !current.hasMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await _fetch(offset: current.items.length);
      state = AsyncData(TaskListState(
        items: [...current.items, ...page.items],
        total: page.total,
      ));
    } catch (_) {
      // Keep what is on screen; the person can scroll to try again.
      state = AsyncData(current.copyWith(loadingMore: false));
    }
  }

  Future<void> refresh() async {
    final orgId = _orgId;
    if (orgId == null) return;
    try {
      final page = await _fetch(offset: 0);
      state = AsyncData(TaskListState(items: page.items, total: page.total));
    } catch (error, stack) {
      if (state.value == null) state = AsyncError(error, stack);
    }
  }

  /// Folds a server-confirmed task back into the list without a refetch.
  void replace(TaskOut task) {
    final current = state.value;
    if (current == null) return;
    final index = current.items.indexWhere((t) => t.id == task.id);
    if (index < 0) return;
    final items = [...current.items];
    items[index] = task;
    state = AsyncData(current.copyWith(items: items));
  }

  /// Drops a row that no longer belongs — closed, hidden, or triaged away.
  void remove(String taskId) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(
      items: current.items.where((t) => t.id != taskId).toList(),
      total: (current.total - 1).clamp(0, 1 << 30),
    ));
  }
}

final taskListProvider =
    AsyncNotifierProvider<TaskListController, TaskListState>(
  () => TaskListController(TaskScope.all),
);

final triageListProvider =
    AsyncNotifierProvider<TaskListController, TaskListState>(
  () => TaskListController(TaskScope.triage),
);

/// One task, fresh from the server.
final taskProvider = FutureProvider.family<TaskOut, String>((ref, taskId) async {
  final orgId = ref.watch(requireOrgIdProvider);
  return ref.watch(repoProvider).task(orgId, taskId);
});

final taskCommentsProvider =
    FutureProvider.family<ThreadOut, String>((ref, taskId) async {
  final orgId = ref.watch(requireOrgIdProvider);
  return ref.watch(repoProvider).comments(orgId, taskId);
});

final taskFilesProvider =
    FutureProvider.family<List<TaskFileOut>, String>((ref, taskId) async {
  final orgId = ref.watch(requireOrgIdProvider);
  return ref.watch(repoProvider).taskFiles(orgId, taskId);
});

final taskChecklistsProvider =
    FutureProvider.family<List<ChecklistOut>, String>((ref, taskId) async {
  final orgId = ref.watch(requireOrgIdProvider);
  return ref.watch(repoProvider).checklists(orgId, taskId);
});

final taskEventsProvider =
    FutureProvider.family<List<TaskEventOut>, String>((ref, taskId) async {
  final orgId = ref.watch(requireOrgIdProvider);
  return ref.watch(repoProvider).taskEvents(orgId, taskId);
});

final taskTimeProvider =
    FutureProvider.family<List<TimeEntryOut>, String>((ref, taskId) async {
  final orgId = ref.watch(requireOrgIdProvider);
  return ref.watch(repoProvider).taskTime(orgId, taskId);
});
