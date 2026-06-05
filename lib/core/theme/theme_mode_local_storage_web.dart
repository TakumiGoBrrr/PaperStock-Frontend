import 'package:shared_preferences/shared_preferences.dart';

void writeThemeModeToLocalStorage(String value) {
  SharedPreferences.getInstance().then((prefs) {
    return prefs.setString('theme_mode', value);
  });
}
