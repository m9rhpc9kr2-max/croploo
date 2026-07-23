import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_colors.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/providers.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/controls.dart';

const _communityCommodities = [
  CroplooDropdownItem(value: 'CORN', label: 'Corn'),
  CroplooDropdownItem(value: 'WHEAT', label: 'Wheat'),
  CroplooDropdownItem(value: 'SOYBEANS', label: 'Soybeans'),
];

/// Community: CullyAI-fact-checked trader insights, Croploo Learn
/// explainer articles, and this week's Croploo Signals newsletter.
class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('COMMUNITY', style: CroplooText.h2),
          const SizedBox(height: 24),
          const SectionHeader(title: 'This Week — Croploo Signals'),
          const SizedBox(height: 12),
          const _NewsletterPreview(),
          const SizedBox(height: 40),
          const SectionHeader(title: 'Community Insights'),
          const SizedBox(height: 12),
          const _AddInsightCard(),
          const SizedBox(height: 16),
          const _CommunityFeed(),
          const SizedBox(height: 40),
          const SectionHeader(title: 'Croploo Learn'),
          const SizedBox(height: 12),
          const _LearnList(),
        ],
      ),
    );
  }
}

class _NewsletterPreview extends ConsumerWidget {
  const _NewsletterPreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issue = ref.watch(newsletterLatestProvider);
    return issue.when(
      loading: () => const SizedBox(height: 100, child: CroplooLoader()),
      error: (e, _) => Text('Error', style: CroplooText.body),
      data: (data) => CroplooCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Week of ${data.issueDate}', style: CroplooText.label),
            const SizedBox(height: 12),
            for (final (i, signal) in data.signals.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('${i + 1}. $signal', style: CroplooText.body),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddInsightCard extends ConsumerStatefulWidget {
  const _AddInsightCard();

  @override
  ConsumerState<_AddInsightCard> createState() => _AddInsightCardState();
}

class _AddInsightCardState extends ConsumerState<_AddInsightCard> {
  String _commodity = 'CORN';
  final _bodyController = TextEditingController();
  bool _posting = false;

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final body = _bodyController.text.trim();
    if (body.isEmpty) return;
    setState(() => _posting = true);
    try {
      await ref.read(repositoryProvider).addCommunityInsight(commodity: _commodity, body: body);
      _bodyController.clear();
      ref.invalidate(communityInsightsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _posting = false);
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
              items: _communityCommodities,
              onChanged: (v) => setState(() => _commodity = v),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: CroplooTextField(
              controller: _bodyController,
              maxLength: 500,
              hintText: 'Share an observation — CullyAI will fact-check it against real data.',
            ),
          ),
          const SizedBox(width: 12),
          CroplooButton(
            label: _posting ? 'Posting…' : 'Post',
            expanded: false,
            onPressed: _posting ? null : _post,
          ),
        ],
      ),
    );
  }
}

class _CommunityFeed extends ConsumerWidget {
  const _CommunityFeed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(communityInsightsProvider);
    return insights.when(
      loading: () => const SizedBox(height: 120, child: CroplooLoader()),
      error: (e, _) => Text('Error', style: CroplooText.body),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyState(icon: PhosphorIconsRegular.chatsCircle, message: 'No insights shared yet.');
        }
        return CroplooCard(
          padding: EdgeInsets.zero,
          child: Column(children: [for (final i in list) _InsightRow(insight: i)]),
        );
      },
    );
  }
}

class _InsightRow extends StatelessWidget {
  final CommunityInsight insight;

  const _InsightRow({required this.insight});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final verdictColor = switch (insight.factCheckVerdict) {
      'CONSISTENT' => theme.positive,
      'QUESTIONABLE' => theme.negative,
      _ => theme.textMuted,
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.border))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('@${insight.username}', style: CroplooText.bodyStrong.copyWith(fontSize: 12)),
              const SizedBox(width: 8),
              Text(insight.commodity, style: CroplooText.label.copyWith(fontSize: 9)),
              const Spacer(),
              Text(Fmt.timeAgo(insight.createdAt),
                  style: CroplooText.label.copyWith(fontSize: 9, color: theme.textMuted)),
            ],
          ),
          const SizedBox(height: 6),
          Text(insight.body, style: CroplooText.body),
          if ((insight.factCheck ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(border: Border(left: BorderSide(color: verdictColor, width: 2))),
              child: Text('${insight.factCheckVerdict}: ${insight.factCheck}',
                  style: CroplooText.dataSmall.copyWith(color: verdictColor)),
            ),
          ],
        ],
      ),
    );
  }
}

class _LearnList extends ConsumerWidget {
  const _LearnList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articles = ref.watch(learnArticlesProvider);
    return articles.when(
      loading: () => const SizedBox(height: 100, child: CroplooLoader()),
      error: (e, _) => Text('Error', style: CroplooText.body),
      data: (list) => Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [for (final a in list) _LearnCard(article: a)],
      ),
    );
  }
}

class _LearnCard extends ConsumerWidget {
  final LearnArticleSummary article;

  const _LearnCard({required this.article});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => showDialog(
        context: context,
        builder: (_) => _LearnArticleDialog(slug: article.slug),
      ),
      child: CroplooCard(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 220,
          child: Text(article.title, style: CroplooText.bodyStrong),
        ),
      ),
    );
  }
}

class _LearnArticleDialog extends ConsumerWidget {
  final String slug;

  const _LearnArticleDialog({required this.slug});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final article = ref.watch(learnArticleProvider(slug));
    return Dialog(
      backgroundColor: theme.bgSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 480,
          height: 420,
          child: article.when(
            loading: () => const CroplooLoader(),
            error: (e, _) => Text('Error', style: CroplooText.body),
            data: (a) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(a.title, style: CroplooText.h3)),
                    CroplooIconButton(
                      icon: PhosphorIconsRegular.x,
                      size: 28,
                      iconColor: theme.textSecondary,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(a.body, style: CroplooText.body.copyWith(height: 1.6)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
