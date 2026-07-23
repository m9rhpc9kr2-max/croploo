import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/theme/theme_providers.dart';
import '../../shared/widgets/controls.dart';
import '../../shared/widgets/window_controls.dart';
import 'cullyai_panel.dart';

/// Root widget for the CullyAI chat window when popped out of the main
/// dashboard into its own native OS window — see the detach button in
/// [CullyAiPanel] and the `kind: 'cullyai'` window payload handled in
/// `main.dart`. This is a separate Flutter engine, so it gets its own,
/// fresh chat history rather than sharing the docked panel's. Expects a
/// `ProviderScope` with `authSessionProvider` already overridden by the
/// caller, same as `CroplooApp`.
class CullyAiWindowApp extends ConsumerWidget {
  const CullyAiWindowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeSettingsProvider);
    final theme = CroplooTheme.fromSettings(settings);
    return MaterialApp(
      title: 'CullyAI',
      debugShowCheckedModeBanner: false,
      theme: buildCroplooTheme(theme),
      home: const _CullyAiWindowScaffold(),
    );
  }
}

class _CullyAiWindowScaffold extends ConsumerWidget {
  const _CullyAiWindowScaffold();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    return Scaffold(
      backgroundColor: theme.bgPrimary,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const WindowControls(),
              const Expanded(child: WindowDragArea()),
            ],
          ),
          Expanded(
            child: CullyAiChatView(
              headerActions: [
                CroplooIconButton(
                  icon: PhosphorIconsRegular.x,
                  size: 32,
                  iconColor: theme.textSecondary,
                  onPressed: () => const MethodChannel('croploo/window_controls')
                      .invokeMethod('close'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
