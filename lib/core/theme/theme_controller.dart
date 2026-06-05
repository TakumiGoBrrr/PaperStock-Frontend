import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_mode_local_storage.dart';

final themeControllerProvider =
    AsyncNotifierProvider<ThemeController, ThemeMode>(
  ThemeController.new,
);

class ThemeController extends AsyncNotifier<ThemeMode> {
  static const _prefsKey = 'theme_mode';

  @override
  Future<ThemeMode> build() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_prefsKey);

    final mode = switch (value) {
      'light' => ThemeMode.light,
      _ => ThemeMode.dark,
    };

    writeThemeModeToLocalStorage(mode == ThemeMode.light ? 'light' : 'dark');
    return mode;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = AsyncData(mode);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      mode == ThemeMode.light ? 'light' : 'dark',
    );

    writeThemeModeToLocalStorage(mode == ThemeMode.light ? 'light' : 'dark');
  }

  Future<void> setDarkMode(bool enabled) async {
    await setThemeMode(enabled ? ThemeMode.dark : ThemeMode.light);
  }
}
