import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/theme_colors.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/providers.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/chart_tooltip.dart';
import '../../shared/widgets/common.dart';

/// Advanced Analytics: intermarket lead-lag correlation, realized
/// volatility, a relative-value screener across grains, and a spread
/// trading terminal — institutional-grade tools built entirely from
/// data already cached elsewhere in the app.
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final hasDesk = user != null && user.tier.atLeast(SubscriptionTier.desk);

    return TierGate(
      requiredTier: 'DESK',
      locked: !hasDesk,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ANALYTICS', style: CroplooText.h2),
            const SizedBox(height: 24),
            const SectionHeader(title: 'Relative Value Screener'),
            const SizedBox(height: 12),
            const _RelativeValuePanel(),
            const SizedBox(height: 40),
            const SectionHeader(title: 'Intermarket Analysis (Lead-Lag)'),
            const SizedBox(height: 12),
            const _IntermarketPanel(),
            const SizedBox(height: 40),
            const SectionHeader(title: 'Volatility Monitor'),
            const SizedBox(height: 12),
            const _VolatilityPanel(),
            const SizedBox(height: 40),
            const SectionHeader(title: 'Spread Trading Terminal'),
            const SizedBox(height: 12),
            const _SpreadTerminalPanel(),
          ],
        ),
      ),
    );
  }
}

// ── Relative Value Screener ─────────────────────────────────────

class _RelativeValuePanel extends ConsumerWidget {
  const _RelativeValuePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final data = ref.watch(relativeValueScreenerProvider);
    return data.when(
      loading: () => const SizedBox(height: 160, child: CroplooLoader()),
      error: (e, _) => Text('Error', style: CroplooText.body),
      data: (screener) => CroplooCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (final row in screener.commodities)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: theme.border))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.commodity, style: CroplooText.bodyStrong),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 24,
                      runSpacing: 8,
                      children: [
                        if (row.from52wHighPct != null)
                          DataLabel(
                              label: 'vs 52W High',
                              value: '${row.from52wHighPct!.toStringAsFixed(1)}%',
                              valueColor: theme.changeColor(row.from52wHighPct!)),
                        if (row.from52wLowPct != null)
                          DataLabel(
                              label: 'vs 52W Low',
                              value: '${row.from52wLowPct!.toStringAsFixed(1)}%',
                              valueColor: theme.changeColor(row.from52wLowPct!)),
                        if (row.seasonalDeviationPct != null)
                          DataLabel(
                              label: 'Seasonal Dev.',
                              value: '${row.seasonalDeviationPct!.toStringAsFixed(1)}%',
                              valueColor: theme.changeColor(row.seasonalDeviationPct!)),
                        if (row.cotPercentile3y != null)
                          DataLabel(
                              label: 'COT Pctile (3y)', value: '${row.cotPercentile3y}%'),
                        if (row.basisPercentile52w != null)
                          DataLabel(
                              label: 'Basis Pctile (52w)',
                              value: '${row.basisPercentile52w}%'),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Intermarket Analysis ────────────────────────────────────────

class _IntermarketPanel extends ConsumerWidget {
  const _IntermarketPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final data = ref.watch(intermarketAnalysisProvider);
    return data.when(
      loading: () => const SizedBox(height: 160, child: CroplooLoader()),
      error: (e, _) => Text('Error', style: CroplooText.body),
      data: (analysis) => CroplooCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (final pair in analysis.pairs)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: theme.border))),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(child: Text(pair.a, style: CroplooText.bodyStrong.copyWith(fontSize: 13))),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(
                              pair.leader == null 
                                  ? PhosphorIconsRegular.arrowsLeftRight
                                  : PhosphorIconsRegular.arrowRight,
                              size: 14,
                              color: theme.textSecondary,
                            ),
                          ),
                          Expanded(child: Text(pair.b, style: CroplooText.bodyStrong.copyWith(fontSize: 13))),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Text(
                        pair.leader == null
                            ? 'Contemporaneous (no clear lead)'
                            : '${pair.leader} leads by ${pair.bestLagDays.abs()}d',
                        style: CroplooText.body.copyWith(fontSize: 12, color: theme.textMuted),
                      ),
                    ),
                    DataLabel(
                      label: 'Corr.',
                      value: pair.correlationAtBestLag.toStringAsFixed(2),
                      valueColor: pair.correlationAtBestLag < 0 ? theme.negative : theme.positive,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Volatility Monitor ──────────────────────────────────────────

class _VolatilityPanel extends ConsumerWidget {
  const _VolatilityPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final data = ref.watch(volatilityMonitorProvider);
    return data.when(
      loading: () => const SizedBox(height: 160, child: CroplooLoader()),
      error: (e, _) => Text('Error', style: CroplooText.body),
      data: (vol) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final c in vol.commodities)
                CroplooCard(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: 200,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.commodity, style: CroplooText.bodyStrong),
                        const SizedBox(height: 8),
                        Text('${c.realizedVol20d.toStringAsFixed(1)}%',
                            style: CroplooText.dataLarge),
                        const SizedBox(height: 2),
                        Text('20D REALIZED VOL (ANN.)',
                            style: CroplooText.label.copyWith(fontSize: 9)),
                        const SizedBox(height: 10),
                        DataLabel(
                          label: '1Y Percentile',
                          value: '${c.volPercentile1y}%',
                          valueColor: c.volPercentile1y >= 75
                              ? theme.negative
                              : (c.volPercentile1y <= 25 ? theme.positive : theme.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(vol.note, style: CroplooText.dataSmall.copyWith(color: theme.textMuted)),
        ],
      ),
    );
  }
}

// ── Spread Trading Terminal ─────────────────────────────────────

final _selectedSpreadProvider = StateProvider<String?>((ref) => null);

class _SpreadTerminalPanel extends ConsumerWidget {
  const _SpreadTerminalPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final data = ref.watch(spreadTerminalProvider);
    return data.when(
      loading: () => const SizedBox(height: 200, child: CroplooLoader()),
      error: (e, _) => Text('Error', style: CroplooText.body),
      data: (terminal) {
        final selectedKey = ref.watch(_selectedSpreadProvider) ??
            (terminal.spreads.isNotEmpty ? terminal.spreads.first.key : null);
        final selected = terminal.spreads.where((s) => s.key == selectedKey).firstOrNull;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final s in terminal.spreads)
                  InkWell(
                    onTap: () => ref.read(_selectedSpreadProvider.notifier).state = s.key,
                    child: Container(
                      width: 200,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: selectedKey == s.key ? theme.accentDim : theme.bgSurface,
                        border: Border.all(
                            color: selectedKey == s.key ? theme.accent : theme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.label, style: CroplooText.bodyStrong),
                          const SizedBox(height: 2),
                          Text(s.formula,
                              style: CroplooText.label.copyWith(fontSize: 9, color: theme.textMuted)),
                          const SizedBox(height: 10),
                          Text('${s.latest} ${s.unit}', style: CroplooText.dataLarge),
                          const SizedBox(height: 4),
                          Text(s.signal, style: CroplooText.dataSmall),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            if (selected != null && selected.history.length > 1) ...[
              const SizedBox(height: 20),
              CroplooCard(
                child: SizedBox(
                  height: 240,
                  child: _SpreadChart(series: selected),
                ),
              ),
            ],
            if (terminal.omitted.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final note in terminal.omitted)
                Text(note, style: CroplooText.dataSmall.copyWith(color: theme.textMuted)),
            ],
          ],
        );
      },
    );
  }
}

class _SpreadChart extends StatelessWidget {
  final SpreadSeries series;

  const _SpreadChart({required this.series});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final history = series.history;
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => FlLine(color: theme.border, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, meta) => Text(v.toStringAsFixed(1),
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
          labels: [series.label],
          colors: [theme.accent],
          dates: [for (final p in history) p.date],
          valueDecimals: 2,
          valueSuffix: ' ${series.unit}',
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (final (i, p) in history.indexed) FlSpot(i.toDouble(), p.value)
            ],
            isCurved: false,
            color: theme.accent,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}
