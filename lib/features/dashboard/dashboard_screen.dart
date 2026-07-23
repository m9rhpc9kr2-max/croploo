import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme_colors.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/providers.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/controls.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : (now.hour < 18 ? 'Good afternoon' : 'Good evening');
    final activeWidgets = ref.watch(activeDashboardWidgetIdsProvider);
    bool visible(String id) => activeWidgets == null || activeWidgets.contains(id);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting row
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  "$greeting, ${user?.name ?? 'trader'}. Here's today's market.",
                  style: CroplooText.h1,
                ),
              ),
              Text('${Fmt.weekday(now)} · ${Fmt.date(now)}',
                  style: CroplooText.dataSmall),
              const SizedBox(width: 12),
              CroplooIconButton(
                icon: PhosphorIconsRegular.squaresFour,
                size: 32,
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const _CustomizeDashboardDialog(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          if (visible('daily_brief')) ...[
            const _DailyBriefCard(),
            const SizedBox(height: 24),
          ],
          if (visible('insights')) ...[
            const _ProactiveInsightsCard(),
            const SizedBox(height: 24),
          ],
          if (visible('synthesis')) ...[
            const _CrossAssetSynthesisCard(),
            const SizedBox(height: 24),
          ],
          if (visible('futures_usda')) ...[
            LayoutBuilder(builder: (context, c) {
              final narrow = c.maxWidth < 760;
              final children = [
                const Expanded(child: _FuturesMiniTable()),
                SizedBox(width: narrow ? 0 : 24, height: narrow ? 24 : 0),
                const Expanded(child: _UsdaCountdownCard()),
              ];
              return narrow
                  ? Column(children: [
                      const _FuturesMiniTable(),
                      const SizedBox(height: 24),
                      const _UsdaCountdownCard(),
                    ])
                  : IntrinsicHeight(
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: children));
            }),
            const SizedBox(height: 24),
          ],
          if (visible('opportunities')) ...[
            const _TopOpportunities(),
            const SizedBox(height: 24),
          ],
          if (visible('alerts')) const _RecentAlerts(),
        ],
      ),
    );
  }
}

const _dashboardWidgetLabels = {
  'daily_brief': 'Daily Brief',
  'insights': "CullyAI Today's Insights",
  'synthesis': 'Cross-Asset Synthesis',
  'futures_usda': 'Futures + USDA Countdown',
  'opportunities': 'Top Opportunities',
  'alerts': 'Recent Alerts',
};

/// Widget-visibility toggles + named saved layouts ("Morning Routine",
/// "WASDE Day"...). Not pixel-perfect drag-drop — this Flutter desktop
/// app has no grid/canvas engine for that yet — but real, persisted
/// per-user layout switching.
class _CustomizeDashboardDialog extends ConsumerStatefulWidget {
  const _CustomizeDashboardDialog();

  @override
  ConsumerState<_CustomizeDashboardDialog> createState() =>
      _CustomizeDashboardDialogState();
}

class _CustomizeDashboardDialogState extends ConsumerState<_CustomizeDashboardDialog> {
  late Set<String> _selected;
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selected = (ref.read(activeDashboardWidgetIdsProvider) ?? _dashboardWidgetLabels.keys.toList())
        .toSet();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final layouts = ref.watch(dashboardLayoutsProvider);
    return Dialog(
      backgroundColor: theme.bgSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('CUSTOMIZE DASHBOARD', style: CroplooText.label)),
                  CroplooIconButton(
                    icon: PhosphorIconsRegular.x,
                    size: 28,
                    iconColor: theme.textSecondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              for (final entry in _dashboardWidgetLabels.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _CroplooCheckboxRow(
                    label: entry.value,
                    checked: _selected.contains(entry.key),
                    onChanged: (v) => setState(() {
                      if (v) {
                        _selected.add(entry.key);
                      } else {
                        _selected.remove(entry.key);
                      }
                    }),
                  ),
                ),
              const SizedBox(height: 4),
              CroplooButton(
                label: 'Apply',
                onPressed: () {
                  ref.read(activeDashboardWidgetIdsProvider.notifier).state =
                      _selected.toList();
                  Navigator.of(context).pop();
                },
              ),
              const SizedBox(height: 20),
              Divider(color: theme.bgBorder),
              const SizedBox(height: 12),
              Text('SAVE AS LAYOUT', style: CroplooText.label.copyWith(fontSize: 10)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: CroplooTextField(
                      controller: _nameController,
                      hintText: 'e.g. Morning Routine',
                    ),
                  ),
                  const SizedBox(width: 8),
                  CroplooIconButton(
                    icon: PhosphorIconsRegular.floppyDisk,
                    size: 36,
                    onPressed: () async {
                      final name = _nameController.text.trim();
                      if (name.isEmpty) return;
                      await ref
                          .read(repositoryProvider)
                          .saveDashboardLayout(name, _selected.toList());
                      ref.invalidate(dashboardLayoutsProvider);
                      _nameController.clear();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              layouts.when(
                loading: () => const SizedBox(),
                error: (e, _) => const SizedBox(),
                data: (list) => list.isEmpty
                    ? const SizedBox()
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final l in list)
                            InkWell(
                              onTap: () => setState(() => _selected = l.widgetIds.toSet()),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration:
                                    BoxDecoration(border: Border.all(color: theme.bgBorder)),
                                child: Text(l.name,
                                    style: CroplooText.label.copyWith(fontSize: 10)),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sharp-cornered checkbox row matching the rest of the app's controls
/// (CroplooSwitch, CroplooButton) — Material's own CheckboxListTile has
/// rounded corners and ripple effects that don't match this look.
class _CroplooCheckboxRow extends StatelessWidget {
  final String label;
  final bool checked;
  final ValueChanged<bool> onChanged;

  const _CroplooCheckboxRow({
    required this.label,
    required this.checked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return InkWell(
      onTap: () => onChanged(!checked),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: checked ? theme.accent : Colors.transparent,
              border: Border.all(color: checked ? theme.accent : theme.border),
            ),
            child: checked
                ? Icon(PhosphorIconsRegular.check,
                    size: 13, color: theme.contrastColor(theme.accent))
                : null,
          ),
          const SizedBox(width: 10),
          Text(label, style: CroplooText.body),
        ],
      ),
    );
  }
}

// ── Proactive Insights ──────────────────────────────────────────

class _ProactiveInsightsCard extends ConsumerWidget {
  const _ProactiveInsightsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final insights = ref.watch(dailyInsightsProvider);
    return insights.when(
      loading: () => const SizedBox(height: 60, child: CroplooLoader()),
      error: (e, _) => const SizedBox.shrink(),
      data: (data) {
        if (data.insights.isEmpty) return const SizedBox.shrink();
        return CroplooCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('CULLYAI — TODAY\'S INSIGHTS', style: CroplooText.label),
              const SizedBox(height: 12),
              for (final line in data.insights)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(line,
                      style: CroplooText.body.copyWith(color: theme.textPrimary)),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ── Cross-Asset Synthesis ───────────────────────────────────────

class _CrossAssetSynthesisCard extends ConsumerWidget {
  const _CrossAssetSynthesisCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final synthesis = ref.watch(crossAssetSynthesisProvider);
    return synthesis.when(
      loading: () => const SizedBox(height: 60, child: CroplooLoader()),
      error: (e, _) => const SizedBox.shrink(),
      data: (data) {
        if (data.commentary.isEmpty) return const SizedBox.shrink();
        return CroplooCard(
          borderColor: theme.accent.withValues(alpha: 0.35),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(PhosphorIconsRegular.shareNetwork, size: 16, color: theme.accent),
                  const SizedBox(width: 8),
                  Text('CULLYAI — CROSS-ASSET SYNTHESIS', style: CroplooText.label),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (data.dollarMove1dPct != null)
                    'Dollar ${Fmt.pct(data.dollarMove1dPct!)}',
                  if (data.crudeMovePct != null) 'Crude ${Fmt.pct(data.crudeMovePct!)}',
                  if (data.yieldCurveInverted != null)
                    'Curve ${data.yieldCurveInverted! ? "inverted" : "normal"}',
                ].join(' · '),
                style: CroplooText.dataSmall.copyWith(color: theme.textMuted),
              ),
              const SizedBox(height: 12),
              for (final entry in data.commentary.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '${entry.key}: ',
                          style: CroplooText.bodyStrong.copyWith(color: theme.textPrimary),
                        ),
                        TextSpan(
                          text: entry.value,
                          style: CroplooText.body.copyWith(color: theme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ── Daily Brief ──────────────────────────────────────────────────

class _DailyBriefCard extends ConsumerWidget {
  const _DailyBriefCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final brief = ref.watch(dailyBriefProvider);
    return CroplooCard(
      borderColor: theme.accent.withValues(alpha: 0.35),
      child: brief.when(
        loading: () => const SizedBox(height: 80, child: CroplooLoader()),
        error: (e, _) => Text('Failed to load brief', style: CroplooText.body),
        data: (b) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('DAILY BRIEF BY CULLYAI', style: CroplooText.label),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.accentDim,
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Text('AI',
                      style: CroplooText.label
                          .copyWith(fontSize: 9, color: theme.accent)),
                ),
                const Spacer(),
                Text(Fmt.date(b.date), style: CroplooText.dataSmall),
              ],
            ),
            const SizedBox(height: 16),
            Text(b.summary,
                style: CroplooText.body.copyWith(
                    color: theme.textPrimary, fontSize: 15)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 32,
              runSpacing: 16,
              children: [
                _briefColumn('TOP OPPORTUNITIES', b.topOpportunities,
                    theme.positive),
                _briefColumn(
                    'RISK FACTORS', b.riskFactors, theme.negative),
                _briefColumn('THIS WEEK', b.keyEventsThisWeek,
                    theme.textSecondary),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _briefColumn(String title, List<String> items, Color dot) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: CroplooText.label.copyWith(fontSize: 10)),
          const SizedBox(height: 8),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Container(
                        width: 4,
                        height: 4,
                        decoration:
                            BoxDecoration(color: dot, borderRadius: BorderRadius.zero)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(item,
                          style: CroplooText.body.copyWith(fontSize: 12))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Futures mini table ───────────────────────────────────────────

class _FuturesMiniTable extends ConsumerWidget {
  const _FuturesMiniTable();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final futures = ref.watch(futuresProvider);
    return CroplooCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Futures Today'),
          const SizedBox(height: 16),
          futures.when(
            loading: () => const SizedBox(height: 120, child: CroplooLoader()),
            error: (e, _) => Text('Error', style: CroplooText.body),
            data: (list) => Column(
              children: [
                for (final f in list.take(4))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 90,
                          child: Tooltip(
                            message: f.source != null && f.asOf != null
                                ? 'Basis data: ${f.source}\nLast updated: ${Fmt.date(f.asOf!)} ${Fmt.timeShort(f.asOf!)}'
                                : '',
                            child: Text(f.name.toUpperCase(),
                                style:
                                    CroplooText.label.copyWith(fontSize: 11)),
                          ),
                        ),
                        Text(f.symbol, style: CroplooText.dataSmall),
                        const Spacer(),
                        Text(Fmt.price(f.price), style: CroplooText.data),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 80,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: ChangeChip(value: f.change),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── USDA countdown ───────────────────────────────────────────────

class _UsdaCountdownCard extends ConsumerWidget {
  const _UsdaCountdownCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final calendar = ref.watch(usdaCalendarProvider);
    return CroplooCard(
      child: calendar.when(
        loading: () => const SizedBox(height: 120, child: CroplooLoader()),
        error: (e, _) => Text('Error', style: CroplooText.body),
        data: (releases) {
          final next = releases.first;
          final diff = next.releaseDate.difference(DateTime.now());
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: 'Next USDA Release'),
              const SizedBox(height: 16),
              Text(next.reportType, style: CroplooText.h3),
              const SizedBox(height: 4),
              Text('${Fmt.date(next.releaseDate)} · 12:00 ET',
                  style: CroplooText.dataSmall),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.bgBorder),
                  borderRadius: BorderRadius.zero,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${diff.inDays}',
                        style: CroplooText.dataLarge
                            .copyWith(color: theme.accent)),
                    Text(' days  ', style: CroplooText.body),
                    Text('${diff.inHours % 24}',
                        style: CroplooText.dataLarge
                            .copyWith(color: theme.accent)),
                    Text(' hours', style: CroplooText.body),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              for (final r in releases.skip(1))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text(r.reportType,
                              style: CroplooText.body.copyWith(fontSize: 12))),
                      Text(Fmt.countdown(r.releaseDate),
                          style: CroplooText.dataSmall),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ── Top opportunities ────────────────────────────────────────────

class _TopOpportunities extends ConsumerWidget {
  const _TopOpportunities();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final top = ref.watch(topBasisDeviationsProvider);
    return CroplooCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Top Basis Deviations Today',
            trailing: CroplooButton(
              label: 'View All',
              variant: CroplooButtonVariant.ghost,
              expanded: false,
              onPressed: () => context.go('/basis'),
            ),
          ),
          const SizedBox(height: 8),
          top.when(
            loading: () => const SizedBox(height: 160, child: CroplooLoader()),
            error: (e, _) => Text('Error', style: CroplooText.body),
            data: (list) {
              final maxDev = list.isEmpty
                  ? 1.0
                  : list.first.deviationFromAvg.abs();
              return Column(
                children: [
                  for (final (i, s) in list.take(5).indexed)
                    _OpportunityRow(rank: i + 1, snapshot: s, maxDev: maxDev),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _OpportunityRow extends StatelessWidget {
  final int rank;
  final BasisSnapshot snapshot;
  final double maxDev;

  const _OpportunityRow(
      {required this.rank, required this.snapshot, required this.maxDev});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final s = snapshot;
    final devColor = theme.changeColor(s.deviationFromAvg);
    return InkWell(
      onTap: () => context
          .go('/basis/detail/${s.elevator.id}/${s.commodity.symbol}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SizedBox(
                width: 32,
                child: Text('#$rank',
                    style: CroplooText.dataSmall
                        .copyWith(color: theme.textMuted))),
            SizedBox(
              width: 220,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${s.elevator.name}, ${s.elevator.state}',
                      style: CroplooText.bodyStrong.copyWith(fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                  Text(s.commodity.name.toUpperCase(),
                      style: CroplooText.label.copyWith(fontSize: 10)),
                ],
              ),
            ),
            SizedBox(
              width: 110,
              child: Text(Fmt.basis(s.basisValue), style: CroplooText.data),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.zero,
                    child: LinearProgressIndicator(
                      value: (s.deviationFromAvg.abs() / maxDev).clamp(0, 1),
                      minHeight: 6,
                      backgroundColor: theme.bgElevated,
                      color: devColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${Fmt.cents(s.deviationFromAvg)} ${s.deviationFromAvg >= 0 ? 'above' : 'below'} 5yr avg',
                    style:
                        CroplooText.dataSmall.copyWith(color: devColor),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            PriorityTag(priority: s.signalStrength),
          ],
        ),
      ),
    );
  }
}

// ── Recent alerts ────────────────────────────────────────────────

class _RecentAlerts extends ConsumerWidget {
  const _RecentAlerts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final alerts = ref.watch(alertsProvider);
    return CroplooCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Recent Alerts',
            trailing: CroplooButton(
              label: 'View All',
              variant: CroplooButtonVariant.ghost,
              expanded: false,
              onPressed: () => context.go('/alerts'),
            ),
          ),
          const SizedBox(height: 8),
          alerts.when(
            loading: () => const SizedBox(height: 100, child: CroplooLoader()),
            error: (e, _) => Text('Error', style: CroplooText.body),
            data: (list) => Column(
              children: [
                for (final a in list.take(3))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        PriorityTag(priority: a.priority),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(a.title,
                              style:
                                  CroplooText.bodyStrong.copyWith(fontSize: 13),
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (!a.isRead)
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                                color: theme.accent,
                                borderRadius: BorderRadius.zero),
                          ),
                        Text(Fmt.timeAgo(a.triggeredAt),
                            style: CroplooText.dataSmall),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
