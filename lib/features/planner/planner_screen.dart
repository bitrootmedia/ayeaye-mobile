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
import '../tasks/task_row.dart';

final plannerProvider = FutureProvider<PlannerOut>((ref) async {
  final orgId = ref.watch(currentOrgIdProvider);
  if (orgId == null) return const PlannerOut(pool: [], buckets: {});
  return ref.watch(repoProvider).planner(orgId);
});

/// The planner, as five lists rather than a drag-and-drop grid.
///
/// The web app drags cards between columns; on a phone that is fiddly and
/// error-prone, so moving a task is a tap that opens the five buckets. Same
/// endpoint, far fewer mis-drops.
class PlannerScreen extends ConsumerWidget {
  const PlannerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planner = ref.watch(plannerProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: const ScreenHeader(
        leading: HeaderBack(),
        title: HeaderTitle('Planner', subtitle: 'What you intend to do, when'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(plannerProvider),
        child: AsyncView(
          value: planner,
          onRetry: () => ref.invalidate(plannerProvider),
          data: (data) {
            final empty = data.pool.isEmpty &&
                data.buckets.values.every((list) => list.isEmpty);
            if (empty) {
              return const CustomScrollView(
                slivers: [
                  SliverFillRemaining(
                    child: EmptyState(
                      icon: LucideIcons.calendarRange,
                      title: 'Nothing planned',
                      message: 'Tasks you place in a bucket show up here.',
                    ),
                  ),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.only(bottom: Gap.xxl),
              children: [
                for (final bucket in PlannerBucket.all)
                  _Bucket(
                    bucket: bucket,
                    entries: data.buckets[bucket.key] ?? const [],
                  ),
                if (data.pool.isNotEmpty) ...[
                  const SectionLabel('Not planned yet'),
                  for (final task in data.pool)
                    _PlannerRow(
                      task: task,
                      currentBucket: null,
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Bucket extends StatelessWidget {
  const _Bucket({required this.bucket, required this.entries});

  final PlannerBucket bucket;
  final List<PlannerEntryOut> entries;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(
            bucket.label,
            trailing: entries.isEmpty ? null : CountBadge(entries.length),
          ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.lg,
                vertical: Gap.xs,
              ),
              child: Text('Empty', style: context.texts.muted),
            )
          else
            for (final entry in entries)
              _PlannerRow(task: entry.task, currentBucket: bucket.key),
        ],
      );
}

class _PlannerRow extends ConsumerWidget {
  const _PlannerRow({required this.task, required this.currentBucket});

  final PlannerTaskOut task;
  final String? currentBucket;

  @override
  Widget build(BuildContext context, WidgetRef ref) => CompactTaskRow(
        title: task.title,
        status: task.status,
        priority: task.priority,
        dimmed: !task.isOpen,
        onTap: () => context.push('/task/${task.id}'),
        trailing: ShadIconButton.ghost(
          width: 30,
          height: 30,
          icon: const Icon(LucideIcons.calendarCog, size: 15),
          onPressed: () => _move(context, ref),
        ),
      );

  Future<void> _move(BuildContext context, WidgetRef ref) async {
    final choice = await showShadSheet<String>(
      context: context,
      side: ShadSheetSide.bottom,
      builder: (context) => ShadSheet(
        title: const Text('Move to'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final bucket in PlannerBucket.all)
              InkWell(
                onTap: () => Navigator.of(context).pop(bucket.key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(bucket.label, style: context.texts.p),
                      ),
                      if (bucket.key == currentBucket)
                        Icon(
                          LucideIcons.check,
                          size: 16,
                          color: context.colors.primary,
                        ),
                    ],
                  ),
                ),
              ),
            if (currentBucket != null) ...[
              HairLine(),
              InkWell(
                onTap: () => Navigator.of(context).pop('__remove__'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.md),
                  child: Text(
                    'Remove from the planner',
                    style: context.texts.p.copyWith(
                      color: context.colors.destructive,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;

    final orgId = ref.read(requireOrgIdProvider);
    final repo = ref.read(repoProvider);
    await runGuarded(
      context,
      () => choice == '__remove__'
          ? repo.removeFromPlanner(orgId, task.id)
          : repo.placeInPlanner(orgId, task.id, bucket: choice),
      success: choice == '__remove__' ? 'Removed' : 'Moved',
    );
    ref.invalidate(plannerProvider);
  }
}
