import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/cursor/cursor_hover.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/theme/typography.dart';

/// Defer a state change to the next frame. This is used for hover/press
/// feedback triggered by [MouseRegion] and [GestureDetector] callbacks, so
/// the rebuild does not happen while Flutter is still updating the mouse
/// tracker (which would throw `_debugDuringDeviceUpdate`).
void _deferState(VoidCallback callback) {
  WidgetsBinding.instance.addPostFrameCallback((_) => callback());
}

/// A glossy, tactile, playful switch with a bouncy thumb, check/x icons and
/// a soft glow when active. The thumb uses an elastic curve and squishes
/// slightly while pressed.
class CroplooSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final double width;
  final double height;

  const CroplooSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.width = 56,
    this.height = 32,
  });

  @override
  State<CroplooSwitch> createState() => _CroplooSwitchState();
}

class _CroplooSwitchState extends State<CroplooSwitch> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final enabled = widget.onChanged != null;
    final thumb = widget.height - 8;
    final padding = 4.0;
    final travel = widget.width - thumb - padding * 2;

    final borderColor = widget.value
        ? theme.accent
        : enabled
            ? theme.border
            : theme.border.withValues(alpha: 0.5);

    return GestureDetector(
      onTapDown: enabled
          ? (_) => _deferState(() {
                if (mounted) setState(() => _pressed = true);
              })
          : null,
      onTapUp: enabled
          ? (_) => _deferState(() {
                if (mounted) setState(() => _pressed = false);
              })
          : null,
      onTapCancel: enabled
          ? () => _deferState(() {
                if (mounted) setState(() => _pressed = false);
              })
          : null,
      onTap: enabled ? () => widget.onChanged!(!widget.value) : null,
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(
          begin: widget.value ? theme.bgElevated : theme.accent,
          end: widget.value ? theme.accent : theme.bgElevated,
        ),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        builder: (context, bgColor, child) {
          return Container(
            width: widget.width,
            height: widget.height,
            // Border lives in foregroundDecoration, not decoration — a
            // border in `decoration` makes Container auto-inset its child
            // by the border width, which threw the thumb off-center.
            decoration: BoxDecoration(
              color: bgColor ?? theme.bgElevated,
              borderRadius: BorderRadius.zero,
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.zero,
              border: Border.all(color: borderColor, width: 1.5),
            ),
            child: child,
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.zero,
          child: Stack(
            children: [
              // Playful subtle inner gradient - only show if app blur is enabled
              if (theme.settings.useAppBlur)
                Positioned.fill(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: widget.value ? 0.15 : 0.08),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.05),
                        ],
                      ),
                    ),
                  ),
                ),
              AnimatedPositioned(
                left: widget.value ? padding + travel : padding,
                top: padding + (_pressed ? 1 : 0),
                duration: const Duration(milliseconds: 500),
                curve: Curves.elasticOut,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: _pressed ? thumb - 4 : thumb,
                  height: thumb,
                  decoration: BoxDecoration(
                    color: widget.value
                        ? theme.contrastColor(theme.accent)
                        : theme.textPrimary,
                    shape: BoxShape.rectangle,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: widget.value
                        ? Icon(
                            PhosphorIconsRegular.check,
                            key: const ValueKey('on'),
                            size: thumb * 0.48,
                            color: theme.accent,
                            weight: 700,
                          )
                        : Icon(
                            PhosphorIconsRegular.x,
                            key: const ValueKey('off'),
                            size: thumb * 0.42,
                            color: theme.bgElevated,
                            weight: 700,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A minimalist slider matching [CroplooSwitch]'s glossy, tactile style: a
/// flat rounded track and a bouncy circular thumb, centered on the track
/// and animated with the same elastic curve as the switch's thumb.
class CroplooSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final Color? activeColor;
  final Color? inactiveColor;
  final double height;

  const CroplooSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    this.divisions = 0,
    required this.onChanged,
    this.activeColor,
    this.inactiveColor,
    this.height = 32,
  });

  @override
  State<CroplooSlider> createState() => _CroplooSliderState();
}

class _CroplooSliderState extends State<CroplooSlider> {
  double _dragValue = 0;
  bool _isDragging = false;
  bool _hovered = false;
  bool _pressed = false;

  static const _thumbSize = 18.0;

  double _fraction(double value) {
    return ((value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);
  }

  double _valueFromFraction(double t) {
    return widget.min + t * (widget.max - widget.min);
  }

  double _discrete(double value) {
    final step = (widget.max - widget.min) / widget.divisions;
    final steps = ((value - widget.min) / step).round();
    return (widget.min + steps * step).clamp(widget.min, widget.max);
  }

  void _update(Offset localPosition, double width) {
    final track = width - _thumbSize;
    final t = track <= 0 ? 0.0 : ((localPosition.dx - _thumbSize / 2) / track).clamp(0.0, 1.0);
    var value = _valueFromFraction(t);
    if (widget.divisions > 0) {
      value = _discrete(value);
    }
    if (_isDragging) {
      _dragValue = value;
    }
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final activeColor = widget.activeColor ?? theme.accent;
    final inactiveColor = widget.inactiveColor ?? theme.border;
    final displayValue = _isDragging ? _dragValue : widget.value;
    final fraction = _fraction(displayValue);
    final thumbScale = _pressed ? 0.88 : (_hovered ? 1.1 : 1.0);
    const trackHeight = 6.0;

    return MouseRegion(
      onEnter: (_) => _deferState(() {
        if (mounted) setState(() => _hovered = true);
      }),
      onExit: (_) => _deferState(() {
        if (mounted) setState(() => _hovered = false);
      }),
      cursor: (CursorHover.enabled ? SystemMouseCursors.none : SystemMouseCursors.click),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (details) {
          _deferState(() {
            if (mounted) setState(() => _pressed = true);
          });
          _update(details.localPosition, context.size?.width ?? 0);
        },
        onTapUp: (_) => _deferState(() {
          if (mounted) setState(() => _pressed = false);
        }),
        onTapCancel: () => _deferState(() {
          if (mounted) setState(() => _pressed = false);
        }),
        onHorizontalDragStart: (_) {
          _isDragging = true;
          _pressed = true;
          _dragValue = widget.value;
          _deferState(() {
            if (mounted) setState(() {});
          });
        },
        onHorizontalDragUpdate: (details) {
          _update(details.localPosition, context.size?.width ?? 0);
        },
        onHorizontalDragEnd: (_) {
          _isDragging = false;
          _pressed = false;
          _deferState(() {
            if (mounted) setState(() {});
          });
        },
        onHorizontalDragCancel: () {
          _isDragging = false;
          _pressed = false;
          _deferState(() {
            if (mounted) setState(() {});
          });
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final track = width - _thumbSize;
            final thumbLeft = fraction * track;
            return SizedBox(
              height: widget.height,
              width: width,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // Track: flat, rounded, centered on the widget's height.
                  Container(
                    height: trackHeight,
                    margin: EdgeInsets.symmetric(horizontal: _thumbSize / 2),
                    decoration: BoxDecoration(
                      color: inactiveColor,
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                  AnimatedContainer(
                    duration: _isDragging ? Duration.zero : const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    margin: EdgeInsets.only(left: _thumbSize / 2),
                    height: trackHeight,
                    width: fraction * track,
                    decoration: BoxDecoration(
                      color: activeColor,
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                  // Thumb: same bouncy, glossy circle as CroplooSwitch.
                  AnimatedPositioned(
                    duration: _isDragging ? Duration.zero : const Duration(milliseconds: 500),
                    curve: Curves.elasticOut,
                    left: thumbLeft,
                    top: (widget.height - _thumbSize) / 2,
                    width: _thumbSize,
                    height: _thumbSize,
                    child: AnimatedScale(
                      scale: thumbScale,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          // Contrast against the surrounding surface, not
                          // the accent color — a light accent (the default)
                          // made this thumb render black-on-black in dark
                          // mode.
                          color: theme.contrastColor(theme.bgElevated),
                          shape: BoxShape.rectangle,
                          border: Border.all(color: theme.border, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Lightweight segmented control with a sliding pill background. The pill
/// position is measured from the active segment via [GlobalKey]s and animated
/// via [AnimatedPositioned]. This works in bounded and unbounded parents
/// (e.g., inside a Row) because it does not rely on [LayoutBuilder]'s maxWidth.
class CroplooSegmentedControl<T extends Object> extends StatefulWidget {
  final List<T> values;
  final T selected;
  final ValueChanged<T> onChanged;
  final String Function(T) labelBuilder;

  const CroplooSegmentedControl({
    super.key,
    required this.values,
    required this.selected,
    required this.onChanged,
    required this.labelBuilder,
  });

  @override
  State<CroplooSegmentedControl<T>> createState() => _CroplooSegmentedControlState<T>();
}

class _CroplooSegmentedControlState<T extends Object> extends State<CroplooSegmentedControl<T>> {
  final _keys = <GlobalKey>[];
  final _stackKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _syncKeys();
  }

  @override
  void didUpdateWidget(covariant CroplooSegmentedControl<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.values.length != _keys.length) {
      _syncKeys();
    }
  }

  void _syncKeys() {
    _keys.clear();
    for (var i = 0; i < widget.values.length; i++) {
      _keys.add(GlobalKey());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final selectedIndex = widget.values.indexOf(widget.selected);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.bgElevated,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: theme.border),
      ),
      child: Stack(
        key: _stackKey,
        children: [
          _SelectionBackground(
            stackKey: _stackKey,
            selectedIndex: selectedIndex,
            keys: _keys,
            color: theme.accent,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < widget.values.length; i++)
                _Segment(
                  key: _keys[i],
                  label: widget.labelBuilder(widget.values[i]),
                  selected: i == selectedIndex,
                  onTap: () => widget.onChanged(widget.values[i]),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SelectionBackground extends StatefulWidget {
  final int selectedIndex;
  final List<GlobalKey> keys;
  final GlobalKey stackKey;
  final Color color;

  const _SelectionBackground({
    required this.stackKey,
    required this.selectedIndex,
    required this.keys,
    required this.color,
  });

  @override
  State<_SelectionBackground> createState() => _SelectionBackgroundState();
}

class _SelectionBackgroundState extends State<_SelectionBackground> {
  _SelectionGeometry _geometry = const _SelectionGeometry.zero();
  bool _hasGeometry = false;

  // Geometry of every segment, measured once after layout and reused on
  // every subsequent selection change. Without this cache, moving the pill
  // would require measuring the newly-selected segment's RenderBox after a
  // fresh frame (post-frame callback -> setState -> another build/layout),
  // adding a visible frame of latency before the slide animation even
  // starts. With the cache, didUpdateWidget can apply the known target
  // geometry immediately so AnimatedPositioned starts moving in the same
  // frame the selection changes, matching CroplooSwitch's feel.
  final _cachedGeometry = <int, _SelectionGeometry>{};

  @override
  void initState() {
    super.initState();
    _scheduleMeasureAll();
  }

  @override
  void didUpdateWidget(covariant _SelectionBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keys.length != widget.keys.length) {
      _cachedGeometry.clear();
    }
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      final cached = _cachedGeometry[widget.selectedIndex];
      if (cached != null) {
        _geometry = cached;
        _hasGeometry = true;
      }
    }
    _scheduleMeasureAll();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleMeasureAll();
  }

  void _scheduleMeasureAll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _measureAll();
    });
  }

  void _measureAll() {
    final stackBox = widget.stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null || !stackBox.hasSize) return;

    for (var i = 0; i < widget.keys.length; i++) {
      final renderBox = widget.keys[i].currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.hasSize) continue;
      final position = renderBox.localToGlobal(Offset.zero, ancestor: stackBox);
      _cachedGeometry[i] = _SelectionGeometry(
        left: position.dx,
        top: position.dy,
        width: renderBox.size.width,
        height: renderBox.size.height,
      );
    }

    final current = _cachedGeometry[widget.selectedIndex];
    if (current == null || (current == _geometry && _hasGeometry)) return;

    setState(() {
      _geometry = current;
      _hasGeometry = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Avoid laying out the AnimatedPositioned before the first valid geometry
    // has been measured, otherwise the inner Container can be painted before
    // it is laid out.
    if (!_hasGeometry) return const SizedBox.shrink();
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      left: _geometry.left,
      top: _geometry.top,
      width: _geometry.width,
      height: _geometry.height,
      child: Container(
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.zero,
        ),
      ),
    );
  }
}

class _SelectionGeometry {
  final double left;
  final double top;
  final double width;
  final double height;

  const _SelectionGeometry({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  const _SelectionGeometry.zero()
      : left = 0,
        top = 0,
        width = 0,
        height = 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _SelectionGeometry &&
          other.left == left &&
          other.top == top &&
          other.width == width &&
          other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);
}

class _Segment extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Segment({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _hovered = false;
  bool _pressed = false;

  void _setHovered(bool value) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _hovered != value) {
        setState(() => _hovered = value);
      }
    });
  }

  void _setPressed(bool value) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pressed != value) {
        setState(() => _pressed = value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final scale = _pressed ? 0.96 : (_hovered ? 1.03 : 1.0);
    return MouseRegion(
      onEnter: (_) {
        _setHovered(true);
        CursorHover.enter();
      },
      onExit: (_) {
        _setHovered(false);
        CursorHover.exit();
      },
      cursor: (CursorHover.enabled ? SystemMouseCursors.none : SystemMouseCursors.click),
      child: GestureDetector(
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            // Transparent when selected so the sliding accent-colored
            // _SelectionBackground underneath is actually visible —
            // painting an opaque fill here would hide it entirely.
            color: widget.selected
                ? Colors.transparent
                : (_hovered || _pressed
                    ? theme.border.withValues(alpha: _pressed ? 0.35 : 0.18)
                    : Colors.transparent),
            borderRadius: BorderRadius.zero,
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            style: CroplooText.bodyStrong.copyWith(
              fontSize: 13,
              color: widget.selected
                  ? theme.contrastColor(theme.accent)
                  : theme.textSecondary,
              fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
            ),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.center,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Invisible bold "ghost" reserves the segment's max width
                  // up front. Without it, the segment measurably widens as
                  // its label animates from w500 to w700 on selection,
                  // which invalidates the pill's cached target geometry
                  // mid-slide and produces a visible double-jump/correction.
                  Opacity(
                    opacity: 0,
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    widget.label,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Playful circular radio button with a bouncy inner dot and springy
/// selection animation.
class CroplooRadioButton<T extends Object> extends StatefulWidget {
  final T value;
  final T groupValue;
  final ValueChanged<T>? onChanged;

  const CroplooRadioButton({
    super.key,
    required this.value,
    required this.groupValue,
    this.onChanged,
  });

  @override
  State<CroplooRadioButton<T>> createState() => _CroplooRadioButtonState<T>();
}

class _CroplooRadioButtonState<T extends Object>
    extends State<CroplooRadioButton<T>> {
  bool _pressed = false;

  void _setPressed(bool value) {
    _deferState(() {
      if (mounted && _pressed != value) setState(() => _pressed = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final selected = widget.value == widget.groupValue;
    final enabled = widget.onChanged != null;

    return GestureDetector(
      onTapDown: enabled ? (_) => _setPressed(true) : null,
      onTapUp: enabled
          ? (_) {
              _setPressed(false);
              widget.onChanged!(widget.value);
            }
          : null,
      onTapCancel: enabled ? () => _setPressed(false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutBack,
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.zero,
          color: selected ? theme.accent : theme.bgSurface,
          border: Border.all(
            color: selected
                ? theme.accent
                : enabled
                    ? theme.border
                    : theme.border.withValues(alpha: 0.5),
            width: 2,
          ),
        ),
        child: Center(
          child: AnimatedScale(
            scale: selected ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 350),
            curve: Curves.elasticOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: _pressed ? 8 : 10,
              height: _pressed ? 8 : 10,
              decoration: BoxDecoration(
                color: theme.contrastColor(theme.accent),
                borderRadius: BorderRadius.zero,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Playful square checkbox with a springy checkmark and a subtle glow.
class CroplooCheckbox extends StatefulWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const CroplooCheckbox({
    super.key,
    required this.value,
    this.onChanged,
  });

  @override
  State<CroplooCheckbox> createState() => _CroplooCheckboxState();
}

class _CroplooCheckboxState extends State<CroplooCheckbox> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final enabled = widget.onChanged != null;

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onChanged!(!widget.value);
            }
          : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        width: _pressed ? 22 : 24,
        height: _pressed ? 22 : 24,
        decoration: BoxDecoration(
          color: widget.value ? theme.accent : theme.bgSurface,
          borderRadius: BorderRadius.zero,
          border: Border.all(
            color: widget.value
                ? theme.accent
                : enabled
                    ? theme.border
                    : theme.border.withValues(alpha: 0.5),
            width: 2,
          ),
        ),
        child: AnimatedScale(
          scale: widget.value ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.elasticOut,
          child: Center(
            child: Icon(
              PhosphorIconsRegular.check,
              size: 16,
              color: theme.contrastColor(theme.accent),
              weight: 800,
            ),
          ),
        ),
      ),
    );
  }
}

/// A single playful list row with a subtle hover lift and an optional
/// selection glow.
class CroplooListItem extends StatefulWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final EdgeInsetsGeometry padding;

  const CroplooListItem({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  });

  @override
  State<CroplooListItem> createState() => _CroplooListItemState();
}

class _CroplooListItemState extends State<CroplooListItem> {
  bool _hovered = false;
  bool _pressed = false;

  void _setHovered(bool value) {
    _deferState(() {
      if (mounted && _hovered != value) setState(() => _hovered = value);
    });
  }

  void _setPressed(bool value) {
    _deferState(() {
      if (mounted && _pressed != value) setState(() => _pressed = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return MouseRegion(
      onEnter: (_) {
        _setHovered(true);
        CursorHover.enter();
      },
      onExit: (_) {
        _setHovered(false);
        CursorHover.exit();
      },
      cursor: widget.onTap != null
          ? (CursorHover.enabled ? SystemMouseCursors.none : SystemMouseCursors.click)
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: widget.onTap != null
            ? (_) => _setPressed(true)
            : null,
        onTapUp: widget.onTap != null
            ? (_) => _setPressed(false)
            : null,
        onTapCancel: widget.onTap != null
            ? () => _setPressed(false)
            : null,
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: widget.selected
                ? theme.accentDim
                : _pressed
                    ? theme.bgElevated
                    : _hovered
                        ? theme.bgElevated
                        : theme.bgSurface,
            border: Border(
              bottom: BorderSide(color: theme.border),
            ),
          ),
          child: Row(
            children: [
              if (widget.leading != null) ...[
                widget.leading!,
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: CroplooText.bodyStrong.copyWith(
                        color: theme.textPrimary,
                      ),
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle!,
                        style: CroplooText.body.copyWith(fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: 12),
                widget.trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Button variants matching the playful Croploo design.
enum CroplooButtonVariant { primary, secondary, ghost, destructive }

/// Playful button with hover lift, press squish, and a soft shadow.
class CroplooButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final CroplooButtonVariant variant;
  final bool expanded;
  final Widget? leading;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  const CroplooButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = CroplooButtonVariant.primary,
    this.expanded = true,
    this.leading,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    this.borderRadius = 0,
  });

  @override
  State<CroplooButton> createState() => _CroplooButtonState();
}

class _CroplooButtonState extends State<CroplooButton> {
  bool _hovered = false;
  bool _pressed = false;

  void _setHovered(bool value) {
    _deferState(() {
      if (mounted && _hovered != value) setState(() => _hovered = value);
    });
  }

  void _setPressed(bool value) {
    _deferState(() {
      if (mounted && _pressed != value) setState(() => _pressed = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final (background, foreground, borderColor) = switch (widget.variant) {
      CroplooButtonVariant.primary => (
          theme.accent,
          theme.contrastColor(theme.accent),
          theme.accent,
        ),
      CroplooButtonVariant.secondary => (
          Colors.transparent,
          theme.textPrimary,
          theme.border,
        ),
      CroplooButtonVariant.ghost => (
          Colors.transparent,
          theme.textPrimary,
          Colors.transparent,
        ),
      CroplooButtonVariant.destructive => (
          Colors.transparent,
          theme.negative,
          Colors.transparent,
        ),
    };

    final child = Row(
      mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.leading != null) ...[
          widget.leading!,
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            widget.label,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: CroplooText.bodyStrong.copyWith(
              color: widget.onPressed == null ? theme.textMuted : foreground,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
    return MouseRegion(
      onEnter: (_) {
        _setHovered(true);
        CursorHover.enter();
      },
      onExit: (_) {
        _setHovered(false);
        CursorHover.exit();
      },
      cursor: widget.onPressed != null
          ? (CursorHover.enabled ? SystemMouseCursors.none : SystemMouseCursors.click)
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: widget.onPressed != null
            ? (_) => _setPressed(true)
            : null,
        onTapUp: widget.onPressed != null
            ? (_) => _setPressed(false)
            : null,
        onTapCancel: widget.onPressed != null
            ? () => _setPressed(false)
            : null,
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : (_hovered ? 1.02 : 1.0),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            padding: widget.padding,
            decoration: BoxDecoration(
              color: widget.onPressed == null
                  ? theme.bgElevated
                  : background,
              borderRadius: BorderRadius.zero,
              border: Border.all(
                color: widget.onPressed == null ? theme.border : borderColor,
                width: 1.5,
              ),
            ),
            child: widget.expanded ? child : IntrinsicWidth(child: child),
          ),
        ),
      ),
    );
  }
}

/// Circular icon button with a playful glow, hover lift, and press pop.
class CroplooIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final Color? backgroundColor;
  final Color? iconColor;
  final bool glow;

  const CroplooIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 40,
    this.backgroundColor,
    this.iconColor,
    this.glow = true,
  });

  @override
  State<CroplooIconButton> createState() => _CroplooIconButtonState();
}

class _CroplooIconButtonState extends State<CroplooIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  void _setHovered(bool value) {
    _deferState(() {
      if (mounted && _hovered != value) setState(() => _hovered = value);
    });
  }

  void _setPressed(bool value) {
    _deferState(() {
      if (mounted && _pressed != value) setState(() => _pressed = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final bg = widget.onPressed == null
        ? theme.bgElevated
        : (widget.backgroundColor ?? theme.bgElevated);
    final fg = widget.onPressed == null
        ? theme.textMuted
        : (widget.iconColor ?? theme.textPrimary);

    return MouseRegion(
      onEnter: (_) {
        _setHovered(true);
        CursorHover.enter();
      },
      onExit: (_) {
        _setHovered(false);
        CursorHover.exit();
      },
      cursor: widget.onPressed != null
          ? (CursorHover.enabled ? SystemMouseCursors.none : SystemMouseCursors.click)
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: widget.onPressed != null
            ? (_) => _setPressed(true)
            : null,
        onTapUp: widget.onPressed != null
            ? (_) => _setPressed(false)
            : null,
        onTapCancel: widget.onPressed != null
            ? () => _setPressed(false)
            : null,
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _pressed ? 0.92 : (_hovered ? 1.12 : 1.0),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.rectangle,
              border: Border.all(
                color: widget.onPressed == null
                    ? theme.border
                    : theme.border,
                width: 1.5,
              ),
            ),
            child: Center(
              child: Icon(
                widget.icon,
                size: widget.size * 0.45,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Single item for [CroplooDropdown].
class CroplooDropdownItem<T> {
  final T value;
  final String label;
  final Widget? leading;

  const CroplooDropdownItem({
    required this.value,
    required this.label,
    this.leading,
  });
}

/// Playful dropdown / select button with a rounded menu and bouncy items.
class CroplooDropdown<T extends Object> extends StatefulWidget {
  final T value;
  final List<CroplooDropdownItem<T>> items;
  final ValueChanged<T> onChanged;
  final String? placeholder;
  final double? width;

  const CroplooDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.placeholder,
    this.width,
  });

  @override
  State<CroplooDropdown<T>> createState() => _CroplooDropdownState<T>();
}

class _CroplooDropdownState<T extends Object>
    extends State<CroplooDropdown<T>> {
  bool _pressed = false;

  void _setPressed(bool value) {
    _deferState(() {
      if (mounted && _pressed != value) setState(() => _pressed = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final selected = widget.items.where((i) => i.value == widget.value).firstOrNull;
    final label = selected?.label ?? widget.placeholder ?? widget.value.toString();

    return PopupMenuButton<T>(
      color: theme.bgElevated,
      elevation: 0,
      offset: const Offset(0, 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: theme.border),
      ),
      onSelected: widget.onChanged,
      itemBuilder: (context) => [
        for (final item in widget.items)
          PopupMenuItem<T>(
            value: item.value,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutBack,
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: item.value == widget.value
                    ? theme.accentDim
                    : theme.bgSurface,
                borderRadius: BorderRadius.zero,
              ),
              child: Row(
                children: [
                  if (item.leading != null) ...[
                    item.leading!,
                    const SizedBox(width: 8),
                  ],
                  Text(
                    item.label,
                    style: CroplooText.bodyStrong.copyWith(
                      fontSize: 13,
                      color: item.value == widget.value
                          ? theme.textPrimary
                          : theme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
      child: Listener(
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: widget.width,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.bgElevated,
            borderRadius: BorderRadius.zero,
            border: Border.all(
              color: _pressed ? theme.accent : theme.border,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: CroplooText.bodyStrong.copyWith(fontSize: 13),
              ),
              const SizedBox(width: 8),
              AnimatedRotation(
                turns: _pressed ? 0.25 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  PhosphorIconsRegular.caretDown,
                  size: 16,
                  color: theme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Groups [CroplooListItem] rows in a playful rounded card with a soft shadow.
class CroplooListGroup extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;

  const CroplooListGroup({
    super.key,
    required this.children,
    this.padding,
    this.borderRadius = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.bgSurface,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: theme.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              children[i],
              if (i < children.length - 1)
                Divider(height: 1, thickness: 1, color: theme.border),
            ],
          ],
        ),
      ),
    );
  }
}

/// Playful floating action button with a soft glow.
class CroplooFab extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  const CroplooFab({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
  });

  @override
  State<CroplooFab> createState() => _CroplooFabState();
}

class _CroplooFabState extends State<CroplooFab> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.onPressed != null
          ? (CursorHover.enabled ? SystemMouseCursors.none : SystemMouseCursors.click)
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: widget.onPressed != null
            ? (_) => setState(() => _pressed = true)
            : null,
        onTapUp: widget.onPressed != null
            ? (_) => setState(() => _pressed = false)
            : null,
        onTapCancel: widget.onPressed != null
            ? () => setState(() => _pressed = false)
            : null,
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _pressed ? 0.92 : (_hovered ? 1.1 : 1.0),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutBack,
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: theme.accent,
              borderRadius: BorderRadius.zero,
          ),
          child: Icon(
            widget.icon,
            color: theme.contrastColor(theme.accent),
            size: 26,
          ),
        ),
        ),
      ),
    );
  }
}

/// The app's one text-input control — sharp corners, `bgElevated` fill,
/// `bgBorder` border that turns `theme.accent` on focus, matching
/// [CroplooDropdown]/[CroplooButton]. Every free-standing `TextField` in
/// the app should use this instead so inputs look consistent everywhere
/// (search boxes, note fields, the CullyAI chat box, account editing,
/// etc.) rather than each screen styling its own.
class CroplooTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? hintText;
  final String? prefixText;
  final IconData? prefixIcon;
  final bool obscureText;
  final int? maxLength;
  final int maxLines;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final bool autofocus;

  const CroplooTextField({
    super.key,
    this.controller,
    this.hintText,
    this.prefixText,
    this.prefixIcon,
    this.obscureText = false,
    this.maxLength,
    this.maxLines = 1,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.autofocus = false,
  });

  @override
  State<CroplooTextField> createState() => _CroplooTextFieldState();
}

class _CroplooTextFieldState extends State<CroplooTextField> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() => _focused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: widget.enabled ? theme.bgElevated : theme.bgElevated.withValues(alpha: 0.5),
        borderRadius: BorderRadius.zero,
        border: Border.all(color: _focused ? theme.accent : theme.border),
      ),
      child: Row(
        children: [
          if (widget.prefixIcon != null) ...[
            Icon(widget.prefixIcon, size: 16, color: theme.textSecondary),
            const SizedBox(width: 8),
          ],
          if (widget.prefixText != null) ...[
            Text(widget.prefixText!,
                style: CroplooText.body.copyWith(color: theme.textMuted, fontSize: 13)),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              obscureText: widget.obscureText,
              maxLength: widget.maxLength,
              maxLines: widget.maxLines,
              keyboardType: widget.keyboardType,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              enabled: widget.enabled,
              autofocus: widget.autofocus,
              style: CroplooText.bodyStrong.copyWith(fontSize: 13),
              cursorColor: theme.accent,
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: CroplooText.body.copyWith(color: theme.textMuted, fontSize: 13),
                // The app's ambient InputDecorationTheme (see theme.dart)
                // fills in any border/fill field left unset here — only
                // nulling `border` still let `enabledBorder`/
                // `focusedBorder`/`filled` fall back to that theme, which
                // drew a second box outline around this widget's own
                // container. Every field has to be explicitly disabled.
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                isDense: true,
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
