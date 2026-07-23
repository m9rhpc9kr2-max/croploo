import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_colors.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/providers.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/chart_tooltip.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/controls.dart';

final _corridorProvider = StateProvider<String>((ref) => 'Midwest–Gulf');
final _railStateProvider = StateProvider<String>((ref) => 'IL');

class FreightScreen extends ConsumerWidget {
  const FreightScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final rates = ref.watch(freightRatesProvider);
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
            Text('FREIGHT', style: CroplooText.h2),
            const SizedBox(height: 24),
            const SectionHeader(title: 'Current Corridor Rates'),
            const SizedBox(height: 12),
            rates.when(
              loading: () =>
                  const SizedBox(height: 120, child: CroplooLoader()),
              error: (e, _) => Text('Error', style: CroplooText.body),
              data: (list) => Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final r in list) _CorridorCard(rate: r),
                ],
              ),
            ),
            const SizedBox(height: 40),
            Row(
              children: [
                const SectionHeader(title: 'Freight–Basis Correlation'),
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: theme.accent.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Text('DESK',
                      style: CroplooText.label
                          .copyWith(fontSize: 9, color: theme.accent)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const _CorrelationSection(),
            const SizedBox(height: 40),
            const SectionHeader(title: 'Grain Rail Car Loadings'),
            const SizedBox(height: 12),
            const _RailCarLoadingsSection(),
            const SizedBox(height: 40),
            const SectionHeader(title: 'Mississippi River Levels'),
            const SizedBox(height: 12),
            const _RiverGaugesSection(),
          ],
        ),
      ),
    );
  }
}

class _CorridorCard extends ConsumerWidget {
  final FreightRate rate;

  const _CorridorCard({required this.rate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final selected = ref.watch(_corridorProvider) == rate.corridor;
    final modeIcon = switch (rate.mode) {
      'truck' => PhosphorIconsRegular.truck,
      'barge' => PhosphorIconsRegular.boat,
      _ => PhosphorIconsRegular.trainSimple,
    };
    return InkWell(
      onTap: () =>
          ref.read(_corridorProvider.notifier).state = rate.corridor,
      borderRadius: BorderRadius.zero,
      child: CroplooCard(
        padding: const EdgeInsets.all(20),
        borderColor: selected ? theme.accent : null,
        child: SizedBox(
          width: 220,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(modeIcon,
                      size: 16, color: theme.textSecondary),
                  const SizedBox(width: 8),
                  Text(rate.mode.toUpperCase(),
                      style: CroplooText.label.copyWith(fontSize: 10)),
                  const Spacer(),
                  ChangeChip(value: rate.weekChangePct, formatter: Fmt.pct),
                ],
              ),
              const SizedBox(height: 12),
              Text(rate.corridor, style: CroplooText.bodyStrong),
              const SizedBox(height: 8),
              Text('${Fmt.number(rate.rateValue)} ${rate.unit}',
                  style: CroplooText.dataLarge),
            ],
          ),
        ),
      ),
    );
  }
}

class _CorrelationSection extends ConsumerWidget {
  const _CorrelationSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final corridor = ref.watch(_corridorProvider);
    final points = ref.watch(freightCorrelationProvider(corridor));
    final user = ref.watch(currentUserProvider).valueOrNull;
    final hasDesk = user != null && user.tier.atLeast(SubscriptionTier.desk);

    return TierGate(
      requiredTier: 'DESK',
      locked: !hasDesk,
      child: points.when(
        loading: () => const SizedBox(height: 320, child: CroplooLoader()),
        error: (e, _) => Text('Error', style: CroplooText.body),
        data: (data) {
          final corr = _pearson(data);
          return CroplooCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(corridor, style: CroplooText.h3),
                    const Spacer(),
                    DataLabel(
                        label: 'Correlation',
                        value: corr.toStringAsFixed(2),
                        valueColor: corr < 0
                            ? theme.negative
                            : theme.positive),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(height: 280, child: _DualLineChart(points: data)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                        width: 16,
                        height: 2,
                        color: theme.textSecondary),
                    const SizedBox(width: 6),
                    Text('FREIGHT ¢/BU',
                        style: CroplooText.label.copyWith(fontSize: 9)),
                    const SizedBox(width: 20),
                    Container(
                        width: 16, height: 2, color: theme.textPrimary),
                    const SizedBox(width: 6),
                    Text('BASIS ¢/BU',
                        style: CroplooText.label.copyWith(fontSize: 9)),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  double _pearson(List<FreightPoint> data) {
    if (data.length < 2) return 0;
    final n = data.length;
    final xs = data.map((p) => p.freight).toList();
    final ys = data.map((p) => p.basis).toList();
    final mx = xs.reduce((a, b) => a + b) / n;
    final my = ys.reduce((a, b) => a + b) / n;
    var cov = 0.0, vx = 0.0, vy = 0.0;
    for (var i = 0; i < n; i++) {
      cov += (xs[i] - mx) * (ys[i] - my);
      vx += (xs[i] - mx) * (xs[i] - mx);
      vy += (ys[i] - my) * (ys[i] - my);
    }
    if (vx == 0 || vy == 0) return 0;
    return cov / math.sqrt(vx * vy);
  }
}

class _DualLineChart extends StatelessWidget {
  final List<FreightPoint> points;

  const _DualLineChart({required this.points});

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
          labels: const ['Freight', 'Basis'],
          colors: [theme.textSecondary, theme.textPrimary],
          dates: [for (final p in points) p.date],
          valueDecimals: 2,
          valueSuffix: '¢',
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (final (i, p) in points.indexed)
                FlSpot(i.toDouble(), p.freight)
            ],
            color: theme.textSecondary,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: [
              for (final (i, p) in points.indexed)
                FlSpot(i.toDouble(), p.basis)
            ],
            color: theme.textPrimary,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}

class _RailCarLoadingsSection extends ConsumerWidget {
  const _RailCarLoadingsSection();

  static const _states = [
    ('IL', 'Illinois'), ('IA', 'Iowa'), ('MN', 'Minnesota'),
    ('IN', 'Indiana'), ('OH', 'Ohio'), ('KS', 'Kansas'),
    ('NE', 'Nebraska'), ('ND', 'North Dakota'), ('SD', 'South Dakota'),
    ('TX', 'Texas'), ('WA', 'Washington'), ('LA', 'Louisiana'),
    ('MO', 'Missouri'), ('AR', 'Arkansas'), ('MS', 'Mississippi'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_railStateProvider);
    final data = ref.watch(railCarLoadingsProvider(state));
    final user = ref.watch(currentUserProvider).valueOrNull;
    final hasPro = user != null && user.tier.atLeast(SubscriptionTier.pro);

    return TierGate(
      requiredTier: 'PRO',
      locked: !hasPro,
      child: CroplooCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Weekly grain cars loaded, by state',
                    style: CroplooText.h3),
                const Spacer(),
                CroplooDropdown<String>(
                  value: state,
                  items: [
                    for (final s in _states)
                      CroplooDropdownItem(value: s.$1, label: s.$2),
                  ],
                  onChanged: (v) =>
                      ref.read(_railStateProvider.notifier).state = v,
                ),
              ],
            ),
            const SizedBox(height: 24),
            data.when(
              loading: () => const SizedBox(height: 240, child: CroplooLoader()),
              error: (e, _) => const SizedBox(
                  height: 240,
                  child: Center(child: Text('No data for this state yet'))),
              data: (loadings) {
                if (loadings.history.isEmpty) {
                  return const SizedBox(
                      height: 240,
                      child: Center(
                          child: Text('No rail car data reported for this state')));
                }
                return SizedBox(
                    height: 240, child: _RailCarBarChart(weeks: loadings.history));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RailCarBarChart extends StatelessWidget {
  final List<RailCarLoadingWeek> weeks;

  const _RailCarBarChart({required this.weeks});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final maxY = weeks.map((w) => w.totalCars).fold<int>(0, math.max) * 1.15;
    return BarChart(
      BarChartData(
        maxY: maxY <= 0 ? 10 : maxY,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) =>
              FlLine(color: theme.bgBorder, strokeWidth: 1),
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
              interval: (weeks.length / 4).floorToDouble().clamp(1, 999),
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= weeks.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(Fmt.dateShort(weeks[i].week),
                      style: CroplooText.dataSmall.copyWith(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => theme.bgElevated,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final w = weeks[group.x.toInt()];
              return BarTooltipItem(
                '${Fmt.dateShort(w.week)}\n${w.totalCars} cars',
                CroplooText.dataSmall.copyWith(color: theme.textPrimary),
              );
            },
          ),
        ),
        barGroups: [
          for (final (i, w) in weeks.indexed)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: w.totalCars.toDouble(),
                color: theme.accent,
                width: (600 / weeks.length).clamp(3, 14),
                borderRadius: BorderRadius.zero,
              ),
            ]),
        ],
      ),
    );
  }
}

class _RiverGaugesSection extends ConsumerWidget {
  const _RiverGaugesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gauges = ref.watch(riverGaugesProvider);
    final user = ref.watch(currentUserProvider).valueOrNull;
    final hasPro = user != null && user.tier.atLeast(SubscriptionTier.pro);

    return TierGate(
      requiredTier: 'PRO',
      locked: !hasPro,
      child: gauges.when(
        loading: () => const SizedBox(height: 180, child: CroplooLoader()),
        error: (e, _) => Text('Error', style: CroplooText.body),
        data: (stations) => Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [for (final s in stations) _RiverGaugeCard(station: s)],
        ),
      ),
    );
  }
}

class _RiverGaugeCard extends StatelessWidget {
  final RiverGaugeStation station;

  const _RiverGaugeCard({required this.station});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final history = station.history;
    final latestStage = station.latestStageFt;
    // Simple week-over-week trend for a quick rising/falling read, not a
    // forecast — the real flood-stage forecast lives upstream at NOAA.
    final weekAgoIdx = history.length > 7 ? history.length - 8 : 0;
    final trend = history.isNotEmpty
        ? latestStage! - history[weekAgoIdx].stageFt
        : 0.0;

    return CroplooCard(
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        width: 220,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(PhosphorIconsRegular.waves,
                    size: 16, color: theme.textSecondary),
                const SizedBox(width: 8),
                Text(station.state, style: CroplooText.label.copyWith(fontSize: 10)),
                const Spacer(),
                if (history.isNotEmpty)
                  ChangeChip(value: trend, formatter: (v) => v.toStringAsFixed(1)),
              ],
            ),
            const SizedBox(height: 12),
            Text(station.name, style: CroplooText.bodyStrong),
            const SizedBox(height: 8),
            Text(
              latestStage != null ? '${latestStage.toStringAsFixed(1)} ft' : '—',
              style: CroplooText.dataLarge,
            ),
            if (history.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('${history.last.flowKcfs.toStringAsFixed(0)} kcfs flow',
                  style: CroplooText.dataSmall.copyWith(color: theme.textMuted)),
            ],
            if (history.length > 2) ...[
              const SizedBox(height: 12),
              SizedBox(height: 40, child: _MiniStageSpark(history: history)),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniStageSpark extends StatelessWidget {
  final List<RiverGaugeReading> history;

  const _MiniStageSpark({required this.history});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (final (i, r) in history.indexed)
                FlSpot(i.toDouble(), r.stageFt)
            ],
            color: theme.accent,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
            isCurved: true,
          ),
        ],
      ),
    );
  }
}
