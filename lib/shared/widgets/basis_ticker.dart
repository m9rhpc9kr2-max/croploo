import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_colors.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/providers.dart';
import '../models/models.dart';

/// Signature element: 36px animated basis ticker, visible on every page.
/// Scrolls at ~40px/s, pauses on hover, wheat-colored separators.
class BasisTicker extends ConsumerStatefulWidget {
  const BasisTicker({super.key});

  @override
  ConsumerState<BasisTicker> createState() => _BasisTickerState();
}

class _BasisTickerState extends ConsumerState<BasisTicker>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _controller.stop();
    } else if (!_hovered) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(tickerProvider).valueOrNull ?? const <TickerItem>[];
    final theme = CroplooTheme.of(context);
    return MouseRegion(
      onEnter: (_) {
        _hovered = true;
        _controller.stop();
      },
      onExit: (_) {
        _hovered = false;
        _controller.repeat();
      },
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: theme.bgSurface,
          border: Border(bottom: BorderSide(color: theme.border)),
        ),
        clipBehavior: Clip.hardEdge,
        child: items.isEmpty
            ? const SizedBox.shrink()
            : LayoutBuilder(builder: (context, constraints) {
                return AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return _MarqueeRow(
                      items: items,
                      progress: _controller.value,
                      width: constraints.maxWidth,
                      paused: _hovered,
                    );
                  },
                );
              }),
      ),
    );
  }
}

class _MarqueeRow extends StatefulWidget {
  final List<TickerItem> items;
  final double progress;
  final double width;
  final bool paused;

  const _MarqueeRow({
    required this.items,
    required this.progress,
    required this.width,
    required this.paused,
  });

  @override
  State<_MarqueeRow> createState() => _MarqueeRowState();
}

class _MarqueeRowState extends State<_MarqueeRow> {
  final _firstStripKey = GlobalKey();
  final _secondStripKey = GlobalKey();
  double _stripWidth = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureStrip();
    });
  }

  void _measureStrip() {
    final context = _firstStripKey.currentContext;
    if (context != null) {
      final RenderBox box = context.findRenderObject() as RenderBox;
      setState(() {
        _stripWidth = box.size.width;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_stripWidth == 0) {
      // First frame - measure without animation
      return OverflowBox(
        alignment: Alignment.centerLeft,
        maxWidth: double.infinity,
        child: Row(
          key: _firstStripKey,
          mainAxisSize: MainAxisSize.min,
          children: [for (final item in widget.items) _TickerCell(item: item)],
        ),
      );
    }

    // Calculate offset: wrap when one full strip has scrolled
    final offset = (widget.progress * _stripWidth) % _stripWidth;
    
    return OverflowBox(
      alignment: Alignment.centerLeft,
      maxWidth: double.infinity,
      child: Transform.translate(
        offset: Offset(-offset, 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              key: _firstStripKey,
              mainAxisSize: MainAxisSize.min,
              children: [for (final item in widget.items) _TickerCell(item: item)],
            ),
            Row(
              key: _secondStripKey,
              mainAxisSize: MainAxisSize.min,
              children: [for (final item in widget.items) _TickerCell(item: item)],
            ),
          ],
        ),
      ),
    );
  }
}

class _TickerCell extends StatelessWidget {
  final TickerItem item;

  const _TickerCell({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final color = item.extreme
        ? theme.accent
        : theme.changeColor(item.basis);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 20),
        Text(item.label,
            style: CroplooText.dataSmall
                .copyWith(color: theme.textSecondary, fontSize: 11)),
        const SizedBox(width: 10),
        Text(
          '${Fmt.change(item.basis)}¢ ${Fmt.arrow(item.basis)}',
          style: CroplooText.dataSmall.copyWith(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 20),
        Container(
          width: 1,
          height: 14,
          color: theme.accent.withValues(alpha: 0.35),
        ),
      ],
    );
  }
}
