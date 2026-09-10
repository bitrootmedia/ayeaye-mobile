import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/api/repo.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/models.dart';
import '../../core/theme_controller.dart';
import '../../ui/format.dart';
import '../../ui/theme.dart';
import '../../ui/toast.dart';
import '../../ui/widgets/badges.dart';
import '../../ui/widgets/screen_header.dart';
import '../../ui/widgets/states.dart';

final _mfaStatusProvider = FutureProvider<MfaStatusOut>((ref) async {
  ref.watch(activeProfileIdProvider);
  return ref.watch(repoProvider).mfaStatus();
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final profile = ref.watch(authControllerProvider).activeProfile;
    final mfa = ref.watch(_mfaStatusProvider).value;

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: const ScreenHeader(
        leading: HeaderBack(),
        title: HeaderTitle('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Gap.xxl),
        children: [
          if (me != null)
            Container(
              padding: const EdgeInsets.all(Gap.lg),
              child: Row(
                children: [
                  PersonAvatar(
                    person: PersonOut(
                      id: me.userId,
                      displayName: me.displayName,
                      email: me.email,
                    ),
                    size: 46,
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Fmt.person(me.displayName, me.email),
                          style: context.texts.large,
                        ),
                        if (me.email != null)
                          Text(me.email!, style: context.texts.muted),
                        if (me.timezone != null)
                          Text(
                            me.timezone!,
                            style: context.texts.small.copyWith(
                              color: context.colors.mutedForeground,
                            ),
                          ),
                      ],
                    ),
                  ),
                  ShadIconButton.ghost(
                    icon: const Icon(LucideIcons.pencil, size: 16),
                    onPressed: () => _editProfile(context, ref, me),
                  ),
                ],
              ),
            ),
          const SectionLabel('This instance'),
          if (profile != null) ...[
            _Row(
              icon: LucideIcons.server,
              label: profile.label,
              detail: profile.baseUrl,
            ),
            if (profile.patPrefix != null)
              _Row(
                icon: LucideIcons.radio,
                label: 'Live updates token',
                detail: '${profile.patPrefix}… (read-only)',
              ),
          ],
          _Row(
            icon: LucideIcons.users,
            label: 'Manage instances',
            onTap: () => context.push('/profiles'),
          ),
          const SectionLabel('Security'),
          _Row(
            icon: LucideIcons.shieldCheck,
            label: 'Two-factor authentication',
            detail: mfa == null
                ? null
                : mfa.enrolled
                    ? 'On · ${Fmt.count(mfa.codesRemaining, 'backup code')} left'
                    : 'Off',
            onTap: () => _manageMfa(context, ref, mfa),
          ),
          _Row(
            icon: LucideIcons.keyRound,
            label: 'Change password',
            onTap: () => _changePassword(context, ref),
          ),
          const SectionLabel('Appearance'),
          const _ThemePicker(),
          const SectionLabel('Notifications'),
          _DailySummaryToggle(me: me),
          const SectionLabel('Session'),
          _Row(
            icon: LucideIcons.logOut,
            label: 'Sign out',
            destructive: true,
            onTap: () async {
              await ref.read(authControllerProvider.notifier).signOutActive();
              if (context.mounted) context.go('/');
            },
          ),
          Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: Text(
              'ayeaye mobile · stage 1–3 build',
              textAlign: TextAlign.center,
              style: context.texts.small.copyWith(
                color: context.colors.mutedForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editProfile(
    BuildContext context,
    WidgetRef ref,
    MeOut me,
  ) async {
    final name = TextEditingController(text: me.displayName ?? '');
    final status = TextEditingController(text: me.statusMessage ?? '');
    final saved = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('Your profile'),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ShadButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.md),
          child: Column(
            children: [
              ShadInputFormField(
                controller: name,
                label: const Text('Display name'),
              ),
              const SizedBox(height: Gap.md),
              ShadInputFormField(
                controller: status,
                label: const Text('Status message'),
                maxLength: 140,
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true || !context.mounted) return;
    await runGuarded(
      context,
      () async {
        final updated = await ref.read(repoProvider).updateMe(
              MeUpdate(
                displayName: name.text.trim(),
                statusMessage: status.text.trim(),
              ),
            );
        await ref.read(authControllerProvider.notifier).updateMe(updated);
      },
      success: 'Saved',
    );
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final current = TextEditingController();
    final next = TextEditingController();
    final go = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('Change password'),
        description: const Text(
          'Ten characters or more, with upper case, lower case and a digit.',
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ShadButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Change'),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.md),
          child: Column(
            children: [
              ShadInputFormField(
                controller: current,
                label: const Text('Current password'),
                obscureText: true,
              ),
              const SizedBox(height: Gap.md),
              ShadInputFormField(
                controller: next,
                label: const Text('New password'),
                obscureText: true,
              ),
            ],
          ),
        ),
      ),
    );
    if (go != true || !context.mounted) return;
    await runGuarded(
      context,
      () => ref.read(repoProvider).changePassword(current.text, next.text),
      success: 'Password changed',
    );
  }

  /// Enrolment is worth having in the app because an instance can require 2FA
  /// org-wide, and somebody caught by that on the road needs a way through.
  Future<void> _manageMfa(
    BuildContext context,
    WidgetRef ref,
    MfaStatusOut? status,
  ) async {
    if (status?.enrolled == true) {
      final off = await showShadDialog<bool>(
        context: context,
        builder: (context) => ShadDialog.alert(
          title: const Text('Turn off two-factor?'),
          description: const Text(
            'Your instance may require it, in which case you will be asked to '
            'set it up again at the next sign-in.',
          ),
          actions: [
            ShadButton.outline(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep it on'),
            ),
            ShadButton.destructive(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Turn off'),
            ),
          ],
        ),
      );
      if (off != true || !context.mounted) return;
      await runGuarded(
        context,
        () => ref.read(repoProvider).disableTotp(),
        success: 'Two-factor is off',
      );
      ref.invalidate(_mfaStatusProvider);
      return;
    }

    await showShadSheet<void>(
      context: context,
      side: ShadSheetSide.bottom,
      builder: (context) => const _TotpEnrolSheet(),
    );
    ref.invalidate(_mfaStatusProvider);
  }
}

/// TOTP enrolment: the secret is not stored until it is confirmed, so it has
/// to be held here and sent back with the code.
class _TotpEnrolSheet extends ConsumerStatefulWidget {
  const _TotpEnrolSheet();

  @override
  ConsumerState<_TotpEnrolSheet> createState() => _TotpEnrolSheetState();
}

class _TotpEnrolSheetState extends ConsumerState<_TotpEnrolSheet> {
  final _code = TextEditingController();
  TotpDeviceOut? _device;
  List<String>? _backupCodes;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final device = await ref.read(repoProvider).startTotpEnrolment();
      if (!mounted) return;
      setState(() {
        _device = device;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _busy = false;
      });
    }
  }

  Future<void> _verify() async {
    final device = _device;
    if (device == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final codes = await ref.read(repoProvider).verifyTotp(
            secret: device.secret,
            code: _code.text.trim(),
          );
      if (!mounted) return;
      setState(() {
        _backupCodes = codes.codes;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final codes = _backupCodes;
    if (codes != null) {
      return ShadSheet(
        title: const Text('Save your backup codes'),
        description: const Text(
          'Ten single-use codes. This is the only time they are shown.',
        ),
        actions: [
          ShadButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Saved them'),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.md),
          child: Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              for (final code in codes)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Gap.sm,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.muted,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: SelectableText(
                    code,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return ShadSheet(
      title: const Text('Set up two-factor'),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ShadButton(
          onPressed: _busy || _device == null ? null : _verify,
          child: const Text('Confirm'),
        ),
      ],
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_busy && _device == null)
              const Padding(
                padding: EdgeInsets.all(Gap.xl),
                child: LoadingView(),
              )
            else if (_device != null) ...[
              Text(
                'Scan this in your authenticator app, or type the secret in by '
                'hand.',
                style: context.texts.muted,
              ),
              const SizedBox(height: Gap.md),
              // The server returns the QR as a data: URI, so it renders
              // without any extra round trip.
              Center(
                child: Image.network(
                  _device!.qrDataUri,
                  width: 180,
                  height: 180,
                  errorBuilder: (context, _, _) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: Gap.md),
              Center(
                child: SelectableText(
                  _device!.secret,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: Gap.lg),
              ShadInputFormField(
                controller: _code,
                label: const Text('Six-digit code'),
                keyboardType: TextInputType.number,
                placeholder: const Text('123456'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: Gap.md),
              Text(
                _error!,
                style: context.texts.small.copyWith(
                  color: context.colors.destructive,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DailySummaryToggle extends ConsumerWidget {
  const _DailySummaryToggle({required this.me});

  final MeOut? me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (me == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Gap.lg,
        vertical: Gap.md,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.colors.border)),
      ),
      child: ShadSwitch(
        value: me!.dailySummaryEnabled,
        label: const Text('Daily summary email'),
        sublabel: Text(
          'Computed in ${me!.timezone ?? 'your timezone'}',
          style: context.texts.small.copyWith(
            color: context.colors.mutedForeground,
          ),
        ),
        onChanged: (value) async {
          await runGuarded(
            context,
            () async {
              final updated = await ref
                  .read(repoProvider)
                  .updateMe(MeUpdate(dailySummaryEnabled: value));
              await ref.read(authControllerProvider.notifier).updateMe(updated);
            },
          );
        },
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    this.detail,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color =
        destructive ? context.colors.destructive : context.colors.foreground;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.lg,
          vertical: Gap.md,
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.colors.border)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: context.texts.p.copyWith(color: color)),
                  if (detail != null)
                    Text(
                      detail!,
                      style: context.texts.muted,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                LucideIcons.chevronRight,
                size: 16,
                color: context.colors.mutedForeground,
              ),
          ],
        ),
      ),
    );
  }
}

/// Light / dark / system, as three buttons rather than a menu.
///
/// A three-way choice is worth showing in full: it is one tap instead of two,
/// and it makes the current state readable at a glance.
class _ThemePicker extends ConsumerWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeModeProvider);
    final controller = ref.read(themeModeProvider.notifier);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Gap.lg,
        vertical: Gap.md,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.colors.border)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.sunMoon, size: 17, color: context.colors.foreground),
          const SizedBox(width: Gap.md),
          Expanded(child: Text('Theme', style: context.texts.p)),
          Wrap(
            spacing: 6,
            children: [
              for (final entry in const {
                ThemeMode.system: 'Auto',
                ThemeMode.light: 'Light',
                ThemeMode.dark: 'Dark',
              }.entries)
                GestureDetector(
                  onTap: () => controller.set(entry.key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: current == entry.key
                          ? context.colors.primary.withValues(alpha: 0.12)
                          : context.colors.card,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: current == entry.key
                            ? context.colors.primary
                            : context.colors.border,
                      ),
                    ),
                    child: Text(
                      entry.value,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: current == entry.key
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: current == entry.key
                            ? context.colors.primary
                            : context.colors.foreground,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
