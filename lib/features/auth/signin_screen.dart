import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../ui/theme.dart';
import 'auth_scaffold.dart';

/// Signing an existing profile back in.
///
/// The URL and email are already known, so this is one field — which is the
/// whole point of keeping the profile around after its session dies.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key, required this.profileId});

  final String profileId;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _prefilled = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref.read(authControllerProvider.notifier).reauthenticate(
          profileId: widget.profileId,
          email: _email.text,
          password: _password.text,
        );
    if (!mounted) return;
    switch (result) {
      case SignInOk():
        context.go('/');
      case SignInFailed(:final message):
        setState(() {
          _busy = false;
          _error = message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref
        .watch(authControllerProvider)
        .profiles
        .where((p) => p.id == widget.profileId)
        .firstOrNull;

    if (profile == null) {
      return AuthScaffold(
        title: 'That profile is gone',
        onBack: () => context.go('/'),
        children: [
          ShadButton(
            width: double.infinity,
            onPressed: () => context.go('/'),
            child: const Text('Back'),
          ),
        ],
      );
    }

    if (!_prefilled) {
      _prefilled = true;
      _email.text = profile.email ?? '';
    }

    return AuthScaffold(
      title: 'Sign back in',
      subtitle: '${profile.label} · ${profile.host}',
      onBack: () => context.go('/'),
      children: [
        ShadInputFormField(
          controller: _email,
          label: const Text('Email'),
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textCapitalization: TextCapitalization.none,
        ),
        const SizedBox(height: Gap.lg),
        ShadInputFormField(
          controller: _password,
          label: const Text('Password'),
          obscureText: true,
          autofocus: true,
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
          child: const Text('Sign in'),
        ),
      ],
    );
  }
}
