import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/api/repo.dart';
import '../../ui/theme.dart';
import '../../ui/toast.dart';
import '../inbox/inbox_providers.dart';

/// Quick capture — the web app's ⌘J.
///
/// One of the two features people will open the app for daily, so it is one
/// tap from the home header and needs nothing but a thought: no title, no
/// project, no organisation. Sparks are cross-organisation by design.
Future<void> showSparkCapture(BuildContext context) => showShadSheet<void>(
      context: context,
      side: ShadSheetSide.bottom,
      builder: (context) => const _SparkSheet(),
    );

class _SparkSheet extends ConsumerStatefulWidget {
  const _SparkSheet();

  @override
  ConsumerState<_SparkSheet> createState() => _SparkSheetState();
}

class _SparkSheetState extends ConsumerState<_SparkSheet> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final body = _controller.text.trim();
    if (body.isEmpty) return;
    setState(() => _busy = true);
    final ok = await runGuarded(
      context,
      () => ref.read(repoProvider).createSpark(body),
      success: 'Captured',
    );
    if (!mounted) return;
    ref.invalidate(sparksProvider);
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ShadSheet(
        title: const Text('Quick capture'),
        description: const Text('Get it out of your head now; sort it later.'),
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
                : const Icon(LucideIcons.zap, size: 15),
            child: const Text('Capture'),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.sm),
          child: ShadInput(
            controller: _controller,
            placeholder: const Text('A thought, a link, a name to follow up'),
            autofocus: true,
            maxLines: 6,
            minLines: 3,
            maxLength: 2000,
            keyboardType: TextInputType.multiline,
            onChanged: (_) => setState(() {}),
          ),
        ),
      );
}
