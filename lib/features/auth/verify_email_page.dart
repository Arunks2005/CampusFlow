import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/auth_service.dart';
import '../../core/navigation.dart';
import '../../widgets/auth_scaffold.dart';
import 'login_page.dart';

/// Page 7: shown when Supabase needs the user to confirm their email.
/// Tapping the link in the email opens the app and logs the user in.
class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({super.key, required this.email});

  final String email;

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  static const _cooldownSeconds = 60;

  Timer? _timer;
  int _secondsLeft = 0;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _secondsLeft = _cooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) timer.cancel();
    });
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await AuthService.resendConfirmation(widget.email);
      if (!mounted) return;
      setState(() => _info = 'Email sent again. Check your inbox and spam.');
      _startCooldown();
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canResend = !_busy && _secondsLeft <= 0;

    return AuthScaffold(
      title: 'Check your inbox',
      subtitle: 'One last step to activate your account.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.mark_email_unread_outlined,
                size: 44,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'We sent a confirmation link to',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.email,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Open the email on this phone and tap the link. The app will log '
            'you in automatically.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          if (_error != null) AuthErrorBanner(message: _error!),
          if (_info != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                _info!,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.primary),
              ),
            ),
          FilledButton(
            onPressed: canResend ? _resend : null,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _secondsLeft > 0
                        ? 'Resend in ${_secondsLeft}s'
                        : 'Resend email',
                  ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pushReplacement(
              slideRoute(LoginPage(initialEmail: widget.email)),
            ),
            child: const Text('Back to log in'),
          ),
        ],
      ),
    );
  }
}
