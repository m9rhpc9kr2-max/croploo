import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'cursor_hover.dart';

/// Croploo's animated desktop cursor: a small dot that tracks the mouse
/// exactly, plus a larger ring that eases a frame behind it — the same
/// dot + lagging ring effect as the marketing website (see
/// `website/js/main.js`'s `raf` loop and `.cursor-dot`/`.cursor-ring` in
/// `website/css/style.css`). Unlike the website (which layers this on top
/// of the normal pointer), the OS cursor is hidden here so this is the only
/// pointer the user sees.
///
/// Color auto-inverts from [background]'s actual luminance (black on a
/// light background, white on a dark one) rather than from the coarser
/// light/dark theme flag — `ThemeSettings.isDark` is true for both gray
/// theme variants regardless of how light or dark their surface color
/// actually renders, which previously left the cursor the wrong color
/// under those themes. True per-pixel sampling (like CSS's
/// mix-blend-mode: difference on the website) isn't reliable in Flutter
/// for an arbitrary backdrop — most real content sits in its own
/// compositing layer (images, cards, charts), so a difference blend on an
/// overlay painter would only see whatever happens to share its layer,
/// not the actual pixels beneath it.
class CursorOverlay extends StatefulWidget {
  const CursorOverlay({
    super.key,
    required this.background,
    required this.enabled,
    required this.child,
  });

  final Color background;
  final bool enabled;
  final Widget child;

  @override
  State<CursorOverlay> createState() => _CursorOverlayState();
}

class _CursorOverlayState extends State<CursorOverlay>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _dotSize = 7.0;
  static const _ringSize = 30.0;
  static const _ringHoverSize = 46.0;

  Offset? _mouse;
  Offset? _ring;
  bool _down = false;
  late final Ticker _ticker;
  bool _tickerRunning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Not started here — a Ticker left running unconditionally for the
    // app's whole lifetime (as this originally was) is a known source of
    // Flutter-desktop frame-pipeline stalls when a window is occluded and
    // later shown again. It only runs while actually animating toward the
    // mouse (see _startTicker/_stopTicker) and never while the window
    // isn't the active one (see didChangeAppLifecycleState).
    _ticker = createTicker(_tick);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _stopTicker();
    } else if (_mouse != null) {
      _startTicker();
    }
  }

  void _startTicker() {
    if (!_tickerRunning) {
      _tickerRunning = true;
      _ticker.start();
    }
  }

  void _stopTicker() {
    if (_tickerRunning) {
      _tickerRunning = false;
      _ticker.stop();
    }
  }

  void _tick(Duration _) {
    final mouse = _mouse;
    if (mouse == null) {
      _stopTicker();
      return;
    }
    final ring = _ring ?? mouse;
    final next = ring + (mouse - ring) * 0.18;
    if (_ring == null || (next - ring).distanceSquared > 0.01) {
      setState(() => _ring = next);
    } else {
      // Caught up to the mouse — stop scheduling frames until it moves
      // again rather than ticking forever for no visible effect.
      _stopTicker();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final color = widget.background.computeLuminance() > 0.5 ? Colors.black : Colors.white;

    return MouseRegion(
      cursor: SystemMouseCursors.none,
      child: Listener(
        onPointerHover: (e) {
          setState(() => _mouse = e.position);
          _startTicker();
        },
        onPointerDown: (_) => setState(() => _down = true),
        onPointerUp: (_) => setState(() => _down = false),
        onPointerCancel: (_) => setState(() => _down = false),
        child: Stack(
          children: [
            widget.child,
            if (_mouse != null)
              IgnorePointer(
                child: ValueListenableBuilder<int>(
                  valueListenable: CursorHover.count,
                  builder: (context, hoverCount, _) {
                    final ring = _ring ?? _mouse!;
                    final ringSize = hoverCount > 0 ? _ringHoverSize : _ringSize;
                    return Stack(
                      children: [
                        Positioned(
                          left: ring.dx - ringSize / 2,
                          top: ring.dy - ringSize / 2,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            curve: Curves.easeOut,
                            width: ringSize,
                            height: ringSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: color, width: 1.4),
                              color: _down ? color.withValues(alpha: 0.25) : null,
                            ),
                          ),
                        ),
                        Positioned(
                          left: _mouse!.dx - _dotSize / 2,
                          top: _mouse!.dy - _dotSize / 2,
                          child: DecoratedBox(
                            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                            child: const SizedBox(width: _dotSize, height: _dotSize),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
