import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme_colors.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/controls.dart';

const _commodities = [
  CroplooDropdownItem(value: 'CORN', label: 'Corn'),
  CroplooDropdownItem(value: 'SOYBEANS', label: 'Soybeans'),
  CroplooDropdownItem(value: 'WHEAT', label: 'Wheat'),
];

const _states = [
  CroplooDropdownItem(value: 'IL', label: 'Illinois'),
  CroplooDropdownItem(value: 'IA', label: 'Iowa'),
  CroplooDropdownItem(value: 'MN', label: 'Minnesota'),
  CroplooDropdownItem(value: 'IN', label: 'Indiana'),
  CroplooDropdownItem(value: 'OH', label: 'Ohio'),
  CroplooDropdownItem(value: 'KS', label: 'Kansas'),
];

const _commodityToSymbol = {'CORN': 'ZC', 'SOYBEANS': 'ZS', 'WHEAT': 'ZW'};

/// Watchlist of commodity+state combos ("Iowa Corn") — basis data is
/// state-level, so that's the natural granularity. Drives personalized
/// alerts and the daily brief (see dailyBrief.js/alertsEngine.js).
class WatchlistScreen extends ConsumerWidget {
  const WatchlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final watchlist = ref.watch(watchlistProvider);
    final snapshots = ref.watch(basisOverviewProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 16),
          child: Row(
            children: [
              Text('WATCHLIST', style: CroplooText.h2),
              const Spacer(),
              CroplooButton(
                label: '+ Add',
                expanded: false,
                onPressed: () => _showAddDialog(context, ref),
              ),
            ],
          ),
        ),
        Divider(color: theme.bgBorder),
        Expanded(
          child: watchlist.when(
            loading: () => const CroplooLoader(),
            error: (e, _) =>
                Center(child: Text('Error', style: CroplooText.body)),
            data: (items) {
              if (items.isEmpty) {
                return const EmptyState(
                    icon: PhosphorIconsRegular.star,
                    message: 'No watched combos yet. Tap + Add to start.');
              }
              return snapshots.when(
                loading: () => const CroplooLoader(),
                error: (e, _) =>
                    Center(child: Text('Error', style: CroplooText.body)),
                data: (all) => ListView.builder(
                  padding: const EdgeInsets.all(24),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final item = items[i];
                    final symbol = _commodityToSymbol[item.commodity];
                    final snap = all.where((s) =>
                        s.elevator.state == item.state &&
                        s.commodity.symbol == symbol);
                    final s = snap.isEmpty ? null : snap.first;
                    final devColor = s != null
                        ? theme.changeColor(s.deviationFromAvg)
                        : theme.textSecondary;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        onTap: s == null
                            ? null
                            : () => context.go(
                                '/basis/detail/${s.elevator.id}/${s.commodity.symbol}'),
                        borderRadius: BorderRadius.zero,
                        child: CroplooCard(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            children: [
                              Icon(PhosphorIconsRegular.star, size: 16, color: theme.accent),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.state,
                                        style: CroplooText.bodyStrong),
                                    Text(item.commodity,
                                        style: CroplooText.label
                                            .copyWith(fontSize: 10)),
                                  ],
                                ),
                              ),
                              if (s != null) ...[
                                DataLabel(
                                    label: 'Basis',
                                    value: Fmt.basis(s.basisValue)),
                                const SizedBox(width: 40),
                                DataLabel(
                                    label: 'vs 5yr avg',
                                    value: Fmt.cents(s.deviationFromAvg),
                                    valueColor: devColor),
                              ] else
                                Text('No data yet', style: CroplooText.dataSmall),
                              const SizedBox(width: 24),
                              CroplooIconButton(
                                icon: PhosphorIconsRegular.x,
                                size: 32,
                                iconColor: theme.textSecondary,
                                onPressed: () => ref
                                    .read(watchlistProvider.notifier)
                                    .remove(item.id),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    var commodity = 'CORN';
    var state = 'IL';
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final theme = CroplooTheme.of(context);
          return Dialog(
            backgroundColor: theme.bgSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('ADD TO WATCHLIST', style: CroplooText.h3),
                        const Spacer(),
                        CroplooIconButton(
                          icon: PhosphorIconsRegular.x,
                          size: 28,
                          iconColor: theme.textSecondary,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text('Commodity',
                        style: CroplooText.label
                            .copyWith(color: theme.textSecondary)),
                    const SizedBox(height: 6),
                    CroplooDropdown<String>(
                      value: commodity,
                      items: _commodities,
                      onChanged: (v) => setState(() => commodity = v),
                    ),
                    const SizedBox(height: 16),
                    Text('State',
                        style: CroplooText.label
                            .copyWith(color: theme.textSecondary)),
                    const SizedBox(height: 6),
                    CroplooDropdown<String>(
                      value: state,
                      items: _states,
                      onChanged: (v) => setState(() => state = v),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        CroplooButton(
                          label: 'Cancel',
                          variant: CroplooButtonVariant.ghost,
                          expanded: false,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          borderRadius: 0,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 12),
                        CroplooButton(
                          label: 'Add',
                          expanded: false,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          borderRadius: 0,
                          onPressed: () {
                            ref.read(watchlistProvider.notifier).add(commodity, state);
                            Navigator.of(context).pop();
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
      ),
    );
  }
}
