import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controls the brightness (dark / light) of swipe cards and the reading view
/// independently from the global app [ThemeMode].
final cardBrightnessProvider =
    AsyncNotifierProvider<CardBrightnessNotifier, Brightness>(
  CardBrightnessNotifier.new,
);

class CardBrightnessNotifier extends AsyncNotifier<Brightness> {
  static const _key = 'card_brightness';

  @override
  Future<Brightness> build() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    return stored == 'light' ? Brightness.light : Brightness.dark;
  }

  Future<void> toggle() async {
    final current = state.valueOrNull ?? Brightness.dark;
    final next =
        current == Brightness.dark ? Brightness.light : Brightness.dark;
    state = AsyncData(next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, next == Brightness.light ? 'light' : 'dark');
  }
}
