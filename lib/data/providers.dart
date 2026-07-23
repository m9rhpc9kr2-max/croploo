import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_session.dart';
import '../shared/models/models.dart';
import 'live_repository.dart';
import 'offline_cache.dart';
import 'repository.dart';

/// Non-null while the app is serving cached (stale) data because the
/// last live request failed — value is when that cached snapshot was
/// taken. Null again as soon as any request succeeds live. See
/// offline_cache.dart and LiveCroplooRepository's _getList/_getObject.
final offlineSinceProvider = StateProvider<DateTime?>((ref) => null);

final repositoryProvider = Provider<CroplooRepository>((ref) {
  OfflineCache.onFallback =
      (cachedAt) => ref.read(offlineSinceProvider.notifier).state = cachedAt;
  return LiveCroplooRepository(
    accessToken: ref.watch(authSessionProvider)?.accessToken,
  );
});

final currentUserProvider = FutureProvider.autoDispose<CroplooUser>(
  (ref) => ref.watch(repositoryProvider).me(),
);

final futuresProvider = FutureProvider.autoDispose<List<FuturesPrice>>(
  (ref) => ref.watch(repositoryProvider).futuresPrices(),
);

final futuresHistoryProvider =
    FutureProvider.autoDispose.family<List<FuturesHistoryPoint>, String>(
  (ref, symbol) => ref.watch(repositoryProvider).futuresHistory(symbol),
);

final tickerProvider = FutureProvider.autoDispose<List<TickerItem>>(
  (ref) => ref.watch(repositoryProvider).ticker(),
);

final basisOverviewProvider = FutureProvider.autoDispose<List<BasisSnapshot>>(
  (ref) => ref.watch(repositoryProvider).basisOverview(),
);

/// Full elevator directory — every real location, regardless of whether
/// its state has live USDA basis data wired yet. Used by the map views so
/// elevators without data still show up (as an explicit "no data" pin)
/// instead of silently vanishing from basisOverview's filtered results.
final elevatorsProvider = FutureProvider.autoDispose<List<ElevatorLocation>>(
  (ref) => ref.watch(repositoryProvider).elevators(),
);

/// Shared so the global keyboard shortcuts (C/W/S — see
/// shared/widgets/croploo_shortcuts.dart) can drive the Basis Monitor's
/// commodity filter regardless of which screen dispatched the key.
final commodityFilterProvider = StateProvider<String>((ref) => 'ZC');

/// Top deviations sorted by |deviation| descending.
final topBasisDeviationsProvider = FutureProvider.autoDispose<List<BasisSnapshot>>(
  (ref) async {
    final all = await ref.watch(basisOverviewProvider.future);
    final sorted = [...all]..sort((a, b) =>
        b.deviationFromAvg.abs().compareTo(a.deviationFromAvg.abs()));
    return sorted;
  },
);

final basisTimeseriesProvider =
    FutureProvider.autoDispose.family<List<BasisPoint>, (int, String)>(
  (ref, key) => ref.watch(repositoryProvider).basisTimeseries(key.$1, key.$2),
);

final usdaReportsProvider = FutureProvider.autoDispose<List<UsdaReport>>(
  (ref) => ref.watch(repositoryProvider).usdaReports(),
);

final usdaCalendarProvider = FutureProvider.autoDispose<List<UsdaRelease>>(
  (ref) => ref.watch(repositoryProvider).usdaCalendar(),
);

final freightRatesProvider = FutureProvider.autoDispose<List<FreightRate>>(
  (ref) => ref.watch(repositoryProvider).freightRates(),
);

final freightCorrelationProvider =
    FutureProvider.autoDispose.family<List<FreightPoint>, String>(
  (ref, corridor) => ref.watch(repositoryProvider).freightCorrelation(corridor),
);

/// Real weekly grain rail car loadings by state (STB Rail Service Metrics
/// via USDA AgTransport, see grainRailCars.js).
final railCarLoadingsProvider =
    FutureProvider.autoDispose.family<RailCarLoadings, String>(
  (ref, state) => ref.watch(repositoryProvider).railCarLoadings(state),
);

/// Real Mississippi River stage/flow readings at five grain-corridor
/// gauges (St. Louis → New Orleans), see mississippiGauges.js.
final riverGaugesProvider = FutureProvider.autoDispose<List<RiverGaugeStation>>(
  (ref) => ref.watch(repositoryProvider).riverGauges(),
);

// ── Market Intel ─────────────────────────────────────────────────

final cotReportProvider = FutureProvider.autoDispose<CotReport>(
  (ref) => ref.watch(repositoryProvider).cotReport(),
);

final seasonalPatternProvider =
    FutureProvider.autoDispose.family<SeasonalPattern, String>(
  (ref, symbol) => ref.watch(repositoryProvider).seasonalPattern(symbol),
);

final weatherImpactProvider = FutureProvider.autoDispose<WeatherImpact>(
  (ref) => ref.watch(repositoryProvider).weatherImpact(),
);

/// Real US Drought Monitor D0–D4 severity per state, see droughtMonitor.js.
final droughtMonitorProvider = FutureProvider.autoDispose<List<DroughtSnapshot>>(
  (ref) => ref.watch(repositoryProvider).droughtMonitor(),
);

final cropTourComparisonsProvider = FutureProvider.autoDispose<List<CropTourComparison>>(
  (ref) => ref.watch(repositoryProvider).cropTourComparisons(),
);

final crushSpreadProvider = FutureProvider.autoDispose<CrushSpread>(
  (ref) => ref.watch(repositoryProvider).crushSpread(),
);

final forwardCurveProvider = FutureProvider.autoDispose.family<ForwardCurve, String>(
  (ref, symbol) => ref.watch(repositoryProvider).forwardCurve(symbol),
);

final calendarSpreadProvider =
    FutureProvider.autoDispose.family<List<CalendarSpreadPoint>, String>(
  (ref, symbol) => ref.watch(repositoryProvider).calendarSpread(symbol),
);

final ethanolMarginProvider = FutureProvider.autoDispose<EthanolMargin>(
  (ref) => ref.watch(repositoryProvider).ethanolMargin(),
);

final dollarIndexProvider = FutureProvider.autoDispose<DollarIndexSnapshot>(
  (ref) => ref.watch(repositoryProvider).dollarIndex(),
);

final eiaInventoryProvider = FutureProvider.autoDispose<EiaInventoryReport>(
  (ref) => ref.watch(repositoryProvider).eiaInventory(),
);

final ngStorageProvider = FutureProvider.autoDispose<NgStorageReport>(
  (ref) => ref.watch(repositoryProvider).ngStorage(),
);

final crackSpreadProvider = FutureProvider.autoDispose<CrackSpread>(
  (ref) => ref.watch(repositoryProvider).crackSpread(),
);

final dailyBriefProvider = FutureProvider.autoDispose<DailyBrief>(
  (ref) => ref.watch(repositoryProvider).dailyBrief(),
);

// ── Macro ─────────────────────────────────────────────────────────

final forexProvider = FutureProvider.autoDispose<ForexSnapshot>(
  (ref) => ref.watch(repositoryProvider).forex(),
);

final cryptoProvider = FutureProvider.autoDispose<CryptoSnapshot>(
  (ref) => ref.watch(repositoryProvider).crypto(),
);

final yieldCurveProvider = FutureProvider.autoDispose<YieldCurveSnapshot>(
  (ref) => ref.watch(repositoryProvider).yieldCurve(),
);

final economicIndicatorsProvider = FutureProvider.autoDispose<EconomicIndicatorsSnapshot>(
  (ref) => ref.watch(repositoryProvider).economicIndicators(),
);

final earningsCalendarProvider = FutureProvider.autoDispose<EarningsCalendar>(
  (ref) => ref.watch(repositoryProvider).earningsCalendar(),
);

final economicCalendarProvider = FutureProvider.autoDispose<EconomicCalendar>(
  (ref) => ref.watch(repositoryProvider).economicCalendar(),
);

final newsProvider = FutureProvider.autoDispose.family<List<NewsHeadline>, String?>(
  (ref, tag) => ref.watch(repositoryProvider).news(tag: tag),
);

final sectorHeatmapProvider = FutureProvider.autoDispose<SectorHeatmap>(
  (ref) => ref.watch(repositoryProvider).sectorHeatmap(),
);

// ── CullyAI memory / synthesis / proactive insights ────────────────

final cullyAiContextProvider = FutureProvider.autoDispose<CullyAiContext>(
  (ref) => ref.watch(repositoryProvider).cullyAiContext(),
);

final crossAssetSynthesisProvider = FutureProvider.autoDispose<CrossAssetSynthesis>(
  (ref) => ref.watch(repositoryProvider).crossAssetSynthesis(),
);

final dailyInsightsProvider = FutureProvider.autoDispose<DailyInsights>(
  (ref) => ref.watch(repositoryProvider).dailyInsights(),
);

// ── Advanced Analytics ──────────────────────────────────────────────

final intermarketAnalysisProvider = FutureProvider.autoDispose<IntermarketAnalysis>(
  (ref) => ref.watch(repositoryProvider).intermarketAnalysis(),
);

final volatilityMonitorProvider = FutureProvider.autoDispose<VolatilityMonitor>(
  (ref) => ref.watch(repositoryProvider).volatilityMonitor(),
);

final relativeValueScreenerProvider = FutureProvider.autoDispose<RelativeValueScreener>(
  (ref) => ref.watch(repositoryProvider).relativeValueScreener(),
);

final spreadTerminalProvider = FutureProvider.autoDispose<SpreadTerminal>(
  (ref) => ref.watch(repositoryProvider).spreadTerminal(),
);

// ── Stocks ───────────────────────────────────────────────────────────

final stockSearchProvider =
    FutureProvider.autoDispose.family<List<StockSearchResult>, String>(
  (ref, query) => ref.watch(repositoryProvider).stockSearch(query),
);

final stockQuoteProvider = FutureProvider.autoDispose.family<StockQuote, String>(
  (ref, symbol) => ref.watch(repositoryProvider).stockQuote(symbol),
);

final selectedStockSymbolProvider = StateProvider<String?>((ref) => null);

// ── Audit Trail / Decision Log ──────────────────────────────────────

final decisionLogProvider = FutureProvider.autoDispose<List<DecisionLogEntry>>(
  (ref) => ref.watch(repositoryProvider).decisionLog(),
);

// ── Custom Dashboards ────────────────────────────────────────────────

final dashboardLayoutsProvider = FutureProvider.autoDispose<List<DashboardLayout>>(
  (ref) => ref.watch(repositoryProvider).dashboardLayouts(),
);

/// Null means "show every widget" (the default, unmodified dashboard).
final activeDashboardWidgetIdsProvider = StateProvider<List<String>?>((ref) => null);

// ── Intraday Futures ─────────────────────────────────────────────────

final futuresIntradayProvider = FutureProvider.autoDispose.family<IntradaySnapshot, String>(
  (ref, symbol) => ref.watch(repositoryProvider).futuresIntraday(symbol),
);

// ── Community Insights ───────────────────────────────────────────────

final communityInsightsProvider = FutureProvider.autoDispose<List<CommunityInsight>>(
  (ref) => ref.watch(repositoryProvider).communityInsights(),
);

// ── Croploo Learn ──────────────────────────────────────────────────────

final learnArticlesProvider = FutureProvider.autoDispose<List<LearnArticleSummary>>(
  (ref) => ref.watch(repositoryProvider).learnArticles(),
);

final learnArticleProvider = FutureProvider.autoDispose.family<LearnArticle, String>(
  (ref, slug) => ref.watch(repositoryProvider).learnArticle(slug),
);

// ── Newsletter ────────────────────────────────────────────────────────

final newsletterLatestProvider = FutureProvider.autoDispose<NewsletterIssue>(
  (ref) => ref.watch(repositoryProvider).newsletterLatest(),
);

// ── Public Profile ────────────────────────────────────────────────────

final myPublicProfileProvider = FutureProvider.autoDispose<PublicProfileSettings?>(
  (ref) => ref.watch(repositoryProvider).myPublicProfile(),
);

final alertRulesProvider = FutureProvider.autoDispose<List<AlertRule>>(
  (ref) => ref.watch(repositoryProvider).alertRules(),
);

// ── Alerts (mutable: mark read) ──────────────────────────────────

class AlertsNotifier extends AsyncNotifier<List<CroplooAlert>> {
  @override
  Future<List<CroplooAlert>> build() =>
      ref.watch(repositoryProvider).alerts();

  Future<void> markRead(int id) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData([
      for (final a in current) a.id == id ? a.copyWith(isRead: true) : a
    ]);
    await ref.read(repositoryProvider).markAlertRead(id);
  }

  Future<void> markAllRead() async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData([for (final a in current) a.copyWith(isRead: true)]);
    await ref.read(repositoryProvider).markAllAlertsRead();
  }
}

final alertsProvider =
    AsyncNotifierProvider<AlertsNotifier, List<CroplooAlert>>(
        AlertsNotifier.new);

final unreadAlertCountProvider = Provider<int>((ref) {
  final alerts = ref.watch(alertsProvider).valueOrNull ?? const [];
  return alerts.where((a) => !a.isRead).length;
});

// ── CullyAI chat ─────────────────────────────────────────────────

/// One independent CullyAI conversation. Several of these can exist at
/// once (see [CullyThreadsNotifier]) — switching the active thread never
/// loses another thread's history or interrupts its in-flight streaming.
class ChatThread {
  final String id;
  final String title;
  final List<ChatMessage> messages;
  final bool streaming;

  const ChatThread({
    required this.id,
    this.title = 'New chat',
    this.messages = const [],
    this.streaming = false,
  });

  ChatThread copyWith({String? title, List<ChatMessage>? messages, bool? streaming}) =>
      ChatThread(
        id: id,
        title: title ?? this.title,
        messages: messages ?? this.messages,
        streaming: streaming ?? this.streaming,
      );
}

class CullyThreadsState {
  final List<ChatThread> threads;
  final String activeId;

  const CullyThreadsState({required this.threads, required this.activeId});

  ChatThread get active => threads.firstWhere(
        (t) => t.id == activeId,
        orElse: () => threads.first,
      );
}

/// Derives a short tab title from a user's first message in a thread.
String _titleFromText(String text) {
  final oneLine = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  return oneLine.length <= 28 ? oneLine : '${oneLine.substring(0, 27)}…';
}

class CullyThreadsNotifier extends Notifier<CullyThreadsState> {
  int _idCounter = 0;

  String _newId() => 'thread-${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

  @override
  CullyThreadsState build() {
    final first = ChatThread(id: _newId());
    return CullyThreadsState(threads: [first], activeId: first.id);
  }

  void newThread() {
    final thread = ChatThread(id: _newId());
    state = CullyThreadsState(threads: [...state.threads, thread], activeId: thread.id);
  }

  void switchTo(String id) {
    if (state.activeId == id || !state.threads.any((t) => t.id == id)) return;
    state = CullyThreadsState(threads: state.threads, activeId: id);
  }

  void closeThread(String id) {
    if (state.threads.length <= 1) return; // always keep at least one thread
    final remaining = state.threads.where((t) => t.id != id).toList();
    final activeId = state.activeId == id ? remaining.last.id : state.activeId;
    state = CullyThreadsState(threads: remaining, activeId: activeId);
  }

  void _replaceThread(ChatThread updated) {
    state = CullyThreadsState(
      threads: [for (final t in state.threads) if (t.id == updated.id) updated else t],
      activeId: state.activeId,
    );
  }

  /// Sends into the active thread (or [threadId] if given — used by the
  /// "ask CullyAI about this alert" quick action, which always targets
  /// whichever thread is open when the user taps it).
  Future<void> send(String text, {String? threadId}) async {
    final id = threadId ?? state.activeId;
    var thread = state.threads.firstWhere((t) => t.id == id, orElse: () => state.active);
    if (thread.streaming || text.trim().isEmpty) return;

    final history = [
      ...thread.messages,
      ChatMessage(fromUser: true, text: text.trim(), at: DateTime.now()),
    ];
    thread = thread.copyWith(
      messages: [...history, ChatMessage(fromUser: false, text: '', at: DateTime.now())],
      streaming: true,
      title: thread.messages.isEmpty ? _titleFromText(text) : thread.title,
    );
    _replaceThread(thread);

    String? statusLabel;
    try {
      final stream = ref.read(repositoryProvider).cullyChat(history);
      var buffer = '';
      final charts = <ChartSpec>[];
      await for (final event in stream) {
        if (event.status != null) statusLabel = event.status;
        if (event.textDelta != null) {
          buffer += event.textDelta!;
          statusLabel = null; // real content arrived — drop the status hint
        }
        if (event.chart != null) charts.add(event.chart!);
        thread = thread.copyWith(messages: [
          ...thread.messages.sublist(0, thread.messages.length - 1),
          ChatMessage(
              fromUser: false,
              text: buffer,
              at: DateTime.now(),
              charts: List.unmodifiable(charts),
              statusLabel: statusLabel),
        ]);
        _replaceThread(thread);
      }
    } catch (e) {
      thread = thread.copyWith(messages: [
        ...thread.messages.sublist(0, thread.messages.length - 1),
        ChatMessage(
            fromUser: false,
            text: e.toString().contains('temporarily unavailable')
                ? 'CullyAI is temporarily unavailable. Please try again in a few minutes.'
                : 'An error occurred. Please try again.',
            at: DateTime.now()),
      ]);
      _replaceThread(thread);
    } finally {
      // Re-read the thread in case switchTo()/closeThread() ran while this
      // was in flight — streaming must clear on the right thread either way.
      final current = state.threads.firstWhere((t) => t.id == id, orElse: () => thread);
      _replaceThread(current.copyWith(streaming: false));
    }
  }
}

final cullyThreadsProvider =
    NotifierProvider<CullyThreadsNotifier, CullyThreadsState>(
        CullyThreadsNotifier.new);

/// Whether the right-hand CullyAI panel is expanded.
final cullyPanelOpenProvider = StateProvider<bool>((ref) => true);

/// Current width of the expanded CullyAI panel (user-resizable).
final cullyPanelWidthProvider = StateProvider<double>((ref) => 320);

// ── Personalization ──────────────────────────────────────────────

class WatchlistNotifier extends AsyncNotifier<List<WatchlistItem>> {
  @override
  Future<List<WatchlistItem>> build() => ref.watch(repositoryProvider).watchlist();

  Future<void> add(String commodity, String state) async {
    final item = await ref.read(repositoryProvider).addWatchlistItem(commodity, state);
    final current = this.state.valueOrNull ?? const [];
    this.state = AsyncData([...current.where((i) => i.id != item.id), item]);
  }

  Future<void> remove(int id) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.where((i) => i.id != id).toList());
    await ref.read(repositoryProvider).removeWatchlistItem(id);
  }
}

final watchlistProvider =
    AsyncNotifierProvider<WatchlistNotifier, List<WatchlistItem>>(
        WatchlistNotifier.new);

class CustomAlertRulesNotifier extends AsyncNotifier<List<CustomAlertRule>> {
  @override
  Future<List<CustomAlertRule>> build() =>
      ref.watch(repositoryProvider).customAlertRules();

  Future<void> add({
    required String ruleType,
    required String commodity,
    String? state,
    required String comparison,
    required double thresholdValue,
  }) async {
    final rule = await ref.read(repositoryProvider).addCustomAlertRule(
          ruleType: ruleType,
          commodity: commodity,
          state: state,
          comparison: comparison,
          thresholdValue: thresholdValue,
        );
    final current = this.state.valueOrNull ?? const [];
    this.state = AsyncData([rule, ...current.where((r) => r.id != rule.id)]);
  }

  Future<void> remove(int id) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.where((r) => r.id != id).toList());
    await ref.read(repositoryProvider).removeCustomAlertRule(id);
  }
}

final customAlertRulesProvider =
    AsyncNotifierProvider<CustomAlertRulesNotifier, List<CustomAlertRule>>(
        CustomAlertRulesNotifier.new);

class PriceTargetsNotifier extends AsyncNotifier<List<PriceTarget>> {
  @override
  Future<List<PriceTarget>> build() => ref.watch(repositoryProvider).priceTargets();

  Future<void> add({
    required String symbol,
    required double targetPrice,
    required String direction,
  }) async {
    final target = await ref.read(repositoryProvider).addPriceTarget(
          symbol: symbol,
          targetPrice: targetPrice,
          direction: direction,
        );
    final current = state.valueOrNull ?? const [];
    state = AsyncData([target, ...current.where((t) => t.id != target.id)]);
  }

  Future<void> remove(int id) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.where((t) => t.id != id).toList());
    await ref.read(repositoryProvider).removePriceTarget(id);
  }
}

final priceTargetsProvider =
    AsyncNotifierProvider<PriceTargetsNotifier, List<PriceTarget>>(
        PriceTargetsNotifier.new);

class PortfolioNotifier extends AsyncNotifier<List<PortfolioPosition>> {
  @override
  Future<List<PortfolioPosition>> build() => ref.watch(repositoryProvider).portfolio();

  Future<void> add({
    required String commodity,
    required double bushels,
    required DateTime storedDate,
    required double breakEvenPrice,
    String? state,
  }) async {
    await ref.read(repositoryProvider).addPortfolioPosition(
          commodity: commodity,
          bushels: bushels,
          storedDate: storedDate,
          breakEvenPrice: breakEvenPrice,
          state: state,
        );
    this.state = AsyncData(await ref.read(repositoryProvider).portfolio());
  }

  Future<void> remove(int id) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.where((p) => p.id != id).toList());
    await ref.read(repositoryProvider).removePortfolioPosition(id);
  }
}

final portfolioProvider =
    AsyncNotifierProvider<PortfolioNotifier, List<PortfolioPosition>>(
        PortfolioNotifier.new);

// ── Trust / transparency ─────────────────────────────────────────

final wasdeSurprisesProvider =
    FutureProvider.autoDispose.family<WasdeSurpriseReport, String>(
  (ref, commodity) => ref.watch(repositoryProvider).wasdeSurprises(commodity),
);

final exportSalesProvider =
    FutureProvider.autoDispose.family<ExportSalesReport, String>(
  (ref, commodity) => ref.watch(repositoryProvider).exportSales(commodity),
);

final statusProvider = FutureProvider.autoDispose<List<DataSourceStatus>>(
  (ref) => ref.watch(repositoryProvider).status(),
);

// ── Growth ─────────────────────────────────────────────────────────

final referralSummaryProvider = FutureProvider.autoDispose<ReferralSummary>(
  (ref) => ref.watch(repositoryProvider).referralSummary(),
);
