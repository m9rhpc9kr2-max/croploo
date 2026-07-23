import 'package:flutter/material.dart';

import 'theme_colors.dart';
import 'typography.dart';

ThemeData buildCroplooTheme(CroplooTheme croplooTheme) {
  final isDark = croplooTheme.isDark;
  final base = isDark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);
  return base.copyWith(
    brightness: isDark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: croplooTheme.bgPrimary,
    colorScheme: ColorScheme.fromSeed(
      seedColor: croplooTheme.accent,
      brightness: isDark ? Brightness.dark : Brightness.light,
      surface: croplooTheme.bgSurface,
      primary: croplooTheme.accent,
      onPrimary: croplooTheme.contrastColor(croplooTheme.accent),
      secondary: croplooTheme.accent,
      error: croplooTheme.negative,
    ),
    textTheme: TextTheme(
      displayLarge: CroplooText.display.copyWith(color: croplooTheme.textPrimary),
      headlineLarge: CroplooText.h1.copyWith(color: croplooTheme.textPrimary),
      headlineMedium: CroplooText.h2.copyWith(color: croplooTheme.textPrimary),
      headlineSmall: CroplooText.h3.copyWith(color: croplooTheme.textPrimary),
      bodyLarge: CroplooText.data.copyWith(color: croplooTheme.textPrimary),
      bodyMedium: CroplooText.body.copyWith(color: croplooTheme.textSecondary),
      labelSmall: CroplooText.label.copyWith(color: croplooTheme.textSecondary),
      titleMedium: CroplooText.bodyStrong.copyWith(color: croplooTheme.textPrimary),
    ),
    dividerColor: croplooTheme.border,
    dividerTheme: DividerThemeData(
      color: croplooTheme.border,
      thickness: 1,
      space: 1,
    ),
    cardTheme: CardThemeData(
      color: croplooTheme.bgSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: croplooTheme.border),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: croplooTheme.bgElevated,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: croplooTheme.border),
      ),
      textStyle: CroplooText.body.copyWith(color: croplooTheme.textPrimary),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(croplooTheme.bgElevated),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: croplooTheme.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: croplooTheme.border),
      ),
      textStyle: CroplooText.bodyStrong,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: croplooTheme.bgElevated,
      hintStyle: CroplooText.body.copyWith(color: croplooTheme.textMuted),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: croplooTheme.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: croplooTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: croplooTheme.accent),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: croplooTheme.accent,
        textStyle: const TextStyle(
            fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: croplooTheme.accent,
        foregroundColor: croplooTheme.contrastColor(croplooTheme.accent),
        textStyle: const TextStyle(
            fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: croplooTheme.textPrimary,
        side: BorderSide(color: croplooTheme.bgBorder),
        textStyle: const TextStyle(
            fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      side: BorderSide(color: croplooTheme.textMuted),
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? croplooTheme.accent
              : Colors.transparent),
      checkColor: WidgetStateProperty.all(
          croplooTheme.contrastColor(croplooTheme.accent)),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: croplooTheme.textPrimary,
      unselectedLabelColor: croplooTheme.textSecondary,
      indicatorColor: croplooTheme.accent,
      labelStyle: const TextStyle(
          fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(
          fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w400),
      dividerColor: croplooTheme.bgBorder,
    ),
    extensions: [croplooTheme],
  );
}
