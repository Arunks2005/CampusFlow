import 'package:flutter/material.dart';

import '../../core/auth_service.dart';
import '../../core/navigation.dart';
import '../../core/validators.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/auth_scaffold.dart';
import '../../widgets/google_button.dart';
import 'forgot_password_page.dart';
import 'sign_up_page.dart';
import 'verify_email_page.dart';

/// Page 5: log in with email and password, or with Google.
/// After a successful login AuthNavigator moves the app to Home.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email;
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _busy = false;
  bool _googleBusy = false;
  bool _needsConfirmation = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
      _needsConfirmation = false;
    });
    try {
      await AuthService.signIn(email: _email.text, password: _password.text);
      // Success: AuthNavigator moves to Home when the session arrives.
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.message;
        _needsConfirmation = failure.message.startsWith('Please confirm');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _googleBusy = true;
      _error = null;
      _needsConfirmation = false;
    });
    try {
      await AuthService.signInWithGoogle();
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  void _openForgotPassword() {
    Navigator.of(context)
        .push(slideRoute(ForgotPasswordPage(initialEmail: _email.text.trim())));
  }

  void _openConfirmation() {
    Navigator.of(context)
        .push(slideRoute(VerifyEmailPage(email: _email.text.trim())));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = _busy || _googleBusy;

    return AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Log in to see live crowd levels and your alerts.',
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                AuthErrorBanner(
                  message: _error!,
                  actionLabel: _needsConfirmation
                      ? 'Resend confirmation email'
                      : null,
                  onAction: _needsConfirmation ? _openConfirmation : null,
                ),
              AppTextField(
                controller: _email,
                label: 'Email',
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                validator: Validators.email,
                enabled: !disabled,
                onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _password,
                label: 'Password',
                focusNode: _passwordFocus,
                textInputAction: TextInputAction.done,
                validator: Validators.loginPassword,
                enabled: !disabled,
                onFieldSubmitted: (_) => _submit(),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: disabled ? null : _openForgotPassword,
                  child: const Text('Forgot password?'),
                ),
              ),
              const SizedBox(height: 4),
              FilledButton(
                onPressed: disabled ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Log in'),
              ),
              const SizedBox(height: 24),
              const OrDivider(),
              const SizedBox(height: 24),
              GoogleButton(
                label: 'Continue with Google',
                loading: _googleBusy,
                onPressed: disabled ? null : _google,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'New here?',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  TextButton(
                    onPressed: disabled
                        ? null
                        : () => Navigator.of(context)
                              .pushReplacement(slideRoute(const SignUpPage())),
                    child: const Text('Create account'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
