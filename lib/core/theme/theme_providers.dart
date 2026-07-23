import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_settings.dart';

const _settingsKey = 'croploo_theme_settings';

/// Simple mutex for synchronizing access to SharedPreferences
class _Lock {
  Completer<void>? _completer;

  Future<T> synchronized<T>(Future<T> Function() fn) async {
    while (_completer != null) {
      await _completer!.future;
    }
    _completer = Completer<void>();
    try {
      return await fn();
    } finally {
      _completer!.complete();
      _completer = null;
    }
  }
}

/// User-controlled appearance settings. Values are loaded from and persisted
/// to SharedPreferences automatically.
final themeSettingsProvider =
    StateNotifierProvider<ThemeSettingsNotifier, ThemeSettings>(
  (ref) => ThemeSettingsNotifier(),
);

class ThemeSettingsNotifier extends StateNotifier<ThemeSettings> {
  ThemeSettingsNotifier() : super(const ThemeSettings()) {
    _load();
  }

  static final _prefsLock = _Lock();
  static SharedPreferences? _prefs;
  static bool _initialized = false;
  Timer? _saveTimer;

  static Future<SharedPreferences> _instance() async {
    if (_initialized && _prefs != null) return _prefs!;
    return await _prefsLock.synchronized(() async {
      if (_initialized && _prefs != null) return _prefs!;
      _prefs = await SharedPreferences.getInstance();
      _initialized = true;
      return _prefs!;
    });
  }

  Future<void> _load() async {
    try {
      final prefs = await _instance();
      final jsonString = prefs.getString(_settingsKey);
      if (jsonString != null) {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        final loaded = ThemeSettings.fromJson(json);
        // Migration: ensure new fields have default values if missing from old saved settings
        state = ThemeSettings(
          brightness: loaded.brightness,
          useBorders: loaded.useBorders,
          useAppBlur: loaded.useAppBlur,
          accentColor: loaded.accentColor,
          windowControlStyle: loaded.windowControlStyle,
          windowControlAlignment: loaded.windowControlAlignment,
          numberFormatStyle: loaded.numberFormatStyle,
          distanceUnit: loaded.distanceUnit,
          volumeUnit: loaded.volumeUnit,
          temperatureUnit: loaded.temperatureUnit, // Will use default if field was missing
          desktopNotifications: loaded.desktopNotifications,
        );
      }
    } catch (e) {
      // Ignore corrupted settings and fall back to defaults.
    }
  }

  Future<void> _save() async {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final prefs = await _instance();
        await prefs.setString(_settingsKey, jsonEncode(state.toJson()));
      } catch (e) {
        // Persistence is best-effort; don't crash the app on failure.
      }
    });
  }

  @override
  set state(ThemeSettings value) {
    super.state = value;
    _save();
  }

  void setBrightness(CroplooBrightness value) {
    state = state.copyWith(brightness: value);
  }

  void setUseBorders(bool value) {
    state = state.copyWith(useBorders: value);
  }

  void setUseAppBlur(bool value) {
    state = state.copyWith(useAppBlur: value);
  }

  void setCustomCursor(bool value) {
    state = state.copyWith(customCursor: value);
  }

  void hideNavRoute(String route) {
    state = state.copyWith(hiddenNavRoutes: {...state.hiddenNavRoutes, route});
  }

  void showNavRoute(String route) {
    state = state.copyWith(
      hiddenNavRoutes: state.hiddenNavRoutes.where((r) => r != route).toSet(),
    );
  }

  void showAllNavRoutes() {
    state = state.copyWith(hiddenNavRoutes: const {});
  }

  void setShowTicker(bool value) {
    state = state.copyWith(showTicker: value);
  }

  void setAccentColor(Color value) {
    state = state.copyWith(accentColor: value);
  }

  void setWindowControlStyle(WindowControlStyle value) {
    state = state.copyWith(windowControlStyle: value);
  }

  void setWindowControlAlignment(WindowControlAlignment value) {
    state = state.copyWith(windowControlAlignment: value);
  }

  void setNumberFormatStyle(NumberFormatStyle value) {
    state = state.copyWith(numberFormatStyle: value);
  }

  void setDistanceUnit(DistanceUnit value) {
    state = state.copyWith(distanceUnit: value);
  }

  void setVolumeUnit(VolumeUnit value) {
    state = state.copyWith(volumeUnit: value);
  }

  void setTemperatureUnit(TemperatureUnit value) {
    state = state.copyWith(temperatureUnit: value);
  }

  void setDesktopNotifications(bool value) {
    state = state.copyWith(desktopNotifications: value);
  }
}
