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

final _alertFilterProvider = StateProvider<String>((ref) => 'All');

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertsProvider);
    final filter = ref.watch(_alertFilterProvider);
    final unread = ref.watch(unreadAlertCountProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 16),
          child: Row(
            children: [
              Text('ALERTS', style: CroplooText.h2),
              const Spacer(),
              CroplooButton(
                label: 'Export CSV',
                variant: CroplooButtonVariant.ghost,
                expanded: false,
                onPressed: () => launchUrl(
                  Uri.parse(ref.read(repositoryProvider).alertsExportUrl()),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              const SizedBox(width: 8),
              CroplooButton(
                label: 'Mark All Read',
                variant: CroplooButtonVariant.ghost,
                expanded: false,
                onPressed: () =>
                    ref.read(alertsProvider.notifier).markAllRead(),
              ),
              const SizedBox(width: 8),
              CroplooButton(
                label: 'Manage Rules',
                variant: CroplooButtonVariant.secondary,
                expanded: false,
                onPressed: () => _showRulesSheet(context, ref),
              ),
            ],
          ),
        ),
        // Filter tabs
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Row(
            children: [
              for (final f in [
                'All',
                'Unread${unread > 0 ? ' ($unread)' : ''}',
                'Basis',
                'USDA',
                'Freight'
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _FilterTab(
                    label: f,
                    selected: filter == f.split(' ').first,
                    onTap: () => ref
                        .read(_alertFilterProvider.notifier)
                        .state = f.split(' ').first,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Divider(),
        Expanded(
          child: alerts.when(
            loading: () => const CroplooLoader(),
            error: (e, _) =>
                Center(child: Text('Error', style: CroplooText.body)),
            data: (list) {
              final filtered = list.where((a) {
                return switch (filter) {
                  'Unread' => !a.isRead,
                  'Basis' => a.alertType == 'basis',
                  'USDA' => a.alertType == 'usda',
                  'Freight' => a.alertType == 'freight',
                  _ => true,
                };
              }).toList();
              if (filtered.isEmpty) {
                return const EmptyState(
                    icon: PhosphorIconsRegular.bellSlash,
                    message: 'No alerts match this filter.');
              }
              return ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, i) => _AlertTile(alert: filtered[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showRulesSheet(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: theme.bgSurface,
        child: SizedBox(
          width: 560,
          height: 640,
          child: const SingleChildScrollView(child: _RulesPanel()),
        ),
      ),
    );
  }
}

class _FilterTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterTab(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? theme.accentDim : theme.bgSurface,
          border: Border.all(
              color: selected ? theme.accent : theme.bgBorder),
          borderRadius: BorderRadius.zero,
        ),
        child: Text(label,
            style: CroplooText.bodyStrong.copyWith(
                fontSize: 12,
                color: selected
                    ? theme.accent
                    : theme.textSecondary)),
      ),
    );
  }
}

class _AlertTile extends ConsumerWidget {
  final CroplooAlert alert;

  const _AlertTile({required this.alert});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    return InkWell(
      onTap: () {
        ref.read(alertsProvider.notifier).markRead(alert.id);
        // Function 8 — Alert-Kontext: open CullyAI already primed with why
        // this alert fired, instead of making the user re-describe it.
        ref.read(cullyPanelOpenProvider.notifier).state = true;
        ref.read(cullyThreadsProvider.notifier).send(alert.cullyAiPrompt);
      },
      hoverColor: theme.bgElevated,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.bgBorder)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PriorityTag(priority: alert.priority),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(alert.title, style: CroplooText.bodyStrong),
                  const SizedBox(height: 4),
                  Text(alert.body,
                      style: CroplooText.body.copyWith(fontSize: 13)),
                  if (alert.outcome != null) ...[
                    const SizedBox(height: 6),
                    _OutcomeLine(alert: alert),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(Fmt.timeAgo(alert.triggeredAt),
                    style: CroplooText.dataSmall),
                if (!alert.isRead)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: theme.accent,
                            borderRadius: BorderRadius.zero)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Proves the alert's value with a real, dated outcome — "3 weeks
/// later, basis was 12¢ tighter" — computed by the backend from the
/// alert's own trigger-time value vs. the current live one.
class _OutcomeLine extends StatelessWidget {
  final CroplooAlert alert;

  const _OutcomeLine({required this.alert});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final outcome = alert.outcome!;
    final elapsed = outcome.asOf.difference(alert.triggeredAt);
    final elapsedLabel = elapsed.inDays >= 7
        ? '${(elapsed.inDays / 7).floor()} week(s) later'
        : (elapsed.inDays >= 1 ? '${elapsed.inDays} day(s) later' : 'since then');
    final unit = outcome.metric == 'basis' ? '¢/bu' : '';
    final direction = outcome.change.abs() < 0.01
        ? 'unchanged'
        : (outcome.change > 0
            ? '${Fmt.cents(outcome.change)}$unit wider'
            : '${Fmt.cents(outcome.change.abs())}$unit tighter');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.bgElevated,
        border: Border(left: BorderSide(color: theme.accent, width: 2)),
      ),
      child: Text(
        '$elapsedLabel: ${outcome.metric} is $direction '
        '(${Fmt.price(outcome.valueAtAlert)} → ${Fmt.price(outcome.valueNow)}).',
        style: CroplooText.dataSmall.copyWith(color: theme.textSecondary),
      ),
    );
  }
}

const _ruleCommodities = [
  CroplooDropdownItem(value: 'CORN', label: 'Corn'),
  CroplooDropdownItem(value: 'SOYBEANS', label: 'Soybeans'),
  CroplooDropdownItem(value: 'WHEAT', label: 'Wheat'),
];

const _ruleStates = [
  CroplooDropdownItem(value: 'IL', label: 'Illinois'),
  CroplooDropdownItem(value: 'IA', label: 'Iowa'),
  CroplooDropdownItem(value: 'MN', label: 'Minnesota'),
  CroplooDropdownItem(value: 'IN', label: 'Indiana'),
  CroplooDropdownItem(value: 'OH', label: 'Ohio'),
  CroplooDropdownItem(value: 'KS', label: 'Kansas'),
];

class _RulesPanel extends ConsumerWidget {
  const _RulesPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(alertRulesProvider).valueOrNull ?? const [];
    final customRules = ref.watch(customAlertRulesProvider).valueOrNull ?? const [];
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SYSTEM RULES', style: CroplooText.h3),
          const SizedBox(height: 12),
          for (final r in rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: CroplooCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.description, style: CroplooText.bodyStrong),
                    const SizedBox(height: 4),
                    Text(r.detail, style: CroplooText.body.copyWith(fontSize: 12)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text('YOUR CUSTOM RULES', style: CroplooText.h3),
              const Spacer(),
              CroplooButton(
                label: '+ New Rule',
                expanded: false,
                onPressed: () => _showNewRuleDialog(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (customRules.isEmpty)
            Text('No custom rules yet.', style: CroplooText.body)
          else
            for (final r in customRules)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: CroplooCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.ruleType == 'BASIS_THRESHOLD'
                                  ? '${r.commodity} Basis — ${r.state}'
                                  : '${r.commodity} Futures Move',
                              style: CroplooText.bodyStrong,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              r.ruleType == 'BASIS_THRESHOLD'
                                  ? 'Alert when basis is ${r.comparison.toLowerCase()} ${r.thresholdValue}¢'
                                  : 'Alert when a daily move is ${r.comparison.toLowerCase()} ${r.thresholdValue}%',
                              style: CroplooText.body.copyWith(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      CroplooButton(
                        label: 'Delete',
                        variant: CroplooButtonVariant.destructive,
                        expanded: false,
                        onPressed: () =>
                            ref.read(customAlertRulesProvider.notifier).remove(r.id),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  void _showNewRuleDialog(BuildContext context, WidgetRef ref) {
    var ruleType = 'BASIS_THRESHOLD';
    var commodity = 'CORN';
    var state = 'IL';
    var comparison = 'BELOW';
    final thresholdController = TextEditingController();

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
                        Text('NEW CUSTOM ALERT', style: CroplooText.h3),
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
                    Text('Type', style: CroplooText.label.copyWith(color: theme.textSecondary)),
                    const SizedBox(height: 6),
                    CroplooDropdown<String>(
                      value: ruleType,
                      items: const [
                        CroplooDropdownItem(
                            value: 'BASIS_THRESHOLD', label: 'Basis Threshold'),
                        CroplooDropdownItem(
                            value: 'FUTURES_MOVE_THRESHOLD', label: 'Futures Move'),
                      ],
                      onChanged: (v) => setState(() => ruleType = v),
                    ),
                    const SizedBox(height: 16),
                    Text('Commodity',
                        style: CroplooText.label.copyWith(color: theme.textSecondary)),
                    const SizedBox(height: 6),
                    CroplooDropdown<String>(
                      value: commodity,
                      items: _ruleCommodities,
                      onChanged: (v) => setState(() => commodity = v),
                    ),
                    if (ruleType == 'BASIS_THRESHOLD') ...[
                      const SizedBox(height: 16),
                      Text('State',
                          style: CroplooText.label.copyWith(color: theme.textSecondary)),
                      const SizedBox(height: 6),
                      CroplooDropdown<String>(
                        value: state,
                        items: _ruleStates,
                        onChanged: (v) => setState(() => state = v),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text('Comparison',
                        style: CroplooText.label.copyWith(color: theme.textSecondary)),
                    const SizedBox(height: 6),
                    CroplooDropdown<String>(
                      value: comparison,
                      items: const [
                        CroplooDropdownItem(value: 'BELOW', label: 'Below'),
                        CroplooDropdownItem(value: 'ABOVE', label: 'Above'),
                      ],
                      onChanged: (v) => setState(() => comparison = v),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      ruleType == 'BASIS_THRESHOLD'
                          ? 'Threshold (¢/bu)'
                          : 'Threshold (%)',
                      style: CroplooText.label.copyWith(color: theme.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    CroplooTextField(
                      controller: thresholdController,
                      autofocus: true,
                      keyboardType:
                          const TextInputType.numberWithOptions(signed: true, decimal: true),
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
                          label: 'Create',
                          expanded: false,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          borderRadius: 0,
                          onPressed: () {
                            final threshold = double.tryParse(thresholdController.text);
                            if (threshold == null) return;
                            ref.read(customAlertRulesProvider.notifier).add(
                                  ruleType: ruleType,
                                  commodity: commodity,
                                  state: ruleType == 'BASIS_THRESHOLD' ? state : null,
                                  comparison: comparison,
                                  thresholdValue: threshold,
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
