import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_colors.dart';
import '../../core/theme/theme_providers.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/providers.dart';
import '../../features/cullyai/cullyai_panel.dart';
import 'basis_ticker.dart';
import 'croploo_shortcuts.dart';
import 'sidebar_nav.dart';
import 'window_controls.dart';

/// App shell: ticker on top, sidebar left, CullyAI panel right. Below
/// [_mobileBreakpoint] the fixed 240px sidebar (designed for desktop
/// window widths) collapses into a drawer behind a menu button instead
/// — the minimum viable "simplified mobile layout": every screen still
/// works, just reachable via a hamburger menu rather than an
/// always-visible rail. This is Dart-only groundwork; there's no iOS/
/// Android platform target in this repo yet (only linux/macos/windows/
/// web), so it can't actually run on a phone until `flutter create
/// --platforms=ios,android .` is run and each platform is set up with
/// its own signing/build toolchain.
const _mobileBreakpoint = 700.0;

class CroplooScaffold extends ConsumerWidget {
  final Widget child;
  final bool showCullyPanel;
  /// False for a sidebar item popped out into its own window (see
  /// `_NavTile._openInNewWindow` in sidebar_nav.dart and `CroplooApp`'s
  /// `standalone` flag) — that window shows only the page itself, with a
  /// minimal title bar standing in for the window controls the sidebar
  /// would otherwise host.
  final bool showSidebar;

  const CroplooScaffold({
    super.key,
    required this.child,
    this.showCullyPanel = true,
    this.showSidebar = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width > 1100;
    final mobile = width < _mobileBreakpoint;
    final offlineSince = ref.watch(offlineSinceProvider);
    final showTicker = ref.watch(themeSettingsProvider.select((s) => s.showTicker));
    return CroplooShortcuts(
      child: Scaffold(
        drawer: (mobile && showSidebar) ? const Drawer(width: 240, child: SidebarNav()) : null,
        body: Column(
          children: [
            if (offlineSince != null) _OfflineBanner(since: offlineSince),
            if (!showSidebar) const _StandaloneTitleBar(),
            if (mobile && showSidebar) const _MobileTopBar(),
            if (showTicker) const BasisTicker(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!mobile && showSidebar) const SidebarNav(),
                  Expanded(child: child),
                  if (showCullyPanel && wide && showSidebar) const CullyAiPanel(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stand-in for the sidebar's window controls, shown only in a
/// [CroplooScaffold] with `showSidebar: false` (a nav item popped out into
/// its own window — see [CroplooScaffold.showSidebar]).
class _StandaloneTitleBar extends StatelessWidget {
  const _StandaloneTitleBar();

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return Container(
      color: theme.bgPrimary,
      child: Row(
        children: [
          const WindowControls(),
          const Expanded(child: WindowDragArea()),
        ],
      ),
    );
  }
}

class _MobileTopBar extends StatelessWidget {
  const _MobileTopBar();

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return Container(
      height: 48,
      color: theme.bgPrimary,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Builder(
            builder: (ctx) => IconButton(
              icon: Icon(PhosphorIconsRegular.list, color: theme.textPrimary),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
          Text('CROPLOO',
              style: CroplooText.label.copyWith(
                  fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 2)),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  final DateTime since;

  const _OfflineBanner({required this.since});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return Container(
      width: double.infinity,
      color: theme.accentDim,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIconsRegular.cloudSlash, size: 14, color: theme.accent),
          const SizedBox(width: 8),
          Text(
            'Offline — showing cached data as of ${Fmt.date(since)} ${Fmt.timeShort(since)}',
            style: CroplooText.dataSmall.copyWith(color: theme.accent),
          ),
        ],
      ),
    );
  }
}
