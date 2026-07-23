import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_colors.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/providers.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/chart_tooltip.dart';
import '../../shared/widgets/common.dart';

/// Energy: EIA weekly petroleum inventory, natural gas storage, and the
/// 3:2:1 crack spread — the energy-market panels that feed into freight
/// (diesel) and ethanol-margin economics elsewhere in the app.
class EnergyScreen extends ConsumerWidget {
  const EnergyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final hasPro = user != null && user.tier.atLeast(SubscriptionTier.pro);

    return TierGate(
      requiredTier: 'PRO',
      locked: !hasPro,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ENERGY', style: CroplooText.h2),
            const SizedBox(height: 24),
            const SectionHeader(title: 'EIA Weekly Petroleum Inventory'),
            const SizedBox(height: 12),
            const _EiaInventoryPanel(),
            const SizedBox(height: 40),
            const SectionHeader(title: 'Natural Gas Storage'),
            const SizedBox(height: 12),
            const _NgStoragePanel(),
            const SizedBox(height: 40),
            const SectionHeader(title: 'Crack Spread (Refining Margin)'),
            const SizedBox(height: 12),
            const _CrackSpreadPanel(),
          ],
        ),
      ),
    );
  }
}

// ── EIA Weekly Petroleum Inventory ──────────────────────────────

class _EiaInventoryPanel extends ConsumerWidget {
  const _EiaInventoryPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(eiaInventoryProvider);
    return report.when(
      loading: () => const SizedBox(height: 200, child: CroplooLoader()),
      error: (e, _) => Text('Error', style: CroplooText.body),
      data: (data) {
        final latest = data.latest;
        return CroplooCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ImpactBadge(direction: latest.aiDirection),
                  const Spacer(),
                  Text('Report: ${Fmt.date(latest.reportDate)}',
                      style: CroplooText.dataSmall),
                ],
              ),
              if (latest.aiHeadline.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(latest.aiHeadline, style: CroplooText.bodyStrong),
              ],
              if (latest.aiSummary.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(latest.aiSummary, style: CroplooText.body),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                      child: _StockColumn(
                          label: 'Crude',
                          stocksKbbl: latest.crudeStocksKbbl,
                          changeKbbl: latest.crudeChangeKbbl)),
                  Expanded(
                      child: _StockColumn(
                          label: 'Gasoline',
                          stocksKbbl: latest.gasolineStocksKbbl,
                          changeKbbl: latest.gasolineChangeKbbl)),
                  Expanded(
                      child: _StockColumn(
                          label: 'Distillate',
                          stocksKbbl: latest.distillateStocksKbbl,
                          changeKbbl: latest.distillateChangeKbbl)),
                ],
              ),
              if (data.history.length > 1) ...[
                const SizedBox(height: 20),
                SizedBox(height: 160, child: _EiaInventoryChart(history: data.history)),
              ],
              const SizedBox(height: 12),
              Text(
                'No market-consensus estimate is shown — EIA doesn\'t publish one and '
                'there\'s no free source for analyst forecasts, only the real reported change.',
                style: CroplooText.dataSmall,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StockColumn extends StatelessWidget {
  final String label;
  final double stocksKbbl;
  final double changeKbbl;

  const _StockColumn({
    required this.label,
    required this.stocksKbbl,
    required this.changeKbbl,
  });

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: CroplooText.label.copyWith(fontSize: 10)),
        const SizedBox(height: 4),
        Text('${(stocksKbbl / 1000).toStringAsFixed(0)}M bbl', style: CroplooText.data),
        const SizedBox(height: 2),
        Text(
          '${changeKbbl >= 0 ? '+' : ''}${(changeKbbl / 1000).toStringAsFixed(0)}M bbl',
          style: CroplooText.dataSmall.copyWith(color: theme.changeColor(changeKbbl)),
        ),
      ],
    );
  }
}

class _EiaInventoryChart extends StatelessWidget {
  final List<EiaInventorySnapshot> history;

  const _EiaInventoryChart({required this.history});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => FlLine(color: theme.bgBorder, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              getTitlesWidget: (v, meta) => Text('${v.toStringAsFixed(0)}M',
                  style: CroplooText.dataSmall.copyWith(fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (history.length / 4).floorToDouble().clamp(1, 999),
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= history.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(Fmt.dateShort(history[i].reportDate),
                      style: CroplooText.dataSmall.copyWith(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        lineTouchData: croplooLineTooltip(
          theme,
          labels: const ['Crude'],
          colors: [theme.accent],
          dates: [for (final p in history) p.reportDate],
          valueDecimals: 1,
          valueSuffix: 'M bbl',
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (final (i, p) in history.indexed)
                FlSpot(i.toDouble(), p.crudeStocksKbbl / 1000)
            ],
            isCurved: false,
            color: theme.accent,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}

// ── Natural Gas Storage ──────────────────────────────────────────

class _NgStoragePanel extends ConsumerWidget {
  const _NgStoragePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final report = ref.watch(ngStorageProvider);
    return report.when(
      loading: () => const SizedBox(height: 200, child: CroplooLoader()),
      error: (e, _) => Text('Error', style: CroplooText.body),
      data: (data) {
        final latest = data.latest;
        return CroplooCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ImpactBadge(direction: latest.aiDirection),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.bgBorder),
                      borderRadius: BorderRadius.zero,
                    ),
                    child: Text(
                      latest.isInjectionSeason ? 'INJECTION SEASON' : 'WITHDRAWAL SEASON',
                      style: CroplooText.label.copyWith(fontSize: 9),
                    ),
                  ),
                  const Spacer(),
                  Text('Report: ${Fmt.date(latest.reportDate)}',
                      style: CroplooText.dataSmall),
                ],
              ),
              if (latest.aiHeadline.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(latest.aiHeadline, style: CroplooText.bodyStrong),
              ],
              if (latest.aiSummary.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(latest.aiSummary, style: CroplooText.body),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: DataLabel(
                      label: 'Storage',
                      value: '${latest.storageBcf.toStringAsFixed(0)} Bcf',
                    ),
                  ),
                  Expanded(
                    child: DataLabel(
                      label: 'Weekly Change',
                      value:
                          '${latest.weeklyChangeBcf >= 0 ? '+' : ''}${latest.weeklyChangeBcf.toStringAsFixed(0)} Bcf',
                      valueColor: theme.changeColor(latest.weeklyChangeBcf),
                    ),
                  ),
                  Expanded(
                    child: DataLabel(
                      label: 'vs Last Year',
                      value: Fmt.pct(latest.vsLastYearPct),
                      valueColor: theme.changeColor(latest.vsLastYearPct),
                    ),
                  ),
                  Expanded(
                    child: DataLabel(
                      label: 'vs 5Y Avg',
                      value: Fmt.pct(latest.vs5yAvgPct),
                      valueColor: theme.changeColor(latest.vs5yAvgPct),
                    ),
                  ),
                ],
              ),
              if (data.history.length > 1) ...[
                const SizedBox(height: 20),
                SizedBox(height: 160, child: _NgStorageChart(history: data.history)),
              ],
              const SizedBox(height: 12),
              Text(
                'No market-consensus estimate is shown — EIA doesn\'t publish one and '
                'there\'s no free source for analyst forecasts, only the real reported change.',
                style: CroplooText.dataSmall,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NgStorageChart extends StatelessWidget {
  final List<NgStorageSnapshot> history;

  const _NgStorageChart({required this.history});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => FlLine(color: theme.bgBorder, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              getTitlesWidget: (v, meta) => Text(v.toStringAsFixed(0),
                  style: CroplooText.dataSmall.copyWith(fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (history.length / 4).floorToDouble().clamp(1, 999),
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= history.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(Fmt.dateShort(history[i].reportDate),
                      style: CroplooText.dataSmall.copyWith(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        lineTouchData: croplooLineTooltip(
          theme,
          labels: const ['Storage'],
          colors: [theme.accent],
          dates: [for (final p in history) p.reportDate],
          valueDecimals: 0,
          valueSuffix: ' Bcf',
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (final (i, p) in history.indexed) FlSpot(i.toDouble(), p.storageBcf)
            ],
            isCurved: false,
            color: theme.accent,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}

// ── Crack Spread ─────────────────────────────────────────────────

class _CrackSpreadPanel extends ConsumerWidget {
  const _CrackSpreadPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spread = ref.watch(crackSpreadProvider);
    return spread.when(
      loading: () => const SizedBox(height: 200, child: CroplooLoader()),
      error: (e, _) => Text('Error', style: CroplooText.body),
      data: (data) => CroplooCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('\$${data.crackSpreadUsdBbl.toStringAsFixed(2)}/bbl',
                    style: CroplooText.dataXL),
                const SizedBox(width: 12),
                ChangeChip(value: data.change1w),
                const Spacer(),
                DataLabel(
                    label: 'Period Avg', value: '\$${data.avgPeriodUsdBbl.toStringAsFixed(2)}'),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DataLabel(
                      label: 'Crude', value: '\$${data.crudeUsdBbl.toStringAsFixed(2)}/bbl'),
                ),
                Expanded(
                  child: DataLabel(
                      label: 'Gasoline',
                      value: '\$${data.gasolineUsdGal.toStringAsFixed(2)}/gal'),
                ),
                Expanded(
                  child: DataLabel(
                      label: 'Heating Oil',
                      value: '\$${data.heatingOilUsdGal.toStringAsFixed(2)}/gal'),
                ),
              ],
            ),
            if (data.aiDirection != null && data.aiHeadline.isNotEmpty) ...[
              const SizedBox(height: 16),
              ImpactBadge(direction: data.aiDirection!),
              const SizedBox(height: 8),
              Text(data.aiHeadline, style: CroplooText.bodyStrong),
              if (data.aiSummary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(data.aiSummary, style: CroplooText.body),
              ],
            ],
            const SizedBox(height: 20),
            SizedBox(height: 160, child: _CrackSpreadChart(history: data.history)),
          ],
        ),
      ),
    );
  }
}

class _CrackSpreadChart extends StatelessWidget {
  final List<CrackSpreadPoint> history;

  const _CrackSpreadChart({required this.history});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    if (history.length < 2) {
      return Center(
        child: Text('Building history — check back tomorrow', style: CroplooText.dataSmall),
      );
    }
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => FlLine(color: theme.bgBorder, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, meta) => Text(v.toStringAsFixed(0),
                  style: CroplooText.dataSmall.copyWith(fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (history.length / 4).floorToDouble().clamp(1, 999),
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= history.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(Fmt.dateShort(history[i].date),
                      style: CroplooText.dataSmall.copyWith(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        lineTouchData: croplooLineTooltip(
          theme,
          labels: const ['Crack Spread'],
          colors: [theme.accent],
          dates: [for (final p in history) p.date],
          valueDecimals: 2,
          valueSuffix: r'$/bbl',
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (final (i, p) in history.indexed)
                FlSpot(i.toDouble(), p.crackSpreadUsdBbl)
            ],
            isCurved: false,
            color: theme.accent,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}
