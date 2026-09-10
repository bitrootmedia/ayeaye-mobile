import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/api/repo.dart';
import '../../core/models/models.dart';
import '../../core/org_controller.dart';
import '../../ui/format.dart';
import '../../ui/theme.dart';
import '../../ui/toast.dart';
import '../../ui/widgets/screen_header.dart';
import '../../ui/widgets/states.dart';
import '../inbox/inbox_providers.dart';
import '../tasks/task_providers.dart';

/// Captured thoughts, waiting to become something.
///
/// The useful verb here is "promote": a spark that turns out to be work should
/// become a task without being retyped.
class SparksScreen extends ConsumerWidget {
  const SparksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sparks = ref.watch(sparksProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: const ScreenHeader(
        leading: HeaderBack(),
        title: HeaderTitle('Sparks', subtitle: 'Across every instance'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(sparksProvider),
        child: AsyncView(
          value: sparks,
          onRetry: () => ref.invalidate(sparksProvider),
          data: (items) {
            if (items.isEmpty) {
              return const CustomScrollView(
                slivers: [
                  SliverFillRemaining(
                    child: EmptyState(
                      icon: LucideIcons.sparkles,
                      title: 'No sparks yet',
                      message: 'Quick capture saves half-formed thoughts here '
                          'so you can keep moving.',
                    ),
                  ),
                ],
              );
            }
            return ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) => _SparkCard(spark: items[index]),
            );
          },
        ),
      ),
    );
  }
}

class _SparkCard extends ConsumerWidget {
  const _SparkCard({required this.spark});

  final SparkOut spark;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
        margin: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, 0),
        padding: const EdgeInsets.all(Gap.md),
        decoration: BoxDecoration(
          color: context.colors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              spark.body,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: Gap.sm),
            // A Wrap rather than a Row with a Spacer: the age and the two
            // actions do not share a line on a small phone at a large text
            // scale, and a ShadButton will not shrink to make them.
            Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.end,
              children: [
                Text(
                  Fmt.ago(spark.createdAt),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: context.colors.mutedForeground,
                  ),
                ),
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  onPressed: () => _promote(context, ref),
                  leading: const Icon(LucideIcons.arrowUpRight, size: 13),
                  child: const Text('Make a task'),
                ),
                ShadIconButton.ghost(
                  width: 28,
                  height: 28,
                  icon: const Icon(LucideIcons.trash2, size: 14),
                  onPressed: () => _delete(context, ref),
                ),
              ],
            ),
          ],
        ),
      );

  /// Turns a spark into a task, then removes the spark: leaving both would mean
  /// two places to keep in sync by hand.
  Future<void> _promote(BuildContext context, WidgetRef ref) async {
    final orgId = ref.read(currentOrgIdProvider);
    if (orgId == null) {
      showToast(context, 'Pick an organisation first');
      return;
    }
    final lines = spark.body.trim().split('\n');
    final title = lines.first.length > 300
        ? lines.first.substring(0, 300)
        : lines.first;
    final body = lines.length > 1 ? lines.sublist(1).join('\n').trim() : '';

    final ok = await runGuarded(
      context,
      () async {
        await ref.read(repoProvider).createTask(
              orgId,
              TaskCreate(
                title: title,
                description: body.isEmpty ? null : body,
                descriptionFormat: 'markdown',
              ),
            );
        await ref.read(repoProvider).deleteSpark(spark.id);
      },
      success: 'Task created',
    );
    if (!ok) return;
    ref.invalidate(sparksProvider);
    ref.read(taskListProvider.notifier).refresh();
    ref.read(triageListProvider.notifier).refresh();
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    await runGuarded(
      context,
      () => ref.read(repoProvider).deleteSpark(spark.id),
      success: 'Deleted',
    );
    ref.invalidate(sparksProvider);
  }
}
