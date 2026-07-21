import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'settings_provider.g.dart';

const _simpleModeKey = 'sosecure.simpleMode';
const _themeModeKey = 'sosecure.themeMode';

// Espeja lib/store.ts: simpleMode persistido en localStorage en la web -> shared_preferences
// aquí. El tema/idioma los maneja easy_localization/ThemeMode nativamente, sin duplicar
// estado — este provider solo cubre lo que no tiene ya un mecanismo de persistencia propio.
@Riverpod(keepAlive: true)
class SimpleMode extends _$SimpleMode {
  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_simpleModeKey) ?? false;
  }

  Future<void> set(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_simpleModeKey, value);
  }
}

// El default de la web es oscuro (:root sin clase = dark, .light es el opt-in — ver
// app/globals.css), así que el default aquí también es ThemeMode.dark, no system.
@Riverpod(keepAlive: true)
class AppThemeMode extends _$AppThemeMode {
  @override
  ThemeMode build() {
    _load();
    return ThemeMode.dark;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_themeModeKey);
    if (saved == 'light') state = ThemeMode.light;
    if (saved == 'dark') state = ThemeMode.dark;
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode == ThemeMode.light ? 'light' : 'dark');
  }
}
