import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../shared/models/models.dart';
import 'offline_cache.dart';
import 'repository.dart';

// Several endpoints call ensureFresh() server-side, which can hit a live
// upstream API (EIA, Alpha Vantage, NASS) with its own ~20s budget before
// falling back to cache — confirmed in production logs at 6-26s for
// /intel/eia-inventory and /intel/ng-storage alone. This used to be 8
// seconds, which aborted client-side well before the backend's genuine
// 200 OK arrived, surfacing as a bare "Error" in the UI for a request that
// actually succeeded.
const _offlineTimeout = Duration(seconds: 30);

/// Live repository backed entirely by the Croploo backend: futures
/// prices/history (Alpha Vantage), basis (USDA AMS AgTransport), USDA
/// reports (NASS Quick Stats + Claude analysis), alerts, freight (EIA),
/// daily brief and CullyAI (Claude). Export Sales reports aren't
/// sourced yet (needs a USDA FAS API key) and return an empty list.
class LiveCroplooRepository implements CroplooRepository {
  LiveCroplooRepository({
    this.baseUrl = 'https://croploo-backend-78230737866.europe-west1.run.app/v1',
    this.accessToken,
  });

  final String baseUrl;
  final String? accessToken;

  String _requireToken() {
    final token = accessToken;
    if (token == null) {
      throw Exception('This endpoint requires an authenticated session');
    }
    return token;
  }

  /// Not cached: requires a per-user token, so caching it could leak one
  /// user's data to another signed-in-later on the same device.
  Future<List<T>> _getList<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson, {
    Map<String, String>? query,
    bool withAuth = false,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final headers = withAuth ? {'Authorization': 'Bearer ${_requireToken()}'} : null;

    try {
      final res = await http.get(uri, headers: headers).timeout(_offlineTimeout);
      if (res.statusCode != 200) {
        throw Exception('$path failed: ${res.statusCode}');
      }
      // Temporarily disable cache to isolate freeze issue
      // if (cacheKey != null) {
      //   OfflineCache.store(cacheKey, res.body).catchError((_) {});
      // }
      final list = jsonDecode(res.body) as List;
      return list.map((j) => fromJson(j as Map<String, dynamic>)).toList();
    } catch (e) {
      // Temporarily disable cache fallback to isolate freeze issue
      // if (cacheKey != null) {
      //   final cached = await OfflineCache.read(cacheKey);
      //   if (cached != null) {
      //     final list = jsonDecode(cached.$1) as List;
      //     return list.map((j) => fromJson(j as Map<String, dynamic>)).toList();
      //   }
      // }
      rethrow;
    }
  }

  Future<T> _getObject<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson, {
    Map<String, String>? query,
    bool withAuth = false,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final headers = withAuth ? {'Authorization': 'Bearer ${_requireToken()}'} : null;

    try {
      final res = await http.get(uri, headers: headers).timeout(_offlineTimeout);
      if (res.statusCode != 200) {
        throw Exception('$path failed: ${res.statusCode}');
      }
      // Temporarily disable cache to isolate freeze issue
      // unawaited(OfflineCache.store(cacheKey, res.body));
      return fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    } catch (e) {
      // Temporarily disable cache fallback to isolate freeze issue
      // final cached = await OfflineCache.read(cacheKey);
      // if (cached != null) {
      //   return fromJson(jsonDecode(cached.$1) as Map<String, dynamic>);
      // }
      rethrow;
    }
  }

  Future<T> _postObject<T>(
    String path,
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final res = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_requireToken()}',
      },
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      throw Exception('$path failed: ${res.statusCode} ${res.body}');
    }
    return fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> _delete(String path) async {
    final res = await http.delete(
      Uri.parse('$baseUrl$path'),
      headers: {'Authorization': 'Bearer ${_requireToken()}'},
    );
    if (res.statusCode != 200) {
      throw Exception('$path failed: ${res.statusCode}');
    }
  }

  Future<List<T>> _getListAuthed<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final res = await http.get(
      Uri.parse('$baseUrl$path'),
      headers: {'Authorization': 'Bearer ${_requireToken()}'},
    );
    if (res.statusCode != 200) {
      throw Exception('$path failed: ${res.statusCode}');
    }
    final list = jsonDecode(res.body) as List;
    return list.map((j) => fromJson(j as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<FuturesPrice>> futuresPrices() =>
      _getList('/futures-prices', FuturesPrice.fromJson);

  @override
  Future<List<FuturesHistoryPoint>> futuresHistory(String symbol,
          {int days = 180}) =>
      _getList('/futures-history/$symbol', FuturesHistoryPoint.fromJson,
          query: {'days': '$days'});

  @override
  Future<CroplooUser> me() async {
    final res = await http.get(
      Uri.parse('$baseUrl/auth/me'),
      headers: {'Authorization': 'Bearer ${_requireToken()}'},
    );
    if (res.statusCode != 200) {
      throw Exception('auth/me failed: ${res.statusCode}');
    }
    return CroplooUser.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<List<TickerItem>> ticker() => _getList('/ticker', TickerItem.fromJson);

  @override
  Future<List<ElevatorLocation>> elevators() =>
      _getList('/elevators', ElevatorLocation.fromJson);

  @override
  Future<List<BasisSnapshot>> basisOverview() =>
      _getList('/basis-overview', BasisSnapshot.fromJson);

  @override
  Future<List<BasisPoint>> basisTimeseries(int elevatorId, String commodity) =>
      _getList('/basis-history', BasisPoint.fromJson, query: {
        'elevatorId': '$elevatorId',
        'commodity': commodity,
        'range': 'ALL',
      });

  @override
  Future<List<UsdaReport>> usdaReports() =>
      _getList('/usda/reports', UsdaReport.fromJson);

  @override
  Future<List<UsdaRelease>> usdaCalendar() =>
      _getList('/usda/calendar', UsdaRelease.fromJson);

  @override
  Future<List<CroplooAlert>> alerts() => _getList('/alerts', CroplooAlert.fromJson);

  @override
  Future<void> markAlertRead(int id) async {
    final res = await http.put(Uri.parse('$baseUrl/alerts/$id/read'));
    if (res.statusCode != 200) {
      throw Exception('markAlertRead failed: ${res.statusCode}');
    }
  }

  @override
  Future<void> markAllAlertsRead() async {
    final res = await http.put(Uri.parse('$baseUrl/alerts/read-all'));
    if (res.statusCode != 200) {
      throw Exception('markAllAlertsRead failed: ${res.statusCode}');
    }
  }

  @override
  Future<List<AlertRule>> alertRules() =>
      _getList('/alert-rules', AlertRule.fromJson);

  @override
  Future<List<FreightRate>> freightRates() =>
      _getList('/freight/rates', FreightRate.fromJson, withAuth: true);

  @override
  Future<List<FreightPoint>> freightCorrelation(String corridor) => _getList(
      '/freight/correlation', FreightPoint.fromJson,
      query: {'corridor': corridor}, withAuth: true);

  @override
  Future<RailCarLoadings> railCarLoadings(String state) => _getObject(
      '/freight/rail-carloadings', RailCarLoadings.fromJson,
      query: {'state': state}, withAuth: true);

  @override
  Future<List<RiverGaugeStation>> riverGauges() => _getList(
      '/freight/river-gauges', RiverGaugeStation.fromJson, withAuth: true);

  @override
  Future<DailyBrief> dailyBrief() async {
    final token = accessToken;
    final cacheKey = 'daily-brief:${token ?? 'anon'}';
    http.Response res;
    try {
      res = await http
          .get(
            Uri.parse('$baseUrl/daily-brief'),
            headers: token != null ? {'Authorization': 'Bearer $token'} : null,
          )
          .timeout(_offlineTimeout);
    } catch (e) {
      // The request itself couldn't complete (no connection, DNS failure,
      // timeout) — this is a genuine "offline" case, so fall back to cache.
      final cached = await OfflineCache.read(cacheKey);
      if (cached != null) {
        return DailyBrief.fromJson(jsonDecode(cached.$1) as Map<String, dynamic>);
      }
      rethrow;
    }
    if (res.statusCode != 200) {
      // The server was reached and responded — this is a real backend
      // error, not a connectivity problem, so don't show an "Offline"
      // banner for it (that was misleading users with a live connection).
      throw Exception('daily-brief failed: ${res.statusCode}');
    }
    unawaited(OfflineCache.store(cacheKey, res.body));
    return DailyBrief.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Stream<CullyChatEvent> cullyChat(List<ChatMessage> messages) async* {
    final request = http.Request('POST', Uri.parse('$baseUrl/cullyai/chat'))
      ..headers['Content-Type'] = 'application/json'
      ..headers['Authorization'] = 'Bearer ${_requireToken()}'
      ..body = jsonEncode({
        'messages': messages
            .map((m) => {
                  'role': m.fromUser ? 'user' : 'assistant',
                  'content': m.text,
                })
            .toList(),
      });

    final client = http.Client();
    try {
      final streamed = await client.send(request).timeout(const Duration(seconds: 20));
      if (streamed.statusCode != 200) {
        throw Exception('cullyai/chat failed: ${streamed.statusCode}');
      }

      var buffer = '';
      await for (final chunk in streamed.stream
          .transform(utf8.decoder)
          .timeout(const Duration(seconds: 45))) {
        buffer += chunk;
        final lines = buffer.split('\n');
        buffer = lines.removeLast();
        for (final line in lines) {
          if (!line.startsWith('data: ')) continue;
          final payload = line.substring(6).trim();
          if (payload.isEmpty || payload == '[DONE]') continue;
          final event = jsonDecode(payload) as Map<String, dynamic>;
          if (event['error'] is String) {
            throw Exception(event['error'] as String);
          }
          if (event['status'] is String) {
            yield CullyChatEvent.status(event['status'] as String);
          }
          if (event['delta'] is String) {
            yield CullyChatEvent.text(event['delta'] as String);
          }
          final block = event['block'];
          if (block is Map<String, dynamic> && block['type'] == 'chart') {
            yield CullyChatEvent.chart(
                ChartSpec.fromJson(block['spec'] as Map<String, dynamic>));
          }
        }
      }
    } on TimeoutException {
      throw Exception('CullyAI request timed out');
    } finally {
      client.close();
    }
  }

  @override
  Future<CotReport> cotReport() => _getObject('/intel/cot', CotReport.fromJson);

  @override
  Future<SeasonalPattern> seasonalPattern(String symbol) => _getObject(
      '/intel/seasonal/$symbol', SeasonalPattern.fromJson);

  @override
  Future<WeatherImpact> weatherImpact() =>
      _getObject('/intel/weather', WeatherImpact.fromJson);

  @override
  Future<List<DroughtSnapshot>> droughtMonitor() =>
      _getList('/intel/drought', DroughtSnapshot.fromJson);

  @override
  Future<List<CropTourComparison>> cropTourComparisons() =>
      _getList('/intel/crop-tour', CropTourComparison.fromJson);

  @override
  Future<CrushSpread> crushSpread() =>
      _getObject('/intel/crush', CrushSpread.fromJson);

  @override
  Future<ForwardCurve> forwardCurve(String symbol) =>
      _getObject('/intel/forward-curve/$symbol', ForwardCurve.fromJson);

  @override
  Future<List<CalendarSpreadPoint>> calendarSpread(String symbol) =>
      _getList('/intel/calendar-spread/$symbol', CalendarSpreadPoint.fromJson);

  @override
  Future<EthanolMargin> ethanolMargin() =>
      _getObject('/intel/ethanol-margin', EthanolMargin.fromJson);

  @override
  Future<DollarIndexSnapshot> dollarIndex() =>
      _getObject('/intel/dollar-index', DollarIndexSnapshot.fromJson);

  @override
  Future<EiaInventoryReport> eiaInventory() =>
      _getObject('/intel/eia-inventory', EiaInventoryReport.fromJson);

  @override
  Future<NgStorageReport> ngStorage() =>
      _getObject('/intel/ng-storage', NgStorageReport.fromJson);

  @override
  Future<CrackSpread> crackSpread() =>
      _getObject('/intel/crack-spread', CrackSpread.fromJson);

  // ── Macro ─────────────────────────────────────────────────────────

  @override
  Future<ForexSnapshot> forex() =>
      _getObject('/macro/forex', ForexSnapshot.fromJson);

  @override
  Future<CryptoSnapshot> crypto() =>
      _getObject('/macro/crypto', CryptoSnapshot.fromJson);

  @override
  Future<YieldCurveSnapshot> yieldCurve() =>
      _getObject('/macro/yield-curve', YieldCurveSnapshot.fromJson);

  @override
  Future<EconomicIndicatorsSnapshot> economicIndicators() => _getObject(
      '/macro/indicators', EconomicIndicatorsSnapshot.fromJson);

  @override
  Future<EarningsCalendar> earningsCalendar() =>
      _getObject('/macro/earnings-calendar', EarningsCalendar.fromJson);

  @override
  Future<EconomicCalendar> economicCalendar() =>
      _getObject('/macro/economic-calendar', EconomicCalendar.fromJson);

  @override
  Future<List<NewsHeadline>> news({String? tag}) => _getList(
      '/macro/news', NewsHeadline.fromJson,
      query: tag != null ? {'tag': tag} : null);

  @override
  Future<SectorHeatmap> sectorHeatmap() =>
      _getObject('/macro/sector-heatmap', SectorHeatmap.fromJson);

  // ── CullyAI memory / synthesis / proactive insights ──────────────

  @override
  Future<CullyAiContext> cullyAiContext() =>
      _getObject('/cullyai/context', CullyAiContext.fromJson, withAuth: true);

  @override
  Future<CrossAssetSynthesis> crossAssetSynthesis() => _getObject(
      '/cullyai/synthesis', CrossAssetSynthesis.fromJson, withAuth: true);

  @override
  Future<DailyInsights> dailyInsights() =>
      _getObject('/intel/insights', DailyInsights.fromJson);

  // ── Advanced Analytics ────────────────────────────────────────────

  @override
  Future<IntermarketAnalysis> intermarketAnalysis() =>
      _getObject('/analytics/intermarket', IntermarketAnalysis.fromJson);

  @override
  Future<VolatilityMonitor> volatilityMonitor() =>
      _getObject('/analytics/volatility', VolatilityMonitor.fromJson);

  @override
  Future<RelativeValueScreener> relativeValueScreener() => _getObject(
      '/analytics/relative-value', RelativeValueScreener.fromJson);

  @override
  Future<SpreadTerminal> spreadTerminal() =>
      _getObject('/analytics/spreads', SpreadTerminal.fromJson);

  // ── Stocks ─────────────────────────────────────────────────────────

  @override
  Future<List<StockSearchResult>> stockSearch(String query) => _getList(
      '/stocks/search', StockSearchResult.fromJson, query: {'q': query});

  @override
  Future<StockQuote> stockQuote(String symbol) =>
      _getObject('/stocks/quote/$symbol', StockQuote.fromJson);

  // ── Audit Trail / Decision Log ────────────────────────────────────

  @override
  Future<List<DecisionLogEntry>> decisionLog() =>
      _getList('/decision-log', DecisionLogEntry.fromJson, withAuth: true);

  @override
  Future<DecisionLogEntry> addDecisionLogEntry({
    required String commodity,
    required String userNote,
    String? cullyaiContext,
  }) =>
      _postObject(
        '/decision-log',
        {
          'commodity': commodity,
          'user_note': userNote,
          if (cullyaiContext != null) 'cullyai_context': cullyaiContext,
        },
        DecisionLogEntry.fromJson,
      );

  @override
  String complianceExportUrl() =>
      '$baseUrl/decision-log/compliance-export?token=${accessToken ?? ''}';

  @override
  String weeklyReportUrl() =>
      '$baseUrl/cullyai/report/weekly?token=${accessToken ?? ''}';

  // ── Custom Dashboards ──────────────────────────────────────────────

  @override
  Future<List<DashboardLayout>> dashboardLayouts() =>
      _getList('/dashboards', DashboardLayout.fromJson, withAuth: true);

  @override
  Future<DashboardLayout> saveDashboardLayout(String name, List<String> widgetIds) =>
      _postObject(
        '/dashboards',
        {'name': name, 'widget_ids': widgetIds},
        DashboardLayout.fromJson,
      );

  @override
  Future<void> deleteDashboardLayout(int id) => _delete('/dashboards/$id');

  // ── Intraday Futures ────────────────────────────────────────────────

  @override
  Future<IntradaySnapshot> futuresIntraday(String symbol) =>
      _getObject('/futures-intraday/$symbol', IntradaySnapshot.fromJson);

  // ── Community Insights ──────────────────────────────────────────────

  @override
  Future<List<CommunityInsight>> communityInsights({String? commodity}) => _getList(
      '/community-insights', CommunityInsight.fromJson,
      query: commodity != null ? {'commodity': commodity} : null, withAuth: true);

  @override
  Future<CommunityInsight> addCommunityInsight({
    required String commodity,
    required String body,
  }) =>
      _postObject(
        '/community-insights',
        {'commodity': commodity, 'body': body},
        CommunityInsight.fromJson,
      );

  // ── Croploo Learn ─────────────────────────────────────────────────────

  @override
  Future<List<LearnArticleSummary>> learnArticles() =>
      _getList('/learn', LearnArticleSummary.fromJson);

  @override
  Future<LearnArticle> learnArticle(String slug) =>
      _getObject('/learn/$slug', LearnArticle.fromJson);

  // ── Newsletter ────────────────────────────────────────────────────────

  @override
  Future<NewsletterIssue> newsletterLatest() =>
      _getObject('/newsletter/latest', NewsletterIssue.fromJson);

  @override
  Future<void> newsletterSubscribe(String email) async {
    final uri = Uri.parse('$baseUrl/newsletter/subscribe');
    await http
        .post(uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email}))
        .timeout(_offlineTimeout);
  }

  // ── Public Profile ────────────────────────────────────────────────────

  @override
  Future<PublicProfileSettings?> myPublicProfile() async {
    final uri = Uri.parse('$baseUrl/profile/me');
    final res = await http
        .get(uri, headers: {'Authorization': 'Bearer ${_requireToken()}'})
        .timeout(_offlineTimeout);
    if (res.statusCode != 200) throw Exception('profile/me failed: ${res.statusCode}');
    final decoded = jsonDecode(res.body);
    if (decoded == null) return null;
    return PublicProfileSettings.fromJson(decoded as Map<String, dynamic>);
  }

  @override
  Future<PublicProfileSettings> savePublicProfile({
    required String username,
    required bool isPublic,
    required List<String> trackedCommodities,
  }) async {
    final uri = Uri.parse('$baseUrl/profile/me');
    final res = await http
        .put(uri,
            headers: {
              'Authorization': 'Bearer ${_requireToken()}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'username': username,
              'is_public': isPublic,
              'tracked_commodities': trackedCommodities,
            }))
        .timeout(_offlineTimeout);
    if (res.statusCode != 200) throw Exception('profile/me save failed: ${res.statusCode}');
    return PublicProfileSettings.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  // ── Personalization ──────────────────────────────────────────────

  @override
  Future<List<WatchlistItem>> watchlist() =>
      _getListAuthed('/watchlist', WatchlistItem.fromJson);

  @override
  Future<WatchlistItem> addWatchlistItem(String commodity, String state) =>
      _postObject('/watchlist', {'commodity': commodity, 'state': state},
          WatchlistItem.fromJson);

  @override
  Future<void> removeWatchlistItem(int id) => _delete('/watchlist/$id');

  @override
  Future<List<CustomAlertRule>> customAlertRules() =>
      _getListAuthed('/custom-alert-rules', CustomAlertRule.fromJson);

  @override
  Future<CustomAlertRule> addCustomAlertRule({
    required String ruleType,
    required String commodity,
    String? state,
    required String comparison,
    required double thresholdValue,
  }) =>
      _postObject(
        '/custom-alert-rules',
        {
          'rule_type': ruleType,
          'commodity': commodity,
          if (state != null) 'state': state,
          'comparison': comparison,
          'threshold_value': thresholdValue,
        },
        CustomAlertRule.fromJson,
      );

  @override
  Future<void> removeCustomAlertRule(int id) =>
      _delete('/custom-alert-rules/$id');

  @override
  Future<List<PriceTarget>> priceTargets() =>
      _getListAuthed('/price-targets', PriceTarget.fromJson);

  @override
  Future<PriceTarget> addPriceTarget({
    required String symbol,
    required double targetPrice,
    required String direction,
  }) =>
      _postObject(
        '/price-targets',
        {'symbol': symbol, 'target_price': targetPrice, 'direction': direction},
        PriceTarget.fromJson,
      );

  @override
  Future<void> removePriceTarget(int id) => _delete('/price-targets/$id');

  @override
  Future<List<PortfolioPosition>> portfolio() =>
      _getListAuthed('/portfolio', PortfolioPosition.fromJson);

  @override
  Future<PortfolioPosition> addPortfolioPosition({
    required String commodity,
    required double bushels,
    required DateTime storedDate,
    required double breakEvenPrice,
    String? state,
  }) =>
      _postObject(
        '/portfolio',
        {
          'commodity': commodity,
          'bushels': bushels,
          'stored_date': storedDate.toIso8601String().substring(0, 10),
          'break_even_price': breakEvenPrice,
          if (state != null) 'state': state,
        },
        PortfolioPosition.fromJson,
      );

  @override
  Future<void> removePortfolioPosition(int id) => _delete('/portfolio/$id');

  // ── Trust / transparency ─────────────────────────────────────────

  @override
  Future<WasdeSurpriseReport> wasdeSurprises(String commodity) => _getObject(
      '/usda/wasde-surprises', WasdeSurpriseReport.fromJson,
      query: {'commodity': commodity});

  @override
  Future<ExportSalesReport> exportSales(String commodity) => _getObject(
      '/usda/export-sales', ExportSalesReport.fromJson,
      query: {'commodity': commodity});

  @override
  Future<List<DataSourceStatus>> status() =>
      _getList('/status', DataSourceStatus.fromJson);

  // ── Preferences ───────────────────────────────────────────────────

  @override
  Future<CroplooUser> setDailyBriefEmail(bool enabled) async {
    final res = await http.put(
      Uri.parse('$baseUrl/auth/me/preferences'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_requireToken()}',
      },
      body: jsonEncode({'daily_brief_email': enabled}),
    );
    if (res.statusCode != 200) {
      throw Exception('setDailyBriefEmail failed: ${res.statusCode}');
    }
    return CroplooUser.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  // ── Account ───────────────────────────────────────────────────────

  @override
  Future<CroplooUser> updateAccount({String? name, String? email, String? username}) async {
    final res = await http.put(
      Uri.parse('$baseUrl/auth/me'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_requireToken()}',
      },
      body: jsonEncode({
        if (name != null) 'name': name,
        if (email != null) 'email': email,
        if (username != null) 'username': username,
      }),
    );
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['detail'] ?? 'updateAccount failed: ${res.statusCode}');
    }
    return CroplooUser.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/change-password'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_requireToken()}',
      },
      body: jsonEncode({
        'current_password': currentPassword,
        'new_password': newPassword,
      }),
    );
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['detail'] ?? 'changePassword failed: ${res.statusCode}');
    }
  }

  // ── Export ────────────────────────────────────────────────────────

  @override
  String basisHistoryExportUrl(int elevatorId, String commodity, String range) =>
      Uri.parse('$baseUrl/basis-history/export').replace(queryParameters: {
        'elevatorId': '$elevatorId',
        'commodity': commodity,
        'range': range,
      }).toString();

  @override
  String alertsExportUrl() => '$baseUrl/alerts/export';

  @override
  String wasdeSurprisesExportUrl(String commodity) =>
      Uri.parse('$baseUrl/usda/wasde-surprises/export')
          .replace(queryParameters: {'commodity': commodity}).toString();

  // ── Growth ────────────────────────────────────────────────────────

  @override
  Future<ReferralSummary> referralSummary() async {
    final res = await http.get(
      Uri.parse('$baseUrl/auth/referrals'),
      headers: {'Authorization': 'Bearer ${_requireToken()}'},
    );
    if (res.statusCode != 200) {
      throw Exception('referralSummary failed: ${res.statusCode}');
    }
    return ReferralSummary.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<CroplooUser> startTrial() async {
    final res = await http.post(
      Uri.parse('$baseUrl/billing/start-trial'),
      headers: {'Authorization': 'Bearer ${_requireToken()}'},
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(body['detail'] as String? ?? 'startTrial failed: ${res.statusCode}');
    }
    return me();
  }

  @override
  String basisWidgetEmbedUrl(String state, String commodity) {
    // The widget lives outside /v1 (it's a public HTML page, not a JSON
    // API endpoint), so strip the /v1 suffix baseUrl carries.
    final root = baseUrl.endsWith('/v1') ? baseUrl.substring(0, baseUrl.length - 3) : baseUrl;
    return Uri.parse('$root/widget/basis')
        .replace(queryParameters: {'state': state, 'commodity': commodity}).toString();
  }
}
