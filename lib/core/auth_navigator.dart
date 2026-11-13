import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/set_new_password_page.dart';
import '../features/placeholder/placeholder_pages.dart';
import '../features/welcome/welcome_page.dart';
import 'app_prefs.dart';
import 'navigation.dart';

/// Listens to Supabase login events for the whole app and moves to the right
/// screen. This is what makes Google sign-in work: when the browser sends the
/// user back to the app, the session arrives here as a "signed in" event, on
/// whatever page happens to be showing.
class AuthNavigator {
  AuthNavigator._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static StreamSubscription<AuthState>? _subscription;
  static String? _lastUserId;
  static bool _recovering = false;
  static bool _pendingRecovery = false;

  /// Call once from main(), after Supabase.initialize().
  static void start() {
    _lastUserId = Supabase.instance.client.auth.currentUser?.id;
    _subscription?.cancel();
    _subscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      _handle,
      onError: (Object error) => debugPrint('Auth event error: $error'),
    );
  }

  /// True if a password-reset link opened the app before the first screen
  /// existed. The splash page asks for this once.
  static bool takePendingRecovery() {
    final pending = _pendingRecovery;
    _pendingRecovery = false;
    return pending;
  }

  /// Called after the user has set a new password.
  static void finishRecovery() {
    _recovering = false;
    _lastUserId = Supabase.instance.client.auth.currentUser?.id;
    _replaceAll(const HomePlaceholderPage());
  }

  static Future<void> _handle(AuthState state) async {
    switch (state.event) {
      case AuthChangeEvent.signedIn:
        final user = state.session?.user;
        if (user == null || user.id == _lastUserId || _recovering) return;
        _lastUserId = user.id;
        await AppPrefs.setGuest(false);
        await AppPrefs.setOnboardingSeen();
        _replaceAll(const HomePlaceholderPage());
      case AuthChangeEvent.signedOut:
        if (_lastUserId == null) return;
        _lastUserId = null;
        _recovering = false;
        _replaceAll(const WelcomePage());
      case AuthChangeEvent.passwordRecovery:
        _recovering = true;
        final navigator = navigatorKey.currentState;
        if (navigator == null) {
          _pendingRecovery = true;
          return;
        }
        navigator.push(slideRoute(const SetNewPasswordPage()));
      default:
        break;
    }
  }

  static void _replaceAll(Widget page) {
    navigatorKey.currentState?.pushAndRemoveUntil(
      fadeRoute(page),
      (route) => false,
    );
  }
}
