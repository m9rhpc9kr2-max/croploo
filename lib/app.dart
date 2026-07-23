import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/cursor/cursor_hover.dart';
import 'core/cursor/cursor_overlay.dart';
import 'core/notifications/alert_notification_service.dart';
import 'core/theme/theme.dart';
import 'core/theme/theme_colors.dart';
import 'core/theme/theme_providers.dart';
import 'core/utils/formatters.dart';
import 'features/alerts/alerts_screen.dart';
import 'features/basis/basis_detail_screen.dart';
import 'features/basis/basis_screen.dart';
import 'features/analytics/analytics_screen.dart';
import 'features/audit/audit_screen.dart';
import 'features/community/community_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/energy/energy_screen.dart';
import 'features/freight/freight_screen.dart';
import 'features/intel/intel_screen.dart';
import 'features/macro/macro_screen.dart';
import 'features/markets/markets_screen.dart';
import 'features/portfolio/portfolio_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/settings/watchlist_screen.dart';
import 'features/status/status_screen.dart';
import 'features/usda/usda_screen.dart';
import 'shared/widgets/croploo_scaffold.dart';
import 'shared/widgets/paywall_gate.dart';

/// Custom page transition: the page itself stays solid (opaque background) while
/// the child content slides in from the side and fades from transparent.
CustomTransitionPage<T> _croplooPage<T>({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 360),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final theme = CroplooTheme.of(context);
      final slide = Tween<Offset>(
        begin: const Offset(0.035, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      ));
      final fade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: animation,
          curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
        ),
      );
      // Solid backdrop prevents the previous page from showing through.
      return Container(
        color: theme.bgPrimary,
        child: SlideTransition(
          position: slide,
          child: FadeTransition(
            opacity: fade,
            child: child,
          ),
        ),
      );
    },
  );
}

GoRouter _buildRouter(String initialLocation, {bool standalone = false}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    ShellRoute(
      builder: (context, state, child) => CroplooScaffold(
        showSidebar: !standalone,
        showCullyPanel: !standalone,
        child: PaywallGate(path: state.uri.path, child: child),
      ),
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) =>
              _croplooPage(context: context, state: state, child: const DashboardScreen()),
        ),
        GoRoute(
          path: '/basis',
          pageBuilder: (context, state) =>
              _croplooPage(context: context, state: state, child: const BasisScreen()),
          routes: [
            GoRoute(
              path: 'detail/:elevatorId/:commodity',
              pageBuilder: (context, state) => _croplooPage(
                context: context,
                state: state,
                child: BasisDetailScreen(
                  elevatorId:
                      int.parse(state.pathParameters['elevatorId']!),
                  commodity: state.pathParameters['commodity']!,
                ),
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/usda',
          pageBuilder: (context, state) =>
              _croplooPage(context: context, state: state, child: const UsdaScreen()),
        ),
        GoRoute(
          path: '/freight',
          pageBuilder: (context, state) =>
              _croplooPage(context: context, state: state, child: const FreightScreen()),
        ),
        GoRoute(
          path: '/intel',
          pageBuilder: (context, state) =>
              _croplooPage(context: context, state: state, child: const IntelScreen()),
        ),
        GoRoute(
          path: '/analytics',
          pageBuilder: (context, state) =>
              _croplooPage(context: context, state: state, child: const AnalyticsScreen()),
        ),
        GoRoute(
          path: '/markets',
          pageBuilder: (context, state) =>
              _croplooPage(context: context, state: state, child: const MarketsScreen()),
        ),
        GoRoute(
          path: '/energy',
          pageBuilder: (context, state) =>
              _croplooPage(context: context, state: state, child: const EnergyScreen()),
        ),
        GoRoute(
          path: '/macro',
          pageBuilder: (context, state) =>
              _croplooPage(context: context, state: state, child: const MacroScreen()),
        ),
        GoRoute(
          path: '/community',
          pageBuilder: (context, state) =>
              _croplooPage(context: context, state: state, child: const CommunityScreen()),
        ),
        GoRoute(
          path: '/audit',
          pageBuilder: (context, state) =>
              _croplooPage(context: context, state: state, child: const AuditScreen()),
        ),
        GoRoute(
          path: '/alerts',
          pageBuilder: (context, state) =>
              _croplooPage(context: context, state: state, child: const AlertsScreen()),
        ),
        GoRoute(
          path: '/watchlist',
          pageBuilder: (context, state) =>
              _croplooPage(context: context, state: state, child: const WatchlistScreen()),
        ),
        GoRoute(
          path: '/portfolio',
          pageBuilder: (context, state) =>
              _croplooPage(context: context, state: state, child: const PortfolioScreen()),
        ),
        GoRoute(
          path: '/status',
          pageBuilder: (context, state) =>
              _croplooPage(context: context, state: state, child: const StatusScreen()),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) =>
              _croplooPage(context: context, state: state, child: const SettingsScreen()),
        ),
      ],
    ),
  ],
);

class CroplooApp extends ConsumerStatefulWidget {
  const CroplooApp({
    super.key,
    this.initialLocation = '/',
    this.standalone = false,
  });

  /// Where this window's router starts — '/' for the primary dashboard
  /// window, or a specific route when opened via a sidebar item's
  /// "Open in New Window" (see `main.dart`'s `kind: 'route'` payload).
  final String initialLocation;

  /// True for a popped-out single-page window: no sidebar, no CullyAI
  /// panel, just the page itself with a minimal title bar.
  final bool standalone;

  @override
  ConsumerState<CroplooApp> createState() => _CroplooAppState();
}

class _CroplooAppState extends ConsumerState<CroplooApp> {
  // Built once per window/isolate rather than per build, so navigation
  // state isn't reset every time an unrelated provider (e.g. theme
  // settings) triggers a rebuild.
  late final GoRouter _router =
      _buildRouter(widget.initialLocation, standalone: widget.standalone);

  @override
  Widget build(BuildContext context) {
    // Window-control style/alignment don't affect colors, so only rebuild
    // the whole app's theme (and everything under it) when a field that
    // actually feeds CroplooTheme.fromSettings changes — otherwise toggling
    // those settings would force a full app-wide theme rebuild.
    ref.watch(alertNotificationServiceProvider);
    final settings = ref.watch(themeSettingsProvider);
    // Sync formatting preferences (number format, units) into Fmt so all
    // existing call sites pick them up automatically.
    Fmt.configure(settings);
    CursorHover.enabled = settings.customCursor;
    final croplooTheme = CroplooTheme.fromSettings(settings);
    return MaterialApp.router(
      title: 'Croploo — The basis for better trades.',
      debugShowCheckedModeBanner: false,
      theme: buildCroplooTheme(croplooTheme),
      routerConfig: _router,
      builder: (context, child) => CursorOverlay(
        background: croplooTheme.bgSurface,
        enabled: settings.customCursor,
        child: child!,
      ),
    );
  }
}
