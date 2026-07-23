import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/theme_colors.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/formatters.dart';
import 'controls.dart';
import '../models/models.dart';

/// Bordered surface card — no shadows, 1px border, 0px radius.
/// When glass mode is enabled via [ThemeSettings] it renders a translucent
/// frosted surface instead.
class CroplooCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;

  const CroplooCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: theme.bgSurface,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: borderColor ?? theme.border),
      ),
      child: child,
    );
  }
}

/// Apple-style liquid-glass container.
///
/// Heavy background blur, translucent gradient body, a subtle specular
/// highlight along the top edge and a soft inner shadow make the surface
/// feel like a thick, glossy glass object. The child is rendered with a
/// slight transparency so it visually sits inside the glass.
class LiquidGlass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? borderColor;
  final bool liquid;

  const LiquidGlass({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.borderRadius = 0,
    this.borderColor,
    this.liquid = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final effectiveRadius = BorderRadius.circular(borderRadius);
    final childOpacity = liquid ? 0.92 : 1.0;

    // Skip blur if app blur is disabled
    if (!theme.settings.useAppBlur) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: effectiveRadius,
          border: Border.all(
            color: borderColor ?? theme.border,
            width: 1.5,
          ),
          color: theme.bgSurface,
        ),
        child: child,
      );
    }

    return ClipRRect(
      borderRadius: effectiveRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: effectiveRadius,
            border: Border.all(
              color: borderColor ?? theme.glassBorderWithBlur,
              width: 1.5,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: const [0.0, 0.45, 1.0],
              colors: [
                theme.liquidGlassHighlight,
                theme.glassBackgroundWithBlur,
                theme.liquidGlassShadow,
              ],
            ),
          ),
          child: ClipRRect(
            borderRadius: effectiveRadius,
            child: Stack(
              children: [
                Opacity(
                  opacity: childOpacity,
                  child: child,
                ),
                // Top specular highlight.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          theme.liquidGlassHighlight.withValues(alpha: 0.7),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                // Subtle inner shadow for depth.
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: borderRadius * 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          theme.liquidGlassShadow.withValues(alpha: 0.5),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                // Slight glass tint over the content.
                Positioned.fill(
                  child: ColoredBox(
                    color: theme.glassBackground.withValues(alpha: 0.25),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// UPPERCASE section header with optional trailing action.
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title.toUpperCase(), style: CroplooText.label),
        ...?trailing != null ? [trailing!] : null,
      ],
    );
  }
}

/// "LABEL: VALUE" pattern — label above, monospace value below.
class DataLabel extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final TextStyle? valueStyle;

  const DataLabel({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.valueStyle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: CroplooText.label.copyWith(fontSize: 10)),
        const SizedBox(height: 4),
        Text(value,
            style: (valueStyle ?? CroplooText.data)
                .copyWith(color: valueColor ?? theme.textPrimary)),
      ],
    );
  }
}

/// +0.32¢ ▲ green / -0.12¢ ▼ red change chip.
class ChangeChip extends StatelessWidget {
  final double value;
  final String Function(num)? formatter;

  const ChangeChip({super.key, required this.value, this.formatter});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final color = theme.changeColor(value);
    final text = (formatter ?? Fmt.change)(value);
    return Text(
      '$text ${Fmt.arrow(value)}',
      style: CroplooText.data.copyWith(color: color, fontSize: 13),
    );
  }
}

/// Bullish/Bearish/Neutral badge.
class ImpactBadge extends StatelessWidget {
  final MarketDirection direction;
  final String? suffix;

  const ImpactBadge({super.key, required this.direction, this.suffix});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final (color, label) = switch (direction) {
      MarketDirection.bullish => (theme.positive, 'BULLISH'),
      MarketDirection.bearish => (theme.negative, 'BEARISH'),
      MarketDirection.neutral => (theme.neutral, 'NEUTRAL'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.zero,
        border: Border.all(color: theme.settings.useBorders ? color.withValues(alpha: 0.45) : Colors.transparent),
      ),
      child: Text(
        suffix == null ? label : '$label $suffix',
        style: CroplooText.label.copyWith(color: color, fontSize: 10),
      ),
    );
  }
}

/// Modern commodity-impact row with a colored left accent border.
class CroplooImpactRow extends StatelessWidget {
  final String title;
  final MarketDirection direction;
  final String headline;
  final String detail;

  const CroplooImpactRow({
    super.key,
    required this.title,
    required this.direction,
    required this.headline,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final accent = switch (direction) {
      MarketDirection.bullish => theme.positive,
      MarketDirection.bearish => theme.negative,
      MarketDirection.neutral => theme.neutral,
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.bgSurface,
        border: Border(
          bottom: BorderSide(color: theme.settings.useBorders ? theme.border : Colors.transparent),
          left: BorderSide(color: accent, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: CroplooText.label.copyWith(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 10),
              ImpactBadge(direction: direction),
            ],
          ),
          const SizedBox(height: 6),
          Text(headline, style: CroplooText.bodyStrong.copyWith(fontSize: 14)),
          const SizedBox(height: 2),
          Text(detail,
              style: CroplooText.body.copyWith(fontSize: 12)),
        ],
      ),
    );
  }
}

/// HIGH / MED / LOW priority tag.
class PriorityTag extends StatelessWidget {
  final AlertPriority priority;

  const PriorityTag({super.key, required this.priority});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final (color, label) = switch (priority) {
      AlertPriority.high => (theme.accent, 'HIGH'),
      AlertPriority.medium => (theme.textSecondary, 'MED'),
      AlertPriority.low => (theme.textMuted, 'LOW'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.zero,
        border: Border.all(color: theme.settings.useBorders ? color.withValues(alpha: 0.5) : Colors.transparent),
      ),
      child:
          Text(label, style: CroplooText.label.copyWith(color: color, fontSize: 9)),
    );
  }
}

/// Subscription tier badge (FREE / BASIC / PRO / DESK).
class TierBadge extends StatelessWidget {
  final SubscriptionTier tier;

  const TierBadge({super.key, required this.tier});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final isPaid = tier != SubscriptionTier.free;
    final color = isPaid ? theme.accent : theme.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isPaid ? theme.accentDim : theme.bgSurface,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: theme.settings.useBorders ? color.withValues(alpha: 0.5) : Colors.transparent),
      ),
      child: Text(tier.name.toUpperCase(),
          style: CroplooText.label.copyWith(color: color, fontSize: 9)),
    );
  }
}

/// Empty state placeholder.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const EmptyState({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: theme.textMuted),
          const SizedBox(height: 12),
          Text(message, style: CroplooText.body),
        ],
      ),
    );
  }
}

/// Centered loading indicator in accent color.
class CroplooLoader extends StatelessWidget {
  const CroplooLoader({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
            strokeWidth: 2, color: theme.accent),
      ),
    );
  }
}

/// "Upgrade to unlock" gate overlay for tier-restricted features.
class TierGate extends StatelessWidget {
  final String requiredTier;
  final Widget child;
  final bool locked;

  const TierGate({
    super.key,
    required this.requiredTier,
    required this.child,
    required this.locked,
  });

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    if (!locked) return child;
    return Stack(
      children: [
        Opacity(opacity: 0.15, child: IgnorePointer(child: child)),
        Positioned.fill(
          child: Center(
            child: CroplooCard(
              borderColor: theme.accent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIconsRegular.lock,
                      color: theme.accent, size: 28),
                  const SizedBox(height: 12),
                  Text('$requiredTier FEATURE', style: CroplooText.label),
                  const SizedBox(height: 8),
                  Text('Upgrade to unlock this module.',
                      style: CroplooText.body),
                  const SizedBox(height: 16),
                  CroplooButton(
                    label: 'Upgrade to $requiredTier',
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
