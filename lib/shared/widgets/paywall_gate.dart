import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme_colors.dart';
import '../../core/theme/typography.dart';
import '../../data/providers.dart';
import '../models/models.dart';
import 'controls.dart';

/// Blocks every route except `/settings` until the signed-in user has an
/// active paid plan — free-tier accounts can only reach billing so they
/// can upgrade.
class PaywallGate extends ConsumerWidget {
  const PaywallGate({super.key, required this.path, required this.child});

  final String path;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (path == '/settings') return child;

    final userAsync = ref.watch(currentUserProvider);
    return userAsync.when(
      loading: () => const _CenteredSpinner(),
      error: (error, _) => _UpgradeRequired(
        message: 'Could not verify your subscription: $error',
      ),
      data: (user) {
        if (user.tier != SubscriptionTier.free) return child;
        return const _UpgradeRequired();
      },
    );
  }
}

class _CenteredSpinner extends StatelessWidget {
  const _CenteredSpinner();

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return Center(child: CircularProgressIndicator(color: theme.accent));
  }
}

class _UpgradeRequired extends StatelessWidget {
  const _UpgradeRequired({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsRegular.lock, size: 40, color: theme.accent),
            const SizedBox(height: 20),
            Text(
              'Subscribe to unlock Croploo',
              style: CroplooText.h2.copyWith(color: theme.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              message ??
                  'Your account is on the free plan — pick a plan to get '
                      'access to live basis data, alerts, and CullyAI.',
              style: CroplooText.body.copyWith(color: theme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            CroplooButton(
              label: 'View plans',
              variant: CroplooButtonVariant.primary,
              onPressed: () => context.go('/settings'),
            ),
          ],
        ),
      ),
    );
  }
}
