import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/api/repo.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/enums.dart';
import '../../core/models/models.dart';
import '../../core/org_controller.dart';
import '../../ui/format.dart';
import '../../ui/theme.dart';
import '../../ui/toast.dart';
import 'task_providers.dart';

/// Create or edit a task.
///
/// One sheet for both, because the fields are identical and a separate "new
/// task" screen would only differ in its verb.
///
/// Descriptions are written as **markdown**: the server stores sanitised HTML
/// on a narrow allow-list that no Flutter editor emits, but the write
/// endpoints accept `description_format: markdown`, which is the door built
/// for exactly this.
Future<void> showTaskEditor(
  BuildContext context,
  WidgetRef ref, {
  TaskOut? task,
  String? initialProjectId,
}) =>
    showShadSheet<void>(
      context: context,
      side: ShadSheetSide.bottom,
      builder: (context) => _TaskEditorSheet(
        task: task,
        initialProjectId: initialProjectId,
      ),
    );

class _TaskEditorSheet extends ConsumerStatefulWidget {
  const _TaskEditorSheet({this.task, this.initialProjectId});

  final TaskOut? task;
  final String? initialProjectId;

  @override
  ConsumerState<_TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends ConsumerState<_TaskEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _hours;

  String? _projectId;
  late String _status;
  late String _priority;
  String? _ownerUserId;
  String? _actionRequiredUserId;
  DateTime? _dueOn;
  bool _busy = false;

  bool get _isEdit => widget.task != null;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _title = TextEditingController(text: task?.title ?? '');
    // An existing description is stored as HTML; editing it as markdown would
    // mean round-tripping through a converter we do not have, so the editor
    // starts from what is there and the person edits text.
    _description = TextEditingController(text: task?.description ?? '');
    _hours = TextEditingController(
      text: task?.estimatedHours == null
          ? ''
          : _trimZeros(task!.estimatedHours!),
    );
    _projectId = task?.projectId ?? widget.initialProjectId;
    _status = task?.status ?? TaskStatus.todo.key;
    _priority = task?.priority ?? TaskPriority.fallback.key;
    _ownerUserId = task?.owner?.id;
    _actionRequiredUserId = task?.actionRequired?.id;
    _dueOn = task?.dueOn;
  }

  static String _trimZeros(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _hours.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      showToast(context, 'A task needs a title');
      return;
    }
    setState(() => _busy = true);

    final orgId = ref.read(requireOrgIdProvider);
    final repo = ref.read(repoProvider);
    final hours = double.tryParse(_hours.text.trim());
    final description = _description.text.trim();

    try {
      if (_isEdit) {
        final updated = await repo.updateTask(orgId, widget.task!.id, {
          'title': title,
          'description': description,
          'description_format': 'markdown',
          'status': _status,
          'priority': _priority,
          'project_id': _projectId,
          'owner_user_id': _ownerUserId,
          'action_required_user_id': _actionRequiredUserId,
          'due_on': fmtDay(_dueOn),
          'estimated_hours': hours,
        });
        ref.read(taskListProvider.notifier).replace(updated);
        ref.invalidate(taskProvider(updated.id));
        if (mounted) {
          Navigator.of(context).pop();
          showToast(context, 'Saved');
        }
      } else {
        final created = await repo.createTask(
          orgId,
          TaskCreate(
            title: title,
            description: description.isEmpty ? null : description,
            descriptionFormat: 'markdown',
            status: _status,
            priority: _priority,
            projectId: _projectId,
            ownerUserId: _ownerUserId,
            actionRequiredUserId: _actionRequiredUserId,
            dueOn: _dueOn,
            estimatedHours: hours,
          ),
        );
        await ref.read(taskListProvider.notifier).refresh();
        ref.read(triageListProvider.notifier).refresh();
        if (mounted) {
          Navigator.of(context).pop();
          context.push('/task/${created.id}');
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        showErrorToast(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsProvider).value ?? const [];
    final members = ref.watch(membersProvider).value ?? const [];
    final me = ref.watch(meProvider);

    return ShadSheet(
      title: Text(_isEdit ? 'Edit task' : 'New task'),
      actions: [
        ShadButton.outline(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ShadButton(
          onPressed: _busy ? null : _save,
          leading: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : null,
          child: Text(_isEdit ? 'Save' : 'Create'),
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
              ShadInputFormField(
                controller: _title,
                label: const Text('Title'),
                placeholder: const Text('What needs doing?'),
                autofocus: !_isEdit,
                maxLength: 300,
              ),
              const SizedBox(height: Gap.md),
              ShadInputFormField(
                controller: _description,
                label: const Text('Description'),
                description: const Text('Markdown — **bold**, lists, `code`.'),
                placeholder: const Text('Any detail worth keeping'),
                maxLines: 6,
                minLines: 3,
              ),
              const SizedBox(height: Gap.lg),
              _Field(
                label: 'Status',
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final status in TaskStatus.all)
                      _Pick(
                        label: status.label,
                        dot: status.color,
                        selected: _status == status.key,
                        onTap: () => setState(() => _status = status.key),
                      ),
                  ],
                ),
              ),
              _Field(
                label: 'Priority',
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final priority in TaskPriority.all)
                      _Pick(
                        label: priority.label,
                        dot: priority.color,
                        selected: _priority == priority.key,
                        onTap: () => setState(() => _priority = priority.key),
                      ),
                  ],
                ),
              ),
              _Field(
                label: 'Waiting on',
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Pick(
                      label: 'Nobody',
                      selected: _actionRequiredUserId == null,
                      onTap: () => setState(() => _actionRequiredUserId = null),
                    ),
                    if (me != null)
                      _Pick(
                        label: 'Me',
                        selected: _actionRequiredUserId == me.userId,
                        onTap: () =>
                            setState(() => _actionRequiredUserId = me.userId),
                      ),
                    for (final member in members.where(
                      (m) => m.userId != null && m.userId != me?.userId,
                    ))
                      _Pick(
                        label: Fmt.person(member.displayName, member.email),
                        selected: _actionRequiredUserId == member.userId,
                        onTap: () => setState(
                          () => _actionRequiredUserId = member.userId,
                        ),
                      ),
                  ],
                ),
              ),
              _Field(
                label: 'Owner',
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Pick(
                      label: 'Unassigned',
                      selected: _ownerUserId == null,
                      onTap: () => setState(() => _ownerUserId = null),
                    ),
                    if (me != null)
                      _Pick(
                        label: 'Me',
                        selected: _ownerUserId == me.userId,
                        onTap: () => setState(() => _ownerUserId = me.userId),
                      ),
                    for (final member in members.where(
                      (m) => m.userId != null && m.userId != me?.userId,
                    ))
                      _Pick(
                        label: Fmt.person(member.displayName, member.email),
                        selected: _ownerUserId == member.userId,
                        onTap: () =>
                            setState(() => _ownerUserId = member.userId),
                      ),
                  ],
                ),
              ),
              if (projects.isNotEmpty)
                _Field(
                  label: 'Project',
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _Pick(
                        label: 'None',
                        selected: _projectId == null,
                        onTap: () => setState(() => _projectId = null),
                      ),
                      for (final project in projects)
                        _Pick(
                          label: project.name,
                          selected: _projectId == project.id,
                          onTap: () =>
                              setState(() => _projectId = project.id),
                        ),
                    ],
                  ),
                ),
              _Field(
                label: 'Due date',
                child: Row(
                  children: [
                    Expanded(
                      child: ShadButton.outline(
                        onPressed: _pickDueDate,
                        leading: const Icon(LucideIcons.calendar, size: 15),
                        child: Text(
                          _dueOn == null ? 'No due date' : Fmt.date(_dueOn!),
                        ),
                      ),
                    ),
                    if (_dueOn != null) ...[
                      const SizedBox(width: Gap.sm),
                      ShadIconButton.ghost(
                        icon: const Icon(LucideIcons.x, size: 16),
                        onPressed: () => setState(() => _dueOn = null),
                      ),
                    ],
                  ],
                ),
              ),
              _Field(
                label: 'Estimate',
                child: ShadInputFormField(
                  controller: _hours,
                  placeholder: const Text('Hours, e.g. 2.5'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueOn ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _dueOn = picked);
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: context.texts.small.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: Gap.sm),
            child,
          ],
        ),
      );
}

class _Pick extends StatelessWidget {
  const _Pick({
    required this.label,
    required this.selected,
    required this.onTap,
    this.dot,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? dot;

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
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected
                        ? context.colors.primary
                        : context.colors.foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
