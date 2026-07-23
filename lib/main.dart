import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';

import 'app.dart';
import 'features/auth/auth_session.dart';
import 'features/auth/login_window_app.dart';
import 'features/cullyai/cullyai_window_app.dart';

/// The platform is delivering a duplicate KeyDownEvent for some keystrokes
/// (root cause still to be found). The first delivery updates
/// `HardwareKeyboard` state and dispatches normally; the duplicate
/// just fails `HardwareKeyboard`'s own consistency assert. Flutter already
/// catches and drops that assert harmlessly, so the only actual problem is
/// console noise — this just silences that one known-benign message without
/// touching keyboard state. (A prior version of this function tried to
/// "repair" state by synthesizing a compensating KeyUpEvent, but that
/// desynced from the *real* key-up arriving later and caused a fresh
/// assertion — and total keyboard lockup — on every keystroke. Don't
/// reintroduce that.)
void _installDuplicateKeyEventLogFilter() {
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exception.toString().contains('physical key is already pressed')) {
      return;
    }
    originalOnError?.call(details);
  };
}

/// [args] is empty for the app's primary window (window id 0). Every other
/// native window this app spawns via `desktop_multi_window` (the dashboard
/// window after login, or a detached panel like CullyAI's chat — see
/// [CullyAiPanel]'s detach button) re-invokes this `main` in a fresh engine
/// with `['multi_window', windowId, jsonArguments]`; `jsonArguments`'
/// `kind` field says which window content to build.
void main(List<String> args) async {
  _installDuplicateKeyEventLogFilter();
  if (args.isNotEmpty && args.first == 'multi_window') {
    WidgetsFlutterBinding.ensureInitialized();
    // Only desktop windows (not the login window) need alert
    // notifications, so this is set up here rather than for it too.
    await localNotifier.setup(
      appName: 'Croploo',
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );
    final payload = args.length > 2 && args[2].isNotEmpty
        ? jsonDecode(args[2]) as Map<String, dynamic>
        : <String, dynamic>{};
    final session = payload['accessToken'] != null
        ? AuthSession(
            accessToken: payload['accessToken'] as String,
            email: (payload['email'] ?? '') as String,
            username: (payload['username'] ?? '') as String,
            name: (payload['name'] ?? '') as String,
          )
        : null;
    final child = switch (payload['kind']) {
      'cullyai' => const CullyAiWindowApp(),
      'route' => CroplooApp(
          initialLocation: payload['path'] as String? ?? '/',
          standalone: true,
        ),
      _ => const CroplooApp(),
    };
    runApp(
      ProviderScope(
        overrides: [authSessionProvider.overrideWith((ref) => session)],
        child: child,
      ),
    );
    return;
  }
  runApp(const ProviderScope(child: LoginWindowApp()));
}
