import 'package:flutter/material.dart';

/// Brightness mode for the app.
enum CroplooBrightness { light, dark, darkGray, lightGray, system }

/// Visual style of the custom window control buttons.
enum WindowControlStyle { macos, windows }

/// Placement of the custom window control buttons in the sidebar.
enum WindowControlAlignment { left, right }

/// Number format style for decimal and thousand separators.
enum NumberFormatStyle { us, european }

/// Distance unit preference.
enum DistanceUnit { miles, km }

/// Volume unit preference.
enum VolumeUnit { gallons, liters }

/// Temperature unit preference.
enum TemperatureUnit { celsius, fahrenheit, system }

/// User-customizable appearance settings.
class ThemeSettings {
  final CroplooBrightness brightness;
  final bool useBorders;
  final bool useAppBlur;
  final Color accentColor;
  final WindowControlStyle? windowControlStyle;
  final WindowControlAlignment? windowControlAlignment;
  final NumberFormatStyle numberFormatStyle;
  final DistanceUnit distanceUnit;
  final VolumeUnit volumeUnit;
  final TemperatureUnit temperatureUnit;
  final bool desktopNotifications;
  final double glassTransparency;
  final bool customCursor;
  final Set<String> hiddenNavRoutes;
  final bool showTicker;

  const ThemeSettings({
    this.brightness = CroplooBrightness.system,
    this.useBorders = true,
    this.useAppBlur = true,
    this.accentColor = Colors.white,
    this.windowControlStyle = WindowControlStyle.macos,
    this.windowControlAlignment = WindowControlAlignment.left,
    this.numberFormatStyle = NumberFormatStyle.us,
    this.distanceUnit = DistanceUnit.miles,
    this.volumeUnit = VolumeUnit.gallons,
    this.temperatureUnit = TemperatureUnit.system,
    this.desktopNotifications = false,
    this.glassTransparency = 0.15,
    this.customCursor = true,
    this.hiddenNavRoutes = const {},
    this.showTicker = true,
  });

  ThemeSettings copyWith({
    CroplooBrightness? brightness,
    bool? useBorders,
    bool? useAppBlur,
    Color? accentColor,
    WindowControlStyle? windowControlStyle,
    WindowControlAlignment? windowControlAlignment,
    NumberFormatStyle? numberFormatStyle,
    DistanceUnit? distanceUnit,
    VolumeUnit? volumeUnit,
    TemperatureUnit? temperatureUnit,
    bool? desktopNotifications,
    double? glassTransparency,
    bool? customCursor,
    Set<String>? hiddenNavRoutes,
    bool? showTicker,
  }) =>
      ThemeSettings(
        brightness: brightness ?? this.brightness,
        useBorders: useBorders ?? this.useBorders,
        useAppBlur: useAppBlur ?? this.useAppBlur,
        accentColor: accentColor ?? this.accentColor,
        windowControlStyle: windowControlStyle ?? this.windowControlStyle,
        windowControlAlignment: windowControlAlignment ?? this.windowControlAlignment,
        numberFormatStyle: numberFormatStyle ?? this.numberFormatStyle,
        distanceUnit: distanceUnit ?? this.distanceUnit,
        volumeUnit: volumeUnit ?? this.volumeUnit,
        temperatureUnit: temperatureUnit ?? this.temperatureUnit,
        desktopNotifications: desktopNotifications ?? this.desktopNotifications,
        glassTransparency: glassTransparency ?? this.glassTransparency,
        customCursor: customCursor ?? this.customCursor,
        hiddenNavRoutes: hiddenNavRoutes ?? this.hiddenNavRoutes,
        showTicker: showTicker ?? this.showTicker,
      );

  bool get isDark =>
      brightness == CroplooBrightness.dark ||
      brightness == CroplooBrightness.darkGray ||
      brightness == CroplooBrightness.lightGray ||
      (brightness == CroplooBrightness.system &&
          WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark);

  Map<String, dynamic> toJson() => {
        'brightness': brightness.name,
        'useBorders': useBorders,
        'useAppBlur': useAppBlur,
        'accentColor': accentColor.value,
        'windowControlStyle': windowControlStyle?.name,
        'windowControlAlignment': windowControlAlignment?.name,
        'numberFormatStyle': numberFormatStyle.name,
        'distanceUnit': distanceUnit.name,
        'volumeUnit': volumeUnit.name,
        'temperatureUnit': temperatureUnit.name,
        'desktopNotifications': desktopNotifications,
        'glassTransparency': glassTransparency,
        'customCursor': customCursor,
        'hiddenNavRoutes': hiddenNavRoutes.toList(),
        'showTicker': showTicker,
      };

  factory ThemeSettings.fromJson(Map<String, dynamic> json) {
    Color colorFromValue(dynamic value) {
      if (value == null) return Colors.white;
      return Color(value is int ? value : int.parse(value.toString()));
    }

    CroplooBrightness? brightnessFromName(dynamic value) =>
        CroplooBrightness.values.where((e) => e.name == value).firstOrNull;

    WindowControlStyle? styleFromName(dynamic value) =>
        WindowControlStyle.values.where((e) => e.name == value).firstOrNull;

    WindowControlAlignment? alignmentFromName(dynamic value) =>
        WindowControlAlignment.values.where((e) => e.name == value).firstOrNull;

    NumberFormatStyle? numberFormatFromName(dynamic value) =>
        NumberFormatStyle.values.where((e) => e.name == value).firstOrNull;

    DistanceUnit? distanceUnitFromName(dynamic value) =>
        DistanceUnit.values.where((e) => e.name == value).firstOrNull;

    VolumeUnit? volumeUnitFromName(dynamic value) =>
        VolumeUnit.values.where((e) => e.name == value).firstOrNull;

    TemperatureUnit? temperatureUnitFromName(dynamic value) =>
        TemperatureUnit.values.where((e) => e.name == value).firstOrNull;

    final tempUnit = json['temperatureUnit'];
    final temperatureUnit = tempUnit != null
        ? (temperatureUnitFromName(tempUnit) ?? TemperatureUnit.system)
        : TemperatureUnit.system;

    return ThemeSettings(
      brightness: brightnessFromName(json['brightness']) ?? CroplooBrightness.system,
      useBorders: json['useBorders'] as bool? ?? true,
      useAppBlur: json['useAppBlur'] as bool? ?? true,
      accentColor: colorFromValue(json['accentColor']),
      windowControlStyle: styleFromName(json['windowControlStyle']),
      windowControlAlignment: alignmentFromName(json['windowControlAlignment']),
      numberFormatStyle: numberFormatFromName(json['numberFormatStyle']) ?? NumberFormatStyle.us,
      distanceUnit: distanceUnitFromName(json['distanceUnit']) ?? DistanceUnit.miles,
      volumeUnit: volumeUnitFromName(json['volumeUnit']) ?? VolumeUnit.gallons,
      temperatureUnit: temperatureUnit,
      desktopNotifications: json['desktopNotifications'] as bool? ?? false,
      glassTransparency: (json['glassTransparency'] as num?)?.toDouble() ?? 0.15,
      customCursor: json['customCursor'] as bool? ?? true,
      hiddenNavRoutes: (json['hiddenNavRoutes'] as List?)?.map((e) => e as String).toSet() ?? const {},
      showTicker: json['showTicker'] as bool? ?? true,
    );
  }
}
