import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/cursor/cursor_hover.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/theme/theme_providers.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/desktop_platform.dart';
import '../../data/providers.dart';
import '../../features/auth/auth_session.dart';
import '../models/models.dart';
import 'common.dart';
import 'window_controls.dart';

class _NavItem {
  final String label;
  final IconData icon;
  final String route;
  final bool pro;

  const _NavItem(this.label, this.icon, this.route, {this.pro = false});
}

class _NavGroup {
  final String label;
  final List<_NavItem> items;

  const _NavGroup(this.label, this.items);
}

// Mirrors the pricing tiers: Commodities (Basic+), Energy & Market Intel
// (Pro+), Markets & Macro (Desk+) — see PaywallGate/TierGate for the
// per-screen tier checks.
const _navGroups = [
  _NavGroup('Markets', [
    _NavItem('Markets', PhosphorIconsRegular.chartLine, '/markets', pro: true),
    _NavItem('Analytics', PhosphorIconsRegular.chartPie, '/analytics', pro: true),
  ]),
  _NavGroup('Commodities', [
    _NavItem('Dashboard', PhosphorIconsRegular.layout, '/'),
    _NavItem('Basis Monitor', PhosphorIconsRegular.chartBar, '/basis'),
    _NavItem('USDA Analyzer', PhosphorIconsRegular.fileText, '/usda'),
    _NavItem('Market Intel', PhosphorIconsRegular.brain, '/intel', pro: true),
    _NavItem('Freight', PhosphorIconsRegular.truck, '/freight', pro: true),
  ]),
  _NavGroup('Energy', [
    _NavItem('Energy', PhosphorIconsRegular.batteryCharging, '/energy', pro: true),
  ]),
  _NavGroup('Macro', [
    _NavItem('Macro', PhosphorIconsRegular.mapTrifold, '/macro', pro: true),
  ]),
];

const _secondaryItems = [
  _NavItem('Alerts', PhosphorIconsRegular.notification, '/alerts'),
  _NavItem('Watchlist', PhosphorIconsRegular.heartStraight, '/watchlist'),
  _NavItem('Portfolio', PhosphorIconsRegular.briefcase, '/portfolio'),
  _NavItem('Audit Trail', PhosphorIconsRegular.scroll, '/audit'),
  _NavItem('Community', PhosphorIconsRegular.usersThree, '/community'),
  _NavItem('Status', PhosphorIconsRegular.pulse, '/status'),
  _NavItem('Settings', PhosphorIconsRegular.sliders, '/settings'),
];

/// All nav items across both groups and the secondary list, keyed by
/// route — used to look up a hidden item's label/icon for the "manage
/// hidden items" menu without needing a separate registry.
final _allNavItemsByRoute = {
  for (final group in _navGroups)
    for (final item in group.items) item.route: item,
  for (final item in _secondaryItems) item.route: item,
};

/// Left navigation sidebar — 240px, logo, nav items, user footer.
class SidebarNav extends ConsumerWidget {
  const SidebarNav({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;
    final unread = ref.watch(unreadAlertCountProvider);
    final user = ref.watch(currentUserProvider).valueOrNull;
    final theme = CroplooTheme.of(context);
    final hiddenRoutes = ref.watch(
      themeSettingsProvider.select((s) => s.hiddenNavRoutes),
    );

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: theme.bgPrimary,
        border: Border(right: BorderSide(color: theme.border)),
      ),
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Window controls (macOS traffic lights replacement)
              const WindowControls(),
              // Draggable area for window movement
              const WindowDragArea(),
              if (hiddenRoutes.isNotEmpty) _HiddenItemsBar(hiddenRoutes: hiddenRoutes),
              Divider(color: theme.border),
              const SizedBox(height: 12),
              for (final group in _navGroups) ...[
                if (group.items.any((item) => !hiddenRoutes.contains(item.route))) ...[
                  _NavGroupHeader(label: group.label),
                  for (final item in group.items)
                    if (!hiddenRoutes.contains(item.route))
                      _NavTile(item: item, selected: location == item.route),
                  const SizedBox(height: 8),
                ],
              ],
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Divider(color: theme.border),
              ),
              const SizedBox(height: 12),
              for (final item in _secondaryItems)
                if (!hiddenRoutes.contains(item.route))
                  _NavTile(
                    item: item,
                    selected: location == item.route,
                    badge: item.route == '/alerts' && unread > 0 ? unread : null,
                  ),
              const SizedBox(height: 32),
              Divider(color: theme.border),
              // User footer
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.bgElevated,
                        borderRadius: BorderRadius.zero,
                      ),
                      child: Text(
                        (user?.name.isNotEmpty ?? false)
                            ? user!.name[0].toUpperCase()
                            : '·',
                        style: CroplooText.bodyStrong.copyWith(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        user?.name ?? '—',
                        style: CroplooText.bodyStrong.copyWith(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TierBadge(tier: user?.tier ?? SubscriptionTier.free),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown above the nav list when one or more items are hidden (via a nav
/// tile's right-click "Hide" menu item). Tapping it opens a menu listing
/// each hidden item individually (tap to unhide) plus a "Show all" action.
class _HiddenItemsBar extends ConsumerWidget {
  const _HiddenItemsBar({required this.hiddenRoutes});

  final Set<String> hiddenRoutes;

  Future<void> _openMenu(BuildContext context, WidgetRef ref, Offset position) async {
    final notifier = ref.read(themeSettingsProvider.notifier);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selection = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final route in hiddenRoutes)
          PopupMenuItem(
            value: route,
            child: Text(_allNavItemsByRoute[route]?.label ?? route),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: '__show_all__', child: Text('Show all')),
      ],
    );
    if (selection == null) return;
    if (selection == '__show_all__') {
      notifier.showAllNavRoutes();
    } else {
      notifier.showNavRoute(selection);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: GestureDetector(
        onTapUp: (details) => _openMenu(context, ref, details.globalPosition),
        child: MouseRegion(
          cursor: CursorHover.enabled ? SystemMouseCursors.none : SystemMouseCursors.click,
          onEnter: (_) => CursorHover.enter(),
          onExit: (_) => CursorHover.exit(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIconsRegular.eyeSlash, size: 12, color: theme.textMuted),
              const SizedBox(width: 6),
              Text(
                '${hiddenRoutes.length} hidden · Show',
                style: CroplooText.label.copyWith(fontSize: 10, color: theme.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small uppercase group label above each nav-item cluster (Markets,
/// Commodities, Energy, Macro).
class _NavGroupHeader extends StatelessWidget {
  final String label;

  const _NavGroupHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: CroplooText.label.copyWith(fontSize: 9, color: theme.textMuted, letterSpacing: 1.2),
      ),
    );
  }
}

class _NavTile extends ConsumerWidget {
  final _NavItem item;
  final bool selected;
  final int? badge;

  const _NavTile({required this.item, required this.selected, this.badge});

  Future<void> _openInNewWindow(WidgetRef ref) async {
    final session = ref.read(authSessionProvider);
    final payload = jsonEncode({
      'kind': 'route',
      'path': item.route,
      if (session != null) ...{
        'accessToken': session.accessToken,
        'email': session.email,
        'username': session.username,
        'name': session.name,
      },
    });
    final controller = await DesktopMultiWindow.createWindow(payload);
    // Below this, AppDelegate.swift's shared `minimumWindowSize` (see
    // `windowDidResize`) would immediately snap the frame back up anyway —
    // matching it here avoids that jarring post-creation resize.
    await controller.setFrame(const Rect.fromLTWH(0, 0, 1600, 900));
    await controller.center();
    await controller.setTitle('Croploo — ${item.label}');
    await controller.show();
  }

  Future<void> _openContextMenu(BuildContext context, WidgetRef ref, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selection = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        if (supportsMultiWindow)
          const PopupMenuItem(value: 'window', child: Text('Open in New Window')),
        const PopupMenuItem(value: 'hide', child: Text('Hide')),
      ],
    );
    switch (selection) {
      case 'window':
        await _openInNewWindow(ref);
      case 'hide':
        ref.read(themeSettingsProvider.notifier).hideNavRoute(item.route);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected ? theme.accentDim : theme.bgSurface,
        borderRadius: BorderRadius.zero,
        child: InkWell(
          borderRadius: BorderRadius.zero,
          hoverColor: theme.bgElevated,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          mouseCursor: CursorHover.enabled ? SystemMouseCursors.none : SystemMouseCursors.click,
          onHover: (hovering) => hovering ? CursorHover.enter() : CursorHover.exit(),
          onTap: () => context.go(item.route),
          onSecondaryTapUp: (details) =>
              _openContextMenu(context, ref, details.globalPosition),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 18,
                  color: selected
                      ? theme.accent
                      : theme.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    style: CroplooText.bodyStrong.copyWith(
                      fontSize: 13,
                      color: selected
                          ? theme.textPrimary
                          : theme.textSecondary,
                    ),
                  ),
                ),
                const Spacer(),
                if (item.pro || badge != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item.pro)
                        Text('PRO',
                            style: CroplooText.label
                                .copyWith(fontSize: 8, color: theme.accent)),
                      if (item.pro && badge != null)
                        const SizedBox(width: 4),
                      if (badge != null)
                        Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: theme.accent,
                            borderRadius: BorderRadius.zero,
                          ),
                          child: Text(
                            '$badge',
                            style: CroplooText.dataSmall
                                .copyWith(color: theme.contrastColor(theme.accent), fontSize: 10),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
