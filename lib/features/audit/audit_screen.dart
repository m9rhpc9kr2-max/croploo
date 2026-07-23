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

const _auditCommodities = [
  CroplooDropdownItem(value: 'CORN', label: 'Corn'),
  CroplooDropdownItem(value: 'WHEAT', label: 'Wheat'),
  CroplooDropdownItem(value: 'SOYBEANS', label: 'Soybeans'),
];

/// Audit Trail / Decision Log: log a note against a CullyAI
/// recommendation ("sold 40% at $4.82"), and the app tracks the real
/// futures price 7/30 days later — the strongest trust signal to show
/// an institutional buyer.
class AuditScreen extends ConsumerWidget {
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final entries = ref.watch(decisionLogProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('AUDIT TRAIL', style: CroplooText.h2),
              const Spacer(),
              CroplooButton(
                label: 'Compliance Export',
                expanded: false,
                onPressed: () => launchUrl(
                  Uri.parse(ref.read(repositoryProvider).complianceExportUrl()),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Log a note whenever you act on a CullyAI read. The app tracks the real '
            'futures price 7 and 30 days later, so this becomes a real record of whether '
            'following it would have worked out.',
            style: CroplooText.body.copyWith(color: theme.textMuted),
          ),
          const SizedBox(height: 20),
          const _AddDecisionCard(),
          const SizedBox(height: 32),
          const SectionHeader(title: 'Log'),
          const SizedBox(height: 12),
          entries.when(
            loading: () => const SizedBox(height: 160, child: CroplooLoader()),
            error: (e, _) => Text('Error', style: CroplooText.body),
            data: (list) {
              if (list.isEmpty) {
                return const EmptyState(
                    icon: PhosphorIconsRegular.clipboardText, message: 'No decisions logged yet.');
              }
              return CroplooCard(
                padding: EdgeInsets.zero,
                child: Column(children: [for (final e in list) _DecisionRow(entry: e)]),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AddDecisionCard extends ConsumerStatefulWidget {
  const _AddDecisionCard();

  @override
  ConsumerState<_AddDecisionCard> createState() => _AddDecisionCardState();
}

class _AddDecisionCardState extends ConsumerState<_AddDecisionCard> {
  String _commodity = 'CORN';
  final _noteController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final note = _noteController.text.trim();
    if (note.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).addDecisionLogEntry(
            commodity: _commodity,
            userNote: note,
          );
      _noteController.clear();
      ref.invalidate(decisionLogProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CroplooCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: CroplooDropdown<String>(
              value: _commodity,
              items: _auditCommodities,
              onChanged: (v) => setState(() => _commodity = v),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: CroplooTextField(
              controller: _noteController,
              hintText: 'e.g. "Sold 40% of position at \$4.82 following the WASDE surprise"',
            ),
          ),
          const SizedBox(width: 12),
          CroplooButton(
            label: _saving ? 'Saving…' : 'Log Decision',
            expanded: false,
            onPressed: _saving ? null : _submit,
          ),
        ],
      ),
    );
  }
}

class _DecisionRow extends StatelessWidget {
  final DecisionLogEntry entry;

  const _DecisionRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.bgBorder))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(entry.commodity, style: CroplooText.bodyStrong),
              const SizedBox(width: 10),
              Text(Fmt.date(entry.createdAt),
                  style: CroplooText.label.copyWith(fontSize: 9, color: theme.textMuted)),
              const Spacer(),
              if (entry.priceAtLog != null)
                DataLabel(label: 'At Log', value: entry.priceAtLog!.toStringAsFixed(2)),
              if (entry.price7d != null) ...[
                const SizedBox(width: 16),
                DataLabel(label: '+7D', value: entry.price7d!.toStringAsFixed(2)),
              ],
              if (entry.price30d != null) ...[
                const SizedBox(width: 16),
                DataLabel(label: '+30D', value: entry.price30d!.toStringAsFixed(2)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(entry.userNote, style: CroplooText.body),
        ],
      ),
    );
  }
}
