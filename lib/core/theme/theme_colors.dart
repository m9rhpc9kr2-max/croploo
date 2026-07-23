import 'package:flutter/material.dart';

import 'theme_settings.dart';

/// App color palette that reacts to [ThemeSettings].
/// Registered as a [ThemeExtension] so it is reachable via
/// `Theme.of(context).extension<CroplooTheme>()!`.
@immutable
class CroplooTheme extends ThemeExtension<CroplooTheme> {
  final ThemeSettings settings;
  final Color bgPrimary;
  final Color bgSurface;
  final Color bgElevated;
  final Color bgBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color accentDim;
  final Color positive;
  final Color negative;
  final Color neutral;
  final Color glassBackground;
  final Color glassBorder;
  final Color liquidGlassHighlight;
  final Color liquidGlassShadow;

  // Helper getters for conditional borders and blur
  Color get border => settings.useBorders ? bgBorder : Colors.transparent;
  Color get glassBorderWithBlur => settings.useAppBlur ? glassBorder : Colors.transparent;
  Color get glassBackgroundWithBlur => settings.useAppBlur ? glassBackground : bgSurface;

  factory CroplooTheme.fromSettings(ThemeSettings settings) {
    final isDark = settings.isDark;
    final isDarkGray = settings.brightness == CroplooBrightness.darkGray;
    final isLightGray = settings.brightness == CroplooBrightness.lightGray;
    final rawAccent = settings.accentColor;
    // In light mode a white/near-white accent is invisible against the white
    // surface, so fall back to a dark accent for usability.
    final accentColor = !isDark && rawAccent.computeLuminance() > 0.85
        ? const Color(0xFF111111)
        : rawAccent;
    
    // Dark gray mode colors (darker than current gray)
    final darkGrayBgPrimary = const Color(0xFF1A1A1A);
    final darkGrayBgSurface = const Color(0xFF222222);
    final darkGrayBgElevated = const Color(0xFF2A2A2A);
    final darkGrayBgBorder = const Color(0xFF333333);
    final darkGrayTextPrimary = const Color(0xFFD0D0D0);
    final darkGrayTextSecondary = const Color(0xFFA0A0A0);
    final darkGrayTextMuted = const Color(0xFF707070);
    
    // Light gray mode colors (medium gray - not too light, not too dark)
    final lightGrayBgPrimary = const Color(0xFF404040);
    final lightGrayBgSurface = const Color(0xFF484848);
    final lightGrayBgElevated = const Color(0xFF565656); // Balanced hover contrast
    final lightGrayBgBorder = const Color(0xFF585858);
    final lightGrayTextPrimary = const Color(0xFFE5E5E5);
    final lightGrayTextSecondary = const Color(0xFFC0C0C0);
    final lightGrayTextMuted = const Color(0xFF909090);
    
    return CroplooTheme._(
      settings: settings,
      bgPrimary: isDarkGray ? darkGrayBgPrimary : (isLightGray ? lightGrayBgPrimary : (isDark ? const Color(0xFF000000) : const Color(0xFFF7F7F7))),
      bgSurface: isDarkGray ? darkGrayBgSurface : (isLightGray ? lightGrayBgSurface : (isDark ? const Color(0xFF0D0D0D) : const Color(0xFFFFFFFF))),
      bgElevated: isDarkGray ? darkGrayBgElevated : (isLightGray ? lightGrayBgElevated : (isDark ? const Color(0xFF161616) : const Color(0xFFF0F0F0))),
      bgBorder: isDarkGray ? darkGrayBgBorder : (isLightGray ? lightGrayBgBorder : (isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE0E0E0))),
      textPrimary: isDarkGray ? darkGrayTextPrimary : (isLightGray ? lightGrayTextPrimary : (isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000))),
      textSecondary: isDarkGray ? darkGrayTextSecondary : (isLightGray ? lightGrayTextSecondary : (isDark ? const Color(0xFF8A8A8A) : const Color(0xFF666666))),
      textMuted: isDarkGray ? darkGrayTextMuted : (isLightGray ? lightGrayTextMuted : (isDark ? const Color(0xFF444444) : const Color(0xFFAAAAAA))),
      accent: accentColor,
      accentDim: accentColor.withValues(alpha: 0.12),
      positive: const Color(0xFF22C55E),
      negative: const Color(0xFFEF4444),
      neutral: isDarkGray ? const Color(0xFFA0A0A0) : (isLightGray ? const Color(0xFFB8B8B8) : (isDark ? const Color(0xFF8A8A8A) : const Color(0xFF666666))),
      glassBackground: isDarkGray
          ? Colors.white.withValues(alpha: settings.glassTransparency * 0.25)
          : (isLightGray
              ? Colors.white.withValues(alpha: settings.glassTransparency * 0.35)
              : (isDark
                  ? Colors.white.withValues(alpha: settings.glassTransparency)
                  : Colors.black.withValues(alpha: settings.glassTransparency))),
      glassBorder: isDarkGray
          ? Colors.white.withValues(alpha: 0.12)
          : (isLightGray
              ? Colors.white.withValues(alpha: 0.18)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.20)
                  : Colors.black.withValues(alpha: 0.08))),
      liquidGlassHighlight: isDarkGray
          ? Colors.white.withValues(alpha: 0.06)
          : (isLightGray
              ? Colors.white.withValues(alpha: 0.10)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.white.withValues(alpha: 0.55))),
      liquidGlassShadow: isDarkGray
          ? Colors.black.withValues(alpha: 0.40)
          : (isDark
              ? Colors.black.withValues(alpha: 0.40)
              : Colors.black.withValues(alpha: 0.06)),
    );
  }

  const CroplooTheme._({
    required this.settings,
    required this.bgPrimary,
    required this.bgSurface,
    required this.bgElevated,
    required this.bgBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentDim,
    required this.positive,
    required this.negative,
    required this.neutral,
    required this.glassBackground,
    required this.glassBorder,
    required this.liquidGlassHighlight,
    required this.liquidGlassShadow,
  });

  bool get isDark => settings.isDark;

  Color get alertHigh => accent;
  Color get alertMedium => neutral;

  Color changeColor(num value) =>
      value > 0 ? positive : (value < 0 ? negative : neutral);

  /// Returns black or white depending on the luminance of [background].
  Color contrastColor(Color background) {
    return background.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }

  static CroplooTheme of(BuildContext context) {
    final theme = Theme.of(context).extension<CroplooTheme>();
    assert(theme != null, 'CroplooTheme is not registered in ThemeData');
    return theme ?? const CroplooTheme.fallback();
  }

  const CroplooTheme.fallback()
      : this._(
          settings: const ThemeSettings(),
          bgPrimary: const Color(0xFF000000),
          bgSurface: const Color(0xFF0D0D0D),
          bgElevated: const Color(0xFF161616),
          bgBorder: const Color(0xFF1F1F1F),
          textPrimary: const Color(0xFFFFFFFF),
          textSecondary: const Color(0xFF8A8A8A),
          textMuted: const Color(0xFF444444),
          accent: const Color(0xFFFFFFFF),
          accentDim: const Color(0x14FFFFFF),
          positive: const Color(0xFF22C55E),
          negative: const Color(0xFFEF4444),
          neutral: const Color(0xFF8A8A8A),
          glassBackground: const Color(0x26FFFFFF),
          glassBorder: const Color(0x33FFFFFF),
          liquidGlassHighlight: const Color(0x14FFFFFF),
          liquidGlassShadow: const Color(0x66000000),
        );

  @override
  CroplooTheme copyWith({
    ThemeSettings? settings,
    Color? bgPrimary,
    Color? bgSurface,
    Color? bgElevated,
    Color? bgBorder,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? accent,
    Color? accentDim,
    Color? positive,
    Color? negative,
    Color? neutral,
    Color? glassBackground,
    Color? glassBorder,
    Color? liquidGlassHighlight,
    Color? liquidGlassShadow,
  }) =>
      CroplooTheme._(
        settings: settings ?? this.settings,
        bgPrimary: bgPrimary ?? this.bgPrimary,
        bgSurface: bgSurface ?? this.bgSurface,
        bgElevated: bgElevated ?? this.bgElevated,
        bgBorder: bgBorder ?? this.bgBorder,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textMuted: textMuted ?? this.textMuted,
        accent: accent ?? this.accent,
        accentDim: accentDim ?? this.accentDim,
        positive: positive ?? this.positive,
        negative: negative ?? this.negative,
        neutral: neutral ?? this.neutral,
        glassBackground: glassBackground ?? this.glassBackground,
        glassBorder: glassBorder ?? this.glassBorder,
        liquidGlassHighlight:
            liquidGlassHighlight ?? this.liquidGlassHighlight,
        liquidGlassShadow: liquidGlassShadow ?? this.liquidGlassShadow,
      );

  @override
  CroplooTheme lerp(ThemeExtension<CroplooTheme>? other, double t) {
    if (other is! CroplooTheme) return this;
    return CroplooTheme._(
      settings: t < 0.5 ? settings : other.settings,
      bgPrimary: Color.lerp(bgPrimary, other.bgPrimary, t)!,
      bgSurface: Color.lerp(bgSurface, other.bgSurface, t)!,
      bgElevated: Color.lerp(bgElevated, other.bgElevated, t)!,
      bgBorder: Color.lerp(bgBorder, other.bgBorder, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentDim: Color.lerp(accentDim, other.accentDim, t)!,
      positive: Color.lerp(positive, other.positive, t)!,
      negative: Color.lerp(negative, other.negative, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
      glassBackground: Color.lerp(glassBackground, other.glassBackground, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      liquidGlassHighlight:
          Color.lerp(liquidGlassHighlight, other.liquidGlassHighlight, t)!,
      liquidGlassShadow:
          Color.lerp(liquidGlassShadow, other.liquidGlassShadow, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CroplooTheme &&
          runtimeType == other.runtimeType &&
          settings == other.settings;

  @override
  int get hashCode => settings.hashCode;
}
