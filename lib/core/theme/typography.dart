import 'package:flutter/material.dart';

/// Croploo typographic scale.
/// Display/Headlines & Body: Poppins. Data/Numbers: JetBrains Mono.
/// Colors are intentionally omitted here so the app theme can apply
/// the correct `textPrimary` / `textSecondary` dynamically.
class CroplooText {
  CroplooText._();

  static const String _poppins = 'Poppins';
  static const String _mono = 'JetBrainsMono';

  static const TextStyle display = TextStyle(
    fontFamily: _poppins,
    fontSize: 48,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.44,
  );

  static const TextStyle h1 = TextStyle(
    fontFamily: _poppins,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.64,
  );

  static const TextStyle h2 = TextStyle(
    fontFamily: _poppins,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.24,
  );

  static const TextStyle h3 = TextStyle(
    fontFamily: _poppins,
    fontSize: 18,
    fontWeight: FontWeight.w600,
  );

  /// 12px UPPERCASE label — always used with `.toUpperCase()` text.
  static const TextStyle label = TextStyle(
    fontFamily: _poppins,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.96,
  );

  static const TextStyle body = TextStyle(
    fontFamily: _poppins,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.6,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontFamily: _poppins,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.5,
  );

  /// Data — all prices, basis values, percentages ALWAYS monospace.
  static const TextStyle data = TextStyle(
    fontFamily: _mono,
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle dataSmall = TextStyle(
    fontFamily: _mono,
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle dataLarge = TextStyle(
    fontFamily: _mono,
    fontSize: 24,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle dataXL = TextStyle(
    fontFamily: _mono,
    fontSize: 40,
    fontWeight: FontWeight.w700,
  );
}
