import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/theme_colors.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/providers.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/controls.dart';

/// Historical database of every WASDE-equivalent surprise this app has
/// itself observed, with the real futures-price reaction at 24h/48h/1
/// week — and, when a new one comes in, which past surprise it most
/// resembles. There's no free 2015-present futures tick history, so
/// this accumulates real data going forward rather than backfilling.
class _WasdeSurpriseTracker extends ConsumerWidget {
  final String commodity;

  const _WasdeSurpriseTracker({required this.commodity});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final report = ref.watch(wasdeSurprisesProvider(commodity));
    return report.when(
      loading: () => const SizedBox(height: 80, child: CroplooLoader()),
      error: (e, _) => Text('Error loading surprise history', style: CroplooText.body),
      data: (data) {
        if (data.history.isEmpty) {
          return const EmptyState(
              icon: PhosphorIconsRegular.clockCounterClockwise,
              message: 'No surprises recorded yet — this builds up as new reports land.');
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (data.mostSimilar != null) _SimilarSurpriseCard(match: data.mostSimilar!),
            if (data.mostSimilar != null) const SizedBox(height: 16),
            CroplooCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                            flex: 2,
                            child: Text('RELEASE',
                                style: CroplooText.label.copyWith(fontSize: 10))),
                        Expanded(
                            child: Text('SURPRISE',
                                style: CroplooText.label.copyWith(fontSize: 10),
                                textAlign: TextAlign.right)),
                        Expanded(
                            child: Text('24H',
                                style: CroplooText.label.copyWith(fontSize: 10),
                                textAlign: TextAlign.right)),
                        Expanded(
                            child: Text('48H',
                                style: CroplooText.label.copyWith(fontSize: 10),
                                textAlign: TextAlign.right)),
                        Expanded(
                            child: Text('1 WEEK',
                                style: CroplooText.label.copyWith(fontSize: 10),
                                textAlign: TextAlign.right)),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: theme.bgBorder),
                  for (final s in data.history)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                              flex: 2,
                              child: Text(Fmt.dateShort(s.releaseDate),
                                  style: CroplooText.data.copyWith(fontSize: 12))),
                          Expanded(
                              child: Text(Fmt.pct(s.surprisePct),
                                  style: CroplooText.data.copyWith(
                                      fontSize: 12, color: theme.changeColor(s.surprisePct)),
                                  textAlign: TextAlign.right)),
                          Expanded(child: _reactionCell(theme, s.reaction24h)),
                          Expanded(child: _reactionCell(theme, s.reaction48h)),
                          Expanded(child: _reactionCell(theme, s.reaction1w)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _reactionCell(CroplooTheme theme, WasdeReaction? r) {
    if (r == null) {
      return Text('—', style: CroplooText.dataSmall, textAlign: TextAlign.right);
    }
    return Text(Fmt.cents(r.absolute),
        style: CroplooText.data.copyWith(fontSize: 12, color: theme.changeColor(r.absolute)),
        textAlign: TextAlign.right);
  }
}

class _SimilarSurpriseCard extends StatelessWidget {
  final WasdeSimilarSurprise match;

  const _SimilarSurpriseCard({required this.match});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final reaction = match.mostSimilar.reaction24h;
    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: theme.accent, width: 3)),
      ),
      child: CroplooCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(PhosphorIconsRegular.sparkle, color: theme.accent, size: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This ${match.latest.commodity.toLowerCase()} surprise most resembles ${Fmt.date(match.mostSimilar.releaseDate)}',
                    style: CroplooText.bodyStrong.copyWith(fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Back then: ${Fmt.pct(match.mostSimilar.surprisePct)} surprise'
                    '${reaction != null ? ', ${Fmt.cents(reaction.absolute)} in 24h' : ''}.',
                    style: CroplooText.body.copyWith(fontSize: 12, color: theme.textSecondary),
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

final _selectedReportProvider = StateProvider<int?>((ref) => null);
final _typeFiltersProvider = StateProvider<Set<String>>(
    (ref) => {'WASDE', 'CROP_PROGRESS', 'EXPORT_SALES'});

/// USDA Analyzer: report list + calendar (left), report detail with
/// CullyAI analysis (right).
class UsdaScreen extends ConsumerWidget {
  const UsdaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final reports = ref.watch(usdaReportsProvider);
    return reports.when(
      loading: () => const CroplooLoader(),
      error: (e, _) =>
          Center(child: Text('Error loading reports', style: CroplooText.body)),
      data: (list) {
        final filters = ref.watch(_typeFiltersProvider);
        final filtered =
            list.where((r) => filters.contains(r.reportType)).toList();
        final selectedId = ref.watch(_selectedReportProvider) ??
            (filtered.isNotEmpty ? filtered.first.id : null);
        final selected =
            filtered.where((r) => r.id == selectedId).firstOrNull ??
                filtered.firstOrNull;
        // Export Sales isn't a Claude-analyzed comparison-table report
        // like WASDE/Crop Progress — it's a real weekly time series +
        // country leaderboard, so it gets its own panel rather than
        // being forced into the UsdaReport shape. Shown whenever the
        // filter is active and no WASDE/Crop Progress report is picked.
        final showExportSales = selected == null && filters.contains('EXPORT_SALES');
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 380, child: _LeftColumn(reports: filtered)),
            VerticalDivider(width: 1, color: theme.bgBorder),
            Expanded(
              child: showExportSales
                  ? const _ExportSalesPanel()
                  : selected == null
                      ? const EmptyState(
                          icon: PhosphorIconsRegular.fileText,
                          message: 'Select a report.')
                      : _ReportDetail(report: selected),
            ),
          ],
        );
      },
    );
  }
}

// ── Left column ──────────────────────────────────────────────────

class _LeftColumn extends ConsumerWidget {
  final List<UsdaReport> reports;

  const _LeftColumn({required this.reports});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final calendar = ref.watch(usdaCalendarProvider).valueOrNull ?? const [];
    final filters = ref.watch(_typeFiltersProvider);
    final selectedId = ref.watch(_selectedReportProvider);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('USDA ANALYZER', style: CroplooText.h2),
        const SizedBox(height: 24),
        const SectionHeader(title: 'Next Releases'),
        const SizedBox(height: 12),
        CroplooCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              for (final r in calendar)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text(r.reportType,
                              style: CroplooText.bodyStrong
                                  .copyWith(fontSize: 13))),
                      Text(Fmt.dateShort(r.releaseDate),
                          style: CroplooText.dataSmall),
                      const SizedBox(width: 16),
                      Text(Fmt.countdown(r.releaseDate),
                          style: CroplooText.dataSmall
                              .copyWith(color: theme.accent)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const SectionHeader(title: 'Recent Reports'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (key, label) in const [
              ('WASDE', 'WASDE'),
              ('CROP_PROGRESS', 'Crop Progress'),
              ('EXPORT_SALES', 'Export Sales'),
            ])
              _FilterChip(
                label: label,
                selected: filters.contains(key),
                onTap: () {
                  final next = {...filters};
                  next.contains(key) ? next.remove(key) : next.add(key);
                  ref.read(_typeFiltersProvider.notifier).state = next;
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        for (final r in reports)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ReportCard(
              report: r,
              selected: r.id == (selectedId ?? reports.first.id),
              onTap: () =>
                  ref.read(_selectedReportProvider.notifier).state = r.id,
            ),
          ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? theme.accentDim : theme.bgSurface,
          border: Border.all(
              color: selected ? theme.accent : theme.bgBorder),
          borderRadius: BorderRadius.zero,
        ),
        child: Text(label.toUpperCase(),
            style: CroplooText.label.copyWith(
                fontSize: 10,
                color: selected
                    ? theme.accent
                    : theme.textSecondary)),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final UsdaReport report;
  final bool selected;
  final VoidCallback onTap;

  const _ReportCard(
      {required this.report, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      child: CroplooCard(
        padding: const EdgeInsets.all(16),
        borderColor: selected ? theme.accent : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child:
                        Text(report.typeLabel, style: CroplooText.bodyStrong)),
                Text(Fmt.dateShort(report.releaseDate),
                    style: CroplooText.dataSmall),
              ],
            ),
            const SizedBox(height: 8),
            ImpactBadge(direction: report.aiDirection),
            const SizedBox(height: 8),
            Text(report.aiHeadline,
                style: CroplooText.body.copyWith(fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

// ── Report detail ────────────────────────────────────────────────

class _ReportDetail extends ConsumerWidget {
  final UsdaReport report;

  const _ReportDetail({required this.report});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: report.source != null
                ? 'Basis data: ${report.source}${report.asOf != null ? '\nLast updated: ${Fmt.date(report.asOf!)}' : ''}'
                : '',
            child: Text(report.title, style: CroplooText.h2),
          ),
          const SizedBox(height: 8),
          Text(
            'Released: ${Fmt.date(report.releaseDate)}'
            '${report.aiProcessedAt != null ? '  ·  Processed by CullyAI: ${Fmt.date(report.aiProcessedAt!)}' : ''}',
            style: CroplooText.dataSmall,
          ),
          const SizedBox(height: 24),
          // AI Analysis block — amber left border.
          Container(
            decoration: BoxDecoration(
              border: Border(
                  left: BorderSide(color: theme.accent, width: 3)),
            ),
            child: CroplooCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(PhosphorIconsRegular.sparkle,
                          color: theme.accent, size: 14),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'CULLYAI ANALYSIS',
                          style: CroplooText.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          'CONFIDENCE ${Fmt.number(report.confidence * 100)}%',
                          style: CroplooText.dataSmall
                              .copyWith(color: theme.accent),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(report.aiHeadline, style: CroplooText.h3),
                  const SizedBox(height: 12),
                  Text(report.aiSummary,
                      style: CroplooText.body
                          .copyWith(color: theme.textPrimary)),
                  const SizedBox(height: 16),
                  Text('KEY POINTS',
                      style: CroplooText.label.copyWith(fontSize: 10)),
                  const SizedBox(height: 8),
                  for (final p in report.aiKeyPoints)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('· ',
                              style: CroplooText.body
                                  .copyWith(color: theme.accent)),
                          Expanded(
                              child: Text(p,
                                  style: CroplooText.body.copyWith(
                                      color: theme.textPrimary,
                                      fontSize: 13))),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.accentDim,
                      borderRadius: BorderRadius.zero,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('BASIS IMPACT: ',
                            style: CroplooText.label.copyWith(
                                fontSize: 10, color: theme.accent)),
                        Expanded(
                          child: Text(report.basisImpact,
                              style: CroplooText.body.copyWith(
                                  color: theme.textPrimary,
                                  fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                  if (report.riskFactors.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('RISK FACTORS',
                        style: CroplooText.label.copyWith(fontSize: 10)),
                    const SizedBox(height: 6),
                    for (final r in report.riskFactors)
                      Text('· $r',
                          style: CroplooText.body.copyWith(fontSize: 12)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Commodity impacts
          const SectionHeader(title: 'Commodity Impacts'),
          const SizedBox(height: 12),
          CroplooCard(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.zero,
              child: Column(
                children: [
                  for (final ci in report.commodityImpacts)
                    CroplooImpactRow(
                      title: ci.commodity,
                      direction: ci.direction,
                      headline: ci.reasoning,
                      detail: 'Basis: ${ci.basisImpact}',
                    ),
                ],
              ),
            ),
          ),
          if (report.comparison.isNotEmpty) ...[
            const SizedBox(height: 24),
            SectionHeader(title: report.comparisonTitle),
            const SizedBox(height: 12),
            _ComparisonTable(rows: report.comparison),
          ],
          if (report.reportType == 'WASDE' &&
              report.commodityImpacts.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(child: SectionHeader(title: 'WASDE Surprise Tracker')),
                CroplooButton(
                  label: 'Export CSV',
                  variant: CroplooButtonVariant.ghost,
                  expanded: false,
                  onPressed: () => launchUrl(
                    Uri.parse(ref
                        .read(repositoryProvider)
                        .wasdeSurprisesExportUrl(report.commodityImpacts.first.commodity)),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _WasdeSurpriseTracker(
                commodity: report.commodityImpacts.first.commodity),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              CroplooButton(
                label: 'Original Report (PDF) →',
                variant: CroplooButtonVariant.secondary,
                expanded: false,
                onPressed: () {},
              ),
              const SizedBox(width: 12),
              CroplooButton(
                label: 'Share Analysis →',
                variant: CroplooButtonVariant.secondary,
                expanded: false,
                onPressed: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Export Sales panel ──────────────────────────────────────────
// Real USDA FAS Export Sales world totals (see backend/src/exportSales.js)
// — weekly net sales/exports/outstanding-sales aggregated across all
// destination countries, plus the top-10 buyers for the latest week.
// Not a Claude-analyzed report, just the real numbers.

final _exportSalesCommodityProvider = StateProvider<String>((ref) => 'CORN');

String _mt(int metricTons) {
  if (metricTons.abs() >= 1000000) {
    return '${(metricTons / 1000000).toStringAsFixed(2)}M MT';
  }
  if (metricTons.abs() >= 1000) {
    return '${(metricTons / 1000).toStringAsFixed(0)}K MT';
  }
  return '$metricTons MT';
}

class _ExportSalesPanel extends ConsumerWidget {
  const _ExportSalesPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final commodity = ref.watch(_exportSalesCommodityProvider);
    final report = ref.watch(exportSalesProvider(commodity));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('EXPORT SALES', style: CroplooText.h2),
              const Spacer(),
              for (final (key, label) in const [
                ('CORN', 'Corn'),
                ('WHEAT', 'Wheat'),
                ('SOYBEANS', 'Soybeans'),
              ])
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _FilterChip(
                    label: label,
                    selected: commodity == key,
                    onTap: () =>
                        ref.read(_exportSalesCommodityProvider.notifier).state = key,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Weekly net sales, exports and outstanding commitments — real USDA FAS data, summed across every destination country.',
            style: CroplooText.dataSmall,
          ),
          const SizedBox(height: 24),
          report.when(
            loading: () => const SizedBox(height: 200, child: CroplooLoader()),
            error: (e, _) =>
                Text('Error loading Export Sales', style: CroplooText.body),
            data: (data) {
              final latest = data.latest;
              if (latest == null) {
                return const EmptyState(
                    icon: PhosphorIconsRegular.globe,
                    message: 'No Export Sales data yet for this commodity.');
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Tooltip(
                    message: data.source != null
                        ? 'Source: ${data.source}\nWeek ending: ${Fmt.date(latest.date)}\nMarketing year: ${latest.marketingYear}'
                        : '',
                    child: Row(
                      children: [
                        Expanded(
                          child: _StatTile(
                            label: 'WEEKLY NET SALES',
                            value: _mt(latest.netSalesMt),
                            positive: latest.netSalesMt >= 0,
                          ),
                        ),
                        const SizedBox(width: 1),
                        Expanded(
                          child: _StatTile(
                            label: 'WEEKLY EXPORTS',
                            value: _mt(latest.weeklyExportsMt),
                          ),
                        ),
                        const SizedBox(width: 1),
                        Expanded(
                          child: _StatTile(
                            label: 'OUTSTANDING SALES',
                            value: _mt(latest.outstandingSalesMt),
                          ),
                        ),
                        const SizedBox(width: 1),
                        Expanded(
                          child: _StatTile(
                            label: 'TOTAL COMMITMENTS',
                            value: _mt(latest.totalCommitmentsMt),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  const SectionHeader(title: 'Recent Weeks'),
                  const SizedBox(height: 12),
                  CroplooCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                  flex: 2,
                                  child: Text('WEEK ENDING',
                                      style: CroplooText.label
                                          .copyWith(fontSize: 10))),
                              Expanded(
                                  child: Text('NET SALES',
                                      style: CroplooText.label
                                          .copyWith(fontSize: 10),
                                      textAlign: TextAlign.right)),
                              Expanded(
                                  child: Text('EXPORTS',
                                      style: CroplooText.label
                                          .copyWith(fontSize: 10),
                                      textAlign: TextAlign.right)),
                              Expanded(
                                  child: Text('OUTSTANDING',
                                      style: CroplooText.label
                                          .copyWith(fontSize: 10),
                                      textAlign: TextAlign.right)),
                            ],
                          ),
                        ),
                        Divider(height: 1, color: theme.bgBorder),
                        for (final w in data.history.reversed.take(12))
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                Expanded(
                                    flex: 2,
                                    child: Text(Fmt.dateShort(w.date),
                                        style: CroplooText.dataSmall)),
                                Expanded(
                                    child: Text(_mt(w.netSalesMt),
                                        style: CroplooText.dataSmall.copyWith(
                                            color: w.netSalesMt >= 0
                                                ? theme.positive
                                                : theme.negative),
                                        textAlign: TextAlign.right)),
                                Expanded(
                                    child: Text(_mt(w.weeklyExportsMt),
                                        style: CroplooText.dataSmall,
                                        textAlign: TextAlign.right)),
                                Expanded(
                                    child: Text(_mt(w.outstandingSalesMt),
                                        style: CroplooText.dataSmall,
                                        textAlign: TextAlign.right)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  const SectionHeader(title: 'Top Destinations (latest week)'),
                  const SizedBox(height: 12),
                  CroplooCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final d in data.topDestinations)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                SizedBox(
                                    width: 24,
                                    child: Text('${d.rank}',
                                        style: CroplooText.dataSmall
                                            .copyWith(color: theme.textSecondary))),
                                Expanded(
                                    flex: 2,
                                    child: Text(d.country,
                                        style: CroplooText.bodyStrong
                                            .copyWith(fontSize: 13))),
                                Expanded(
                                    child: Text(_mt(d.netSalesMt),
                                        style: CroplooText.dataSmall.copyWith(
                                            color: d.netSalesMt >= 0
                                                ? theme.positive
                                                : theme.negative),
                                        textAlign: TextAlign.right)),
                                Expanded(
                                    child: Text(_mt(d.weeklyExportsMt),
                                        style: CroplooText.dataSmall,
                                        textAlign: TextAlign.right)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final bool? positive;

  const _StatTile({required this.label, required this.value, this.positive});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final color = positive == null
        ? theme.textPrimary
        : (positive! ? theme.positive : theme.negative);
    return CroplooCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: CroplooText.label.copyWith(fontSize: 10)),
          const SizedBox(height: 8),
          Text(value, style: CroplooText.h3.copyWith(color: color, fontSize: 18)),
        ],
      ),
    );
  }
}

class _ComparisonTable extends StatelessWidget {
  final List<DataComparisonRow> rows;

  const _ComparisonTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    Widget cell(String text,
        {bool header = false, bool highlight = false, TextAlign? align}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(
          text,
          textAlign: align,
          style: header
              ? CroplooText.label.copyWith(fontSize: 10)
              : CroplooText.data.copyWith(
                  fontSize: 13,
                  color: highlight
                      ? theme.accent
                      : theme.textPrimary),
        ),
      );
    }

    return CroplooCard(
      padding: EdgeInsets.zero,
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2),
          1: FlexColumnWidth(1),
          2: FlexColumnWidth(1),
          3: FlexColumnWidth(1),
        },
        border: TableBorder(
          horizontalInside: BorderSide(color: theme.bgBorder),
        ),
        children: [
          TableRow(children: [
            cell('METRIC', header: true),
            cell('PREVIOUS', header: true, align: TextAlign.right),
            cell('CURRENT', header: true, align: TextAlign.right),
            cell('CHANGE', header: true, align: TextAlign.right),
          ]),
          for (final r in rows)
            TableRow(children: [
              cell(r.metric),
              cell(r.previous, align: TextAlign.right),
              cell(r.current, align: TextAlign.right),
              cell('${r.change}${r.highlight ? ' ⚠' : ''}',
                  highlight: r.highlight, align: TextAlign.right),
            ]),
        ],
      ),
    );
  }
}
