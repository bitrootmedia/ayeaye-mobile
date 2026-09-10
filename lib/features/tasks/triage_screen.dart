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
import '../../ui/widgets/badges.dart';
import '../../ui/widgets/screen_header.dart';
import '../../ui/widgets/states.dart';
import '../shell/org_switcher.dart';
import 'task_providers.dart';

/// Triage: the tasks nobody is action-required on.
///
/// Not its own endpoint — it is the task list with the "nobody
/// action-required" filter — but it is very much its own *screen*, because the
/// question here is only ever "who holds this next?". Every row therefore
/// offers the three answers directly, so clearing a queue of twenty is twenty
/// taps rather than twenty round trips through a detail screen.
class TriageScreen extends ConsumerWidget {
  const TriageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgId = ref.watch(currentOrgIdProvider);
    final list = ref.watch(triageListProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: ScreenHeader(
        title: const OrgSwitcherButton(),
        actions: [
          ShadIconButton.ghost(
            icon: const Icon(LucideIcons.refreshCw, size: 17),
            onPressed: () => ref.read(triageListProvider.notifier).refresh(),
          ),
        ],
      ),
      body: orgId == null
          ? const EmptyState(
              icon: LucideIcons.building2,
              title: 'Pick an organisation',
              message: 'Triage works inside one organisation at a time.',
            )
          : RefreshIndicator(
              onRefresh: () => ref.read(triageListProvider.notifier).refresh(),
              child: AsyncView(
                value: list,
                onRetry: () => ref.invalidate(triageListProvider),
                data: (state) {
                  if (state.items.isEmpty) {
                    return const CustomScrollView(
                      slivers: [
                        SliverFillRemaining(
                          child: EmptyState(
                            icon: LucideIcons.circleCheck,
                            title: 'Nothing to triage',
                            message: 'Every open task has someone holding it. '
                                'That is the goal.',
                          ),
                        ),
                      ],
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.only(
                      top: Gap.sm,
                      bottom: Gap.xl,
                    ),
                    itemCount: state.items.length + 1,
                    itemBuilder: (context, index) {
                      if (index == state.items.length) {
                        return Padding(
                          padding: const EdgeInsets.all(Gap.lg),
                          child: Center(
                            child: Text(
                              '${Fmt.count(state.total, 'task')} waiting',
                              style: context.texts.muted,
                            ),
                          ),
                        );
                      }
                      return _TriageCard(task: state.items[index]);
                    },
                  );
                },
              ),
            ),
    );
  }
}

class _TriageCard extends ConsumerStatefulWidget {
  const _TriageCard({required this.task});

  final TaskOut task;

  @override
  ConsumerState<_TriageCard> createState() => _TriageCardState();
}

class _TriageCardState extends ConsumerState<_TriageCard> {
  bool _busy = false;

  TaskOut get task => widget.task;

  Future<void> _assign(String? userId, {required String message}) async {
    setState(() => _busy = true);
    final orgId = ref.read(requireOrgIdProvider);
    final ok = await runGuarded(
      context,
      () => ref
          .read(repoProvider)
          .updateTask(orgId, task.id, {'action_required_user_id': userId}),
      success: message,
    );
    if (!mounted) return;
    if (ok) {
      // It has an owner now, so it leaves the queue — animating it out would
      // be slower than simply not drawing it again.
      ref.read(triageListProvider.notifier).remove(task.id);
      ref.read(taskListProvider.notifier).refresh();
      ref.invalidate(taskProvider(task.id));
    } else {
      setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    setState(() => _busy = true);
    final orgId = ref.read(requireOrgIdProvider);
    final ok = await runGuarded(
      context,
      () => ref.read(repoProvider).setClosed(orgId, task.id, true),
      success: 'Closed',
    );
    if (!mounted) return;
    if (ok) {
      ref.read(triageListProvider.notifier).remove(task.id);
      ref.read(taskListProvider.notifier).refresh();
    } else {
      setState(() => _busy = false);
    }
  }

  Future<void> _pickPerson() async {
    final members = ref.read(membersProvider).value ?? const [];
    final me = ref.read(meProvider);
    final choice = await showShadSheet<MemberOut>(
      context: context,
      side: ShadSheetSide.bottom,
      builder: (context) => ShadSheet(
        title: const Text('Who should hold this?'),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.5,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final member in members.where(
                (m) => m.userId != null && m.userId != me?.userId,
              ))
                InkWell(
                  onTap: () => Navigator.of(context).pop(member),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Gap.md),
                    child: Row(
                      children: [
                        PersonAvatar(
                          person: PersonOut(
                            id: member.userId ?? member.id,
                            displayName: member.displayName,
                            email: member.email,
                          ),
                          size: 30,
                        ),
                        const SizedBox(width: Gap.md),
                        Expanded(
                          child: Text(
                            Fmt.person(member.displayName, member.email),
                            style: context.texts.p,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice?.userId == null || !mounted) return;
    await _assign(
      choice!.userId,
      message: 'Assigned to ${Fmt.person(choice.displayName, choice.email)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    return Opacity(
      opacity: _busy ? 0.5 : 1,
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: Gap.md,
          vertical: Gap.xs + 2,
        ),
        decoration: BoxDecoration(
          color: context.colors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: _busy ? null : () => context.push('/task/${task.id}'),
              child: Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: PriorityDot(task.priority, size: 9),
                    ),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            maxLines: 3,
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (Fmt.preview(task.description).isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              Fmt.preview(task.description, max: 100),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: context.texts.muted,
                            ),
                          ],
                          const SizedBox(height: Gap.sm),
                          Wrap(
                            spacing: Gap.md,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              StatusPill(task.status, compact: true),
                              if (task.dueOn != null) DueChip(task.dueOn!),
                              if (task.projectName != null)
                                Text(
                                  task.projectName!,
                                  style: context.texts.small.copyWith(
                                    color: context.colors.mutedForeground,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            HairLine(),
            Padding(
              padding: const EdgeInsets.all(Gap.sm),
              // A Wrap, not a Row of Expandeds: ShadButton sizes itself to
              // its content and ignores a tight slot, so a flexed one
              // overflows on a narrow phone or at a large text scale. Natural
              // widths that fall onto a second line cannot.
              child: Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                alignment: WrapAlignment.end,
                children: [
                  ShadButton.secondary(
                    size: ShadButtonSize.sm,
                    onPressed: _busy || me == null
                        ? null
                        : () => _assign(me.userId, message: 'Yours now'),
                    leading: const Icon(LucideIcons.userCheck, size: 14),
                    child: const Text("I'll take it"),
                  ),
                  ShadButton.outline(
                    size: ShadButtonSize.sm,
                    onPressed: _busy ? null : _pickPerson,
                    leading: const Icon(LucideIcons.users, size: 14),
                    child: const Text('Assign'),
                  ),
                  if (task.canClose)
                    ShadIconButton.ghost(
                      width: 32,
                      height: 32,
                      icon: const Icon(LucideIcons.check, size: 16),
                      onPressed: _busy ? null : _close,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
