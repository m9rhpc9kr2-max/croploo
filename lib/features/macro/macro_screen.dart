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

/// Macro: headline FRED indicators (CPI, GDP, Fed funds, etc), the
/// upcoming agribusiness earnings and high-impact economic calendars,
/// and a CullyAI-tagged live news feed — the broader macro backdrop
/// that grain trading sits inside.
class MacroScreen extends ConsumerWidget {
  const MacroScreen({super.key});

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
            Text('MACRO', style: CroplooText.h2),
            const SizedBox(height: 24),
            const SectionHeader(title: 'Economic Indicators'),
            const SizedBox(height: 12),
            const _EconomicIndicatorsPanel(),
            const SizedBox(height: 40),
            const SectionHeader(title: 'Earnings Calendar'),
            const SizedBox(height: 12),
            const _EarningsCalendarPanel(),
            const SizedBox(height: 40),
            const SectionHeader(title: 'Economic Calendar'),
            const SizedBox(height: 12),
            const _EconomicCalendarPanel(),
            const SizedBox(height: 40),
            const SectionHeader(title: 'News Terminal'),
            const SizedBox(height: 12),
            const _NewsPanel(),
          ],
        ),
      ),
    );
  }
}

// ── Economic Indicators ─────────────────────────────────────────

class _EconomicIndicatorsPanel extends ConsumerWidget {
  const _EconomicIndicatorsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(economicIndicatorsProvider);
    return snapshot.when(
      loading: () => const SizedBox(height: 200, child: CroplooLoader()),
      error: (e, _) => Text('Error', style: CroplooText.body),
      data: (data) => CroplooCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 24,
              runSpacing: 20,
              children: [
                for (final indicator in data.indicators)
                  _IndicatorTile(indicator: indicator),
              ],
            ),
            if (data.note.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(data.note, style: CroplooText.dataSmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _IndicatorTile extends StatelessWidget {
  final EconomicIndicator indicator;

  const _IndicatorTile({required this.indicator});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(indicator.label.toUpperCase(),
              style: CroplooText.label.copyWith(fontSize: 10)),
          const SizedBox(height: 6),
          Text('${Fmt.number(indicator.latestValue)} ${indicator.unit}',
              style: CroplooText.dataLarge),
          const SizedBox(height: 4),
          Row(
            children: [
              ChangeChip(value: indicator.changePct, formatter: Fmt.pct),
              const SizedBox(width: 8),
              Text(Fmt.dateShort(indicator.latestDate),
                  style: CroplooText.label
                      .copyWith(fontSize: 9, color: theme.textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Earnings Calendar ───────────────────────────────────────────

class _EarningsCalendarPanel extends ConsumerWidget {
  const _EarningsCalendarPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(earningsCalendarProvider);
    return snapshot.when(
      loading: () => const SizedBox(height: 160, child: CroplooLoader()),
      error: (e, _) => Text('Error', style: CroplooText.body),
      data: (data) {
        if (data.events.isEmpty) {
          return const EmptyState(
              icon: PhosphorIconsRegular.calendarX,
              message: 'No agribusiness earnings in the next 2 weeks.');
        }
        return CroplooCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final e in data.events) _EarningsRow(event: e),
              if (data.note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(data.note, style: CroplooText.dataSmall),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EarningsRow extends StatelessWidget {
  final EarningsEvent event;

  const _EarningsRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.border))),
      child: Row(
        children: [
          SizedBox(width: 60, child: Text(event.symbol, style: CroplooText.bodyStrong)),
          Expanded(child: Text(Fmt.date(event.date), style: CroplooText.body)),
          if (event.epsEstimate != null)
            DataLabel(label: 'EPS Est.', value: event.epsEstimate!.toStringAsFixed(2)),
        ],
      ),
    );
  }
}

// ── Economic Calendar ───────────────────────────────────────────

class _EconomicCalendarPanel extends ConsumerWidget {
  const _EconomicCalendarPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(economicCalendarProvider);
    return snapshot.when(
      loading: () => const SizedBox(height: 160, child: CroplooLoader()),
      error: (e, _) => Text('Error', style: CroplooText.body),
      data: (data) {
        if (data.events.isEmpty) {
          return const EmptyState(
              icon: PhosphorIconsRegular.calendarBlank,
              message: 'No high-impact macro events in the next 2 weeks.');
        }
        return CroplooCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final e in data.events) _EconCalendarRow(event: e),
              if (data.note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(data.note, style: CroplooText.dataSmall),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EconCalendarRow extends StatelessWidget {
  final EconCalendarEvent event;

  const _EconCalendarRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.border))),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(event.country, style: CroplooText.label.copyWith(fontSize: 10)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.event, style: CroplooText.bodyStrong.copyWith(fontSize: 13)),
                const SizedBox(height: 2),
                Text(Fmt.date(event.date),
                    style: CroplooText.body.copyWith(fontSize: 11, color: theme.textMuted)),
              ],
            ),
          ),
          if (event.estimate != null)
            DataLabel(label: 'Est.', value: event.estimate!.toStringAsFixed(1)),
          const SizedBox(width: 16),
          if (event.previous != null)
            DataLabel(label: 'Prev.', value: event.previous!.toStringAsFixed(1)),
        ],
      ),
    );
  }
}

// ── News Terminal ────────────────────────────────────────────────

final _newsTagFilterProvider = StateProvider<String?>((ref) => null);

const _newsTagFilters = [
  (null, 'ALL'),
  ('GRAIN', 'GRAIN'),
  ('ENERGY', 'ENERGY'),
  ('MACRO', 'MACRO'),
];

class _NewsPanel extends ConsumerWidget {
  const _NewsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTag = ref.watch(_newsTagFilterProvider);
    final headlines = ref.watch(newsProvider(activeTag));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final (value, label) in _newsTagFilters)
              _NewsTagChip(
                label: label,
                selected: activeTag == value,
                onTap: () => ref.read(_newsTagFilterProvider.notifier).state = value,
              ),
          ],
        ),
        const SizedBox(height: 12),
        headlines.when(
          loading: () => const SizedBox(height: 160, child: CroplooLoader()),
          error: (e, _) => Text('Error', style: CroplooText.body),
          data: (list) {
            if (list.isEmpty) {
              return const EmptyState(
                  icon: PhosphorIconsRegular.newspaper, message: 'No headlines yet.');
            }
            return CroplooCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [for (final h in list) _NewsRow(headline: h)],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _NewsTagChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NewsTagChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? theme.accentDim : theme.bgSurface,
          border: Border.all(color: selected ? theme.accent : theme.border),
        ),
        child: Text(label,
            style: CroplooText.label.copyWith(
                fontSize: 10, color: selected ? theme.accent : theme.textSecondary)),
      ),
    );
  }
}

class _NewsRow extends StatelessWidget {
  final NewsHeadline headline;

  const _NewsRow({required this.headline});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final tagColor = switch (headline.tag) {
      NewsTag.grain => theme.positive,
      NewsTag.energy => theme.accent,
      NewsTag.macro => theme.textSecondary,
      _ => theme.textMuted,
    };
    return InkWell(
      onTap: () => launchUrl(Uri.parse(headline.link)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.border))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (headline.tag != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: tagColor.withValues(alpha: 0.5)),
                  ),
                  child: Text(headline.tag!.name.toUpperCase(),
                      style: CroplooText.label.copyWith(fontSize: 8, color: tagColor)),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(headline.title, style: CroplooText.body.copyWith(fontSize: 13)),
                  const SizedBox(height: 2),
                  Text('${headline.source} · ${Fmt.timeAgo(headline.publishedAt)}',
                      style: CroplooText.label.copyWith(fontSize: 9, color: theme.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
