import 'package:shared_preferences/shared_preferences.dart';

/// Tiny wrapper around local storage. No database or internet needed.
class AppPrefs {
  AppPrefs._();

  static const _kOnboardingSeen = 'onboarding_seen';
  static const _kGuest = 'guest_mode';

  static Future<bool> isOnboardingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOnboardingSeen) ?? false;
  }

  static Future<void> setOnboardingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingSeen, true);
  }

  static Future<bool> isGuest() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kGuest) ?? false;
  }

  static Future<void> setGuest(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kGuest, value);
  }

  /// Used by the "Reset app" test button.
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
