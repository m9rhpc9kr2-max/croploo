import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme/theme_colors.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/formatters.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/chart_tooltip.dart';
import '../../shared/widgets/controls.dart';

/// Time ranges for the basis chart. USDA basis data updates weekly, so
/// 1D/5D windows are omitted — they'd contain at most one real data point.
enum BasisTimeRange { all, oneYear, ytd, ninetyDays, thirtyDays }

extension on BasisTimeRange {
  String get label => switch (this) {
        BasisTimeRange.all => 'All',
        BasisTimeRange.oneYear => '1Y',
        BasisTimeRange.ytd => 'YTD',
        BasisTimeRange.ninetyDays => '90D',
        BasisTimeRange.thirtyDays => '30D',
      };
}

/// Basis timeseries chart. Current basis line is colored green when the series
/// trends up and red when it trends down. A 5-year average is shown dashed.
class BasisChart extends StatelessWidget {
  final List<BasisPoint> points;
  final BasisTimeRange timeRange;
  final bool showDeviation;

  const BasisChart({
    super.key,
    required this.points,
    this.timeRange = BasisTimeRange.all,
    this.showDeviation = false,
  });

  List<BasisPoint> get _filteredPoints {
    if (points.isEmpty) return [];
    final now = points.last.date;
    final cutoff = switch (timeRange) {
      BasisTimeRange.all => DateTime(1900),
      BasisTimeRange.oneYear => now.subtract(const Duration(days: 365)),
      BasisTimeRange.ytd => DateTime(now.year, 1, 1),
      BasisTimeRange.ninetyDays => now.subtract(const Duration(days: 90)),
      BasisTimeRange.thirtyDays => now.subtract(const Duration(days: 30)),
    };
    return points.where((p) => p.date.isAfter(cutoff)).toList();
  }

  Color _lineColor(List<BasisPoint> filtered, CroplooTheme theme) {
    if (filtered.length < 2) return theme.textPrimary;
    final first = filtered.first.basis;
    final last = filtered.last.basis;
    if (last > first) return theme.positive;
    if (last < first) return theme.negative;
    return theme.textPrimary;
  }

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final filtered = _filteredPoints;
    if (filtered.isEmpty) return const SizedBox.shrink();

    final lineColor = _lineColor(filtered, theme);
    final basisSpots = <FlSpot>[];
    final avgSpots = <FlSpot>[];
    for (final (i, p) in filtered.indexed) {
      basisSpots.add(FlSpot(i.toDouble(), showDeviation ? p.deviation : p.basis));
      if (!showDeviation) {
        avgSpots.add(FlSpot(i.toDouble(), p.avg5yr));
      }
    }

    final allValues = [
      ...basisSpots.map((s) => s.y),
      ...avgSpots.map((s) => s.y)
    ];
    final minY = allValues.reduce((a, b) => a < b ? a : b) - 4;
    final maxY = allValues.reduce((a, b) => a > b ? a : b) + 4;

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => FlLine(
              color: theme.border, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, meta) => Text(
                v.toStringAsFixed(0),
                style: CroplooText.dataSmall.copyWith(fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (filtered.length / 4).floorToDouble().clamp(1, 999),
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= filtered.length) return const SizedBox();
                final label = Fmt.dateShort(filtered[i].date);
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(label,
                      style: CroplooText.dataSmall.copyWith(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        lineTouchData: croplooLineTooltip(
          theme,
          labels: const ['Basis', 'Avg'],
          colors: [lineColor, theme.textSecondary],
          dates: [for (final p in filtered) p.date],
          valueDecimals: 2,
          valueSuffix: '¢',
        ),
        lineBarsData: [
          LineChartBarData(
            spots: basisSpots,
            // USDA basis data updates weekly, not daily — a smoothed
            // bezier spline through so few real points implies a
            // continuous daily movement that doesn't exist. Straight
            // segments + visible dots show the real sample cadence.
            isCurved: false,
            color: lineColor,
            barWidth: 2,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 2.5,
                color: lineColor,
                strokeWidth: 0,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  lineColor.withValues(alpha: 0.25),
                  lineColor.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          if (avgSpots.isNotEmpty)
            LineChartBarData(
              spots: avgSpots,
              isCurved: false,
              color: theme.textSecondary,
              barWidth: 1.5,
              dashArray: [6, 4],
              dotData: const FlDotData(show: false),
            ),
        ],
      ),
    );
  }
}

/// Legend row for the basis chart. Uses the current trend color.
class BasisChartLegend extends StatelessWidget {
  final List<BasisPoint> points;

  const BasisChartLegend({super.key, this.points = const []});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final color = points.length < 2
        ? theme.textPrimary
        : (points.last.basis > points.first.basis
            ? theme.positive
            : (points.last.basis < points.first.basis
                ? theme.negative
                : theme.textPrimary));

    Widget item(Color color, String label, {bool dashed = false}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 2,
              decoration: dashed
                  ? BoxDecoration(
                      border: Border(
                        top: BorderSide(color: color, width: 2),
                      ),
                    )
                  : null,
              color: dashed ? null : color,
            ),
            const SizedBox(width: 6),
            Text(label, style: CroplooText.dataSmall.copyWith(fontSize: 11)),
          ],
        );
    return Row(
      children: [
        item(color, 'CURRENT BASIS'),
        const SizedBox(width: 20),
        item(theme.textSecondary, '5YR AVERAGE', dashed: true),
      ],
    );
  }
}

/// Time range selector for the basis chart.
class BasisChartTimeRangeSelector extends StatelessWidget {
  final BasisTimeRange value;
  final ValueChanged<BasisTimeRange> onChanged;

  const BasisChartTimeRangeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CroplooSegmentedControl<BasisTimeRange>(
      values: BasisTimeRange.values,
      selected: value,
      onChanged: onChanged,
      labelBuilder: (r) => r.label,
    );
  }
}
