import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/org_controller.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/badges.dart';
import '../../ui/widgets/states.dart';

/// The header control that names where you are: which organisation, on which
/// instance.
///
/// Both live in one sheet because on a phone they answer the same question —
/// "whose tasks am I looking at?" — and separating them would mean two
/// controls competing for the same corner.
class OrgSwitcherButton extends ConsumerWidget {
  const OrgSwitcherButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final org = ref.watch(currentOrgProvider);
    final profile = ref.watch(authControllerProvider).activeProfile;

    // An InkWell rather than a ShadButton: ShadButton sizes itself to its
    // content and lets `maxWidth` go to infinity, so a long organisation name
    // inside one overflows the header instead of ellipsising.
    return InkWell(
      onTap: () => showContextSwitcher(context),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    org?.name ?? 'No organisation',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: context.colors.foreground,
                    ),
                  ),
                  if (profile != null)
                    Text(
                      profile.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.15,
                        color: context.colors.mutedForeground,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              LucideIcons.chevronsUpDown,
              size: 14,
              color: context.colors.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showContextSwitcher(BuildContext context) => showShadSheet<void>(
      context: context,
      side: ShadSheetSide.bottom,
      builder: (context) => const _ContextSheet(),
    );

class _ContextSheet extends ConsumerWidget {
  const _ContextSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgs = ref.watch(organisationsProvider);
    final currentOrgId = ref.watch(currentOrgIdProvider);
    final auth = ref.watch(authControllerProvider);

    return ShadSheet(
      title: const Text('Switch'),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SheetLabel('Organisations'),
              AsyncView(
                value: orgs,
                onRetry: () => ref.invalidate(organisationsProvider),
                loading: const Padding(
                  padding: EdgeInsets.all(Gap.lg),
                  child: LoadingView(),
                ),
                data: (list) => Column(
                  children: [
                    if (list.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: Gap.md),
                        child: Text(
                          'You are not in any organisation yet. Create one, or '
                          'ask someone to invite you.',
                          style: context.texts.muted,
                        ),
                      ),
                    for (final org in list)
                      _SheetRow(
                        leading: PersonAvatar(
                          label: org.name.substring(0, 1).toUpperCase(),
                          size: 30,
                        ),
                        title: org.name,
                        subtitle: org.role,
                        selected: org.id == currentOrgId,
                        onTap: () {
                          ref.read(currentOrgIdProvider.notifier).select(org.id);
                          Navigator.of(context).pop();
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.lg),
              _SheetLabel('Instances'),
              for (final profile in auth.profiles)
                _SheetRow(
                  leading: PersonAvatar(label: profile.initials, size: 30),
                  title: profile.label,
                  subtitle: profile.signedIn ? profile.host : 'signed out',
                  selected: profile.id == auth.activeProfileId,
                  onTap: () async {
                    Navigator.of(context).pop();
                    if (!profile.signedIn) {
                      context.push('/signin/${profile.id}');
                      return;
                    }
                    await ref
                        .read(authControllerProvider.notifier)
                        .switchProfile(profile.id);
                  },
                ),
              const SizedBox(height: Gap.sm),
              ShadButton.outline(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push('/profiles');
                },
                leading: const Icon(LucideIcons.settings2, size: 15),
                child: const Text('Manage instances'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.sm, top: Gap.xs),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
            color: context.colors.mutedForeground,
          ),
        ),
      );
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.sm,
            vertical: Gap.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? context.colors.muted : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? context.colors.border : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.texts.p.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: context.texts.small.copyWith(
                        color: context.colors.mutedForeground,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(LucideIcons.check, size: 16, color: context.colors.primary),
            ],
          ),
        ),
      );
}
