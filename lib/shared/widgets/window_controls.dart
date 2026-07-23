import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_colors.dart';
import '../../core/theme/theme_providers.dart';
import '../../core/theme/theme_settings.dart';

const _windowChannel = MethodChannel('croploo/window_controls');

/// Transparent draggable strip that lets the user move the window by
/// click-dragging it, standing in for the native title bar this app hides
/// in favor of custom-drawn [WindowControls].
class WindowDragArea extends StatelessWidget {
  final double height;

  const WindowDragArea({super.key, this.height = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: height);
  }
}

/// Custom window controls (close / minimize / maximize) placed inside the app UI
/// when the native title bar is hidden. Style and alignment are user-configurable.
class WindowControls extends ConsumerWidget {
  final bool canMinimize;
  final bool canMaximize;

  const WindowControls({
    super.key,
    this.canMinimize = true,
    this.canMaximize = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeSettingsProvider);
    final style = settings.windowControlStyle ?? WindowControlStyle.macos;
    final alignment =
        settings.windowControlAlignment ?? WindowControlAlignment.left;

    final buttons = [
      _WindowButton(
        style: style,
        type: _WindowButtonType.close,
        onTap: () => _windowChannel.invokeMethod('close'),
      ),
      if (canMinimize)
        _WindowButton(
          style: style,
          type: _WindowButtonType.minimize,
          onTap: () => _windowChannel.invokeMethod('minimize'),
        ),
      if (canMaximize)
        _WindowButton(
          style: style,
          type: _WindowButtonType.maximize,
          onTap: () async {
            final isMaximized =
                await _windowChannel.invokeMethod<bool>('isMaximized') ?? false;
            await _windowChannel.invokeMethod(isMaximized ? 'unmaximize' : 'maximize');
          },
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: constraints.maxWidth.isFinite ? constraints.maxWidth : null,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment:
                alignment == WindowControlAlignment.right
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
            children: buttons,
          ),
        );
      },
    );
  }
}

enum _WindowButtonType { close, minimize, maximize }

class _WindowButton extends StatefulWidget {
  final WindowControlStyle style;
  final _WindowButtonType type;
  final VoidCallback onTap;

  const _WindowButton({
    required this.style,
    required this.type,
    required this.onTap,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;
  bool _pressed = false;

  Color _macosColor() => switch (widget.type) {
        _WindowButtonType.close => const Color(0xFFFF5F57),
        _WindowButtonType.minimize => const Color(0xFFFEBC2E),
        _WindowButtonType.maximize => const Color(0xFF28C840),
      };

  Color _macosHoverColor() => switch (widget.type) {
        _WindowButtonType.close => const Color(0xFFE0443E),
        _WindowButtonType.minimize => const Color(0xFFDEA123),
        _WindowButtonType.maximize => const Color(0xFF1AAB29),
      };

  IconData _macosIcon() => switch (widget.type) {
        _WindowButtonType.close => PhosphorIconsRegular.x,
        _WindowButtonType.minimize => PhosphorIconsRegular.minus,
        _WindowButtonType.maximize => PhosphorIconsRegular.square,
      };

  IconData _windowsIcon() => switch (widget.type) {
        _WindowButtonType.close => PhosphorIconsRegular.x,
        _WindowButtonType.minimize => PhosphorIconsRegular.minus,
        _WindowButtonType.maximize => PhosphorIconsRegular.square,
      };

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final isMac = widget.style == WindowControlStyle.macos;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.onTap,
          child: Transform.scale(
            scale: _pressed ? 0.9 : 1.0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutBack,
              width: isMac ? 13 : 34,
              height: isMac ? 13 : 26,
              decoration: BoxDecoration(
                color: isMac 
                    ? (_pressed ? _macosHoverColor() : (_hovered ? _macosColor() : _macosColor()))
                    : (_hovered ? theme.border : Colors.transparent),
                shape: BoxShape.rectangle,
                borderRadius: BorderRadius.zero,
              ),
              child: isMac
                  ? AnimatedOpacity(
                      duration: const Duration(milliseconds: 140),
                      opacity: _hovered ? 1.0 : 0.0,
                      child: Icon(
                        _macosIcon(),
                        size: 8,
                        color: Colors.black,
                      ),
                    )
                  : Icon(
                      _windowsIcon(),
                      size: 14,
                      color: _pressed
                          ? theme.textMuted
                          : _hovered
                              ? theme.textPrimary
                              : theme.textSecondary,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
