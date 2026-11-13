import 'package:flutter/material.dart';

import '../../core/auth_service.dart';
import '../../core/navigation.dart';
import '../../core/validators.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/auth_scaffold.dart';
import '../../widgets/google_button.dart';
import '../../widgets/password_strength.dart';
import 'login_page.dart';
import 'verify_email_page.dart';

/// Page 4: create an account with email and password, or with Google.
/// Google "sign up" and "log in" are the same call: Supabase creates the
/// account the first time and logs in on later visits.
class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  bool _busy = false;
  bool _googleBusy = false;
  bool _agreed = false;
  bool _consentMissing = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final valid = _formKey.currentState?.validate() ?? false;
    if (!_agreed) setState(() => _consentMissing = true);
    if (!valid || !_agreed) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final outcome = await AuthService.signUp(
        name: _name.text,
        email: _email.text,
        password: _password.text,
      );
      if (!mounted) return;
      if (outcome == SignUpOutcome.needsEmailConfirmation) {
        Navigator.of(context).pushReplacement(
          slideRoute(VerifyEmailPage(email: _email.text.trim())),
        );
      }
      // Otherwise the account is already signed in and AuthNavigator
      // moves to Home.
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _googleBusy = true;
      _error = null;
    });
    try {
      await AuthService.signInWithGoogle();
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final disabled = _busy || _googleBusy;

    return AuthScaffold(
      title: 'Create your account',
      subtitle: 'Sync your favourites and alerts across devices.',
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) AuthErrorBanner(message: _error!),
              AppTextField(
                controller: _name,
                label: 'Full name',
                icon: Icons.person_outline_rounded,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                validator: Validators.name,
                enabled: !disabled,
                onFieldSubmitted: (_) => _emailFocus.requestFocus(),
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _email,
                label: 'Email',
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                validator: Validators.email,
                enabled: !disabled,
                focusNode: _emailFocus,
                onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _password,
                label: 'Password',
                focusNode: _passwordFocus,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                validator: Validators.newPassword,
                enabled: !disabled,
                onChanged: (_) => setState(() {}),
                onFieldSubmitted: (_) => _confirmFocus.requestFocus(),
              ),
              const SizedBox(height: 10),
              PasswordStrengthMeter(password: _password.text),
              const SizedBox(height: 16),
              PasswordField(
                controller: _confirm,
                label: 'Confirm password',
                focusNode: _confirmFocus,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                enabled: !disabled,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please confirm your password';
                  }
                  if (value != _password.text) return 'Passwords do not match';
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: disabled
                    ? null
                    : () => setState(() {
                        _agreed = !_agreed;
                        _consentMissing = false;
                      }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _agreed,
                        onChanged: disabled
                            ? null
                            : (value) => setState(() {
                                _agreed = value ?? false;
                                _consentMissing = false;
                              }),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            'I understand CampusFlow stores only my name and '
                            'email. Sensors count people anonymously, with no '
                            'cameras.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: _consentMissing
                                  ? scheme.error
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_consentMissing)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 4),
                  child: Text(
                    'Please tick the box to continue',
                    style: TextStyle(fontSize: 12, color: scheme.error),
                  ),
                ),
              const SizedBox(height: 12),
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
                    : const Text('Create account'),
              ),
              const SizedBox(height: 24),
              const OrDivider(),
              const SizedBox(height: 24),
              GoogleButton(
                label: 'Sign up with Google',
                loading: _googleBusy,
                onPressed: disabled ? null : _google,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Already have an account?',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  TextButton(
                    onPressed: disabled
                        ? null
                        : () => Navigator.of(context)
                              .pushReplacement(slideRoute(const LoginPage())),
                    child: const Text('Log in'),
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
