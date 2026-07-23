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
import '../../shared/widgets/controls.dart';

/// Market Intel: COT positioning, seasonal price patterns, weather
/// impact, Pro Farmer crop tour vs USDA, soybean board crush, forward
/// curve, ethanol margin, and dollar index — real-data panels that
/// don't fit cleanly under any existing section, so they get their own
/// screen. Energy-market panels (EIA inventory, NG storage, crack
/// spread) live in their own Energy screen instead — see
/// features/energy/energy_screen.dart.
class IntelScreen extends ConsumerWidget {
  const IntelScreen({super.key});

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
            Text('MARKET INTEL', style: CroplooText.h2),
            const SizedBox(height: 24),
            const SectionHeader(title: 'COT Positioning'),
            const SizedBox(height: 12),
            const _CotPanel(),
            const SizedBox(height: 40),
            const SectionHeader(title: 'Seasonal Pattern'),
            const SizedBox(height: 12),
            const _SeasonalPanel(),
            const SizedBox(height: 40),
            const SectionHeader(title: 'Weather Impact'),
            const SizedBox(height: 12),
            const _WeatherPanel(),
            const SizedBox(height: 40),
            const SectionHeader(title: 'Crop Tour vs USDA'),
            const SizedBox(height: 12),
            const _CropTourPanel(),
            const SizedBox(height: 40),
            const SectionHeader(title: 'Soybean Board Crush'),
            const SizedBox(height: 12),
            const _CrushPanel(),
            const SizedBox(height: 40),
            const SectionHeader(title: 'Forward Curve & Calendar Spread'),
            const SizedBox(height: 12),
            const _ForwardCurvePanel(),
            const SizedBox(height: 40),
            const SectionHeader(title: 'Corn-to-Ethanol Margin'),
            const SizedBox(height: 12),
            const _EthanolMarginPanel(),
            const SizedBox(height: 40),
            const SectionHeader(title: 'Dollar Index vs Corn'),
            const SizedBox(height: 12),
            const _DollarIndexPanel(),
          ],
        ),
      ),
    );
  }
}

// ── COT ──────────────────────────────────────────────────────────

class _CotPanel extends ConsumerWidget {
  const _CotPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(cotReportProvider);
    return report.when(
      loading: () => const SizedBox(height: 160, child: CroplooLoader()),
      error: (e, _) => Text('Error', style: CroplooText.body),
      data: (data) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.summary.isNotEmpty) ...[
            Text(data.summary, style: CroplooText.body),
            const SizedBox(height: 16),
          ],
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final c in data.commodities) _CotCommodityCard(snapshot: c),
            ],
          ),
        ],
      ),
    );
  }
}

class _CotCommodityCard extends StatelessWidget {
  final CotCommoditySnapshot snapshot;

  const _CotCommodityCard({required this.snapshot});

  Color _signalColor(CroplooTheme theme) => switch (snapshot.contrarianSignal) {
        'CROWDED_LONG' => theme.negative,
        'STRETCHED_LONG' => theme.negative,
        'CROWDED_SHORT' => theme.positive,
        'STRETCHED_SHORT' => theme.positive,
        _ => theme.textSecondary,
      };

  String _signalLabel() => switch (snapshot.contrarianSignal) {
        'CROWDED_LONG' => 'Crowded Long',
        'STRETCHED_LONG' => 'Stretched Long',
        'CROWDED_SHORT' => 'Crowded Short',
        'STRETCHED_SHORT' => 'Stretched Short',
        _ => 'Neutral',
      };

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return CroplooCard(
      child: SizedBox(
        width: 320,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(snapshot.commodity, style: CroplooText.h3),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: _signalColor(theme).withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Text(
                    _signalLabel().toUpperCase(),
                    style: CroplooText.label
                        .copyWith(fontSize: 9, color: _signalColor(theme)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DataLabel(
                    label: 'Managed Money Net',
                    value: snapshot.managedMoney.net.toString(),
                    valueColor: theme.changeColor(
                        snapshot.managedMoney.net.toDouble()),
                  ),
                ),
                Expanded(
                  child: DataLabel(
                    label: 'Commercials Net',
                    value: snapshot.commercials.net.toString(),
                    valueColor: theme.changeColor(
                        snapshot.commercials.net.toDouble()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DataLabel(
              label: '3Y Fund-Net Percentile',
              value: '${snapshot.netPercentile3y}%',
            ),
            if (snapshot.netHistory.length > 1) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 60,
                child: _Sparkline(
                  values: snapshot.netHistory.map((p) => p.net.toDouble()).toList(),
                ),
              ),
            ],
            if (snapshot.readout.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(snapshot.readout, style: CroplooText.dataSmall),
            ],
            if (snapshot.contrarianNote.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(snapshot.contrarianNote,
                  style: CroplooText.dataSmall
                      .copyWith(color: theme.textSecondary)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Sparkline extends StatelessWidget {
  final List<double> values;

  const _Sparkline({required this.values});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final last = values.last;
    final first = values.first;
    final color = last >= first ? theme.positive : theme.negative;
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (final (i, v) in values.indexed) FlSpot(i.toDouble(), v)
            ],
            isCurved: false,
            color: color,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}

// ── Seasonal ─────────────────────────────────────────────────────

final _seasonalSymbolProvider = StateProvider<String>((ref) => 'ZC');
const _seasonalSymbols = ['ZC', 'ZW', 'ZS'];
const _seasonalSymbolNames = {'ZC': 'Corn', 'ZW': 'Wheat', 'ZS': 'Soybeans'};

class _SeasonalPanel extends ConsumerWidget {
  const _SeasonalPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final symbol = ref.watch(_seasonalSymbolProvider);
    final pattern = ref.watch(seasonalPatternProvider(symbol));

    return CroplooCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(_seasonalSymbolNames[symbol] ?? symbol,
                  style: CroplooText.h3),
              const Spacer(),
              CroplooSegmentedControl<String>(
                values: _seasonalSymbols,
                selected: symbol,
                onChanged: (v) =>
                    ref.read(_seasonalSymbolProvider.notifier).state = v,
                labelBuilder: (s) => s,
              ),
            ],
          ),
          const SizedBox(height: 20),
          pattern.when(
            loading: () =>
                const SizedBox(height: 280, child: CroplooLoader()),
            error: (e, _) => Text('Error', style: CroplooText.body),
            data: (data) => SizedBox(
              height: 280,
              child: _SeasonalChart(pattern: data),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _legendItem(context, 'CURRENT YEAR', CroplooTheme.of(context).accent),
              const SizedBox(width: 20),
              _legendItem(
                  context, '5YR AVG', CroplooTheme.of(context).textPrimary),
              const SizedBox(width: 20),
              _legendItem(context, '10YR AVG',
                  CroplooTheme.of(context).textSecondary,
                  dashed: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendItem(BuildContext context, String label, Color color,
      {bool dashed = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 2,
          decoration: dashed
              ? BoxDecoration(border: Border(top: BorderSide(color: color, width: 2)))
              : null,
          color: dashed ? null : color,
        ),
        const SizedBox(width: 6),
        Text(label, style: CroplooText.label.copyWith(fontSize: 9)),
      ],
    );
  }
}

class _SeasonalChart extends StatelessWidget {
  final SeasonalPattern pattern;

  const _SeasonalChart({required this.pattern});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final weeks = pattern.weeks;

    List<FlSpot> spotsFor(double? Function(SeasonalWeek) pick) => [
          for (final (i, w) in weeks.indexed)
            if (pick(w) != null) FlSpot(i.toDouble(), pick(w)!),
        ];

    final avg5Spots = spotsFor((w) => w.avg5yr);
    final avg10Spots = spotsFor((w) => w.avg10yr);
    final currentSpots = spotsFor((w) => w.current);

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) =>
              FlLine(color: theme.bgBorder, strokeWidth: 1),
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
              reservedSize: 40,
              getTitlesWidget: (v, meta) => Text('${v.toStringAsFixed(0)}%',
                  style: CroplooText.dataSmall.copyWith(fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 8,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= weeks.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('W${weeks[i].week}',
                      style: CroplooText.dataSmall.copyWith(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipRoundedRadius: 0,
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            tooltipMargin: 8,
            maxContentWidth: 200,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipColor: (_) => theme.bgElevated,
            getTooltipItems: (spots) {
              final i = spots.firstOrNull?.x.toInt() ?? 0;
              final week = i >= 0 && i < weeks.length ? 'W${weeks[i].week}' : '';
              return spots.map((s) {
                final label = switch (s.barIndex) {
                  0 => '10yr avg',
                  1 => '5yr avg',
                  _ => 'Current',
                };
                final color = switch (s.barIndex) {
                  0 => theme.textSecondary,
                  1 => theme.textPrimary,
                  _ => theme.accent,
                };
                final prefix = s == spots.first ? '$week\n' : '';
                return LineTooltipItem(
                  '$prefix$label ${s.y.toStringAsFixed(1)}%',
                  CroplooText.dataSmall.copyWith(color: color, fontSize: 12, height: 1.4),
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: avg10Spots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: theme.textSecondary,
            barWidth: 1.5,
            dashArray: [6, 4],
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: avg5Spots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: theme.textPrimary,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: currentSpots,
            isCurved: false,
            color: theme.accent,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}

// ── Weather ──────────────────────────────────────────────────────

class _WeatherPanel extends ConsumerWidget {
  const _WeatherPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final impact = ref.watch(weatherImpactProvider);
    final drought = ref.watch(droughtMonitorProvider).valueOrNull ?? const [];
    final droughtByState = {for (final d in drought) d.state: d};
    return impact.when(
      loading: () => const SizedBox(height: 160, child: CroplooLoader()),
      error: (e, _) => Text('Error', style: CroplooText.body),
      data: (data) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.headline.isNotEmpty) ...[
            Text(data.headline, style: CroplooText.bodyStrong),
            const SizedBox(height: 8),
          ],
          if (data.summary.isNotEmpty) ...[
            Text(data.summary, style: CroplooText.body),
            const SizedBox(height: 16),
          ],
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final s in data.states)
                _WeatherStateCard(state: s, drought: droughtByState[s.state]),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeatherStateCard extends StatelessWidget {
  final WeatherStateImpact state;
  final DroughtSnapshot? drought;

  const _WeatherStateCard({required this.state, this.drought});

  Color _droughtColor(CroplooTheme theme, String category) => switch (category) {
        'D4' || 'D3' => theme.negative,
        'D2' || 'D1' => theme.accent,
        'D0' => theme.textSecondary,
        _ => theme.positive,
      };

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final severityColor = switch (state.severity) {
      'HIGH' => theme.negative,
      'MEDIUM' => theme.accent,
      _ => theme.textSecondary,
    };
    return CroplooCard(
      padding: const EdgeInsets.all(16),
      borderColor: state.severity == 'HIGH' ? severityColor : null,
      child: SizedBox(
        width: 240,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(state.name, style: CroplooText.bodyStrong),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: severityColor.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Text(state.severity,
                      style: CroplooText.label
                          .copyWith(fontSize: 9, color: severityColor)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DataLabel(
              label: '3M Precip vs Normal',
              value: Fmt.pct(state.precip3mDeparturePct),
              valueColor: theme.changeColor(-state.precip3mDeparturePct),
            ),
            if (drought != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  DataLabel(
                    label: 'US Drought Monitor',
                    value: drought!.worstCategory,
                    valueColor: _droughtColor(theme, drought!.worstCategory),
                  ),
                  const Spacer(),
                  Text('${drought!.anyDroughtPct.toStringAsFixed(0)}% D0+',
                      style: CroplooText.dataSmall
                          .copyWith(color: theme.textMuted)),
                ],
              ),
            ],
            if (state.implication.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(state.implication, style: CroplooText.dataSmall),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Crop Tour ────────────────────────────────────────────────────

class _CropTourPanel extends ConsumerWidget {
  const _CropTourPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comparisons = ref.watch(cropTourComparisonsProvider);
    return comparisons.when(
      loading: () => const SizedBox(height: 160, child: CroplooLoader()),
      error: (e, _) => Text('Error', style: CroplooText.body),
      data: (list) => Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final c in list) _CropTourCard(comparison: c),
        ],
      ),
    );
  }
}

class _CropTourCard extends StatelessWidget {
  final CropTourComparison comparison;

  const _CropTourCard({required this.comparison});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return CroplooCard(
      child: SizedBox(
        width: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(comparison.commodity, style: CroplooText.h3),
            const SizedBox(height: 8),
            if (comparison.headline.isNotEmpty)
              Text(comparison.headline, style: CroplooText.bodyStrong),
            const SizedBox(height: 12),
            for (final y in comparison.years)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                        width: 44,
                        child: Text('${y.year}', style: CroplooText.dataSmall)),
                    Expanded(
                      child: Text('PF ${y.proFarmer.toStringAsFixed(0)}',
                          style: CroplooText.dataSmall),
                    ),
                    Expanded(
                      child: Text('USDA ${y.usda.toStringAsFixed(0)}',
                          style: CroplooText.dataSmall),
                    ),
                    Text(
                      Fmt.change(y.diff),
                      style: CroplooText.dataSmall
                          .copyWith(color: theme.changeColor(y.diff)),
                    ),
                  ],
                ),
              ),
            if (comparison.summary.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(comparison.summary, style: CroplooText.dataSmall),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Crush ────────────────────────────────────────────────────────

class _CrushPanel extends ConsumerWidget {
  const _CrushPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final crush = ref.watch(crushSpreadProvider);
    return crush.when(
      loading: () => const SizedBox(height: 200, child: CroplooLoader()),
      error: (e, _) => Text('Error', style: CroplooText.body),
      data: (data) => CroplooCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('\$${Fmt.price(data.crush)}/bu',
                    style: CroplooText.dataXL),
                const SizedBox(width: 12),
                ChangeChip(value: data.change1w),
                const Spacer(),
                DataLabel(
                  label: 'Period Avg',
                  value: '\$${Fmt.price(data.avgPeriod)}',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DataLabel(
                    label: 'Soybeans',
                    value: '${data.legs.soybeansCentsBu.toStringAsFixed(0)}¢',
                  ),
                ),
                Expanded(
                  child: DataLabel(
                    label: 'Oil Value',
                    value: '\$${Fmt.price(data.legs.oilValueUsdBu)}',
                  ),
                ),
                Expanded(
                  child: DataLabel(
                    label: 'Meal Value',
                    value: '\$${Fmt.price(data.legs.mealValueUsdBu)}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: _CrushChart(history: data.history),
            ),
          ],
        ),
      ),
    );
  }
}

class _CrushChart extends StatelessWidget {
  final List<CrushHistoryPoint> history;

  const _CrushChart({required this.history});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) =>
              FlLine(color: theme.bgBorder, strokeWidth: 1),
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
          labels: const ['Crush'],
          colors: [theme.accent],
          dates: [for (final p in history) p.date],
          valueDecimals: 2,
          valueSuffix: '',
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (final (i, p) in history.indexed)
                FlSpot(i.toDouble(), p.crush)
            ],
            isCurved: true,
            curveSmoothness: 0.15,
            color: theme.accent,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  theme.accent.withValues(alpha: 0.2),
                  theme.accent.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Forward Curve & Calendar Spread ──────────────────────────────

final _curveSymbolProvider = StateProvider<String>((ref) => 'ZC');

class _ForwardCurvePanel extends ConsumerWidget {
  const _ForwardCurvePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final symbol = ref.watch(_curveSymbolProvider);
    final curve = ref.watch(forwardCurveProvider(symbol));
    final spread = ref.watch(calendarSpreadProvider(symbol));

    return CroplooCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(_seasonalSymbolNames[symbol] ?? symbol, style: CroplooText.h3),
              const Spacer(),
              CroplooSegmentedControl<String>(
                values: _seasonalSymbols,
                selected: symbol,
                onChanged: (v) => ref.read(_curveSymbolProvider.notifier).state = v,
                labelBuilder: (s) => s,
              ),
            ],
          ),
          const SizedBox(height: 16),
          curve.when(
            loading: () => const SizedBox(height: 240, child: CroplooLoader()),
            error: (e, _) => Text('Error', style: CroplooText.body),
            data: (data) {
              final structureColor = switch (data.structure) {
                'CARRY' => theme.positive,
                'INVERSION' => theme.negative,
                _ => theme.textSecondary,
              };
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: structureColor.withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.zero,
                    ),
                    child: Text(data.structure,
                        style: CroplooText.label
                            .copyWith(fontSize: 9, color: structureColor)),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 220,
                    child: _ForwardCurveChart(contracts: data.contracts),
                  ),
                  if (data.note.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(data.note, style: CroplooText.dataSmall),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          Text('CALENDAR SPREAD (NEAR − FAR)', style: CroplooText.label.copyWith(fontSize: 10)),
          const SizedBox(height: 12),
          spread.when(
            loading: () => const SizedBox(height: 160, child: CroplooLoader()),
            error: (e, _) => Text('Error', style: CroplooText.body),
            data: (points) => SizedBox(
              height: 160,
              child: _CalendarSpreadChart(points: points),
            ),
          ),
        ],
      ),
    );
  }
}

class _ForwardCurveChart extends StatelessWidget {
  final List<ForwardCurveContract> contracts;

  const _ForwardCurveChart({required this.contracts});

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
              reservedSize: 44,
              getTitlesWidget: (v, meta) => Text(v.toStringAsFixed(0),
                  style: CroplooText.dataSmall.copyWith(fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= contracts.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(contracts[i].contractMonth,
                      style: CroplooText.dataSmall.copyWith(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipRoundedRadius: 0,
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            tooltipMargin: 8,
            maxContentWidth: 180,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipColor: (_) => theme.bgElevated,
            getTooltipItems: (spots) => spots.map((s) {
              final i = s.x.toInt();
              final contract = i >= 0 && i < contracts.length ? contracts[i].contractMonth : '';
              return LineTooltipItem(
                '$contract\nPrice \$${s.y.toStringAsFixed(2)}',
                CroplooText.dataSmall.copyWith(color: theme.accent, fontSize: 12, height: 1.4),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (final (i, c) in contracts.indexed) FlSpot(i.toDouble(), c.price)
            ],
            isCurved: false,
            color: theme.accent,
            barWidth: 2,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) =>
                  FlDotCirclePainter(radius: 3, color: theme.accent, strokeWidth: 0),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarSpreadChart extends StatelessWidget {
  final List<CalendarSpreadPoint> points;

  const _CalendarSpreadChart({required this.points});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    if (points.isEmpty) {
      return Center(child: Text('No history yet', style: CroplooText.dataSmall));
    }
    final last = points.last.spread;
    final first = points.first.spread;
    final color = last >= first ? theme.positive : theme.negative;
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
              interval: (points.length / 4).floorToDouble().clamp(1, 999),
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= points.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(Fmt.dateShort(points[i].date),
                      style: CroplooText.dataSmall.copyWith(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        lineTouchData: croplooLineTooltip(
          theme,
          labels: const ['Spread'],
          colors: [color],
          dates: [for (final p in points) p.date],
          valueDecimals: 2,
          valueSuffix: '',
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (final (i, p) in points.indexed) FlSpot(i.toDouble(), p.spread)
            ],
            isCurved: false,
            color: color,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}

// ── Ethanol Margin ────────────────────────────────────────────────

class _EthanolMarginPanel extends ConsumerWidget {
  const _EthanolMarginPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final margin = ref.watch(ethanolMarginProvider);
    return margin.when(
      loading: () => const SizedBox(height: 200, child: CroplooLoader()),
      error: (e, _) => Text('Error', style: CroplooText.body),
      data: (data) => CroplooCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('\$${data.margin.toStringAsFixed(2)}/bu', style: CroplooText.dataXL),
                const SizedBox(width: 12),
                ChangeChip(value: data.change1w),
                const Spacer(),
                DataLabel(label: 'Period Avg', value: '\$${data.avgPeriod.toStringAsFixed(2)}'),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DataLabel(
                      label: 'Corn', value: '\$${data.cornPriceUsdBu.toStringAsFixed(2)}/bu'),
                ),
                Expanded(
                  child: DataLabel(
                      label: 'Ethanol',
                      value: '\$${data.ethanolPriceUsdGal.toStringAsFixed(2)}/gal'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(height: 160, child: _EthanolChart(history: data.history)),
          ],
        ),
      ),
    );
  }
}

class _EthanolChart extends StatelessWidget {
  final List<EthanolMarginPoint> history;

  const _EthanolChart({required this.history});

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
          labels: const ['Margin'],
          colors: [theme.accent],
          dates: [for (final p in history) p.date],
          valueDecimals: 2,
          valueSuffix: '',
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (final (i, p) in history.indexed) FlSpot(i.toDouble(), p.margin)
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

// ── Dollar Index ─────────────────────────────────────────────────

class _DollarIndexPanel extends ConsumerWidget {
  const _DollarIndexPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final snapshot = ref.watch(dollarIndexProvider);
    return snapshot.when(
      loading: () => const SizedBox(height: 240, child: CroplooLoader()),
      error: (e, _) => Text('Error', style: CroplooText.body),
      data: (data) => CroplooCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(data.dollarIndex.toStringAsFixed(1), style: CroplooText.dataXL),
                const SizedBox(width: 12),
                ChangeChip(value: data.change30dPct, formatter: Fmt.pct),
                const Spacer(),
                DataLabel(
                  label: '1Y Corr. w/ Corn',
                  value: data.correlationWithCorn1y.toStringAsFixed(2),
                  valueColor: data.correlationWithCorn1y < 0 ? theme.negative : theme.positive,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(height: 220, child: _DollarIndexChart(history: data.history)),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(width: 16, height: 2, color: theme.textPrimary),
                const SizedBox(width: 6),
                Text('DOLLAR INDEX', style: CroplooText.label.copyWith(fontSize: 9)),
                const SizedBox(width: 20),
                Container(width: 16, height: 2, color: theme.textSecondary),
                const SizedBox(width: 6),
                Text('CORN', style: CroplooText.label.copyWith(fontSize: 9)),
              ],
            ),
            if (data.note.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(data.note, style: CroplooText.dataSmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _DollarIndexChart extends StatelessWidget {
  final List<DollarIndexPoint> history;

  const _DollarIndexChart({required this.history});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    // Different scales (index ~28, corn ~450¢) — index both to their
    // own first value = 100 so the two lines are visually comparable.
    final dollarBase = history.first.dollarIndex;
    final cornBase = history.first.cornPrice;

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
              reservedSize: 44,
              getTitlesWidget: (v, meta) => Text('${v.toStringAsFixed(0)}%',
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
          labels: const ['CORN', 'DXY'],
          colors: [theme.textSecondary, theme.textPrimary],
          dates: [for (final p in history) p.date],
          valueDecimals: 1,
          valueSuffix: '%',
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (final (i, p) in history.indexed)
                FlSpot(i.toDouble(), (p.cornPrice / cornBase) * 100)
            ],
            isCurved: false,
            color: theme.textSecondary,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: [
              for (final (i, p) in history.indexed)
                FlSpot(i.toDouble(), (p.dollarIndex / dollarBase) * 100)
            ],
            isCurved: false,
            color: theme.textPrimary,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}
