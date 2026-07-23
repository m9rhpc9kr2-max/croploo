import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/formatters.dart';

/// Modern, rectangular tooltip for FLChart line charts.
///
/// Use this as the default [LineTouchData] for any chart that shows values on
/// interaction. The tooltip uses the app's rectangular shape, a clean border
/// color, and formats values with [Fmt.value] to avoid long decimals.
LineTouchData croplooLineTooltip(
  CroplooTheme theme, {
  required List<String> labels,
  required List<Color> colors,
  List<DateTime>? dates,
  int valueDecimals = 2,
  String valueSuffix = '',
}) {
  return LineTouchData(
    touchTooltipData: LineTouchTooltipData(
      tooltipRoundedRadius: 0,
      tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      tooltipMargin: 8,
      maxContentWidth: 240,
      fitInsideHorizontally: true,
      fitInsideVertically: true,
      getTooltipColor: (_) => theme.bgElevated,
      getTooltipItems: (spots) {
        return spots.map((s) {
          final dateIndex = s.x.toInt();
          final label = s.barIndex < labels.length ? labels[s.barIndex] : '';
          final color = s.barIndex < colors.length ? colors[s.barIndex] : theme.textPrimary;
          final dateLine = dates != null && dateIndex < dates.length
              ? '${Fmt.dateShort(dates[dateIndex])}\n'
              : '';
          return LineTooltipItem(
            '$dateLine$label ${s.y.toStringAsFixed(valueDecimals)}$valueSuffix',
            CroplooText.dataSmall.copyWith(
              color: color,
              fontSize: 12,
              height: 1.4,
            ),
          );
        }).toList();
      },
    ),
  );
}
