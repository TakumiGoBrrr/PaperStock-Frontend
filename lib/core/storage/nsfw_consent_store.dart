import 'package:shared_preferences/shared_preferences.dart';

/// Stores whether the user has confirmed they are 18+ to view NSFW content.
class NsfwConsentStore {
  static const String _keyHasConfirmed18Plus = 'nsfw_has_confirmed_18_plus';

  /// Check if user has previously confirmed they are 18+
  static Future<bool> hasConfirmed18Plus() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyHasConfirmed18Plus) ?? false;
  }

  /// Save that user has confirmed they are 18+
  static Future<void> setConfirmed18Plus(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHasConfirmed18Plus, value);
  }
}
