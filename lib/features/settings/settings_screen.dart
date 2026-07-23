import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/theme_colors.dart';
import '../../core/theme/theme_providers.dart';
import '../../core/theme/theme_settings.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/providers.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/controls.dart';
import '../../data/offline_cache.dart';
import '../auth/auth_session.dart';
import '../auth/session_storage.dart';
import 'billing_api.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SETTINGS', style: CroplooText.h2),
          const SizedBox(height: 24),
          // Account
          const SectionHeader(title: 'Account'),
          const SizedBox(height: 12),
          _AccountSettings(user: user),
          const SizedBox(height: 32),
          // Billing
          Row(
            children: [
              const SectionHeader(title: 'Your Plan'),
              const SizedBox(width: 12),
              Text('· Billed monthly. Cancel anytime. Powered by Stripe.',
                  style: CroplooText.body.copyWith(fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          if (user != null) _TrialBanner(user: user),
          LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < 900;
            final cards = [
              _PlanCard(
                tier: 'basic',
                name: 'BASIC',
                price: r'$19/mo',
                features: const [
                  'Commodities — Dashboard, Basis Monitor, USDA Reports',
                  'Basis Monitor — 20 locations',
                  '1 year basis history',
                  '5 alert rules · email alerts',
                ],
                current: user?.tier == SubscriptionTier.basic,
              ),
              _PlanCard(
                tier: 'pro',
                name: 'PRO',
                price: r'$49/mo',
                highlighted: true,
                features: const [
                  'Everything in Basic',
                  '+ Energy (EIA, NG storage, crack spread)',
                  '+ Market Intel (COT, seasonal, crush, dollar index)',
                  'CullyAI analysis + Daily Brief · Freight rates',
                  '100 locations · 5yr history',
                ],
                current: user?.tier == SubscriptionTier.pro,
              ),
              _PlanCard(
                tier: 'desk',
                name: 'DESK',
                price: r'$99/mo',
                features: const [
                  'Everything in Pro',
                  '+ Markets (Forex, crypto, yield curve, sector heatmap)',
                  '+ Macro (FRED indicators, calendars, news terminal)',
                  'Freight–basis correlation',
                  'Unlimited AI · 300 locations',
                ],
                current: user?.tier == SubscriptionTier.desk,
              ),
              _PlanCard(
                tier: 'team',
                name: 'TEAM',
                price: r'$399/mo',
                features: const [
                  'Everything in Desk',
                  '5 team seats',
                  'Shared watchlist & alerts',
                  'Team management',
                ],
                current: user?.tier == SubscriptionTier.team,
              ),
              _PlanCard(
                tier: 'institutional',
                name: 'INSTITUTIONAL',
                price: r'$799/mo',
                features: const [
                  'Everything in Team',
                  '10 team seats',
                  'API access',
                  'Priority support',
                ],
                current: user?.tier == SubscriptionTier.institutional,
              ),
            ];
            return narrow
                ? Column(
                    children: [
                      for (final card in cards)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: card),
                    ],
                  )
                : IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (i, card) in cards.indexed) ...[
                          if (i > 0) const SizedBox(width: 16),
                          Expanded(child: card),
                        ],
                      ],
                    ),
                  );
          }),
          const SizedBox(height: 32),
          // API Keys (only for plans with API access)
          if (user?.tier == SubscriptionTier.desk || 
              user?.tier == SubscriptionTier.team || 
              user?.tier == SubscriptionTier.institutional) ...[
            const SectionHeader(title: 'API Access'),
            const SizedBox(height: 12),
            const _ApiKeysSettings(),
            const SizedBox(height: 32),
          ],
          // Team Management (only for team plans)
          if (user?.teamId != null) ...[
            const SectionHeader(title: 'Team Management'),
            const SizedBox(height: 12),
            const _TeamSettings(),
            const SizedBox(height: 32),
          ],
          // Referrals
          const SectionHeader(title: 'Refer a Colleague'),
          const SizedBox(height: 12),
          const _ReferralSettings(),
          const SizedBox(height: 32),
          // Price Targets
          const SectionHeader(title: 'Price Targets'),
          const SizedBox(height: 12),
          const _PriceTargetsSettings(),
          const SizedBox(height: 32),
          // Notifications
          const SectionHeader(title: 'Notifications'),
          const SizedBox(height: 12),
          const _NotificationSettings(),
          const SizedBox(height: 32),
          // Appearance
          const SectionHeader(title: 'Appearance'),
          const SizedBox(height: 12),
          const _AppearanceSettings(),
          const SizedBox(height: 32),
          // Regional & Units
          const SectionHeader(title: 'Regional & Units'),
          const SizedBox(height: 12),
          const _RegionalSettings(),
          const SizedBox(height: 32),
          // Public Profile
          const SectionHeader(title: 'Public Profile'),
          const SizedBox(height: 12),
          const _PublicProfileSettings(),
          const SizedBox(height: 32),
          // Croploo Signals Newsletter
          const SectionHeader(title: 'Croploo Signals Newsletter'),
          const SizedBox(height: 12),
          const _NewsletterSettings(),
        ],
      ),
    );
  }
}

/// No-credit-card 14-day Pro trial — a real subscription_tier flip on
/// the backend (see billing.js's /start-trial), not a client-side flag,
/// and it lazily reverts to free once trial_ends_at passes (requireAuth.js).
const _windowChannel = MethodChannel('croploo/window_controls');

/// Account details (editable name/email), password change, and sign
/// out. This is a native multi-window desktop app — a separate login
/// window hands the dashboard window its session once at launch and
/// then closes itself (see main.dart), so there's no in-app login
/// screen to return to. "Sign out" here clears the in-memory session
/// and closes this window; relaunching the app opens the login window
/// fresh.
class _AccountSettings extends ConsumerStatefulWidget {
  final CroplooUser? user;

  const _AccountSettings({required this.user});

  @override
  ConsumerState<_AccountSettings> createState() => _AccountSettingsState();
}

class _AccountSettingsState extends ConsumerState<_AccountSettings> {
  bool _editing = false;
  bool _changingPassword = false;
  bool _saving = false;
  late final TextEditingController _nameController =
      TextEditingController(text: widget.user?.name ?? '');
  late final TextEditingController _emailController =
      TextEditingController(text: widget.user?.email ?? '');
  late final TextEditingController _usernameController =
      TextEditingController(text: widget.user?.username ?? '');
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // The backend checks name/email/username for conflicts (uniqueness
      // on email and username) before writing anything — if either is
      // taken, this throws and nothing is saved, including the other
      // fields. See routes/auth.js PUT /me.
      await ref.read(repositoryProvider).updateAccount(
            name: _nameController.text.trim(),
            email: _emailController.text.trim(),
            username: _usernameController.text.trim(),
          );
      ref.invalidate(currentUserProvider);
      if (mounted) setState(() => _editing = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submitPasswordChange() async {
    final current = _currentPasswordController.text;
    final next = _newPasswordController.text;
    if (current.isEmpty || next.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).changePassword(
            currentPassword: current,
            newPassword: next,
          );
      _currentPasswordController.clear();
      _newPasswordController.clear();
      if (mounted) {
        setState(() => _changingPassword = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Password changed.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    // Clear the persisted session (SessionStorage) so relaunching the
    // app doesn't silently auto-restore this login — see
    // login_window_app.dart, which reads it on startup to skip the
    // login screen. Also wipe every cached API response so a different
    // user signing in on this device never sees stale data from this
    // session, then the in-memory session, then close the window.
    await SessionStorage.clear();
    await OfflineCache.clearAll();
    ref.read(authSessionProvider.notifier).state = null;
    _windowChannel.invokeMethod('close');
  }

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final user = widget.user;

    return CroplooCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _editing
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CroplooTextField(
                            controller: _nameController,
                            hintText: 'Name',
                          ),
                          const SizedBox(height: 8),
                          CroplooTextField(
                            controller: _emailController,
                            hintText: 'Email',
                          ),
                          const SizedBox(height: 8),
                          CroplooTextField(
                            controller: _usernameController,
                            hintText: 'Username',
                            prefixText: '@',
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user?.name ?? '—', style: CroplooText.h3),
                          const SizedBox(height: 4),
                          Text(user?.email ?? '—', style: CroplooText.body),
                          const SizedBox(height: 2),
                          Text('@${user?.username ?? '—'}',
                              style: CroplooText.body.copyWith(color: theme.textMuted)),
                        ],
                      ),
              ),
              const SizedBox(width: 12),
              TierBadge(tier: user?.tier ?? SubscriptionTier.free),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (_editing) ...[
                CroplooButton(
                  label: _saving ? 'Saving…' : 'Save',
                  expanded: false,
                  onPressed: _saving ? null : _save,
                ),
                const SizedBox(width: 8),
                CroplooButton(
                  label: 'Cancel',
                  variant: CroplooButtonVariant.secondary,
                  expanded: false,
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                            _editing = false;
                            _nameController.text = user?.name ?? '';
                            _emailController.text = user?.email ?? '';
                            _usernameController.text = user?.username ?? '';
                          }),
                ),
              ] else
                CroplooButton(
                  label: 'Edit',
                  variant: CroplooButtonVariant.secondary,
                  expanded: false,
                  onPressed: () => setState(() => _editing = true),
                ),
              const SizedBox(width: 8),
              CroplooButton(
                label: 'Change Password',
                variant: CroplooButtonVariant.secondary,
                expanded: false,
                onPressed: () => setState(() => _changingPassword = !_changingPassword),
              ),
              const Spacer(),
              CroplooButton(
                label: 'Sign Out',
                variant: CroplooButtonVariant.secondary,
                expanded: false,
                onPressed: _signOut,
              ),
            ],
          ),
          if (_changingPassword) ...[
            const SizedBox(height: 16),
            Divider(color: theme.bgBorder),
            const SizedBox(height: 16),
            CroplooTextField(
              controller: _currentPasswordController,
              obscureText: true,
              hintText: 'Current password',
            ),
            const SizedBox(height: 8),
            CroplooTextField(
              controller: _newPasswordController,
              obscureText: true,
              hintText: 'New password (min. 6 characters)',
            ),
            const SizedBox(height: 12),
            CroplooButton(
              label: _saving ? 'Saving…' : 'Update Password',
              expanded: false,
              onPressed: _saving ? null : _submitPasswordChange,
            ),
          ],
        ],
      ),
    );
  }
}

class _TrialBanner extends ConsumerStatefulWidget {
  final CroplooUser user;

  const _TrialBanner({required this.user});

  @override
  ConsumerState<_TrialBanner> createState() => _TrialBannerState();
}

class _TrialBannerState extends ConsumerState<_TrialBanner> {
  bool _starting = false;

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      await ref.read(repositoryProvider).startTrial();
      ref.invalidate(currentUserProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final user = widget.user;

    if (user.onTrial) {
      final daysLeft = user.trialEndsAt!.difference(DateTime.now()).inDays + 1;
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: CroplooCard(
          borderColor: theme.accent,
          child: Row(
            children: [
              Icon(PhosphorIconsRegular.timer, color: theme.accent, size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Pro trial — $daysLeft day${daysLeft == 1 ? '' : 's'} left, no card on file.',
                  style: CroplooText.bodyStrong.copyWith(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (user.tier != SubscriptionTier.free || user.hasUsedTrial) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: CroplooCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Try Pro free for 14 days', style: CroplooText.bodyStrong),
                  const SizedBox(height: 4),
                  Text('No credit card required.',
                      style: CroplooText.body.copyWith(fontSize: 12)),
                ],
              ),
            ),
            CroplooButton(
              label: _starting ? 'Starting…' : 'Start free trial',
              expanded: false,
              onPressed: _starting ? null : _start,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends ConsumerStatefulWidget {
  final String tier;
  final String name;
  final String price;
  final List<String> features;
  final bool highlighted;
  final bool current;

  const _PlanCard({
    required this.tier,
    required this.name,
    required this.price,
    required this.features,
    this.highlighted = false,
    this.current = false,
  });

  @override
  ConsumerState<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends ConsumerState<_PlanCard> {
  final _billingApi = BillingApi();
  bool _launching = false;
  Timer? _pollTimer;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _startCheckout() async {
    final session = ref.read(authSessionProvider);
    if (session == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in again to manage billing.')),
      );
      return;
    }
    setState(() => _launching = true);
    try {
      final url = await _billingApi.createCheckoutSession(
        tier: widget.tier,
        accessToken: session.accessToken,
      );
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      _pollForUpgrade();
    } on BillingException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  /// Checkout happens in the external browser, so the app has no direct
  /// signal for when payment completes — poll `/v1/auth/me` for a bit so
  /// the tier updates automatically once Stripe redirects to the success
  /// page (which persists the new tier server-side).
  void _pollForUpgrade() {
    _pollTimer?.cancel();
    var attempts = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      attempts++;
      try {
        final user = await ref.refresh(currentUserProvider.future);
        if (user.tier != SubscriptionTier.free) {
          timer.cancel();
        }
      } catch (_) {
        // Keep polling through transient network errors.
      }
      if (attempts >= 40) timer.cancel(); // ~2 minutes
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final name = widget.name;
    final price = widget.price;
    final features = widget.features;
    final highlighted = widget.highlighted;
    final current = widget.current;
    return CroplooCard(
      borderColor: highlighted ? theme.accent : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(name, style: CroplooText.label),
              const Spacer(),
              if (highlighted)
                Text('★ POPULAR',
                    style: CroplooText.label
                        .copyWith(fontSize: 9, color: theme.accent)),
            ],
          ),
          const SizedBox(height: 8),
          Text(price, style: CroplooText.dataLarge),
          const SizedBox(height: 16),
          for (final f in features)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(PhosphorIconsRegular.check,
                      size: 14, color: theme.accent),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(f,
                          style: CroplooText.body.copyWith(fontSize: 12))),
                ],
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: current
                ? CroplooButton(
                    label: 'Current Plan',
                    variant: CroplooButtonVariant.secondary,
                    onPressed: null,
                  )
                : CroplooButton(
                    label: _launching ? 'Opening checkout…' : 'Get $name',
                    variant: highlighted
                        ? CroplooButtonVariant.primary
                        : CroplooButtonVariant.secondary,
                    onPressed: _launching ? null : _startCheckout,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Referral rewards: 1 month of Pro-plan-equivalent Stripe credit per
/// referred user who converts to paid — real customer-balance credit
/// applied automatically to the next invoice (see backend/src/referrals.js),
/// not a promotional label.
class _ReferralSettings extends ConsumerWidget {
  const _ReferralSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final summary = ref.watch(referralSummaryProvider);
    return summary.when(
      loading: () => const SizedBox(height: 60, child: CroplooLoader()),
      error: (e, _) => Text('Error loading referrals', style: CroplooText.body),
      data: (data) => CroplooCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your referral code', style: CroplooText.label),
                      const SizedBox(height: 6),
                      Text(data.code,
                          style: CroplooText.dataLarge.copyWith(letterSpacing: 2)),
                    ],
                  ),
                ),
                CroplooButton(
                  label: 'Copy',
                  variant: CroplooButtonVariant.secondary,
                  expanded: false,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: data.code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Referral code copied.')),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'New users enter this as "Referral code" when they sign up. '
              'When one of them subscribes to a paid plan, you get a month of '
              'that plan credited to your account.',
              style: CroplooText.body.copyWith(fontSize: 12, color: theme.textSecondary),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _statBlock(theme, '${data.signups.length}', 'REFERRED'),
                const SizedBox(width: 32),
                _statBlock(theme, '${data.credits.length}', 'CONVERTED'),
                const SizedBox(width: 32),
                _statBlock(
                    theme,
                    '\$${(data.totalCreditCents / 100).toStringAsFixed(2)}',
                    'CREDITED'),
              ],
            ),
            if (data.signups.isNotEmpty) ...[
              const SizedBox(height: 16),
              Divider(color: theme.bgBorder),
              const SizedBox(height: 8),
              for (final s in data.signups)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text('@${s.username}',
                              style: CroplooText.body.copyWith(fontSize: 13))),
                      Text(
                        s.subscriptionTier == 'free' ? 'Free' : s.subscriptionTier.toUpperCase(),
                        style: CroplooText.dataSmall.copyWith(
                            color: s.subscriptionTier == 'free'
                                ? theme.textSecondary
                                : theme.positive),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statBlock(CroplooTheme theme, String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: CroplooText.dataLarge),
        const SizedBox(height: 2),
        Text(label, style: CroplooText.label.copyWith(fontSize: 9)),
      ],
    );
  }
}

const _targetSymbols = [
  CroplooDropdownItem(value: 'ZC', label: 'Corn'),
  CroplooDropdownItem(value: 'ZS', label: 'Soybeans'),
  CroplooDropdownItem(value: 'ZW', label: 'Wheat'),
];

/// "Sell corn above $5.20" — tracked against real futures_prices;
/// alertsEngine.js fires once, then deactivates the target.
class _PriceTargetsSettings extends ConsumerWidget {
  const _PriceTargetsSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final targets = ref.watch(priceTargetsProvider).valueOrNull ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final t in targets)
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
                          '${t.symbol} ${t.direction.toLowerCase()} \$${Fmt.price(t.targetPrice)}',
                          style: CroplooText.bodyStrong,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t.triggeredAt != null
                              ? 'Triggered ${Fmt.timeAgo(t.triggeredAt!)}'
                              : (t.isActive ? 'Watching' : 'Inactive'),
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
                        ref.read(priceTargetsProvider.notifier).remove(t.id),
                  ),
                ],
              ),
            ),
          ),
        CroplooButton(
          label: '+ New Price Target',
          expanded: false,
          variant: CroplooButtonVariant.secondary,
          onPressed: () => _showAddDialog(context, ref, theme),
        ),
      ],
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref, CroplooTheme theme) {
    var symbol = 'ZC';
    var direction = 'ABOVE';
    final priceController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
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
                      Text('NEW PRICE TARGET', style: CroplooText.h3),
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
                    value: symbol,
                    items: _targetSymbols,
                    onChanged: (v) => setState(() => symbol = v),
                  ),
                  const SizedBox(height: 16),
                  Text('Direction',
                      style: CroplooText.label.copyWith(color: theme.textSecondary)),
                  const SizedBox(height: 6),
                  CroplooDropdown<String>(
                    value: direction,
                    items: const [
                      CroplooDropdownItem(value: 'ABOVE', label: 'Sell above'),
                      CroplooDropdownItem(value: 'BELOW', label: 'Buy below'),
                    ],
                    onChanged: (v) => setState(() => direction = v),
                  ),
                  const SizedBox(height: 16),
                  Text('Target Price (\$)',
                      style: CroplooText.label.copyWith(color: theme.textSecondary)),
                  const SizedBox(height: 6),
                  CroplooTextField(
                    controller: priceController,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                          final price = double.tryParse(priceController.text);
                          if (price == null) return;
                          ref.read(priceTargetsProvider.notifier).add(
                                symbol: symbol,
                                targetPrice: price,
                                direction: direction,
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
        ),
      ),
    );
  }
}

class _NotificationSettings extends ConsumerStatefulWidget {
  const _NotificationSettings();

  @override
  ConsumerState<_NotificationSettings> createState() => _NotificationSettingsState();
}

class _NotificationSettingsState extends ConsumerState<_NotificationSettings> {
  bool inApp = true;

  @override
  Widget build(BuildContext context) {
    final desktopNotifications = ref.watch(
      themeSettingsProvider.select((settings) => settings.desktopNotifications),
    );
    return CroplooListGroup(
      children: [
        CroplooListItem(
          title: 'In-app alerts',
          subtitle: 'Bell badge and alert feed',
          trailing: CroplooSwitch(
            value: inApp,
            onChanged: (v) => setState(() => inApp = v),
          ),
        ),
        const _DailyBriefEmailToggle(),
        CroplooListItem(
          title: 'Desktop push',
          subtitle: 'Native notifications for new market alerts',
          trailing: CroplooSwitch(
            value: desktopNotifications,
            onChanged: (value) => ref
                .read(themeSettingsProvider.notifier)
                .setDesktopNotifications(value),
          ),
        ),
      ],
    );
  }
}

/// Unlike the other two toggles above (still local-only placeholders),
/// this one is real end-to-end: it's the opt-out for the 7:30am ET
/// Morning Brief email (see backend/src/dailyBriefEmail.js), persisted
/// on the user's account.
class _DailyBriefEmailToggle extends ConsumerWidget {
  const _DailyBriefEmailToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    return CroplooListItem(
      title: 'Morning Brief email',
      subtitle: 'Daily at 7:30am ET, even if you don\'t open the app',
      trailing: CroplooSwitch(
        value: user?.dailyBriefEmail ?? true,
        onChanged: user == null
            ? null
            : (v) async {
                await ref.read(repositoryProvider).setDailyBriefEmail(v);
                ref.invalidate(currentUserProvider);
              },
      ),
    );
  }
}

class _AppearanceSettings extends ConsumerWidget {
  const _AppearanceSettings();

  static const _accents = [
    Colors.white,
    Color(0xFF22C55E), // Green
    Color(0xFFEF4444), // Red
    Color(0xFF3B82F6), // Blue
    Color(0xFFA855F7), // Purple
    Color(0xFFF59E0B), // Amber
    Color(0xFF06B6D4), // Cyan
    Color(0xFFEC4899), // Pink
    Color(0xFF10B981), // Emerald
    Color(0xFFF97316), // Orange
    Color(0xFF6366F1), // Indigo
    Color(0xFF84CC16), // Lime
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeSettingsProvider);
    final notifier = ref.read(themeSettingsProvider.notifier);
    final theme = CroplooTheme.of(context);

    return CroplooListGroup(
      children: [
        CroplooListItem(
          title: 'Theme',
          subtitle: 'Choose light, dark, dark gray, light gray or system',
          trailing: CroplooSegmentedControl<CroplooBrightness>(
            values: CroplooBrightness.values,
            selected: settings.brightness,
            onChanged: notifier.setBrightness,
            labelBuilder: (b) => switch (b) {
              CroplooBrightness.light => 'Light',
              CroplooBrightness.dark => 'Dark',
              CroplooBrightness.darkGray => 'Dark Gray',
              CroplooBrightness.lightGray => 'Light Gray',
              CroplooBrightness.system => 'System',
            },
          ),
        ),
        CroplooListItem(
          title: 'Borders',
          subtitle: 'Show borders on containers and buttons',
          trailing: CroplooSwitch(
            value: settings.useBorders,
            onChanged: notifier.setUseBorders,
          ),
        ),
        CroplooListItem(
          title: 'App blur',
          subtitle: 'Enable blur effects throughout the app',
          trailing: CroplooSwitch(
            value: settings.useAppBlur,
            onChanged: notifier.setUseAppBlur,
          ),
        ),
        CroplooListItem(
          title: 'Custom cursor',
          subtitle: 'Animated dot + ring pointer, hides the system cursor',
          trailing: CroplooSwitch(
            value: settings.customCursor,
            onChanged: notifier.setCustomCursor,
          ),
        ),
        CroplooListItem(
          title: 'Price ticker',
          subtitle: 'Scrolling futures ticker at the top of the app',
          trailing: CroplooSwitch(
            value: settings.showTicker,
            onChanged: notifier.setShowTicker,
          ),
        ),
        CroplooListItem(
          title: 'Accent color',
          subtitle: 'Highlights, buttons, switches',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final color in _accents)
                GestureDetector(
                  onTap: () => notifier.setAccentColor(color),
                  child: Container(
                    width: 24,
                    height: 24,
                    margin: const EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.zero,
                      border: Border.all(
                        color: settings.accentColor == color
                            ? theme.textPrimary
                            : theme.border,
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        CroplooListItem(
          title: 'Window buttons',
          subtitle: 'macOS traffic lights or Windows icons',
          trailing: CroplooSegmentedControl<WindowControlStyle>(
            values: WindowControlStyle.values,
            selected: settings.windowControlStyle ?? WindowControlStyle.macos,
            onChanged: notifier.setWindowControlStyle,
            labelBuilder: (s) => switch (s) {
              WindowControlStyle.macos => 'macOS',
              WindowControlStyle.windows => 'Windows',
            },
          ),
        ),
        CroplooListItem(
          title: 'Window buttons position',
          subtitle: 'Left or right side of the sidebar',
          trailing: CroplooSegmentedControl<WindowControlAlignment>(
            values: WindowControlAlignment.values,
            selected: settings.windowControlAlignment ?? WindowControlAlignment.left,
            onChanged: notifier.setWindowControlAlignment,
            labelBuilder: (a) => switch (a) {
              WindowControlAlignment.left => 'Left',
              WindowControlAlignment.right => 'Right',
            },
          ),
        ),
      ],
    );
  }
}

class _RegionalSettings extends ConsumerWidget {
  const _RegionalSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeSettingsProvider);
    final notifier = ref.read(themeSettingsProvider.notifier);

    return CroplooListGroup(
      children: [
        CroplooListItem(
          title: 'Number format',
          subtitle: '1,234.56 (US) or 1.234,56 (European)',
          trailing: CroplooSegmentedControl<NumberFormatStyle>(
            values: NumberFormatStyle.values,
            selected: settings.numberFormatStyle,
            onChanged: notifier.setNumberFormatStyle,
            labelBuilder: (s) => switch (s) {
              NumberFormatStyle.us => '1,234.56',
              NumberFormatStyle.european => '1.234,56',
            },
          ),
        ),
        CroplooListItem(
          title: 'Distance unit',
          subtitle: 'Miles or kilometers',
          trailing: CroplooSegmentedControl<DistanceUnit>(
            values: DistanceUnit.values,
            selected: settings.distanceUnit,
            onChanged: notifier.setDistanceUnit,
            labelBuilder: (u) => switch (u) {
              DistanceUnit.miles => 'Miles',
              DistanceUnit.km => 'km',
            },
          ),
        ),
        CroplooListItem(
          title: 'Volume unit',
          subtitle: 'Gallons or liters',
          trailing: CroplooSegmentedControl<VolumeUnit>(
            values: VolumeUnit.values,
            selected: settings.volumeUnit,
            onChanged: notifier.setVolumeUnit,
            labelBuilder: (u) => switch (u) {
              VolumeUnit.gallons => 'Gallons',
              VolumeUnit.liters => 'Liters',
            },
          ),
        ),
        CroplooListItem(
          title: 'Temperature unit',
          subtitle: 'Celsius, Fahrenheit, or system default',
          trailing: CroplooSegmentedControl<TemperatureUnit>(
            values: TemperatureUnit.values,
            selected: settings.temperatureUnit,
            onChanged: notifier.setTemperatureUnit,
            labelBuilder: (u) => switch (u) {
              TemperatureUnit.celsius => '°C',
              TemperatureUnit.fahrenheit => '°F',
              TemperatureUnit.system => 'System',
            },
          ),
        ),
      ],
    );
  }
}

class _TeamSettings extends ConsumerWidget {
  const _TeamSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final theme = CroplooTheme.of(context);
    
    // For now, show a placeholder - the full implementation would call the team API
    return CroplooCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.usersThree, size: 20, color: theme.accent),
              const SizedBox(width: 12),
              Text('Team Member', style: CroplooText.bodyStrong),
              const Spacer(),
              if (user?.teamRole != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.settings.useBorders ? theme.accent.withValues(alpha: 0.5) : Colors.transparent),
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Text(
                    user?.teamRole?.toUpperCase() ?? 'MEMBER',
                    style: CroplooText.label.copyWith(fontSize: 9, color: theme.accent),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'You are part of a team plan. Team management features are coming soon.',
            style: CroplooText.body.copyWith(fontSize: 13, color: theme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ApiKeysSettings extends ConsumerStatefulWidget {
  const _ApiKeysSettings();

  @override
  ConsumerState<_ApiKeysSettings> createState() => _ApiKeysSettingsState();
}

class _ApiKeysSettingsState extends ConsumerState<_ApiKeysSettings> {
  bool _creating = false;
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createKey() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _creating = true);
    try {
      // TODO: Call API to create key
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API key created (placeholder)')),
      );
      _nameController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    
    return CroplooCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.plugsConnected, size: 20, color: theme.accent),
              const SizedBox(width: 12),
              Text('API Keys', style: CroplooText.bodyStrong),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Generate API keys to access Croploo data programmatically. Include the key in the X-API-Key header.',
            style: CroplooText.body.copyWith(fontSize: 13, color: theme.textSecondary),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: CroplooTextField(
                  controller: _nameController,
                  hintText: 'Key name (e.g., "Production")',
                ),
              ),
              const SizedBox(width: 12),
              CroplooButton(
                label: _creating ? 'Creating...' : 'Create Key',
                onPressed: _creating ? null : _createKey,
                expanded: false,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Your API keys will appear here. API access is available on Desk, Team, and Institutional plans.',
            style: CroplooText.body.copyWith(fontSize: 12, color: theme.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// croploo.app/u/&lt;username&gt; — public profile toggle. No public web
/// frontend exists in this repo yet to actually render that page; this
/// section just manages the backend-side settings for when one does.
class _PublicProfileSettings extends ConsumerStatefulWidget {
  const _PublicProfileSettings();

  @override
  ConsumerState<_PublicProfileSettings> createState() => _PublicProfileSettingsState();
}

class _PublicProfileSettingsState extends ConsumerState<_PublicProfileSettings> {
  final _usernameController = TextEditingController();
  bool _isPublic = false;
  bool _saving = false;
  bool _hydrated = false;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).savePublicProfile(
            username: username,
            isPublic: _isPublic,
            trackedCommodities: const ['CORN', 'WHEAT', 'SOYBEANS'],
          );
      ref.invalidate(myPublicProfileProvider);
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
    final theme = CroplooTheme.of(context);
    final profile = ref.watch(myPublicProfileProvider);

    return profile.when(
      loading: () => const SizedBox(height: 60, child: CroplooLoader()),
      error: (e, _) => Text('Error', style: CroplooText.body),
      data: (p) {
        if (!_hydrated) {
          _hydrated = true;
          _usernameController.text = p?.username ?? '';
          _isPublic = p?.isPublic ?? false;
        }
        return CroplooCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: CroplooTextField(
                      controller: _usernameController,
                      hintText: 'username',
                      prefixText: 'croploo.app/u/',
                    ),
                  ),
                  const SizedBox(width: 12),
                  CroplooSwitch(
                    value: _isPublic,
                    onChanged: (v) => setState(() => _isPublic = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    _isPublic
                        ? 'Public — anyone with the link can see your tracked commodities and shared insights.'
                        : 'Private — your profile is not visible to anyone.',
                    style: CroplooText.body.copyWith(fontSize: 12, color: theme.textMuted),
                  ),
                  const Spacer(),
                  CroplooButton(
                    label: _saving ? 'Saving…' : 'Save',
                    expanded: false,
                    onPressed: _saving ? null : _save,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Free weekly digest, no Croploo account required to subscribe — this
/// toggle subscribes the signed-in user's own account email.
class _NewsletterSettings extends ConsumerStatefulWidget {
  const _NewsletterSettings();

  @override
  ConsumerState<_NewsletterSettings> createState() => _NewsletterSettingsState();
}

class _NewsletterSettingsState extends ConsumerState<_NewsletterSettings> {
  bool _subscribing = false;
  bool _subscribed = false;

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final user = ref.watch(currentUserProvider).valueOrNull;
    return CroplooCard(
      child: Row(
        children: [
          Expanded(
            child: Text(
              'The 5 most important commodity signals of the week, generated by CullyAI '
              'from real market data — every Monday.',
              style: CroplooText.body.copyWith(color: theme.textMuted),
            ),
          ),
          const SizedBox(width: 16),
          CroplooButton(
            label: _subscribed ? 'Subscribed' : (_subscribing ? 'Subscribing…' : 'Subscribe'),
            expanded: false,
            onPressed: (_subscribed || _subscribing || user?.email == null)
                ? null
                : () async {
                    setState(() => _subscribing = true);
                    try {
                      await ref.read(repositoryProvider).newsletterSubscribe(user!.email);
                      if (mounted) setState(() => _subscribed = true);
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('$e')));
                      }
                    } finally {
                      if (mounted) setState(() => _subscribing = false);
                    }
                  },
          ),
        ],
      ),
    );
  }
}
