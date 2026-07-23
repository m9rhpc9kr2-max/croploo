import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/theme_settings.dart';

/// Formatting helpers — prices in cents/bushel, dates, deltas.
///
/// Call [configure] with the current [ThemeSettings] to make all methods
/// respect the user's number-format and unit preferences.
class Fmt {
  Fmt._();

  /// Current user settings (number format, distance/volume units).
  /// Updated from [CroplooApp] whenever theme settings change.
  static ThemeSettings _settings = const ThemeSettings();

  /// Update the static settings reference so all [Fmt] methods use the
  /// user's preferred number format and units.
  static void configure(ThemeSettings settings) {
    _settings = settings;
  }

  /// The active number-format style.
  static NumberFormatStyle get _numberStyle => _settings.numberFormatStyle;

  static NumberFormat _priceFormat(NumberFormatStyle style) {
    switch (style) {
      case NumberFormatStyle.us:
        return NumberFormat('#,##0.00', 'en_US');
      case NumberFormatStyle.european:
        return NumberFormat('#,##0.00', 'de_DE');
    }
  }

  static final DateFormat _date = DateFormat('MMM d, yyyy');
  static final DateFormat _dateShort = DateFormat('MMM d');
  static final DateFormat _timeShort = DateFormat('HH:mm');
  static final DateFormat _weekday = DateFormat('EEEE');

  /// e.g. 1,234.56 (US) or 1.234,56 (European) — uses user preference.
  static String price(num v) => _priceFormat(_numberStyle).format(v);

  /// Format with an explicit style (bypasses user preference).
  static String priceWithStyle(num v, NumberFormatStyle style) =>
      _priceFormat(style).format(v);

  /// Signed cents value: +14¢ / -22¢
  static String cents(num v) {
    final formatted = _priceFormat(_numberStyle).format(v.abs());
    return '${v >= 0 ? '+' : '-'}$formatted¢';
  }

  /// Signed basis in ¢/bu: -0.32¢/bu
  static String basis(num v) {
    final formatted = _priceFormat(_numberStyle).format(v.abs());
    return '${v >= 0 ? '+' : '-'}$formatted¢/bu';
  }

  /// Signed change: +4.50 / -2.25 (or +4,50 / -2,25)
  static String change(num v) {
    final formatted = _priceFormat(_numberStyle).format(v.abs());
    return '${v >= 0 ? '+' : '-'}$formatted';
  }

  /// Signed change with explicit number format.
  static String changeWithStyle(num v, NumberFormatStyle style) {
    final formatted = _priceFormat(style).format(v.abs());
    return '${v >= 0 ? '+' : '-'}$formatted';
  }

  /// Signed percent: +2.1%
  static String pct(num v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}%';

  static String date(DateTime d) => _date.format(d);
  static String dateShort(DateTime d) => _dateShort.format(d);
  static String timeShort(DateTime d) => _timeShort.format(d);
  static String weekday(DateTime d) => _weekday.format(d);

  static String arrow(num v) => v > 0 ? '▲' : (v < 0 ? '▼' : '—');

  static String timeAgo(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  static String countdown(DateTime target) {
    final diff = target.difference(DateTime.now());
    if (diff.isNegative) return 'released';
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    return '${days}d ${hours}h';
  }

  // Unit conversions

  /// Convert miles to kilometers
  static double milesToKm(double miles) => miles * 1.60934;

  /// Convert kilometers to miles
  static double kmToMiles(double km) => km / 1.60934;

  /// Convert gallons to liters
  static double gallonsToLiters(double gallons) => gallons * 3.78541;

  /// Convert liters to gallons
  static double litersToGallons(double liters) => liters / 3.78541;

  /// Convert Celsius to Fahrenheit
  static double celsiusToFahrenheit(double celsius) => celsius * 9 / 5 + 32;

  /// Convert Fahrenheit to Celsius
  static double fahrenheitToCelsius(double fahrenheit) => (fahrenheit - 32) * 5 / 9;

  /// Format temperature — uses user's preferred unit and number format.
  /// [value] is in Celsius; converted to Fahrenheit if needed.
  /// If unit is 'system', uses the system locale preference.
  static String temperature(double valueInCelsius, {TemperatureUnit? unit, NumberFormatStyle? numberStyle}) {
    final u = unit ?? _settings.temperatureUnit;
    final format = numberStyle ?? _numberStyle;
    
    double displayValue;
    String unitSymbol;
    
    if (u == TemperatureUnit.system) {
      // Use system locale to determine default temperature unit
      final locale = WidgetsBinding.instance.platformDispatcher.locale;
      final isMetric = locale.countryCode != 'US' && locale.countryCode != 'LR' && locale.countryCode != 'MM';
      if (isMetric) {
        displayValue = valueInCelsius;
        unitSymbol = '°C';
      } else {
        displayValue = celsiusToFahrenheit(valueInCelsius);
        unitSymbol = '°F';
      }
    } else if (u == TemperatureUnit.celsius) {
      displayValue = valueInCelsius;
      unitSymbol = '°C';
    } else {
      displayValue = celsiusToFahrenheit(valueInCelsius);
      unitSymbol = '°F';
    }
    
    final formatted = _priceFormat(format).format(displayValue);
    return '$formatted$unitSymbol';
  }

  /// Format distance — uses user's preferred unit and number format.
  /// [value] is in miles; converted to km if needed.
  static String distance(double valueInMiles, {DistanceUnit? unit, NumberFormatStyle? numberStyle}) {
    final u = unit ?? _settings.distanceUnit;
    final format = numberStyle ?? _numberStyle;
    final displayValue = u == DistanceUnit.km ? milesToKm(valueInMiles) : valueInMiles;
    final formatted = _priceFormat(format).format(displayValue);
    return '$formatted ${u == DistanceUnit.km ? 'km' : 'mi'}';
  }

  /// Format volume — uses user's preferred unit and number format.
  /// [value] is in gallons; converted to liters if needed.
  static String volume(double valueInGallons, {VolumeUnit? unit, NumberFormatStyle? numberStyle}) {
    final u = unit ?? _settings.volumeUnit;
    final format = numberStyle ?? _numberStyle;
    final displayValue = u == VolumeUnit.liters ? gallonsToLiters(valueInGallons) : valueInGallons;
    final formatted = _priceFormat(format).format(displayValue);
    return '$formatted ${u == VolumeUnit.liters ? 'L' : 'gal'}';
  }

  /// Format any number with user's preferred number format
  static String number(num value, {NumberFormatStyle? style}) =>
      _priceFormat(style ?? _numberStyle).format(value);
}
