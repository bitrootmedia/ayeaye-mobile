import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_controller.dart';
import '../../ui/theme.dart';
import 'auth_scaffold.dart';

/// Add an instance: one URL plus one credential set, and nothing else.
///
/// Registering and signing in are the same form with a different verb, because
/// on a self-hosted instance the first thing a person does is create the
/// account they are about to sign in with.
class AddProfileScreen extends ConsumerStatefulWidget {
  const AddProfileScreen({super.key, this.canGoBack = true});

  final bool canGoBack;

  @override
  ConsumerState<AddProfileScreen> createState() => _AddProfileScreenState();
}

class _AddProfileScreenState extends ConsumerState<AddProfileScreen> {
  final _url = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _label = TextEditingController();

  bool _register = false;
  bool _busy = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    _url.dispose();
    _email.dispose();
    _password.dispose();
    _label.dispose();
    super.dispose();
  }

  String get _normalisedUrl => normaliseBaseUrl(_url.text);

  /// http is warned about, never blocked: self-hosters run plain
  /// `http://localhost`, and an app that refuses it is an app they cannot use.
  bool get _insecure =>
      _normalisedUrl.startsWith('http://') && _normalisedUrl.isNotEmpty;

  String? _validate() {
    if (_url.text.trim().isEmpty) return 'Enter the address of your instance';
    final uri = Uri.tryParse(_normalisedUrl);
    if (uri == null || uri.host.isEmpty) return 'That does not look like a URL';
    if (!_email.text.contains('@')) return 'Enter your email address';
    if (_password.text.isEmpty) return 'Enter your password';
    // Mirrored as a courtesy; the server decides and reports per field.
    if (_register && _password.text.length < 10) {
      return 'Passwords need at least 10 characters, with upper case, lower case and a digit';
    }
    return null;
  }

  Future<void> _submit() async {
    final problem = _validate();
    if (problem != null) {
      setState(() {
        _error = problem;
        _fieldErrors = const {};
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors = const {};
    });

    final result = await ref.read(authControllerProvider.notifier).addProfile(
          label: _label.text,
          baseUrl: _normalisedUrl,
          email: _email.text,
          password: _password.text,
          register: _register,
        );

    if (!mounted) return;
    switch (result) {
      case SignInOk():
        // The router takes it from here: it sends us to the gates if the
        // session needs 2FA or a confirmed address, and to the app if not.
        context.go('/');
      case SignInFailed(:final message, :final fieldErrors):
        setState(() {
          _busy = false;
          _error = message;
          _fieldErrors = fieldErrors;
        });
    }
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
        title: _register ? 'Create an account' : 'Add an instance',
        subtitle: _register
            ? 'Your instance decides the password rules; ten characters with '
                'mixed case and a digit will pass.'
            : 'An ayeaye instance is one address. The API, the app and your '
                'files all live behind it.',
        onBack: widget.canGoBack ? () => context.pop() : null,
        children: [
          ShadInputFormField(
            controller: _url,
            label: const Text('Instance address'),
            placeholder: const Text('tasks.example.com'),
            keyboardType: TextInputType.url,
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            onChanged: (_) => setState(() {}),
          ),
          if (_insecure) ...[
            const SizedBox(height: Gap.sm),
            const NoticeCard(
              icon: LucideIcons.triangleAlert,
              message: 'This connects over plain http, so traffic is not '
                  'encrypted. That is normal for a local instance.',
            ),
          ],
          const SizedBox(height: Gap.lg),
          ShadInputFormField(
            controller: _email,
            label: const Text('Email'),
            placeholder: const Text('you@example.com'),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            // The server's own per-field rejection, shown where it belongs.
            forceErrorText: _fieldErrors['email'],
          ),
          const SizedBox(height: Gap.lg),
          ShadInputFormField(
            controller: _password,
            label: const Text('Password'),
            obscureText: true,
            placeholder: const Text('••••••••••'),
            onSubmitted: (_) => _busy ? null : _submit(),
            forceErrorText: _fieldErrors['password'],
          ),
          const SizedBox(height: Gap.lg),
          ShadInputFormField(
            controller: _label,
            label: const Text('Name for this profile'),
            description: const Text('Optional — defaults to the hostname.'),
            placeholder: const Text('Work'),
          ),
          const SizedBox(height: Gap.lg),
          ShadSwitch(
            value: _register,
            onChanged: (v) => setState(() {
              _register = v;
              _error = null;
              _fieldErrors = const {};
            }),
            label: const Text('Create a new account'),
            sublabel: const Text('Turn this on if you have not registered yet'),
          ),
          if (_error != null) ...[
            const SizedBox(height: Gap.lg),
            NoticeCard(message: _error!, destructive: true),
          ],
          const SizedBox(height: Gap.xl),
          ShadButton(
            onPressed: _busy ? null : _submit,
            width: double.infinity,
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
            child: Text(_register ? 'Create account and sign in' : 'Sign in'),
          ),
        ],
      );
}
