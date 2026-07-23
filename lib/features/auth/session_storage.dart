import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'auth_api.dart';

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

/// Caches the signed-in session locally (plain app-preferences storage,
/// not Keychain) so the app can restore it on the next launch without
/// showing the login screen again.
class SessionStorage {
  SessionStorage._();

  static const _key = 'croploo_session';
  static final _prefsLock = _Lock();
  static SharedPreferences? _prefs;
  static bool _initialized = false;

  static Future<SharedPreferences> _instance() async {
    if (_initialized && _prefs != null) return _prefs!;
    return await _prefsLock.synchronized(() async {
      if (_initialized && _prefs != null) return _prefs!;
      _prefs = await SharedPreferences.getInstance();
      _initialized = true;
      return _prefs!;
    });
  }

  static Future<void> save(AuthResult result) async {
    try {
      final prefs = await _instance();
      await prefs.setString(
        _key,
        jsonEncode({
          'accessToken': result.accessToken,
          'email': result.email,
          'username': result.username,
          'name': result.name,
        }),
      );
    } catch (e) {
      // Silently fail to prevent app freezes
    }
  }

  static Future<AuthResult?> load() async {
    try {
      final prefs = await _instance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return AuthResult(
        accessToken: json['accessToken'] as String,
        email: json['email'] as String,
        username: json['username'] as String,
        name: json['name'] as String,
      );
    } catch (e) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await _instance();
      await prefs.remove(_key);
    } catch (e) {
      // Silently fail to prevent app freezes
    }
  }
}
