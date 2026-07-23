import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Caches the last-good raw JSON response per GET endpoint locally, so
/// that when the network is down (common on desktop in rural areas with
/// poor internet) the app shows yesterday's basis/futures/alerts values
/// instead of an empty screen. Only used for unauthenticated, non-user-
/// specific endpoints — see [LiveCroplooRepository]'s `_getList`/`_getObject`.
class OfflineCache {
  OfflineCache._();

  static SharedPreferences? _prefs;
  static final _prefsLock = Lock();
  static bool _initialized = false;

  /// Set by the UI layer (see providers.dart) whenever a request falls
  /// back to cached data, so a banner can show "Offline — data as of ...".
  /// Cleared (set to null) whenever a live request succeeds.
  static void Function(DateTime? cachedAt)? onFallback;

  static Future<SharedPreferences> _instance() async {
    if (_initialized && _prefs != null) return _prefs!;
    return await _prefsLock.synchronized(() async {
      if (_initialized && _prefs != null) return _prefs!;
      _prefs = await SharedPreferences.getInstance();
      _initialized = true;
      return _prefs!;
    });
  }

  static String _dataKey(String key) => 'offline_cache_v1_$key';
  static String _atKey(String key) => 'offline_cache_v1_${key}_at';

  static Future<void> store(String key, String rawJson) async {
    try {
      final prefs = await _instance();
      await prefs.setString(_dataKey(key), rawJson);
      await prefs.setString(_atKey(key), DateTime.now().toIso8601String());
      onFallback?.call(null);
    } catch (e) {
      // Silently fail cache writes to prevent app freezes
    }
  }

  /// Returns the cached raw JSON and its timestamp, or null if nothing's
  /// cached yet for this key (e.g. first-ever launch while offline).
  static Future<(String, DateTime)?> read(String key) async {
    try {
      final prefs = await _instance();
      final data = prefs.getString(_dataKey(key));
      final atRaw = prefs.getString(_atKey(key));
      if (data == null || atRaw == null) return null;
      final at = DateTime.tryParse(atRaw);
      if (at == null) return null;
      onFallback?.call(at);
      return (data, at);
    } catch (e) {
      // Silently fail cache reads to prevent app freezes
      return null;
    }
  }

  /// Wipes every cached response (all `offline_cache_v1_*` keys) — used
  /// on sign-out so a different user signing in on the same device
  /// never sees a stale previous user's cached data.
  static Future<void> clearAll() async {
    try {
      final prefs = await _instance();
      final keys = prefs.getKeys().where((k) => k.startsWith('offline_cache_v1_'));
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (e) {
      // Silently fail to prevent app freezes
    }
  }
}

/// Simple mutex for synchronizing access to SharedPreferences
class Lock {
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
