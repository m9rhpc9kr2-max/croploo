import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_colors.dart';
import '../../core/theme/theme_settings.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/providers.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/calendar_picker.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/controls.dart';

const _positionCommodities = [
  CroplooDropdownItem(value: 'CORN', label: 'Corn'),
  CroplooDropdownItem(value: 'SOYBEANS', label: 'Soybeans'),
  CroplooDropdownItem(value: 'WHEAT', label: 'Wheat'),
];

const _positionStates = [
  CroplooDropdownItem(value: 'IL', label: 'Illinois'),
  CroplooDropdownItem(value: 'IA', label: 'Iowa'),
  CroplooDropdownItem(value: 'MN', label: 'Minnesota'),
  CroplooDropdownItem(value: 'IN', label: 'Indiana'),
  CroplooDropdownItem(value: 'OH', label: 'Ohio'),
  CroplooDropdownItem(value: 'KS', label: 'Kansas'),
];

/// Stored-grain inventory: P&L, sell-window, and hedge context are all
/// computed live from real data (cash prices, seasonal pattern, COT) —
/// see backend/src/portfolio.js.
class PortfolioScreen extends ConsumerWidget {
  const PortfolioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positions = ref.watch(portfolioProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('PORTFOLIO', style: CroplooText.h2),
              const Spacer(),
              CroplooButton(
                label: '+ Add Position',
                expanded: false,
                onPressed: () => _showAddDialog(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _CurrencyConverterCard(),
          const SizedBox(height: 24),
          positions.when(
            loading: () => const SizedBox(height: 200, child: CroplooLoader()),
            error: (e, _) => Text('Error', style: CroplooText.body),
            data: (list) {
              if (list.isEmpty) {
                return const EmptyState(
                  icon: PhosphorIconsRegular.package,
                  message: 'No stored positions yet. Add one to track P&L.',
                );
              }
              return Column(
                children: [
                  for (final p in list) ...[
                    _PositionCard(position: p),
                    const SizedBox(height: 16),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    var commodity = 'CORN';
    var state = 'IL';
    var storedDate = DateTime.now();
    final bushelsController = TextEditingController();
    final breakEvenController = TextEditingController();

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
                        Text('ADD STORED POSITION', style: CroplooText.h3),
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
                        style: CroplooText.label.copyWith(color: theme.textSecondary)),
                    const SizedBox(height: 6),
                    CroplooDropdown<String>(
                      value: commodity,
                      items: _positionCommodities,
                      onChanged: (v) => setState(() => commodity = v),
                    ),
                    const SizedBox(height: 16),
                    Text('State (for local cash price)',
                        style: CroplooText.label.copyWith(color: theme.textSecondary)),
                    const SizedBox(height: 6),
                    CroplooDropdown<String>(
                      value: state,
                      items: _positionStates,
                      onChanged: (v) => setState(() => state = v),
                    ),
                    const SizedBox(height: 16),
                    Text('Bushels',
                        style: CroplooText.label.copyWith(color: theme.textSecondary)),
                    const SizedBox(height: 6),
                    CroplooTextField(
                      controller: bushelsController,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 16),
                    Text('Break-Even Price (\$/bu)',
                        style: CroplooText.label.copyWith(color: theme.textSecondary)),
                    const SizedBox(height: 6),
                    CroplooTextField(
                      controller: breakEvenController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 16),
                    Text('Stored Date',
                        style: CroplooText.label.copyWith(color: theme.textSecondary)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final picked = await showCroplooCalendar(
                          context: context,
                          initialDate: storedDate,
                          firstDate: DateTime(2015),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) setState(() => storedDate = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: theme.bgElevated,
                          border: Border.all(color: theme.border),
                          borderRadius: BorderRadius.zero,
                        ),
                        child: Text(Fmt.date(storedDate), style: CroplooText.data),
                      ),
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
                            final bushels = double.tryParse(bushelsController.text);
                            final breakEven = double.tryParse(breakEvenController.text);
                            if (bushels == null || breakEven == null) return;
                            ref.read(portfolioProvider.notifier).add(
                                  commodity: commodity,
                                  bushels: bushels,
                                  storedDate: storedDate,
                                  breakEvenPrice: breakEven,
                                  state: state,
                                );
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

final _portfolioCurrencyProvider = StateProvider<String>((ref) => 'USD');

const _currencies = [
  CroplooDropdownItem(value: 'USD', label: 'USD'),
  CroplooDropdownItem(value: 'EUR', label: 'EUR'),
  CroplooDropdownItem(value: 'GBP', label: 'GBP'),
  CroplooDropdownItem(value: 'CHF', label: 'CHF'),
];

/// Converts the summed P&L across all positions into EUR/GBP/CHF using
/// live Forex Terminal rates (see backend/src/forex.js) — for
/// international users who think in their home currency, not USD.
class _CurrencyConverterCard extends ConsumerWidget {
  const _CurrencyConverterCard();

  double? _convert(double usdAmount, String currency, ForexSnapshot fx) {
    if (currency == 'USD') return usdAmount;
    ForexPair? pair(String key) =>
        fx.pairs.where((p) => p.pair == key).firstOrNull;
    return switch (currency) {
      'EUR' => pair('EURUSD') != null ? usdAmount / pair('EURUSD')!.rate : null,
      'GBP' => pair('GBPUSD') != null ? usdAmount / pair('GBPUSD')!.rate : null,
      'CHF' => pair('USDCHF') != null ? usdAmount * pair('USDCHF')!.rate : null,
      _ => usdAmount,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final positions = ref.watch(portfolioProvider).valueOrNull ?? const [];
    final currency = ref.watch(_portfolioCurrencyProvider);
    final totalPlUsd = positions.fold<double>(0, (sum, p) => sum + (p.totalPl ?? 0));

    if (positions.isEmpty) return const SizedBox.shrink();

    return CroplooCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TOTAL P&L', style: CroplooText.label),
                const SizedBox(height: 6),
                if (currency == 'USD')
                  Text('\$${Fmt.number(totalPlUsd)}',
                      style: CroplooText.dataXL.copyWith(color: theme.changeColor(totalPlUsd))),
                if (currency != 'USD')
                  ref.watch(forexProvider).when(
                        loading: () => const SizedBox(height: 32, child: CroplooLoader()),
                        error: (e, _) => Text('—', style: CroplooText.dataXL),
                        data: (fx) {
                          final converted = _convert(totalPlUsd, currency, fx);
                          return Text(
                            converted != null
                                ? '${_symbolFor(currency)}${Fmt.number(converted)}'
                                : '—',
                            style: CroplooText.dataXL.copyWith(color: theme.changeColor(totalPlUsd)),
                          );
                        },
                      ),
              ],
            ),
          ),
          SizedBox(
            width: 140,
            child: CroplooDropdown<String>(
              value: currency,
              items: _currencies,
              onChanged: (v) => ref.read(_portfolioCurrencyProvider.notifier).state = v,
            ),
          ),
        ],
      ),
    );
  }

  String _symbolFor(String currency) => switch (currency) {
        'EUR' => '€',
        'GBP' => '£',
        'CHF' => 'CHF ',
        _ => '\$',
      };
}

class _PositionCard extends ConsumerWidget {
  final PortfolioPosition position;

  const _PositionCard({required this.position});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final pl = position.totalPl;
    final plColor = pl == null ? theme.textSecondary : theme.changeColor(pl);
    final windowColor = switch (position.sellWindow.label) {
      'FAVORABLE' => theme.positive,
      'UNFAVORABLE' => theme.negative,
      _ => theme.textSecondary,
    };

    return CroplooCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${position.commodity} — ${position.state ?? "—"}',
                        style: CroplooText.h3),
                    const SizedBox(height: 4),
                    Text(
                      '${Fmt.number(position.bushels, style: NumberFormatStyle.us)} bu · stored ${Fmt.date(position.storedDate)} · '
                      'break-even \$${Fmt.price(position.breakEvenPrice)}',
                      style: CroplooText.dataSmall,
                    ),
                  ],
                ),
              ),
              CroplooIconButton(
                icon: PhosphorIconsRegular.x,
                size: 32,
                iconColor: theme.textSecondary,
                onPressed: () =>
                    ref.read(portfolioProvider.notifier).remove(position.id),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DataLabel(
                  label: 'Current Cash Price',
                  value: position.currentCashPrice != null
                      ? '\$${Fmt.price(position.currentCashPrice!)}'
                      : '—',
                ),
              ),
              Expanded(
                child: DataLabel(
                  label: 'P&L / bu',
                  value: position.plPerBushel != null
                      ? '\$${Fmt.price(position.plPerBushel!)}'
                      : '—',
                  valueColor: plColor,
                ),
              ),
              Expanded(
                child: DataLabel(
                  label: 'Total P&L',
                  value: pl != null ? '\$${Fmt.number(pl)}' : '—',
                  valueColor: plColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: windowColor.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.zero,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SELL WINDOW: ${position.sellWindow.label}',
                    style: CroplooText.label.copyWith(fontSize: 10, color: windowColor)),
                const SizedBox(height: 4),
                Text(position.sellWindow.detail, style: CroplooText.dataSmall),
              ],
            ),
          ),
          if (position.hedgeNote.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(position.hedgeNote, style: CroplooText.dataSmall),
          ],
        ],
      ),
    );
  }
}
