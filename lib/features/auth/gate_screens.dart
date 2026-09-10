import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../ui/theme.dart';
import 'auth_scaffold.dart';

/// The 2FA gate.
///
/// Until this clears, *every* `/api/*` route returns 403 with an
/// `st-mfa-ok` claim error, however valid the password was. The claim is
/// decided once per session at first use, so an organisation turning the
/// requirement on reaches an open session at its next sign-in.
class MfaGateScreen extends ConsumerStatefulWidget {
  const MfaGateScreen({super.key});

  @override
  ConsumerState<MfaGateScreen> createState() => _MfaGateScreenState();
}

class _MfaGateScreenState extends ConsumerState<MfaGateScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  bool _useBackupCode = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter the code');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller = ref.read(authControllerProvider.notifier);

    // The challenge answers 204 with a *new* access token in the headers, and
    // the old one keeps returning 403 forever. The client absorbs `St-*` on
    // every response, so by the time this returns the session is unblocked.
    final error = _useBackupCode
        ? await controller.redeemBackupCode(code)
        : await controller.submitTotp(code);

    if (!mounted) return;
    if (error == null) {
      context.go('/');
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
      _code.clear();
    });
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
        title: 'Two-factor required',
        subtitle: _useBackupCode
            ? 'Enter one of the ten single-use backup codes you saved when you '
                'set up two-factor.'
            : 'Enter the six-digit code from your authenticator app.',
        footer: const _SwitchProfileFooter(),
        children: [
          ShadInputFormField(
            controller: _code,
            label: Text(_useBackupCode ? 'Backup code' : 'Authentication code'),
            keyboardType:
                _useBackupCode ? TextInputType.text : TextInputType.number,
            autofocus: true,
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            placeholder: Text(_useBackupCode ? 'xxxx-xxxx' : '123456'),
            onSubmitted: (_) => _busy ? null : _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: Gap.lg),
            NoticeCard(message: _error!, destructive: true),
          ],
          const SizedBox(height: Gap.xl),
          ShadButton(
            width: double.infinity,
            onPressed: _busy ? null : _submit,
            leading: _busy
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : null,
            child: const Text('Continue'),
          ),
          const SizedBox(height: Gap.md),
          ShadButton.ghost(
            width: double.infinity,
            onPressed: () => setState(() {
              _useBackupCode = !_useBackupCode;
              _error = null;
              _code.clear();
            }),
            child: Text(
              _useBackupCode
                  ? 'Use my authenticator app instead'
                  : 'Use a backup code instead',
            ),
          ),
        ],
      );
}

/// The email-verification gate.
///
/// Enforcement is the server's decision — it is on only where SMTP is
/// configured — so the app reacts to the 403 rather than pre-empting it.
///
/// The subtle part is the re-check: verification is recorded against the
/// account, but the access token still carries the stale `st-ev` claim, and
/// refreshing the session is what picks up the new value. Without that,
/// "I've confirmed it" gets the same answer forever.
class EmailGateScreen extends ConsumerStatefulWidget {
  const EmailGateScreen({super.key});

  @override
  ConsumerState<EmailGateScreen> createState() => _EmailGateScreenState();
}

class _EmailGateScreenState extends ConsumerState<EmailGateScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _recheck() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await ref
        .read(authControllerProvider.notifier)
        .recheckEmailVerification();
    if (!mounted) return;
    if (error == null) {
      context.go('/');
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(authControllerProvider).activeProfile?.email;
    return AuthScaffold(
      title: 'Confirm your email',
      subtitle: email == null
          ? 'Your instance needs a confirmed email address before you can '
              'continue.'
          : 'We sent a link to $email. Open it, then come back here.',
      footer: const _SwitchProfileFooter(),
      children: [
        ShadButton(
          width: double.infinity,
          onPressed: _busy ? null : _recheck,
          leading: _busy
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(LucideIcons.refreshCw, size: 16),
          child: const Text("I've confirmed it"),
        ),
        if (_error != null) ...[
          const SizedBox(height: Gap.lg),
          NoticeCard(message: _error!, destructive: true),
        ],
      ],
    );
  }
}

/// Both gates are per-profile, so both offer a way out to the other ones.
class _SwitchProfileFooter extends ConsumerWidget {
  const _SwitchProfileFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
        children: [
          ShadButton.link(
            onPressed: () => context.go('/profiles'),
            child: const Text('Use another instance'),
          ),
          ShadButton.link(
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).signOutActive();
              if (context.mounted) context.go('/');
            },
            child: const Text('Sign out'),
          ),
        ],
      );
}
