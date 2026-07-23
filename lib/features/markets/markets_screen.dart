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

/// Markets: Forex majors, crypto, the Treasury yield curve, and the
/// cross-sector performance heatmap — a Desk-tier broad-markets view
/// that sits alongside (not inside) the grain-specific Commodities
/// section.
class MarketsScreen extends ConsumerWidget {
  const MarketsScreen({super.key});

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
            Text('MARKETS', style: CroplooText.h2),
            const SizedBox(height: 24),
            const SectionHeader(title: 'Stocks'),
            const SizedBox(height: 12),
            const _StocksPanel(),
            const SizedBox(height: 40),
            const SectionHeader(title: 'Forex Terminal'),
            const SizedBox(height: 12),
            const _ForexPanel(),
            const SizedBox(height: 40),
            const SectionHeader(title: 'Crypto'),
            const SizedBox(height: 12),
            const _CryptoPanel(),
            const SizedBox(height: 40),
            const SectionHeader(title: 'Treasury Yield Curve'),
            const SizedBox(height: 12),
            const _YieldCurvePanel(),
            const SizedBox(height: 40),
            const SectionHeader(title: 'Sector Heatmap'),
            const SizedBox(height: 12),
            const _SectorHeatmapPanel(),
          ],
        ),
      ),
    );
  }
}

// ── Stocks ───────────────────────────────────────────────────────

final _stockQueryProvider = StateProvider<String>((ref) => '');

class _StocksPanel extends ConsumerStatefulWidget {
  const _StocksPanel();

  @override
  ConsumerState<_StocksPanel> createState() => _StocksPanelState();
}

class _StocksPanelState extends ConsumerState<_StocksPanel> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final query = ref.watch(_stockQueryProvider);
    final selected = ref.watch(selectedStockSymbolProvider);

    return CroplooCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CroplooTextField(
            controller: _controller,
            hintText: 'Search stocks (e.g. ADM, DE, BG)...',
            prefixIcon: PhosphorIconsRegular.magnifyingGlass,
            onChanged: (v) => ref.read(_stockQueryProvider.notifier).state = v,
          ),
          if (query.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _StockSearchResults(query: query),
          ],
          if (selected != null) ...[
            const SizedBox(height: 20),
            Divider(color: theme.border),
            const SizedBox(height: 20),
            _StockDetail(symbol: selected),
          ],
        ],
      ),
    );
  }
}

class _StockSearchResults extends ConsumerWidget {
  final String query;

  const _StockSearchResults({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final results = ref.watch(stockSearchProvider(query));
    return results.when(
      loading: () => const SizedBox(height: 40, child: CroplooLoader()),
      error: (e, _) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(
          children: [
            for (final r in list.take(6))
              InkWell(
                onTap: () {
                  ref.read(selectedStockSymbolProvider.notifier).state = r.symbol;
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: theme.border))),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 70,
                          child: Text(r.symbol, style: CroplooText.bodyStrong)),
                      Expanded(
                          child: Text(r.name,
                              style: CroplooText.body.copyWith(fontSize: 12),
                              overflow: TextOverflow.ellipsis)),
                      Text(r.exchange,
                          style: CroplooText.label
                              .copyWith(fontSize: 9, color: theme.textMuted)),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Time ranges for the stock chart. The backend now returns up to 5y of
/// daily closes (see backend/src/stocks.js), so every option here has real
/// data behind it rather than re-slicing the same few months. There's no
/// intraday ("1D") option since the history is daily-close only, same
/// constraint noted on BasisTimeRange in basis_chart.dart.
enum StockTimeRange { all, oneYear, sixMonths, threeMonths, oneMonth, oneWeek }

extension on StockTimeRange {
  String get label => switch (this) {
        StockTimeRange.all => 'All',
        StockTimeRange.oneYear => '1Y',
        StockTimeRange.sixMonths => '6M',
        StockTimeRange.threeMonths => '3M',
        StockTimeRange.oneMonth => '1M',
        StockTimeRange.oneWeek => '1W',
      };
}

class StockChartTimeRangeSelector extends StatelessWidget {
  final StockTimeRange value;
  final ValueChanged<StockTimeRange> onChanged;

  const StockChartTimeRangeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CroplooSegmentedControl<StockTimeRange>(
      values: StockTimeRange.values,
      selected: value,
      onChanged: onChanged,
      labelBuilder: (r) => r.label,
    );
  }
}

class _StockDetail extends ConsumerStatefulWidget {
  final String symbol;

  const _StockDetail({required this.symbol});

  @override
  ConsumerState<_StockDetail> createState() => _StockDetailState();
}

class _StockDetailState extends ConsumerState<_StockDetail> {
  StockTimeRange _range = StockTimeRange.threeMonths;

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final quote = ref.watch(stockQuoteProvider(widget.symbol));
    return quote.when(
      loading: () => const SizedBox(height: 160, child: CroplooLoader()),
      error: (e, _) => Text('Error loading ${widget.symbol}', style: CroplooText.body),
      data: (q) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(q.symbol, style: CroplooText.h3),
              const SizedBox(width: 12),
              Text('\$${Fmt.number(q.price)}', style: CroplooText.dataXL),
              const SizedBox(width: 12),
              ChangeChip(value: q.changePct, formatter: Fmt.pct),
            ],
          ),
          const SizedBox(height: 4),
          Text(q.name, style: CroplooText.body.copyWith(color: theme.textMuted)),
          const SizedBox(height: 16),
          Row(
            children: [
              if (q.fiftyTwoWeekHigh != null)
                Expanded(
                    child: DataLabel(
                        label: '52W High', value: '\$${Fmt.number(q.fiftyTwoWeekHigh!)}')),
              if (q.fiftyTwoWeekLow != null)
                Expanded(
                    child: DataLabel(
                        label: '52W Low', value: '\$${Fmt.number(q.fiftyTwoWeekLow!)}')),
            ],
          ),
          if (q.history.length > 1) ...[
            const SizedBox(height: 20),
            StockChartTimeRangeSelector(
              value: _range,
              onChanged: (r) => setState(() => _range = r),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: _StockChart(history: q.history, timeRange: _range),
            ),
          ],
        ],
      ),
    );
  }
}

class _StockChart extends StatelessWidget {
  final List<StockPoint> history;
  final StockTimeRange timeRange;

  const _StockChart({required this.history, required this.timeRange});

  List<StockPoint> get _filteredPoints {
    if (history.isEmpty) return [];
    final now = history.last.date;
    final cutoff = switch (timeRange) {
      StockTimeRange.all => DateTime(1900),
      StockTimeRange.oneYear => now.subtract(const Duration(days: 365)),
      StockTimeRange.sixMonths => now.subtract(const Duration(days: 182)),
      StockTimeRange.threeMonths => now.subtract(const Duration(days: 91)),
      StockTimeRange.oneMonth => now.subtract(const Duration(days: 30)),
      StockTimeRange.oneWeek => now.subtract(const Duration(days: 7)),
    };
    return history.where((p) => p.date.isAfter(cutoff)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final filtered = _filteredPoints;
    if (filtered.isEmpty) return const SizedBox.shrink();
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
              reservedSize: 48,
              getTitlesWidget: (v, meta) => Text(v.toStringAsFixed(0),
                  style: CroplooText.dataSmall.copyWith(fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (filtered.length / 4).floorToDouble().clamp(1, 999),
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= filtered.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(Fmt.dateShort(filtered[i].date),
                      style: CroplooText.dataSmall.copyWith(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        lineTouchData: croplooLineTooltip(
          theme,
          labels: const ['Close'],
          colors: [theme.accent],
          dates: [for (final p in filtered) p.date],
          valueDecimals: 2,
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (final (i, p) in filtered.indexed) FlSpot(i.toDouble(), p.close)
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

// ── Forex ────────────────────────────────────────────────────────

class _ForexPanel extends ConsumerWidget {
  const _ForexPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(forexProvider);
    return snapshot.when(
      loading: () => const SizedBox(height: 240, child: CroplooLoader()),
      error: (e, _) => Text('Error', style: CroplooText.body),
      data: (data) => CroplooCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final p in data.pairs) _ForexPairCard(pair: p),
              ],
            ),
            if (data.history.isNotEmpty) ...[
              const SizedBox(height: 24),
              SizedBox(height: 200, child: _ForexChart(history: data.history)),
              const SizedBox(height: 8),
              Text('EUR/USD — 180D', style: CroplooText.label.copyWith(fontSize: 9)),
            ],
            if (data.note.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(data.note, style: CroplooText.dataSmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _ForexPairCard extends StatelessWidget {
  final ForexPair pair;

  const _ForexPairCard({required this.pair});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${pair.pair.substring(0, 3)}/${pair.pair.substring(3)}',
            style: CroplooText.label.copyWith(fontSize: 10),
          ),
          const SizedBox(height: 6),
          Text(pair.rate.toStringAsFixed(4), style: CroplooText.dataLarge),
          const SizedBox(height: 4),
          ChangeChip(value: pair.change1dPct, formatter: Fmt.pct),
        ],
      ),
    );
  }
}

class _ForexChart extends StatelessWidget {
  final List<ForexRatePoint> history;

  const _ForexChart({required this.history});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
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
              reservedSize: 48,
              getTitlesWidget: (v, meta) => Text(v.toStringAsFixed(3),
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
          labels: const ['EUR/USD'],
          colors: [theme.textPrimary],
          dates: [for (final p in history) p.date],
          valueDecimals: 4,
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (final (i, p) in history.indexed) FlSpot(i.toDouble(), p.rate)
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

// ── Crypto ───────────────────────────────────────────────────────

class _CryptoPanel extends ConsumerWidget {
  const _CryptoPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(cryptoProvider);
    return snapshot.when(
      loading: () => const SizedBox(height: 200, child: CroplooLoader()),
      error: (e, _) => Text('Error', style: CroplooText.body),
      data: (data) => Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final c in data.coins) _CryptoCoinCard(coin: c),
        ],
      ),
    );
  }
}

class _CryptoCoinCard extends StatelessWidget {
  final CryptoCoin coin;

  const _CryptoCoinCard({required this.coin});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return CroplooCard(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(coin.symbol, style: CroplooText.bodyStrong),
                const Spacer(),
                ChangeChip(value: coin.change24hPct, formatter: Fmt.pct),
              ],
            ),
            const SizedBox(height: 2),
            Text(coin.name,
                style: CroplooText.label.copyWith(fontSize: 9),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Text('\$${Fmt.number(coin.price)}', style: CroplooText.dataLarge),
            const SizedBox(height: 8),
            if (coin.sparkline7d.length > 1)
              SizedBox(
                height: 32,
                child: LineChart(
                  LineChartData(
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: const FlTitlesData(show: false),
                    lineTouchData: const LineTouchData(enabled: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: [
                          for (final (i, v) in coin.sparkline7d.indexed)
                            FlSpot(i.toDouble(), v)
                        ],
                        isCurved: false,
                        color: theme.changeColor(coin.change24hPct),
                        barWidth: 1.2,
                        dotData: const FlDotData(show: false),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Yield Curve ──────────────────────────────────────────────────

class _YieldCurvePanel extends ConsumerWidget {
  const _YieldCurvePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final snapshot = ref.watch(yieldCurveProvider);
    return snapshot.when(
      loading: () => const SizedBox(height: 280, child: CroplooLoader()),
      error: (e, _) => Text('Error', style: CroplooText.body),
      data: (data) => CroplooCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DataLabel(
                  label: '2s/10s Spread',
                  value: '${data.spread2s10s >= 0 ? '+' : ''}${data.spread2s10s.toStringAsFixed(2)}',
                  valueColor: data.spread2s10s < 0 ? theme.negative : theme.positive,
                ),
                const SizedBox(width: 24),
                if (data.inverted)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.negative.withValues(alpha: 0.10),
                      border: Border.all(color: theme.settings.useBorders ? theme.negative.withValues(alpha: 0.45) : Colors.transparent),
                    ),
                    child: Text('INVERTED',
                        style: CroplooText.label.copyWith(color: theme.negative, fontSize: 10)),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(height: 240, child: _YieldCurveChart(data: data)),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(width: 16, height: 2, color: theme.textPrimary),
                const SizedBox(width: 6),
                Text('TODAY', style: CroplooText.label.copyWith(fontSize: 9)),
                const SizedBox(width: 20),
                Container(width: 16, height: 2, color: theme.textSecondary),
                const SizedBox(width: 6),
                Text('1Y AGO', style: CroplooText.label.copyWith(fontSize: 9)),
                const SizedBox(width: 20),
                Container(width: 16, height: 2, color: theme.textMuted),
                const SizedBox(width: 6),
                Text('2Y AGO', style: CroplooText.label.copyWith(fontSize: 9)),
              ],
            ),
            if (data.note.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(data.note, style: CroplooText.dataSmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _YieldCurveChart extends StatelessWidget {
  final YieldCurveSnapshot data;

  const _YieldCurveChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final tenors = data.current.map((p) => p.tenor).toList();

    List<FlSpot> spotsFor(List<YieldPoint> points) => [
          for (final (i, tenor) in tenors.indexed)
            if (points.any((p) => p.tenor == tenor))
              FlSpot(i.toDouble(), points.firstWhere((p) => p.tenor == tenor).yieldPct)
        ];

    // fl_chart computes chart-wide min/max extents across every bar's
    // spots — a bar with zero spots (e.g. "2Y ago" before enough FRED
    // history has been cached) crashes that calculation. Only include
    // series that actually have data, and keep the tooltip labels/colors
    // arrays in sync since they're indexed by the same barIndex.
    final series = [
      ('Today', theme.textPrimary, 2.0, data.current),
      ('1Y ago', theme.textSecondary, 1.5, data.oneYearAgo),
      ('2Y ago', theme.textMuted, 1.5, data.twoYearsAgo),
    ].where((s) => s.$4.isNotEmpty).toList();

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
              reservedSize: 40,
              getTitlesWidget: (v, meta) => Text('${v.toStringAsFixed(1)}%',
                  style: CroplooText.dataSmall.copyWith(fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= tenors.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(tenors[i], style: CroplooText.dataSmall.copyWith(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        lineTouchData: croplooLineTooltip(
          theme,
          labels: [for (final s in series) s.$1],
          colors: [for (final s in series) s.$2],
          valueDecimals: 2,
          valueSuffix: '%',
        ),
        lineBarsData: [
          for (final s in series)
            LineChartBarData(
              spots: spotsFor(s.$4),
              isCurved: false,
              color: s.$2,
              barWidth: s.$3,
              dotData: const FlDotData(show: false),
            ),
        ],
      ),
    );
  }
}

// ── Sector Heatmap ───────────────────────────────────────────────

class _SectorHeatmapPanel extends ConsumerWidget {
  const _SectorHeatmapPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(sectorHeatmapProvider);
    return snapshot.when(
      loading: () => const SizedBox(height: 160, child: CroplooLoader()),
      error: (e, _) => Text('Error', style: CroplooText.body),
      data: (data) => Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final s in data.sectors) _SectorTile(sector: s),
        ],
      ),
    );
  }
}

class _SectorTile extends StatelessWidget {
  final SectorPerformance sector;

  const _SectorTile({required this.sector});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final color = theme.changeColor(sector.changePct);
    return Container(
      width: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: theme.settings.useBorders ? color.withValues(alpha: 0.45) : Colors.transparent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(sector.label.toUpperCase(),
              style: CroplooText.label.copyWith(fontSize: 9)),
          const SizedBox(height: 2),
          Text(sector.symbol, style: CroplooText.label.copyWith(fontSize: 9, color: theme.textMuted)),
          const SizedBox(height: 10),
          Text('${sector.changePct >= 0 ? '+' : ''}${sector.changePct.toStringAsFixed(2)}%',
              style: CroplooText.dataLarge.copyWith(color: color)),
        ],
      ),
    );
  }
}
