import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme_colors.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/mock_data.dart';
import '../../data/providers.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/controls.dart';
import 'basis_chart.dart';

/// Single elevator + commodity detail: big basis number, chart,
/// history table, CullyAI insight.
class BasisDetailScreen extends ConsumerWidget {
  final int elevatorId;
  final String commodity;

  const BasisDetailScreen(
      {super.key, required this.elevatorId, required this.commodity});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(basisOverviewProvider);
    return overview.when(
      loading: () => const CroplooLoader(),
      error: (e, _) =>
          Center(child: Text('Error loading data', style: CroplooText.body)),
      data: (all) {
        final snapshot = all
            .where((s) =>
                s.elevator.id == elevatorId &&
                s.commodity.symbol == commodity)
            .firstOrNull;
        if (snapshot == null) {
          return const EmptyState(
              icon: PhosphorIconsRegular.mapPinLine,
              message: 'Location not found.');
        }
        return _DetailBody(snapshot: snapshot);
      },
    );
  }
}

class _DetailBody extends ConsumerWidget {
  final BasisSnapshot snapshot;

  const _DetailBody({required this.snapshot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final s = snapshot;
    final devColor = theme.changeColor(s.deviationFromAvg);
    return DefaultTabController(
      length: 3,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Back + title
            Row(
              children: [
                CroplooIconButton(
                  icon: PhosphorIconsRegular.arrowLeft,
                  size: 36,
                  onPressed: () => context.go('/basis'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      '${s.elevator.name}, ${s.elevator.state} — ${s.commodity.name} Basis',
                      style: CroplooText.h2),
                ),
                CroplooButton(
                  label: 'Embed Widget',
                  variant: CroplooButtonVariant.ghost,
                  expanded: false,
                  onPressed: () => _showEmbedDialog(context, ref, s),
                ),
              ],
            ),
            const SizedBox(height: 32),
            // Hero number
            Center(
              child: Column(
                children: [
                  Text(Fmt.basis(s.basisValue), style: CroplooText.dataXL),
                  const SizedBox(height: 8),
                  Text(
                    '${Fmt.cents(s.deviationFromAvg)} ${s.deviationFromAvg >= 0 ? 'above' : 'below'} 5-year average',
                    style: CroplooText.data.copyWith(color: devColor),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DataLabel(
                          label: 'Cash Bid', value: Fmt.price(s.cashPrice)),
                      const SizedBox(width: 40),
                      DataLabel(
                          label: 'Futures', value: Fmt.price(s.futuresPrice)),
                      const SizedBox(width: 40),
                      DataLabel(
                          label: '5yr Avg',
                          value: '${Fmt.number(s.avg5yr)}¢'),
                      const SizedBox(width: 40),
                      DataLabel(
                          label: 'Deviation',
                          value: Fmt.pct(s.deviationPct),
                          valueColor: devColor),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: 'CHART'),
                Tab(text: 'HISTORY'),
                Tab(text: 'CULLYAI INSIGHT'),
              ],
            ),
            SizedBox(
              height: 420,
              child: TabBarView(
                children: [
                  _ChartTab(snapshot: s),
                  _HistoryTab(snapshot: s),
                  _InsightTab(snapshot: s),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartTab extends ConsumerStatefulWidget {
  final BasisSnapshot snapshot;

  const _ChartTab({required this.snapshot});

  @override
  ConsumerState<_ChartTab> createState() => _ChartTabState();
}

class _ChartTabState extends ConsumerState<_ChartTab> {
  BasisTimeRange _range = BasisTimeRange.all;

  @override
  Widget build(BuildContext context) {
    final series = ref.watch(basisTimeseriesProvider(
        (widget.snapshot.elevator.id, widget.snapshot.commodity.symbol)));
    return series.when(
      loading: () => const CroplooLoader(),
      error: (e, _) => Text('Error', style: CroplooText.body),
      data: (points) => Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                BasisChartLegend(points: points),
                const Spacer(),
                BasisChartTimeRangeSelector(
                  value: _range,
                  onChanged: (r) => setState(() => _range = r),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(child: BasisChart(points: points, timeRange: _range)),
          ],
        ),
      ),
    );
  }
}

class _HistoryTab extends ConsumerWidget {
  final BasisSnapshot snapshot;

  const _HistoryTab({required this.snapshot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final series = ref.watch(basisTimeseriesProvider(
        (snapshot.elevator.id, snapshot.commodity.symbol)));
    return series.when(
      loading: () => const CroplooLoader(),
      error: (e, _) => Text('Error', style: CroplooText.body),
      data: (points) {
        final rows = points.reversed.take(30).toList();
        return ListView(
          padding: const EdgeInsets.only(top: 16),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(child: Text('DATE', style: CroplooText.label.copyWith(fontSize: 10))),
                  SizedBox(width: 100, child: Text('CASH BID', style: CroplooText.label.copyWith(fontSize: 10), textAlign: TextAlign.right)),
                  SizedBox(width: 100, child: Text('FUTURES', style: CroplooText.label.copyWith(fontSize: 10), textAlign: TextAlign.right)),
                  SizedBox(width: 100, child: Text('BASIS', style: CroplooText.label.copyWith(fontSize: 10), textAlign: TextAlign.right)),
                  SizedBox(width: 100, child: Text('VS AVG', style: CroplooText.label.copyWith(fontSize: 10), textAlign: TextAlign.right)),
                ],
              ),
            ),
            const Divider(),
            for (final p in rows)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(color: theme.border))),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(Fmt.date(p.date),
                            style: CroplooText.dataSmall)),
                    SizedBox(
                        width: 100,
                        child: Text(
                            Fmt.price(snapshot.futuresPrice + p.basis),
                            style: CroplooText.data.copyWith(fontSize: 12),
                            textAlign: TextAlign.right)),
                    SizedBox(
                        width: 100,
                        child: Text(Fmt.price(snapshot.futuresPrice),
                            style: CroplooText.data.copyWith(fontSize: 12),
                            textAlign: TextAlign.right)),
                    SizedBox(
                        width: 100,
                        child: Text('${Fmt.number(p.basis)}¢',
                            style: CroplooText.data.copyWith(fontSize: 12),
                            textAlign: TextAlign.right)),
                    SizedBox(
                        width: 100,
                        child: Text(Fmt.cents(p.deviation),
                            style: CroplooText.data.copyWith(
                                fontSize: 12,
                                color:
                                    theme.changeColor(p.deviation)),
                            textAlign: TextAlign.right)),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _InsightTab extends StatefulWidget {
  final BasisSnapshot snapshot;

  const _InsightTab({required this.snapshot});

  @override
  State<_InsightTab> createState() => _InsightTabState();
}

class _InsightTabState extends State<_InsightTab> {
  bool _generated = false;
  bool _loading = false;

  Future<void> _generate() async {
    setState(() => _loading = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) {
      setState(() {
        _loading = false;
        _generated = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final s = widget.snapshot;
    if (_loading) return const CroplooLoader();
    if (!_generated) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(PhosphorIconsRegular.sparkle,
                color: theme.accent, size: 32),
            const SizedBox(height: 16),
            Text('Generate a CullyAI insight for this location.',
                style: CroplooText.body),
            const SizedBox(height: 16),
            CroplooButton(
              label: 'Generate Insight',
              onPressed: _generate,
            ),
          ],
        ),
      );
    }
    final direction = s.deviationFromAvg < 0 ? 'below' : 'above';
    final insight =
        '${MockData.cullyReply('basis')}\n\nFor ${s.elevator.name}: the current ${s.commodity.name.toLowerCase()} basis of ${Fmt.basis(s.basisValue)} sits ${Fmt.number(s.deviationFromAvg.abs())}¢ $direction the 5-year seasonal average. Based on historical patterns, a basis this far $direction the average at this location in this part of the season typically resolves within 2–3 weeks — in roughly 74% of comparable cases the gap closed at least halfway.';
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 24),
      child: CroplooCard(
        borderColor: theme.accent.withValues(alpha: 0.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(PhosphorIconsRegular.sparkle,
                    color: theme.accent, size: 14),
                const SizedBox(width: 8),
                Text('CULLYAI INSIGHT', style: CroplooText.label),
              ],
            ),
            const SizedBox(height: 16),
            Text(insight,
                style:
                    CroplooText.body.copyWith(color: theme.textPrimary)),
          ],
        ),
      ),
    );
  }
}

/// Free, embeddable widget: elevators can drop this on their own site to
/// show a live basis number — free advertising for Croploo, since anyone
/// who sees it asks where the data comes from. Backed by the public,
/// auth-less /widget/basis HTML route (see backend/src/routes/widget.js).
void _showEmbedDialog(BuildContext context, WidgetRef ref, BasisSnapshot s) {
  final embedUrl =
      ref.read(repositoryProvider).basisWidgetEmbedUrl(s.elevator.state, s.commodity.symbol);
  final snippet =
      '<iframe src="$embedUrl" width="280" height="140" frameborder="0" loading="lazy"></iframe>';

  showDialog(
    context: context,
    builder: (context) {
      final theme = CroplooTheme.of(context);
      return Dialog(
        backgroundColor: theme.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('EMBED THIS WIDGET', style: CroplooText.h3),
                    const Spacer(),
                    CroplooIconButton(
                      icon: PhosphorIconsRegular.x,
                      size: 28,
                      iconColor: theme.textSecondary,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Free for elevators to show a live basis number on their own '
                  'website. Updates automatically — no login required.',
                  style: CroplooText.body.copyWith(fontSize: 12, color: theme.textSecondary),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.bgElevated,
                    border: Border.all(color: theme.border),
                  ),
                  child: SelectableText(snippet, style: CroplooText.dataSmall),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    CroplooButton(
                      label: 'Copy Embed Code',
                      expanded: false,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: snippet));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Embed code copied.')),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
