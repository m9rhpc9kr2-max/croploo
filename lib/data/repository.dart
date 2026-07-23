import '../shared/models/models.dart';

/// Data access contract mirroring the Croploo backend API
/// (api.croploo.app/v1). The UI depends only on this interface, so
/// swapping the implementation requires no widget changes. The only
/// implementation is [LiveCroplooRepository] — every field is backed by
/// a real data source (see live_repository.dart's doc comment for which
/// upstream API backs each one).
abstract class CroplooRepository {
  Future<CroplooUser> me();
  Future<List<FuturesPrice>> futuresPrices();
  Future<List<FuturesHistoryPoint>> futuresHistory(String symbol,
      {int days = 180});
  Future<List<TickerItem>> ticker();
  Future<List<ElevatorLocation>> elevators();
  Future<List<BasisSnapshot>> basisOverview();
  Future<List<BasisPoint>> basisTimeseries(int elevatorId, String commodity);
  Future<List<UsdaReport>> usdaReports();
  Future<List<UsdaRelease>> usdaCalendar();
  Future<ExportSalesReport> exportSales(String commodity);
  Future<List<CroplooAlert>> alerts();
  Future<void> markAlertRead(int id);
  Future<void> markAllAlertsRead();
  Future<List<AlertRule>> alertRules();
  Future<List<FreightRate>> freightRates();
  Future<List<FreightPoint>> freightCorrelation(String corridor);
  Future<RailCarLoadings> railCarLoadings(String state);
  Future<List<RiverGaugeStation>> riverGauges();
  Future<DailyBrief> dailyBrief();

  /// Streams the assistant's reply — text deltas plus any chart blocks
  /// CullyAI renders via its `render_chart` tool — given the full
  /// conversation so far (last entry is the new user message).
  Stream<CullyChatEvent> cullyChat(List<ChatMessage> messages);

  // ── Market Intel ─────────────────────────────────────────────────
  Future<CotReport> cotReport();
  Future<SeasonalPattern> seasonalPattern(String symbol);
  Future<WeatherImpact> weatherImpact();
  Future<List<DroughtSnapshot>> droughtMonitor();
  Future<List<CropTourComparison>> cropTourComparisons();
  Future<CrushSpread> crushSpread();
  Future<ForwardCurve> forwardCurve(String symbol);
  Future<List<CalendarSpreadPoint>> calendarSpread(String symbol);
  Future<EthanolMargin> ethanolMargin();
  Future<DollarIndexSnapshot> dollarIndex();
  Future<EiaInventoryReport> eiaInventory();
  Future<NgStorageReport> ngStorage();
  Future<CrackSpread> crackSpread();

  // ── Macro ─────────────────────────────────────────────────────────
  Future<ForexSnapshot> forex();
  Future<CryptoSnapshot> crypto();
  Future<YieldCurveSnapshot> yieldCurve();
  Future<EconomicIndicatorsSnapshot> economicIndicators();
  Future<EarningsCalendar> earningsCalendar();
  Future<EconomicCalendar> economicCalendar();
  Future<List<NewsHeadline>> news({String? tag});
  Future<SectorHeatmap> sectorHeatmap();

  // ── CullyAI memory / synthesis / proactive insights ──────────────
  Future<CullyAiContext> cullyAiContext();
  Future<CrossAssetSynthesis> crossAssetSynthesis();
  Future<DailyInsights> dailyInsights();

  // ── Advanced Analytics ────────────────────────────────────────────
  Future<IntermarketAnalysis> intermarketAnalysis();
  Future<VolatilityMonitor> volatilityMonitor();
  Future<RelativeValueScreener> relativeValueScreener();
  Future<SpreadTerminal> spreadTerminal();

  // ── Stocks ─────────────────────────────────────────────────────────
  Future<List<StockSearchResult>> stockSearch(String query);
  Future<StockQuote> stockQuote(String symbol);

  // ── Audit Trail / Decision Log ────────────────────────────────────
  Future<List<DecisionLogEntry>> decisionLog();
  Future<DecisionLogEntry> addDecisionLogEntry({
    required String commodity,
    required String userNote,
    String? cullyaiContext,
  });
  String complianceExportUrl();

  /// Direct-download link for CullyAI's weekly market report PDF (real
  /// cached data only — see backend/src/reportGenerator.js).
  String weeklyReportUrl();

  // ── Custom Dashboards ──────────────────────────────────────────────
  Future<List<DashboardLayout>> dashboardLayouts();
  Future<DashboardLayout> saveDashboardLayout(String name, List<String> widgetIds);
  Future<void> deleteDashboardLayout(int id);

  // ── Intraday Futures ────────────────────────────────────────────────
  Future<IntradaySnapshot> futuresIntraday(String symbol);

  // ── Community Insights ──────────────────────────────────────────────
  Future<List<CommunityInsight>> communityInsights({String? commodity});
  Future<CommunityInsight> addCommunityInsight({
    required String commodity,
    required String body,
  });

  // ── Croploo Learn ─────────────────────────────────────────────────────
  Future<List<LearnArticleSummary>> learnArticles();
  Future<LearnArticle> learnArticle(String slug);

  // ── Newsletter ────────────────────────────────────────────────────────
  Future<NewsletterIssue> newsletterLatest();
  Future<void> newsletterSubscribe(String email);

  // ── Public Profile ────────────────────────────────────────────────────
  Future<PublicProfileSettings?> myPublicProfile();
  Future<PublicProfileSettings> savePublicProfile({
    required String username,
    required bool isPublic,
    required List<String> trackedCommodities,
  });

  // ── Personalization ──────────────────────────────────────────────
  Future<List<WatchlistItem>> watchlist();
  Future<WatchlistItem> addWatchlistItem(String commodity, String state);
  Future<void> removeWatchlistItem(int id);

  Future<List<CustomAlertRule>> customAlertRules();
  Future<CustomAlertRule> addCustomAlertRule({
    required String ruleType,
    required String commodity,
    String? state,
    required String comparison,
    required double thresholdValue,
  });
  Future<void> removeCustomAlertRule(int id);

  Future<List<PriceTarget>> priceTargets();
  Future<PriceTarget> addPriceTarget({
    required String symbol,
    required double targetPrice,
    required String direction,
  });
  Future<void> removePriceTarget(int id);

  Future<List<PortfolioPosition>> portfolio();
  Future<PortfolioPosition> addPortfolioPosition({
    required String commodity,
    required double bushels,
    required DateTime storedDate,
    required double breakEvenPrice,
    String? state,
  });
  Future<void> removePortfolioPosition(int id);

  // ── Trust / transparency ─────────────────────────────────────────
  Future<WasdeSurpriseReport> wasdeSurprises(String commodity);
  Future<List<DataSourceStatus>> status();

  // ── Preferences ───────────────────────────────────────────────────
  Future<CroplooUser> setDailyBriefEmail(bool enabled);

  // ── Account ───────────────────────────────────────────────────────
  Future<CroplooUser> updateAccount({String? name, String? email, String? username});
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  // ── Export ────────────────────────────────────────────────────────
  String basisHistoryExportUrl(int elevatorId, String commodity, String range);
  String alertsExportUrl();
  String wasdeSurprisesExportUrl(String commodity);

  // ── Growth ────────────────────────────────────────────────────────
  Future<ReferralSummary> referralSummary();
  Future<CroplooUser> startTrial();
  String basisWidgetEmbedUrl(String state, String commodity);
}
