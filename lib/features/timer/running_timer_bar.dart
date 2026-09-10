import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/api/repo.dart';
import '../../ui/format.dart';
import '../../ui/theme.dart';
import '../../ui/toast.dart';
import '../tasks/task_providers.dart';
import 'timer_providers.dart';

/// The running timer, ticking.
///
/// Shown wherever a person might be about to put the phone down. A timer left
/// running overnight is the one mistake the app can make on somebody's behalf,
/// so it is loud, it counts up live, and stopping it is one tap.
class RunningTimerBar extends ConsumerStatefulWidget {
  const RunningTimerBar({super.key});

  @override
  ConsumerState<RunningTimerBar> createState() => _RunningTimerBarState();
}

class _RunningTimerBarState extends ConsumerState<RunningTimerBar> {
  Timer? _ticker;
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    // Local ticking: the elapsed time is derived from `started_at`, so this
    // only needs to repaint, never to refetch.
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _stop(String taskId) async {
    setState(() => _stopping = true);
    await runGuarded(
      context,
      () => ref.read(repoProvider).stopTimer(),
      success: 'Timer stopped',
    );
    if (!mounted) return;
    setState(() => _stopping = false);
    ref.invalidate(timerProvider);
    ref.invalidate(taskTimeProvider(taskId));
  }

  @override
  Widget build(BuildContext context) {
    final entry = ref.watch(timerProvider).value?.entry;
    if (entry == null) return const SizedBox.shrink();

    final elapsed = DateTime.now().difference(entry.startedAt);

    return Container(
      margin: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, 0),
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.sm, Gap.sm),
      decoration: BoxDecoration(
        color: context.colors.primary.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: context.colors.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.timer, size: 16, color: context.colors.primary),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: GestureDetector(
              onTap: () => context.push('/task/${entry.taskId}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Fmt.stopwatch(elapsed),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: context.colors.primary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    entry.taskTitle ?? 'Running',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.small.copyWith(
                      color: context.colors.foreground,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: Gap.sm),
          ShadButton.destructive(
            size: ShadButtonSize.sm,
            onPressed: _stopping ? null : () => _stop(entry.taskId),
            leading: const Icon(LucideIcons.square, size: 12),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }
}
