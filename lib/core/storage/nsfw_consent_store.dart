import 'package:shared_preferences/shared_preferences.dart';

/// Stores whether the user has chosen to reveal sensitive content.
///
/// Sensitive content (mature themes such as violence or distressing topics) is
/// shown with a blur and a content warning. This is a viewing preference, not an
/// age gate - the user simply opts in to revealing it.
class NsfwConsentStore {
  static const String _keyHasConfirmed = 'sensitive_content_reveal_opt_in';

  /// Whether the user has previously chosen to reveal sensitive content.
  static Future<bool> hasConfirmed18Plus() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyHasConfirmed) ?? false;
  }

  /// Persist the user's choice to reveal sensitive content.
  static Future<void> setConfirmed18Plus(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHasConfirmed, value);
  }
}
