import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../ui/theme.dart';
import 'auth_scaffold.dart';

/// Shown while the keychain is read and `/api/me` answers.
///
/// `/api/me` is not just a fetch: it creates the local user row on first sight
/// and binds pending invitations, and everything else keys on the id it
/// returns — so the app genuinely cannot draw anything until it lands.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider);
    final error = state.meError;

    if (error != null) {
      return AuthScaffold(
        title: 'Could not reach your instance',
        subtitle: state.activeProfile?.host,
        children: [
          NoticeCard(message: error, destructive: true),
          const SizedBox(height: Gap.xl),
          ShadButton(
            width: double.infinity,
            onPressed: () => ref.read(authControllerProvider.notifier).loadMe(),
            leading: const Icon(LucideIcons.refreshCw, size: 16),
            child: const Text('Try again'),
          ),
          const SizedBox(height: Gap.sm),
          ShadButton.ghost(
            width: double.infinity,
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).signOutActive();
            },
            child: const Text('Sign out'),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Wordmark(size: 26),
            const SizedBox(height: Gap.xxl),
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.colors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
