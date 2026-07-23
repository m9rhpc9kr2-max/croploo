import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme/theme_colors.dart';
import '../../core/theme/typography.dart';
import '../../shared/models/models.dart';

/// Renders a [ChartSpec] that CullyAI produced via its `render_chart` tool
/// (see backend/src/aiTools.js). Supports the MVP chart kinds — line, bar,
/// area — styled with the same fl_chart conventions as [BasisChart]
/// (straight segments, sharp corners, CroplooTheme colors).
class AiChartWidget extends StatelessWidget {
  final ChartSpec spec;

  const AiChartWidget({super.key, required this.spec});

  Color _seriesColor(CroplooTheme theme, int index) {
    final colors = [theme.accent, theme.positive, theme.negative, theme.textSecondary];
    return colors[index % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    if (spec.series.isEmpty || spec.series.every((s) => s.points.isEmpty)) {
      return const SizedBox.shrink();
    }

    final labels = spec.series.first.points.map((p) => p.x).toList();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 8),
      decoration: BoxDecoration(
        color: theme.bgSurface,
        border: Border.all(color: theme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (spec.title.isNotEmpty) ...[
            Text(spec.title,
                style: CroplooText.bodyStrong
                    .copyWith(fontSize: 12, color: theme.textPrimary)),
            const SizedBox(height: 10),
          ],
          SizedBox(
            height: 180,
            child: spec.kind == ChartKind.bar
                ? _buildBar(theme, labels)
                : _buildLine(theme, labels),
          ),
          if (spec.series.length > 1) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                for (final (i, s) in spec.series.indexed)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                          width: 10,
                          height: 2,
                          color: _seriesColor(theme, i)),
                      const SizedBox(width: 6),
                      Text(s.label,
                          style: CroplooText.dataSmall.copyWith(fontSize: 10)),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLine(CroplooTheme theme, List<String> labels) {
    final barsData = <LineChartBarData>[];
    for (final (i, series) in spec.series.indexed) {
      final color = _seriesColor(theme, i);
      final spots = [
        for (final (idx, p) in series.points.indexed) FlSpot(idx.toDouble(), p.y)
      ];
      barsData.add(LineChartBarData(
        spots: spots,
        isCurved: false,
        color: color,
        barWidth: 2,
        dotData: FlDotData(
          show: series.points.length < 40,
          getDotPainter: (spot, percent, bar, index) =>
              FlDotCirclePainter(radius: 2.5, color: color, strokeWidth: 0),
        ),
        belowBarData: spec.kind == ChartKind.area
            ? BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    color.withValues(alpha: 0.22),
                    color.withValues(alpha: 0.0),
                  ],
                ),
              )
            : BarAreaData(show: false),
      ));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => FlLine(color: theme.border, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: _titlesData(theme, labels),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipRoundedRadius: 0,
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            getTooltipColor: (_) => theme.bgElevated,
            getTooltipItems: (spots) => spots.map((s) {
              final i = s.x.toInt();
              final label = i >= 0 && i < labels.length ? labels[i] : '';
              return LineTooltipItem(
                '$label\n${s.y.toStringAsFixed(2)}',
                CroplooText.dataSmall.copyWith(color: theme.textPrimary, fontSize: 11),
              );
            }).toList(),
          ),
        ),
        lineBarsData: barsData,
      ),
    );
  }

  Widget _buildBar(CroplooTheme theme, List<String> labels) {
    final series = spec.series.first;
    final color = _seriesColor(theme, 0);
    final groups = [
      for (final (idx, p) in series.points.indexed)
        BarChartGroupData(x: idx, barRods: [
          BarChartRodData(toY: p.y, color: color, width: 12),
        ])
    ];

    return BarChart(
      BarChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => FlLine(color: theme.border, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: _titlesData(theme, labels),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            tooltipRoundedRadius: 0,
            getTooltipColor: (_) => theme.bgElevated,
            getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
              '${groupIndex >= 0 && groupIndex < labels.length ? labels[groupIndex] : ''}\n${rod.toY.toStringAsFixed(2)}',
              CroplooText.dataSmall.copyWith(color: theme.textPrimary, fontSize: 11),
            ),
          ),
        ),
        barGroups: groups,
      ),
    );
  }

  FlTitlesData _titlesData(CroplooTheme theme, List<String> labels) {
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 40,
          getTitlesWidget: (v, meta) => Text(
            v.toStringAsFixed(0),
            style: CroplooText.dataSmall.copyWith(fontSize: 9),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: (labels.length / 4).floorToDouble().clamp(1, 999),
          getTitlesWidget: (v, meta) {
            final i = v.toInt();
            if (i < 0 || i >= labels.length) return const SizedBox();
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(labels[i],
                  style: CroplooText.dataSmall.copyWith(fontSize: 9)),
            );
          },
        ),
      ),
    );
  }
}
