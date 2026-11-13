import 'package:supabase_flutter/supabase_flutter.dart';

enum SignUpOutcome { signedIn, needsEmailConfirmation }

/// An error with a message that is safe and friendly to show to the user.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// All Supabase authentication calls live here.
class AuthService {
  AuthService._();

  /// Must match the Android intent filter and the Redirect URLs entry
  /// in Supabase, including the trailing slash.
  static const redirectUrl = 'io.supabase.campusflow://login-callback/';

  static GoTrueClient get _auth => Supabase.instance.client.auth;

  static User? get currentUser => _auth.currentUser;
  static Session? get currentSession => _auth.currentSession;

  static Future<SignUpOutcome> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final response = await _auth.signUp(
        email: email.trim(),
        password: password,
        data: {'full_name': name.trim()},
        emailRedirectTo: redirectUrl,
      );

      // Supabase may return a user with no identities when this email
      // already has an account and email confirmation is enabled.
      final identities = response.user?.identities;
      if (identities != null && identities.isEmpty) {
        throw const AuthFailure(
          'This email is already registered. Try logging in instead.',
        );
      }

      return response.session != null
          ? SignUpOutcome.signedIn
          : SignUpOutcome.needsEmailConfirmation;
    } on AuthFailure {
      rethrow;
    } catch (error) {
      throw AuthFailure(friendlyMessage(error));
    }
  }

  static Future<void> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } catch (error) {
      throw AuthFailure(friendlyMessage(error));
    }
  }

  /// Google sign-up and sign-in use the same flow:
  /// the first successful Google login creates the account.
  static Future<void> signInWithGoogle() async {
    try {
      final opened = await _auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectUrl,
      );

      if (!opened) {
        throw const AuthFailure(
          'Could not open the Google sign-in page. Please try again.',
        );
      }
    } on AuthFailure {
      rethrow;
    } catch (error) {
      throw AuthFailure(friendlyMessage(error));
    }
  }

  static Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: redirectUrl,
      );
    } catch (error) {
      throw AuthFailure(friendlyMessage(error));
    }
  }

  static Future<void> resendConfirmation(String email) async {
    try {
      await _auth.resend(
        type: OtpType.signup,
        email: email.trim(),
        emailRedirectTo: redirectUrl,
      );
    } catch (error) {
      throw AuthFailure(friendlyMessage(error));
    }
  }

  static Future<void> updatePassword(String newPassword) async {
    try {
      await _auth.updateUser(
        UserAttributes(password: newPassword),
      );
    } catch (error) {
      throw AuthFailure(friendlyMessage(error));
    }
  }

  /// Call this only when the user chooses to log out.
  static Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (error) {
      throw AuthFailure(friendlyMessage(error));
    }
  }

  /// Turns Supabase errors into messages suitable for the UI.
  static String friendlyMessage(Object error) {
    final raw = error is AuthException ? error.message : error.toString();
    final text = raw.toLowerCase();

    if (text.contains('unsupported provider') &&
        text.contains('not enabled')) {
      return 'Google sign-in is not enabled for this Supabase project. '
          'Enable the Google provider in Supabase Authentication settings.';
    }

    if (text.contains('invalid login credentials')) {
      return 'Wrong email or password.';
    }

    if (text.contains('email not confirmed')) {
      return 'Please confirm your email first. Check your inbox.';
    }

    if (text.contains('already registered') ||
        text.contains('already been registered')) {
      return 'This email is already registered. Try logging in instead.';
    }

    if (text.contains('password should be at least') ||
        text.contains('weak password')) {
      return 'That password is too weak. Use at least 8 characters with '
          'letters and numbers.';
    }

    if (text.contains('same password') ||
        text.contains('different from the old')) {
      return 'Your new password must be different from the old one.';
    }

    if (text.contains('not authorized') && text.contains('email')) {
      return "Supabase's built-in email service cannot send to this address. "
          'Turn off email confirmation for testing, or set up custom SMTP.';
    }

    if (text.contains('rate limit') ||
        text.contains('too many requests') ||
        text.contains('security purposes')) {
      return 'Too many attempts. Please wait a few minutes and try again.';
    }

    if (text.contains('unable to validate email') ||
        text.contains('invalid format')) {
      return 'That email address does not look valid.';
    }

    if (text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('clientexception') ||
        text.contains('timed out') ||
        text.contains('network')) {
      return 'No internet connection. Check your network and try again.';
    }

    if (error is AuthException && error.message.isNotEmpty) {
      return error.message;
    }

    return 'Something went wrong. Please try again.';
  }
}