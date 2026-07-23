import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_colors.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/providers.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';

/// In-app mirror of the public /status page: is every real upstream
/// data source live right now? Answers "is this stale number Croploo's
/// fault or an upstream outage" without needing to leave the app.
class StatusScreen extends ConsumerWidget {
  const StatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(statusProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DATA SOURCE STATUS', style: CroplooText.h2),
          const SizedBox(height: 8),
          Text(
            'Live health of every real data source Croploo depends on.',
            style: CroplooText.dataSmall,
          ),
          const SizedBox(height: 24),
          status.when(
            loading: () => const CroplooLoader(),
            error: (e, _) => Text('Error loading status', style: CroplooText.body),
            data: (sources) => Column(
              children: [
                for (final s in sources)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _StatusRow(source: s),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final DataSourceStatus source;

  const _StatusRow({required this.source});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final (color, label) = switch (source.state) {
      'operational' => (theme.positive, 'Operational'),
      'stale' => (theme.accent, 'Delayed'),
      'not_configured' => (theme.textSecondary, 'Not Configured'),
      _ => (theme.textSecondary, 'No Data Yet'),
    };
    return CroplooCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(source.label, style: CroplooText.bodyStrong),
                const SizedBox(height: 2),
                Text(source.detail,
                    style: CroplooText.body.copyWith(fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(label,
                  style: CroplooText.bodyStrong.copyWith(color: color, fontSize: 13)),
              const SizedBox(height: 2),
              Text(
                source.lastUpdated != null
                    ? 'Updated ${Fmt.timeAgo(source.lastUpdated!)}'
                    : '—',
                style: CroplooText.dataSmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
