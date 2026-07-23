import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/theme/theme_colors.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/providers.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/controls.dart';
import 'basis_chart.dart';

// `grid` is the original zero-network stylized scatter; `map` is a real
// pannable/zoomable OpenStreetMap view added alongside it — both stay,
// switchable via the view toggle.
enum BasisView { grid, map, list, chart }

final _viewProvider = StateProvider<BasisView>((ref) => BasisView.list);
// Empty set = no filter applied (all states). Multi-select.
final _stateFilterProvider = StateProvider<Set<String>>((ref) => {});
final _extremesOnlyProvider = StateProvider<bool>((ref) => false);
final _chartSelectionProvider = StateProvider<int?>((ref) => null);

class BasisScreen extends ConsumerWidget {
  const BasisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(_viewProvider);
    final theme = CroplooTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 16),
          child: Row(
            children: [
              Text('BASIS MONITOR', style: CroplooText.h2),
              const SizedBox(width: 32),
              _ViewToggle(view: view),
              const Spacer(),
              const _CommodityDropdown(),
              const SizedBox(width: 12),
              const _StateDropdown(),
              const SizedBox(width: 12),
              const _ExtremesToggle(),
            ],
          ),
        ),
        Divider(color: theme.bgBorder),
        Expanded(
          child: switch (view) {
            BasisView.grid => const _BasisMapView(),
            BasisView.map => const _BasisRealMapView(),
            BasisView.list => const _BasisListView(),
            BasisView.chart => const _BasisChartView(),
          },
        ),
      ],
    );
  }
}

// ── Filters ──────────────────────────────────────────────────────

final _filteredSnapshotsProvider = Provider<List<BasisSnapshot>>((ref) {
  final all = ref.watch(basisOverviewProvider).valueOrNull ?? const [];
  final commodity = ref.watch(commodityFilterProvider);
  final states = ref.watch(_stateFilterProvider);
  final extremesOnly = ref.watch(_extremesOnlyProvider);
  return all.where((s) {
    if (s.commodity.symbol != commodity) return false;
    if (states.isNotEmpty && !states.contains(s.elevator.state)) return false;
    if (extremesOnly && !s.isExtreme) return false;
    return true;
  }).toList()
    ..sort((a, b) =>
        b.deviationFromAvg.abs().compareTo(a.deviationFromAvg.abs()));
});

/// An elevator paired with its basis snapshot for the selected commodity,
/// if one exists yet — `snapshot == null` means the elevator is real
/// (shown on the map) but that state isn't wired to live USDA basis data
/// yet, so it renders as an explicit "no data" pin instead of vanishing.
class _MapPoint {
  final ElevatorLocation elevator;
  final BasisSnapshot? snapshot;
  const _MapPoint(this.elevator, this.snapshot);
}

final _mapPointsProvider = Provider<List<_MapPoint>>((ref) {
  final elevators = ref.watch(elevatorsProvider).valueOrNull ?? const [];
  final snapshots = ref.watch(_filteredSnapshotsProvider);
  final states = ref.watch(_stateFilterProvider);
  final extremesOnly = ref.watch(_extremesOnlyProvider);
  final byElevatorId = {for (final s in snapshots) s.elevator.id: s};

  return elevators
      .where((e) => states.isEmpty || states.contains(e.state))
      .where((e) => !extremesOnly || byElevatorId.containsKey(e.id))
      .map((e) => _MapPoint(e, byElevatorId[e.id]))
      .toList();
});

class _ViewToggle extends ConsumerWidget {
  final BasisView view;

  const _ViewToggle({required this.view});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.border),
        borderRadius: BorderRadius.zero,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final v in BasisView.values)
            InkWell(
              onTap: () => ref.read(_viewProvider.notifier).state = v,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: view == v ? theme.accentDim : theme.bgSurface,
                child: Text(
                  v.name.toUpperCase(),
                  style: CroplooText.label.copyWith(
                    fontSize: 11,
                    color: view == v
                        ? theme.accent
                        : theme.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CommodityDropdown extends ConsumerWidget {
  const _CommodityDropdown();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(commodityFilterProvider);
    return CroplooDropdown<String>(
      value: value,
      items: const [
        CroplooDropdownItem(value: 'ZC', label: 'Corn'),
        CroplooDropdownItem(value: 'ZS', label: 'Soybeans'),
        CroplooDropdownItem(value: 'ZW', label: 'Wheat (Soft Red Winter)'),
        CroplooDropdownItem(value: 'KE', label: 'Wheat (Hard Red Winter)'),
        CroplooDropdownItem(value: 'MWE', label: 'Wheat (Hard Red Spring)'),
      ],
      onChanged: (v) => ref.read(commodityFilterProvider.notifier).state = v,
    );
  }
}

// All states with at least one elevator in the directory — including
// ones without live basis data yet (see elevators.js), so the state
// filter can still narrow the map/list down to them.
const _kAllStateOptions = [
  ('IL', 'Illinois'), ('IA', 'Iowa'), ('MN', 'Minnesota'), ('IN', 'Indiana'),
  ('OH', 'Ohio'), ('KS', 'Kansas'), ('NE', 'Nebraska'),
  ('SD', 'South Dakota'), ('ND', 'North Dakota'), ('NC', 'North Carolina'),
  ('MO', 'Missouri'), ('WI', 'Wisconsin'), ('MI', 'Michigan'),
  ('KY', 'Kentucky'), ('AL', 'Alabama'), ('OK', 'Oklahoma'),
  ('TX', 'Texas'), ('LA', 'Louisiana'), ('AR', 'Arkansas'),
  ('TN', 'Tennessee'), ('WA', 'Washington'), ('OR', 'Oregon'),
  ('MT', 'Montana'), ('ID', 'Idaho'), ('MD', 'Maryland'),
  ('VA', 'Virginia'), ('CO', 'Colorado'),
];

/// Multi-select state filter. Built on [MenuAnchor] rather than
/// [CroplooDropdown] because selecting an item must NOT close the menu —
/// the user toggles as many states as they want, then dismisses it.
class _StateDropdown extends ConsumerStatefulWidget {
  const _StateDropdown();

  @override
  ConsumerState<_StateDropdown> createState() => _StateDropdownState();
}

class _StateDropdownState extends ConsumerState<_StateDropdown> {
  final _menuController = MenuController();

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final selected = ref.watch(_stateFilterProvider);
    final label = selected.isEmpty
        ? 'All States'
        : selected.length == 1
            ? (_kAllStateOptions
                    .where((s) => s.$1 == selected.first)
                    .firstOrNull
                    ?.$2 ??
                selected.first)
            : '${selected.length} States';

    return MenuAnchor(
      controller: _menuController,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(theme.bgElevated),
        elevation: const WidgetStatePropertyAll(0),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: theme.border),
        )),
      ),
      menuChildren: [
        SizedBox(
          width: 210,
          height: 340,
          child: ListView(
            shrinkWrap: true,
            children: [
              _StateCheckRow(
                label: 'All States',
                checked: selected.isEmpty,
                onTap: () => ref.read(_stateFilterProvider.notifier).state = {},
              ),
              Divider(height: 1, color: theme.bgBorder),
              for (final option in _kAllStateOptions)
                _StateCheckRow(
                  label: option.$2,
                  checked: selected.contains(option.$1),
                  onTap: () {
                    final next = {...selected};
                    if (!next.remove(option.$1)) next.add(option.$1);
                    ref.read(_stateFilterProvider.notifier).state = next;
                  },
                ),
            ],
          ),
        ),
      ],
      builder: (context, controller, child) => GestureDetector(
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(border: Border.all(color: theme.border)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style:
                      CroplooText.bodyStrong.copyWith(fontSize: 13)),
              const SizedBox(width: 6),
              Icon(PhosphorIconsRegular.caretDown,
                  size: 12, color: theme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _StateCheckRow extends StatelessWidget {
  final String label;
  final bool checked;
  final VoidCallback onTap;

  const _StateCheckRow(
      {required this.label, required this.checked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                border: Border.all(
                    color: checked ? theme.accent : theme.border),
                color: checked ? theme.accent : Colors.transparent,
              ),
              child: checked
                  ? Icon(PhosphorIconsRegular.check,
                      size: 10, color: theme.bgPrimary)
                  : null,
            ),
            const SizedBox(width: 8),
            Text(label, style: CroplooText.body.copyWith(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _ExtremesToggle extends ConsumerWidget {
  const _ExtremesToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(_extremesOnlyProvider);
    final theme = CroplooTheme.of(context);
    return GestureDetector(
      onTap: () => ref.read(_extremesOnlyProvider.notifier).state = !on,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: on ? theme.accentDim : theme.bgElevated,
          border: Border.all(
            color: on ? theme.accent : theme.border,
            width: 1,
          ),
          borderRadius: BorderRadius.zero,
        ),
        child: Text(
          'EXTREMES ONLY',
          style: CroplooText.bodyStrong.copyWith(
            fontSize: 13,
            color: on ? theme.accent : theme.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ── MAP VIEW ─────────────────────────────────────────────────────
// Stylized scatter projection of the Midwest (no external tiles —
// terminal aesthetic, zero network dependency).

class _BasisMapView extends ConsumerWidget {
  const _BasisMapView();

  // Continental US bounds (with a small margin) — was previously tuned
  // tight around the original 6-state Corn Belt cluster only, which
  // clipped every elevator added outside IL/IA/MN/IN/OH/KS off-screen.
  static const _minLat = 24.0, _maxLat = 49.5;
  static const _minLng = -125.0, _maxLng = -66.5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final points = ref.watch(_mapPointsProvider);
    final commodity = ref.watch(commodityFilterProvider);
    final theme = CroplooTheme.of(context);
    if (ref.watch(basisOverviewProvider).isLoading ||
        ref.watch(elevatorsProvider).isLoading) {
      return const CroplooLoader();
    }
    return Padding(
      padding: const EdgeInsets.all(32),
      child: CroplooCard(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(builder: (context, c) {
          return Stack(
            children: [
              // Grid backdrop
              CustomPaint(
                  size: Size(c.maxWidth, c.maxHeight),
                  painter: _MapGridPainter(theme: theme)),
              for (final p in points)
                Positioned(
                  left: (p.elevator.lng - _minLng) /
                          (_maxLng - _minLng) *
                          (c.maxWidth - 32) +
                      8,
                  top: (1 -
                              (p.elevator.lat - _minLat) /
                                  (_maxLat - _minLat)) *
                          (c.maxHeight - 32) +
                      8,
                  child: _MapDot(
                      elevator: p.elevator,
                      snapshot: p.snapshot,
                      commoditySymbol: commodity),
                ),
              Positioned(
                left: 8,
                bottom: 8,
                child: Row(
                  children: [
                    _legendDot(theme.negative, 'BELOW AVG'),
                    const SizedBox(width: 16),
                    _legendDot(theme.neutral, 'NEAR AVG'),
                    const SizedBox(width: 16),
                    _legendDot(theme.positive, 'ABOVE AVG'),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _legendDot(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.zero)),
          const SizedBox(width: 6),
          Text(label, style: CroplooText.label.copyWith(fontSize: 9)),
        ],
      );
}

class _MapGridPainter extends CustomPainter {
  final CroplooTheme theme;

  const _MapGridPainter({required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = theme.bgBorder.withValues(alpha: 0.5)
      ..strokeWidth = 0.5;
    for (var x = 0.0; x < size.width; x += 60) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += 60) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MapGridPainter oldDelegate) =>
      oldDelegate.theme != theme;
}

class _MapDot extends StatelessWidget {
  final ElevatorLocation elevator;
  final BasisSnapshot? snapshot;
  final String commoditySymbol;

  const _MapDot({
    required this.elevator,
    required this.commoditySymbol,
    this.snapshot,
  });

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final s = snapshot;

    if (s == null) {
      // Real elevator, no live USDA basis feed for this state yet — shown
      // as a small muted pin rather than hidden, so the map reflects the
      // full directory.
      return Tooltip(
        richMessage: TextSpan(
          children: [
            TextSpan(
                text: '${elevator.name}, ${elevator.state}\n',
                style: CroplooText.bodyStrong.copyWith(fontSize: 12)),
            TextSpan(
                text: 'No live basis data for this state yet',
                style: CroplooText.label.copyWith(fontSize: 9)),
          ],
        ),
        child: GestureDetector(
          onTap: () => context
              .go('/basis/detail/${elevator.id}/$commoditySymbol'),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: theme.textMuted.withValues(alpha: 0.6),
                borderRadius: BorderRadius.zero,
                border: Border.all(color: theme.textMuted, width: 0.5),
              ),
            ),
          ),
        ),
      );
    }

    final dev = s.deviationFromAvg;
    final color = dev.abs() < 8
        ? theme.neutral
        : (dev > 0 ? theme.positive : theme.negative);
    final size = 8.0 + (dev.abs() / 35 * 12).clamp(0, 12);
    return Tooltip(
      richMessage: TextSpan(
        children: [
          TextSpan(
              text: '${s.elevator.name}, ${s.elevator.state}\n',
              style: CroplooText.bodyStrong.copyWith(fontSize: 12)),
          TextSpan(
              text:
                  '${s.commodity.name.toUpperCase()} Basis: ${Fmt.basis(s.basisValue)}\n',
              style: CroplooText.dataSmall),
          TextSpan(
              text: '${Fmt.cents(dev)} vs 5yr avg\n',
              style: CroplooText.dataSmall.copyWith(color: color)),
          if (s.source != null)
            TextSpan(
                text:
                    'Basis data: ${s.source}, last updated: ${Fmt.date(s.snapshotDate)}',
                style: CroplooText.label.copyWith(fontSize: 9)),
        ],
      ),
      child: GestureDetector(
        onTap: () => context
            .go('/basis/detail/${s.elevator.id}/${s.commodity.symbol}'),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.75),
              borderRadius: BorderRadius.zero,
              border: Border.all(
                  color: s.isExtreme ? theme.accent : color,
                  width: s.isExtreme ? 1.5 : 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

// ── REAL MAP VIEW ────────────────────────────────────────────────
// Real pannable/zoomable US map (OpenStreetMap tiles via flutter_map) as
// an alternative to the stylized zero-network scatter above. Same
// color-by-deviation legend, tooltip and tap-to-select behavior.

class _BasisRealMapView extends ConsumerWidget {
  const _BasisRealMapView();

  static const _usCenter = ll.LatLng(39.5, -98.35);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final points = ref.watch(_mapPointsProvider);
    final commodity = ref.watch(commodityFilterProvider);
    final theme = CroplooTheme.of(context);
    if (ref.watch(basisOverviewProvider).isLoading ||
        ref.watch(elevatorsProvider).isLoading) {
      return const CroplooLoader();
    }
    return Padding(
      padding: const EdgeInsets.all(32),
      child: CroplooCard(
        padding: EdgeInsets.zero,
        child: ClipRect(
          child: Stack(
            children: [
              FlutterMap(
                options: const MapOptions(
                  initialCenter: _usCenter,
                  initialZoom: 4.2,
                  minZoom: 3,
                  maxZoom: 12,
                ),
                children: [
                  TileLayer(
                    // CartoDB's free, no-API-key basemaps — actual dark
                    // cartography (dark land/water, dim labels) in dark
                    // mode, not just a filter over daylight tiles, and
                    // switches live with the app's theme setting.
                    urlTemplate: theme.settings.isDark
                        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                        : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                    subdomains: const ['a', 'b', 'c', 'd'],
                    userAgentPackageName: 'com.croploo.app',
                  ),
                  MarkerLayer(
                    markers: [
                      for (final p in points)
                        Marker(
                          point: ll.LatLng(p.elevator.lat, p.elevator.lng),
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          child: _MapDot(
                              elevator: p.elevator,
                              snapshot: p.snapshot,
                              commoditySymbol: commodity),
                        ),
                    ],
                  ),
                ],
              ),
              Positioned(
                left: 8,
                bottom: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  color: theme.bgSurface.withValues(alpha: 0.9),
                  child: Row(
                    children: [
                      _legendDot(theme, theme.negative, 'BELOW AVG'),
                      const SizedBox(width: 16),
                      _legendDot(theme, theme.neutral, 'NEAR AVG'),
                      const SizedBox(width: 16),
                      _legendDot(theme, theme.positive, 'ABOVE AVG'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _legendDot(CroplooTheme theme, Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.zero)),
          const SizedBox(width: 6),
          Text(label, style: CroplooText.label.copyWith(fontSize: 9)),
        ],
      );
}

// ── LIST VIEW ────────────────────────────────────────────────────

class _BasisListView extends ConsumerWidget {
  const _BasisListView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshots = ref.watch(_filteredSnapshotsProvider);
    final theme = CroplooTheme.of(context);
    if (ref.watch(basisOverviewProvider).isLoading) {
      return const CroplooLoader();
    }
    if (snapshots.isEmpty) {
      return const EmptyState(
          icon: PhosphorIconsRegular.funnelX,
          message: 'No locations match the current filters.');
    }
    return Column(
      children: [
        // Header row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.bgBorder)),
          ),
          child: Row(
            children: [
              Expanded(flex: 3, child: Text('ELEVATOR', style: CroplooText.label.copyWith(fontSize: 10))),
              SizedBox(width: 60, child: Text('STATE', style: CroplooText.label.copyWith(fontSize: 10))),
              SizedBox(width: 100, child: Text('COMMODITY', style: CroplooText.label.copyWith(fontSize: 10))),
              SizedBox(width: 100, child: Text('CASH BID', style: CroplooText.label.copyWith(fontSize: 10), textAlign: TextAlign.right)),
              SizedBox(width: 110, child: Text('BASIS', style: CroplooText.label.copyWith(fontSize: 10), textAlign: TextAlign.right)),
              SizedBox(width: 120, child: Text('VS 5YR AVG', style: CroplooText.label.copyWith(fontSize: 10), textAlign: TextAlign.right)),
              const SizedBox(width: 70),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: snapshots.length,
            itemBuilder: (context, i) => _ListRow(snapshot: snapshots[i]),
          ),
        ),
      ],
    );
  }
}

class _ListRow extends StatelessWidget {
  final BasisSnapshot snapshot;

  const _ListRow({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final s = snapshot;
    final devColor = theme.changeColor(s.deviationFromAvg);
    return InkWell(
      onTap: () => context
          .go('/basis/detail/${s.elevator.id}/${s.commodity.symbol}'),
      hoverColor: theme.bgElevated,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.bgBorder)),
        ),
        child: Row(
          children: [
            Expanded(
                flex: 3,
                child: Tooltip(
                  message: s.source != null
                      ? 'Basis data: ${s.source}\nLast updated: ${Fmt.date(s.snapshotDate)}'
                      : '',
                  child: Text(s.elevator.name,
                      style: CroplooText.bodyStrong.copyWith(fontSize: 13)),
                )),
            SizedBox(
                width: 60,
                child: Text(s.elevator.state, style: CroplooText.dataSmall)),
            SizedBox(
                width: 100,
                child: Text(s.commodity.name.toUpperCase(),
                    style: CroplooText.label.copyWith(fontSize: 10))),
            SizedBox(
                width: 100,
                child: Text(Fmt.price(s.cashPrice),
                    style: CroplooText.data.copyWith(fontSize: 13),
                    textAlign: TextAlign.right)),
            SizedBox(
                width: 110,
                child: Text(Fmt.basis(s.basisValue),
                    style: CroplooText.data.copyWith(fontSize: 13),
                    textAlign: TextAlign.right)),
            SizedBox(
                width: 120,
                child: Text(
                    '${Fmt.cents(s.deviationFromAvg)} ${Fmt.arrow(s.deviationFromAvg)}',
                    style: CroplooText.data
                        .copyWith(fontSize: 13, color: devColor),
                    textAlign: TextAlign.right)),
            SizedBox(
              width: 70,
              child: Align(
                alignment: Alignment.centerRight,
                child: s.isExtreme
                    ? PriorityTag(priority: s.signalStrength)
                    : const SizedBox(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── CHART VIEW ───────────────────────────────────────────────────

class _BasisChartView extends ConsumerWidget {
  const _BasisChartView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshots = ref.watch(_filteredSnapshotsProvider);
    final selectedId = ref.watch(_chartSelectionProvider) ??
        (snapshots.isNotEmpty ? snapshots.first.elevator.id : null);
    final commodity = ref.watch(commodityFilterProvider);
    final theme = CroplooTheme.of(context);

    if (snapshots.isEmpty) {
      return const EmptyState(
          icon: PhosphorIconsRegular.chartLine, message: 'No locations available.');
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Location selector
        Container(
          width: 280,
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: theme.bgBorder)),
          ),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: snapshots.length,
            itemBuilder: (context, i) {
              final s = snapshots[i];
              final selected = s.elevator.id == selectedId;
              return InkWell(
                onTap: () => ref.read(_chartSelectionProvider.notifier).state =
                    s.elevator.id,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  color: selected ? theme.accentDim : null,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('${s.elevator.name}, ${s.elevator.state}',
                            style: CroplooText.bodyStrong.copyWith(
                                fontSize: 12,
                                color: selected
                                    ? theme.textPrimary
                                    : theme.textSecondary),
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text(Fmt.cents(s.deviationFromAvg),
                          style: CroplooText.dataSmall.copyWith(
                              color: theme.changeColor(
                                  s.deviationFromAvg))),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Chart panel
        Expanded(
          child: selectedId == null
              ? const SizedBox()
              : Padding(
                  padding: const EdgeInsets.all(32),
                  child: _ChartPanel(
                      elevatorId: selectedId, commodity: commodity),
                ),
        ),
      ],
    );
  }
}

class _ChartPanel extends ConsumerStatefulWidget {
  final int elevatorId;
  final String commodity;

  const _ChartPanel({required this.elevatorId, required this.commodity});

  @override
  ConsumerState<_ChartPanel> createState() => _ChartPanelState();
}

class _ChartPanelState extends ConsumerState<_ChartPanel> {
  BasisTimeRange _range = BasisTimeRange.all;

  @override
  Widget build(BuildContext context) {
    final series =
        ref.watch(basisTimeseriesProvider((widget.elevatorId, widget.commodity)));
    return series.when(
      loading: () => const CroplooLoader(),
      error: (e, _) => Text('Error loading chart', style: CroplooText.body),
      data: (points) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SectionHeader(title: 'Basis Timeseries'),
              const Spacer(),
              CroplooButton(
                label: 'Export CSV',
                variant: CroplooButtonVariant.ghost,
                expanded: false,
                onPressed: () => launchUrl(
                  Uri.parse(ref.read(repositoryProvider).basisHistoryExportUrl(
                      widget.elevatorId, widget.commodity, 'ALL')),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              const SizedBox(width: 12),
              BasisChartTimeRangeSelector(
                value: _range,
                onChanged: (r) => setState(() => _range = r),
              ),
            ],
          ),
          const SizedBox(height: 16),
          BasisChartLegend(points: points),
          const SizedBox(height: 16),
          Expanded(
              child: BasisChart(points: points, timeRange: _range)),
        ],
      ),
    );
  }
}
