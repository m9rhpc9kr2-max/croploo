import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/theme/theme_settings.dart';
import '../../core/utils/desktop_platform.dart';
import 'auth_api.dart';
import 'auth_session.dart';
import 'login_screen.dart';
import 'session_storage.dart';

/// Entry point for the app's primary window (window id 0).
///
/// On desktop this window shows *only* the login screen: on successful
/// sign-in it opens a brand-new native OS window running the full Croploo
/// app and closes itself, so the login window disappears once the user
/// is in. On platforms without real multi-window support (web) it falls
/// back to swapping in the dashboard within the same window.
class LoginWindowApp extends StatefulWidget {
  const LoginWindowApp({super.key});

  @override
  State<LoginWindowApp> createState() => _LoginWindowAppState();
}

class _LoginWindowAppState extends State<LoginWindowApp> with WidgetsBindingObserver {
  bool _authenticatedInPlace = false;
  AuthResult? _inPlaceResult;
  bool _restoringSession = true;
  ThemeSettings _settings = const ThemeSettings(accentColor: Color(0xFFF5C842));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (supportsMultiWindow) {
      // The default primary-window frame (set in the native project) isn't
      // sized or positioned for a small login form — make it compact and
      // centered as soon as this window comes up.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final main = WindowController.main();
        await main.setFrame(const Rect.fromLTWH(0, 0, 1600, 900));
        await main.center();
      });
    }
    _loadSettings();
    _restoreSession();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('croploo_theme_settings');
      if (jsonString != null) {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        setState(() => _settings = ThemeSettings.fromJson(json));
      }
    } catch (_) {
      // Fall back to the default login theme.
    }
  }

  /// Restores a previously saved session on launch, so signing in once
  /// keeps the user signed in on subsequent app starts. Falls through to
  /// the normal login screen if there's no saved session or it's expired.
  Future<void> _restoreSession() async {
    final stored = await SessionStorage.load();
    if (stored == null) {
      if (mounted) setState(() => _restoringSession = false);
      return;
    }
    try {
      final result = await AuthApi().me(stored.accessToken);
      await _onAuthenticated(result);
    } catch (_) {
      await SessionStorage.clear();
    } finally {
      if (mounted) setState(() => _restoringSession = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    setState(() {});
  }

  Future<void> _onAuthenticated(AuthResult result) async {
    await SessionStorage.save(result);

    if (!supportsMultiWindow) {
      setState(() {
        _inPlaceResult = result;
        _authenticatedInPlace = true;
      });
      return;
    }

    final payload = jsonEncode({
      'accessToken': result.accessToken,
      'email': result.email,
      'username': result.username,
      'name': result.name,
    });
    final controller = await DesktopMultiWindow.createWindow(payload);
    await controller.setFrame(const Rect.fromLTWH(0, 0, 1600, 900));
    await controller.center();
    await controller.setTitle('Croploo');
    await controller.show();

    // Close the login window now that the dashboard window is up.
    await WindowController.main().close();
  }

  @override
  Widget build(BuildContext context) {
    if (_authenticatedInPlace) {
      final result = _inPlaceResult!;
      final session = AuthSession(
        accessToken: result.accessToken,
        email: result.email,
        username: result.username,
        name: result.name,
      );
      return ProviderScope(
        overrides: [authSessionProvider.overrideWith((ref) => session)],
        child: const CroplooApp(),
      );
    }
    // Login window always uses a clean light/white theme with a neutral
    // dark accent so it never inherits the user's saved gold accent.
    final theme = CroplooTheme.fromSettings(
      _settings.copyWith(
        brightness: CroplooBrightness.light,
        accentColor: const Color(0xFF111111),
      ),
    );

    if (_restoringSession) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildCroplooTheme(theme),
        home: Scaffold(
          backgroundColor: theme.bgSurface,
          body: Center(
            child: CircularProgressIndicator(color: theme.accent),
          ),
        ),
      );
    }

    return MaterialApp(
      title: 'Croploo — Sign in',
      debugShowCheckedModeBanner: false,
      theme: buildCroplooTheme(theme),
      home: LoginScreen(onAuthenticated: _onAuthenticated),
    );
  }
}
