import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/profile.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/badges.dart';
import 'auth_scaffold.dart';

/// The landing screen when nothing is signed in, and the switcher when
/// something is.
///
/// Renders entirely from stored profile fields, so it works with no network:
/// the label, host and email are all kept locally for exactly this reason.
class ProfilesScreen extends ConsumerWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider);
    final profiles = state.profiles;

    if (profiles.isEmpty) {
      return const AddProfileWelcome();
    }

    return AuthScaffold(
      title: 'Choose an instance',
      subtitle: 'Signed-in instances keep separate sessions, so you can hold a '
          'work and a personal one at once.',
      children: [
        for (final profile in profiles) ...[
          _ProfileRow(profile: profile, isActive: profile.id == state.activeProfileId),
          const SizedBox(height: Gap.sm),
        ],
        const SizedBox(height: Gap.md),
        ShadButton.outline(
          width: double.infinity,
          onPressed: () => context.push('/profiles/add'),
          leading: const Icon(LucideIcons.plus, size: 16),
          child: const Text('Add instance'),
        ),
      ],
    );
  }
}

class _ProfileRow extends ConsumerWidget {
  const _ProfileRow({required this.profile, required this.isActive});

  final Profile profile;
  final bool isActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(authControllerProvider.notifier);
    return GestureDetector(
      onTap: () async {
        if (!profile.signedIn) {
          context.push('/signin/${profile.id}');
          return;
        }
        await controller.switchProfile(profile.id);
        if (context.mounted) context.go('/');
      },
      child: Container(
        padding: const EdgeInsets.all(Gap.md),
        decoration: BoxDecoration(
          color: context.colors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? context.colors.primary : context.colors.border,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            PersonAvatar(label: profile.initials, size: 38),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          profile.label,
                          style: context.texts.p.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!profile.signedIn) ...[
                        const SizedBox(width: Gap.sm),
                        Text(
                          'signed out',
                          style: context.texts.small.copyWith(
                            color: context.colors.destructive,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    profile.email ?? profile.host,
                    style: context.texts.muted,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    profile.host,
                    style: context.texts.small.copyWith(
                      color: context.colors.mutedForeground,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            ShadIconButton.ghost(
              icon: const Icon(LucideIcons.trash2, size: 16),
              onPressed: () => _confirmRemove(context, ref, profile),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    Profile profile,
  ) async {
    final confirmed = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog.alert(
        title: Text('Remove ${profile.label}?'),
        description: const Text(
          'This signs the instance out on this device and revokes the token '
          'the app uses for live updates. Nothing on the server is deleted.',
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ShadButton.destructive(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(authControllerProvider.notifier).removeProfile(profile.id);
    if (context.mounted) context.go('/');
  }
}

/// First run: no profiles at all.
class AddProfileWelcome extends StatelessWidget {
  const AddProfileWelcome({super.key});

  @override
  Widget build(BuildContext context) => AuthScaffold(
        title: 'Connect your instance',
        subtitle: 'ayeaye runs wherever you put it. Point the app at your '
            'instance and sign in — or create an account if you have not yet.',
        children: [
          ShadButton(
            width: double.infinity,
            onPressed: () => context.push('/profiles/add'),
            leading: const Icon(LucideIcons.plus, size: 16),
            child: const Text('Get started'),
          ),
          const SizedBox(height: Gap.lg),
          const NoticeCard(
            icon: LucideIcons.info,
            message: 'Running ayeaye locally? An emulator cannot reach '
                '"localhost" — use 10.0.2.2 on Android, or your machine\'s LAN '
                'address, and make sure SITE_URL matches it.',
          ),
        ],
      );
}
