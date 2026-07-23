/// Croploo data models. All `fromJson` factories match the backend API
/// contract (api.croploo.app/v1) so the mock repository can be swapped
/// for a live Dio-backed implementation without touching the UI.
library;

/// Ordered low-to-high — index comparisons (see [SubscriptionTierX.atLeast])
/// depend on this order matching the plan hierarchy.
enum SubscriptionTier { free, basic, pro, desk, team, institutional }

extension SubscriptionTierX on SubscriptionTier {
  /// True if this tier's plan includes everything [min] includes, e.g. a
  /// Desk or Terminal user viewing a Pro-gated feature.
  bool atLeast(SubscriptionTier min) => index >= min.index;
}

enum MarketDirection { bullish, bearish, neutral }

enum AlertPriority { high, medium, low }

MarketDirection directionFromString(String s) => switch (s.toLowerCase()) {
      'bullish' => MarketDirection.bullish,
      'bearish' => MarketDirection.bearish,
      _ => MarketDirection.neutral,
    };

class CroplooUser {
  final String id;
  final String email;
  final String username;
  final String name;
  final SubscriptionTier tier;
  final bool dailyBriefEmail;
  final String? referralCode;
  final DateTime? trialEndsAt;
  final bool hasUsedTrial;
  final String? teamId;
  final String? teamRole;

  const CroplooUser({
    required this.id,
    required this.email,
    required this.username,
    required this.name,
    required this.tier,
    this.dailyBriefEmail = true,
    this.referralCode,
    this.trialEndsAt,
    this.hasUsedTrial = false,
    this.teamId,
    this.teamRole,
  });

  factory CroplooUser.fromJson(Map<String, dynamic> j) => CroplooUser(
        id: j['id'] as String,
        email: j['email'] as String,
        username: (j['username'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        tier: SubscriptionTier.values.firstWhere(
          (t) => t.name == j['subscription_tier'],
          orElse: () => SubscriptionTier.free,
        ),
        dailyBriefEmail: (j['daily_brief_email'] as bool?) ?? true,
        referralCode: j['referral_code'] as String?,
        trialEndsAt: j['trial_ends_at'] != null
            ? DateTime.tryParse(j['trial_ends_at'] as String)
            : null,
        hasUsedTrial: (j['has_used_trial'] as bool?) ?? false,
        teamId: j['team_id'] as String?,
        teamRole: j['team_role'] as String?,
      );

  bool get onTrial => trialEndsAt != null && trialEndsAt!.isAfter(DateTime.now());
}

class Commodity {
  final String symbol; // 'ZC'
  final String name; // 'Corn'

  const Commodity({required this.symbol, required this.name});

  factory Commodity.fromJson(Map<String, dynamic> j) =>
      Commodity(symbol: j['symbol'] as String, name: j['name'] as String);
}

class FuturesPrice {
  final String symbol;
  final String name;
  final String contractMonth;
  final double price; // cents/bushel
  final double change;
  final double changePct;
  final String? source;
  final DateTime? asOf;

  const FuturesPrice({
    required this.symbol,
    required this.name,
    required this.contractMonth,
    required this.price,
    required this.change,
    required this.changePct,
    this.source,
    this.asOf,
  });

  factory FuturesPrice.fromJson(Map<String, dynamic> j) => FuturesPrice(
        symbol: j['symbol'] as String,
        name: j['name'] as String,
        contractMonth: j['contract_month'] as String,
        price: (j['price'] as num).toDouble(),
        change: (j['change'] as num).toDouble(),
        changePct: (j['change_pct'] as num).toDouble(),
        source: j['source'] as String?,
        asOf: j['as_of'] != null ? DateTime.tryParse(j['as_of'] as String) : null,
      );
}

class ElevatorLocation {
  final int id;
  final String name;
  final String city;
  final String state;
  final double lat;
  final double lng;

  const ElevatorLocation({
    required this.id,
    required this.name,
    required this.city,
    required this.state,
    required this.lat,
    required this.lng,
  });

  factory ElevatorLocation.fromJson(Map<String, dynamic> j) =>
      ElevatorLocation(
        id: j['id'] as int,
        name: j['name'] as String,
        city: (j['city'] ?? '') as String,
        state: (j['state'] ?? '') as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
      );
}

class BasisSnapshot {
  final ElevatorLocation elevator;
  final Commodity commodity;
  final double basisValue; // ¢/bu, cash - futures
  final double cashPrice;
  final double futuresPrice;
  final double avg5yr;
  final double deviationFromAvg; // cents
  final double deviationPct;
  final DateTime snapshotDate;
  final String? source;

  const BasisSnapshot({
    required this.elevator,
    required this.commodity,
    required this.basisValue,
    required this.cashPrice,
    required this.futuresPrice,
    required this.avg5yr,
    required this.deviationFromAvg,
    required this.deviationPct,
    required this.snapshotDate,
    this.source,
  });

  factory BasisSnapshot.fromJson(Map<String, dynamic> j) => BasisSnapshot(
        elevator:
            ElevatorLocation.fromJson(j['elevator'] as Map<String, dynamic>),
        commodity:
            Commodity.fromJson(j['commodity'] as Map<String, dynamic>),
        basisValue: (j['basis_value'] as num).toDouble(),
        cashPrice: (j['cash_price'] as num).toDouble(),
        futuresPrice: (j['futures_price'] as num).toDouble(),
        avg5yr: (j['avg_5yr'] as num).toDouble(),
        deviationFromAvg: (j['deviation_from_avg'] as num).toDouble(),
        deviationPct: (j['deviation_pct'] as num).toDouble(),
        snapshotDate: DateTime.parse(j['snapshot_date'] as String),
        source: j['source'] as String?,
      );

  bool get isExtreme => deviationFromAvg.abs() > 15;
  AlertPriority get signalStrength => deviationPct.abs() > 20
      ? AlertPriority.high
      : (deviationPct.abs() > 10 ? AlertPriority.medium : AlertPriority.low);
}

class BasisPoint {
  final DateTime date;
  final double basis;
  final double avg5yr;

  const BasisPoint(
      {required this.date, required this.basis, required this.avg5yr});

  factory BasisPoint.fromJson(Map<String, dynamic> j) => BasisPoint(
        date: DateTime.parse(j['date'] as String),
        basis: (j['basis'] as num).toDouble(),
        avg5yr: (j['avg_5yr'] as num).toDouble(),
      );

  double get deviation => basis - avg5yr;
}

class CommodityImpact {
  final String commodity;
  final MarketDirection direction;
  final String reasoning;
  final String basisImpact;

  const CommodityImpact({
    required this.commodity,
    required this.direction,
    required this.reasoning,
    required this.basisImpact,
  });

  factory CommodityImpact.fromJson(Map<String, dynamic> j) => CommodityImpact(
        commodity: j['commodity'] as String,
        direction: directionFromString(j['direction'] as String),
        reasoning: (j['reasoning'] ?? '') as String,
        basisImpact: (j['basis_impact'] ?? '') as String,
      );
}

class DataComparisonRow {
  final String metric;
  final String previous;
  final String current;
  final String change;
  final bool highlight;

  const DataComparisonRow({
    required this.metric,
    required this.previous,
    required this.current,
    required this.change,
    this.highlight = false,
  });

  factory DataComparisonRow.fromJson(Map<String, dynamic> j) => DataComparisonRow(
        metric: j['metric'] as String,
        previous: j['previous'] as String,
        current: j['current'] as String,
        change: j['change'] as String,
        highlight: (j['highlight'] as bool?) ?? false,
      );
}

class UsdaReport {
  final int id;
  final String reportType; // 'WASDE' | 'CROP_PROGRESS' | 'EXPORT_SALES'
  final String title;
  final DateTime releaseDate;
  final DateTime? aiProcessedAt;
  final String aiHeadline;
  final MarketDirection aiDirection;
  final String aiSummary;
  final List<String> aiKeyPoints;
  final List<CommodityImpact> commodityImpacts;
  final List<String> riskFactors;
  final String basisImpact;
  final double confidence;
  final String comparisonTitle;
  final List<DataComparisonRow> comparison;
  final String? source;
  final DateTime? asOf;

  const UsdaReport({
    required this.id,
    required this.reportType,
    required this.title,
    required this.releaseDate,
    this.aiProcessedAt,
    required this.aiHeadline,
    required this.aiDirection,
    required this.aiSummary,
    required this.aiKeyPoints,
    required this.commodityImpacts,
    required this.riskFactors,
    required this.basisImpact,
    required this.confidence,
    this.comparisonTitle = '',
    this.comparison = const [],
    this.source,
    this.asOf,
  });

  factory UsdaReport.fromJson(Map<String, dynamic> j) => UsdaReport(
        id: j['id'] as int,
        reportType: j['report_type'] as String,
        title: j['title'] as String,
        releaseDate: DateTime.parse(j['release_date'] as String),
        aiProcessedAt: j['ai_processed_at'] != null
            ? DateTime.parse(j['ai_processed_at'] as String)
            : null,
        aiHeadline: (j['ai_headline'] ?? '') as String,
        aiDirection: directionFromString((j['ai_direction'] ?? 'NEUTRAL') as String),
        aiSummary: (j['ai_summary'] ?? '') as String,
        aiKeyPoints: ((j['ai_key_points'] as List?) ?? [])
            .map((e) => e as String)
            .toList(),
        commodityImpacts: ((j['commodity_impacts'] as List?) ?? [])
            .map((e) => CommodityImpact.fromJson(e as Map<String, dynamic>))
            .toList(),
        riskFactors: ((j['risk_factors'] as List?) ?? [])
            .map((e) => e as String)
            .toList(),
        basisImpact: (j['basis_impact'] ?? '') as String,
        confidence: ((j['confidence'] as num?) ?? 0.5).toDouble(),
        comparisonTitle: (j['comparison_title'] ?? '') as String,
        comparison: ((j['comparison'] as List?) ?? [])
            .map((e) => DataComparisonRow.fromJson(e as Map<String, dynamic>))
            .toList(),
        source: j['source'] as String?,
        asOf: j['as_of'] != null ? DateTime.tryParse(j['as_of'] as String) : null,
      );

  String get typeLabel => switch (reportType) {
        'WASDE' => 'WASDE',
        'CROP_PROGRESS' => 'Crop Progress',
        'EXPORT_SALES' => 'Export Sales',
        _ => reportType,
      };
}

class UsdaRelease {
  final String reportType;
  final DateTime releaseDate;

  const UsdaRelease({required this.reportType, required this.releaseDate});

  factory UsdaRelease.fromJson(Map<String, dynamic> j) => UsdaRelease(
        reportType: j['report_type'] as String,
        releaseDate: DateTime.parse(j['release_date'] as String),
      );
}

/// What actually happened to the underlying value after an alert fired —
/// e.g. "basis 12¢ tighter 3 weeks later" — computed by the backend from
/// the alert's own trigger-time value plus the current live one.
class AlertOutcome {
  final String metric; // 'basis' | 'price'
  final double valueAtAlert;
  final double valueNow;
  final double change;
  final DateTime asOf;

  const AlertOutcome({
    required this.metric,
    required this.valueAtAlert,
    required this.valueNow,
    required this.change,
    required this.asOf,
  });

  factory AlertOutcome.fromJson(Map<String, dynamic> j) => AlertOutcome(
        metric: j['metric'] as String,
        valueAtAlert: (j['value_at_alert'] as num).toDouble(),
        valueNow: (j['value_now'] as num).toDouble(),
        change: (j['change'] as num).toDouble(),
        asOf: DateTime.parse(j['as_of'] as String),
      );
}

class CroplooAlert {
  final int id;
  final String alertType; // 'basis' | 'usda' | 'freight' | 'price'
  final AlertPriority priority;
  final String title;
  final String body;
  final DateTime triggeredAt;
  final bool isRead;
  final AlertOutcome? outcome;
  final String commodity;
  final Map<String, dynamic> metadata;

  const CroplooAlert({
    required this.id,
    required this.alertType,
    required this.priority,
    required this.title,
    required this.body,
    required this.triggeredAt,
    this.isRead = false,
    this.outcome,
    this.commodity = 'ALL',
    this.metadata = const {},
  });

  factory CroplooAlert.fromJson(Map<String, dynamic> j) => CroplooAlert(
        id: j['id'] as int,
        alertType: switch (j['type'] as String) {
          'BASIS_ANOMALY' => 'basis',
          'USDA_RELEASE' => 'usda',
          'FUTURES_MOVE' => 'price',
          _ => 'basis',
        },
        priority: AlertPriority.values.firstWhere(
          (p) => p.name == (j['severity'] as String).toLowerCase(),
          orElse: () => AlertPriority.low,
        ),
        title: j['title'] as String,
        body: (j['body'] ?? '') as String,
        triggeredAt: DateTime.parse(j['created_at'] as String),
        isRead: (j['is_read'] as bool?) ?? false,
        outcome: j['outcome'] != null
            ? AlertOutcome.fromJson(j['outcome'] as Map<String, dynamic>)
            : null,
        commodity: (j['commodity'] as String?) ?? 'ALL',
        metadata: (j['metadata'] as Map<String, dynamic>?) ?? const {},
      );

  CroplooAlert copyWith({bool? isRead}) => CroplooAlert(
        id: id,
        alertType: alertType,
        priority: priority,
        title: title,
        body: body,
        triggeredAt: triggeredAt,
        isRead: isRead ?? this.isRead,
        outcome: outcome,
        commodity: commodity,
        metadata: metadata,
      );

  /// A first-person prompt describing why this alert fired, used to seed
  /// CullyAI with full context the moment the user taps the alert — see
  /// Function 8 ("Alert-Kontext") in the CullyAI spec.
  String get cullyAiPrompt {
    final buffer = StringBuffer(
        'I just got this alert: "$title" — $body. Commodity: $commodity.');
    if (metadata.isNotEmpty) {
      buffer.write(' Details: $metadata.');
    }
    buffer.write(
        ' Pull the relevant real data and explain why this is happening, '
        'any historical parallels, and what I should consider doing.');
    return buffer.toString();
  }
}

class AlertRule {
  final int id;
  final String ruleType; // 'basis_deviation' | 'usda_release' | ...
  final String description;
  final String detail;
  final bool isActive;

  const AlertRule({
    required this.id,
    required this.ruleType,
    required this.description,
    required this.detail,
    this.isActive = true,
  });

  factory AlertRule.fromJson(Map<String, dynamic> j) => AlertRule(
        id: j['id'] as int,
        ruleType: j['rule_type'] as String,
        description: j['description'] as String,
        detail: j['detail'] as String,
        isActive: (j['is_active'] as bool?) ?? true,
      );
}

class FreightRate {
  final String corridor;
  final String mode; // truck | barge | rail
  final double rateValue;
  final String unit;
  final double weekChangePct;

  const FreightRate({
    required this.corridor,
    required this.mode,
    required this.rateValue,
    required this.unit,
    required this.weekChangePct,
  });

  factory FreightRate.fromJson(Map<String, dynamic> j) => FreightRate(
        corridor: j['corridor'] as String,
        mode: j['mode'] as String,
        rateValue: (j['rate_value'] as num).toDouble(),
        unit: j['unit'] as String,
        weekChangePct: (j['week_change_pct'] as num).toDouble(),
      );
}

class FreightPoint {
  final DateTime date;
  final double freight;
  final double basis;

  const FreightPoint(
      {required this.date, required this.freight, required this.basis});

  factory FreightPoint.fromJson(Map<String, dynamic> j) => FreightPoint(
        date: DateTime.parse(j['date'] as String),
        freight: (j['freight'] as num).toDouble(),
        basis: (j['basis'] as num).toDouble(),
      );
}

class RailCarLoadingWeek {
  final DateTime week;
  final int totalCars;
  final int shuttleCars;

  const RailCarLoadingWeek(
      {required this.week, required this.totalCars, required this.shuttleCars});

  factory RailCarLoadingWeek.fromJson(Map<String, dynamic> j) =>
      RailCarLoadingWeek(
        week: DateTime.parse(j['week'] as String),
        totalCars: (j['total_cars'] as num).toInt(),
        shuttleCars: (j['shuttle_cars'] as num).toInt(),
      );
}

class RailCarLoadings {
  final String state;
  final String? source;
  final List<RailCarLoadingWeek> history;

  const RailCarLoadings(
      {required this.state, this.source, required this.history});

  factory RailCarLoadings.fromJson(Map<String, dynamic> j) => RailCarLoadings(
        state: j['state'] as String,
        source: j['source'] as String?,
        history: (j['history'] as List)
            .map((e) => RailCarLoadingWeek.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class RiverGaugeReading {
  final DateTime date;
  final double stageFt;
  final double flowKcfs;

  const RiverGaugeReading(
      {required this.date, required this.stageFt, required this.flowKcfs});

  factory RiverGaugeReading.fromJson(Map<String, dynamic> j) =>
      RiverGaugeReading(
        date: DateTime.parse(j['date'] as String),
        stageFt: (j['stage_ft'] as num).toDouble(),
        flowKcfs: (j['flow_kcfs'] as num).toDouble(),
      );
}

class RiverGaugeStation {
  final String lid;
  final String name;
  final String state;
  final double lat;
  final double lng;
  final String? source;
  final List<RiverGaugeReading> history;

  const RiverGaugeStation({
    required this.lid,
    required this.name,
    required this.state,
    required this.lat,
    required this.lng,
    this.source,
    required this.history,
  });

  double? get latestStageFt => history.isEmpty ? null : history.last.stageFt;

  factory RiverGaugeStation.fromJson(Map<String, dynamic> j) =>
      RiverGaugeStation(
        lid: j['lid'] as String,
        name: j['name'] as String,
        state: j['state'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        source: j['source'] as String?,
        history: (j['history'] as List)
            .map((e) => RiverGaugeReading.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class DailyBrief {
  final DateTime date;
  final String summary;
  final List<String> topOpportunities;
  final List<String> riskFactors;
  final List<String> keyEventsThisWeek;

  const DailyBrief({
    required this.date,
    required this.summary,
    required this.topOpportunities,
    required this.riskFactors,
    required this.keyEventsThisWeek,
  });

  factory DailyBrief.fromJson(Map<String, dynamic> j) => DailyBrief(
        date: DateTime.parse(j['date'] as String),
        summary: (j['summary'] ?? '') as String,
        topOpportunities: ((j['top_opportunities'] as List?) ?? [])
            .map((e) => e as String)
            .toList(),
        riskFactors: ((j['risk_factors'] as List?) ?? [])
            .map((e) => e as String)
            .toList(),
        keyEventsThisWeek: ((j['key_events_this_week'] as List?) ?? [])
            .map((e) => e as String)
            .toList(),
      );
}

/// One SSE event from `/cullyai/chat`: a text delta to append, a chart
/// block CullyAI rendered via the `render_chart` tool, or a transient
/// status label (e.g. "Checking live market data…") shown only while
/// waiting for the first real token — never appended to the message text.
class CullyChatEvent {
  final String? textDelta;
  final ChartSpec? chart;
  final String? status;

  const CullyChatEvent.text(String delta)
      : textDelta = delta,
        chart = null,
        status = null;
  const CullyChatEvent.chart(ChartSpec spec)
      : textDelta = null,
        chart = spec,
        status = null;
  const CullyChatEvent.status(String label)
      : textDelta = null,
        chart = null,
        status = label;
}

class ChatMessage {
  final bool fromUser;
  final String text;
  final DateTime at;
  // Charts CullyAI rendered alongside this message via the `render_chart`
  // tool. Appended below the text rather than interleaved mid-paragraph —
  // simpler than a full ordered content-block model and covers the same
  // user-visible outcome (chart shows up in the reply).
  final List<ChartSpec> charts;
  // Transient "what CullyAI is doing right now" label (e.g. "Checking live
  // market data…"), shown only until the first real token arrives — never
  // part of the persisted message text.
  final String? statusLabel;

  const ChatMessage({
    required this.fromUser,
    required this.text,
    required this.at,
    this.charts = const [],
    this.statusLabel,
  });
}

enum ChartKind { line, bar, area }

class ChartPoint {
  final String x;
  final double y;

  const ChartPoint({required this.x, required this.y});

  factory ChartPoint.fromJson(Map<String, dynamic> j) => ChartPoint(
        x: j['x'].toString(),
        y: (j['y'] as num).toDouble(),
      );
}

class ChartSeries {
  final String label;
  final List<ChartPoint> points;

  const ChartSeries({required this.label, required this.points});

  factory ChartSeries.fromJson(Map<String, dynamic> j) => ChartSeries(
        label: j['label'] as String? ?? '',
        points: ((j['points'] as List?) ?? [])
            .map((e) => ChartPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Mirrors the `render_chart` tool's input schema (see
/// backend/src/aiTools.js) — CullyAI calls that tool with real data it
/// already pulled via a query tool, never invented numbers.
class ChartSpec {
  final ChartKind kind;
  final String title;
  final String? xLabel;
  final String? yLabel;
  final List<ChartSeries> series;

  const ChartSpec({
    required this.kind,
    required this.title,
    this.xLabel,
    this.yLabel,
    required this.series,
  });

  factory ChartSpec.fromJson(Map<String, dynamic> j) => ChartSpec(
        kind: switch (j['chart_type']) {
          'bar' => ChartKind.bar,
          'area' => ChartKind.area,
          _ => ChartKind.line,
        },
        title: j['title'] as String? ?? '',
        xLabel: j['x_label'] as String?,
        yLabel: j['y_label'] as String?,
        series: ((j['series'] as List?) ?? [])
            .map((e) => ChartSeries.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class TickerItem {
  final String label; // 'CBOT CORN'
  final double basis; // ¢
  final bool extreme;

  const TickerItem(
      {required this.label, required this.basis, this.extreme = false});

  factory TickerItem.fromJson(Map<String, dynamic> j) => TickerItem(
        label: j['label'] as String,
        basis: (j['basis'] as num).toDouble(),
        extreme: (j['extreme'] as bool?) ?? false,
      );
}

class FuturesHistoryPoint {
  final DateTime date;
  final double close;

  const FuturesHistoryPoint({required this.date, required this.close});

  factory FuturesHistoryPoint.fromJson(Map<String, dynamic> j) =>
      FuturesHistoryPoint(
        date: DateTime.parse(j['date'] as String),
        close: (j['close'] as num).toDouble(),
      );
}

// ── Market Intel: COT, Seasonal, Weather, Crop Tour, Crush ──────────

class CotPosition {
  final int long;
  final int short;
  final int net;
  final int netChange;

  const CotPosition({
    required this.long,
    required this.short,
    required this.net,
    required this.netChange,
  });

  factory CotPosition.fromJson(Map<String, dynamic> j) => CotPosition(
        long: (j['long'] as num).toInt(),
        short: (j['short'] as num).toInt(),
        net: (j['net'] as num).toInt(),
        netChange: (j['netChange'] as num).toInt(),
      );
}

class CotNetPoint {
  final DateTime date;
  final int net;

  const CotNetPoint({required this.date, required this.net});

  factory CotNetPoint.fromJson(Map<String, dynamic> j) => CotNetPoint(
        date: DateTime.parse(j['date'] as String),
        net: (j['net'] as num).toInt(),
      );
}

class CotCommoditySnapshot {
  final String commodity;
  final DateTime reportDate;
  final int openInterest;
  final CotPosition managedMoney;
  final CotPosition commercials;
  final int netPercentile3y;
  final String contrarianSignal;
  final String readout;
  final String contrarianNote;
  final List<CotNetPoint> netHistory;

  const CotCommoditySnapshot({
    required this.commodity,
    required this.reportDate,
    required this.openInterest,
    required this.managedMoney,
    required this.commercials,
    required this.netPercentile3y,
    required this.contrarianSignal,
    required this.readout,
    required this.contrarianNote,
    required this.netHistory,
  });

  factory CotCommoditySnapshot.fromJson(Map<String, dynamic> j) =>
      CotCommoditySnapshot(
        commodity: j['commodity'] as String,
        reportDate: DateTime.parse(j['report_date'] as String),
        openInterest: (j['open_interest'] as num).toInt(),
        managedMoney:
            CotPosition.fromJson(j['managed_money'] as Map<String, dynamic>),
        commercials:
            CotPosition.fromJson(j['commercials'] as Map<String, dynamic>),
        netPercentile3y: (j['net_percentile_3y'] as num).toInt(),
        contrarianSignal: j['contrarian_signal'] as String,
        readout: (j['readout'] ?? '') as String,
        contrarianNote: (j['contrarian_note'] ?? '') as String,
        netHistory: ((j['net_history'] as List?) ?? [])
            .map((e) => CotNetPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class CotReport {
  final DateTime? reportDate;
  final String summary;
  final List<CotCommoditySnapshot> commodities;

  const CotReport({
    required this.reportDate,
    required this.summary,
    required this.commodities,
  });

  factory CotReport.fromJson(Map<String, dynamic> j) => CotReport(
        reportDate: j['report_date'] != null
            ? DateTime.parse(j['report_date'] as String)
            : null,
        summary: (j['summary'] ?? '') as String,
        commodities: ((j['commodities'] as List?) ?? [])
            .map((e) =>
                CotCommoditySnapshot.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class SeasonalWeek {
  final int week;
  final double? avg5yr;
  final double? avg10yr;
  final double? current;
  final double? currentPrice;

  const SeasonalWeek({
    required this.week,
    this.avg5yr,
    this.avg10yr,
    this.current,
    this.currentPrice,
  });

  factory SeasonalWeek.fromJson(Map<String, dynamic> j) => SeasonalWeek(
        week: (j['week'] as num).toInt(),
        avg5yr: (j['avg_5y'] as num?)?.toDouble(),
        avg10yr: (j['avg_10y'] as num?)?.toDouble(),
        current: (j['current'] as num?)?.toDouble(),
        currentPrice: (j['current_price'] as num?)?.toDouble(),
      );
}

class SeasonalPattern {
  final String symbol;
  final int currentYear;
  final int yearsAvailable;
  final List<SeasonalWeek> weeks;

  const SeasonalPattern({
    required this.symbol,
    required this.currentYear,
    required this.yearsAvailable,
    required this.weeks,
  });

  factory SeasonalPattern.fromJson(Map<String, dynamic> j) => SeasonalPattern(
        symbol: j['symbol'] as String,
        currentYear: (j['current_year'] as num).toInt(),
        yearsAvailable: (j['years_available'] as num).toInt(),
        weeks: ((j['weeks'] as List?) ?? [])
            .map((e) => SeasonalWeek.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class WeatherStateImpact {
  final String state;
  final String name;
  final String period;
  final double precip1mDeparturePct;
  final double precip3mDeparturePct;
  final double precip3mInches;
  final double precip3mNormalInches;
  final String severity;
  final String implication;

  const WeatherStateImpact({
    required this.state,
    required this.name,
    required this.period,
    required this.precip1mDeparturePct,
    required this.precip3mDeparturePct,
    required this.precip3mInches,
    required this.precip3mNormalInches,
    required this.severity,
    required this.implication,
  });

  factory WeatherStateImpact.fromJson(Map<String, dynamic> j) =>
      WeatherStateImpact(
        state: j['state'] as String,
        name: j['name'] as String,
        period: (j['period'] ?? '') as String,
        precip1mDeparturePct: (j['precip_1m_departure_pct'] as num).toDouble(),
        precip3mDeparturePct: (j['precip_3m_departure_pct'] as num).toDouble(),
        precip3mInches: (j['precip_3m_inches'] as num).toDouble(),
        precip3mNormalInches:
            (j['precip_3m_normal_inches'] as num).toDouble(),
        severity: j['severity'] as String,
        implication: (j['implication'] ?? '') as String,
      );
}

class DroughtSnapshot {
  final String state;
  final String name;
  final DateTime mapDate;
  final double nonePct;
  final double d0Pct;
  final double d1Pct;
  final double d2Pct;
  final double d3Pct;
  final double d4Pct;
  final double anyDroughtPct;

  const DroughtSnapshot({
    required this.state,
    required this.name,
    required this.mapDate,
    required this.nonePct,
    required this.d0Pct,
    required this.d1Pct,
    required this.d2Pct,
    required this.d3Pct,
    required this.d4Pct,
    required this.anyDroughtPct,
  });

  /// Worst category with non-trivial coverage (>1%), for a single badge —
  /// mirrors how droughtmonitor.unl.edu itself headlines a state.
  String get worstCategory {
    if (d4Pct > 1) return 'D4';
    if (d3Pct > 1) return 'D3';
    if (d2Pct > 1) return 'D2';
    if (d1Pct > 1) return 'D1';
    if (d0Pct > 1) return 'D0';
    return 'None';
  }

  factory DroughtSnapshot.fromJson(Map<String, dynamic> j) => DroughtSnapshot(
        state: j['state'] as String,
        name: j['name'] as String,
        mapDate: DateTime.parse(j['map_date'] as String),
        nonePct: (j['none_pct'] as num).toDouble(),
        d0Pct: (j['d0_pct'] as num).toDouble(),
        d1Pct: (j['d1_pct'] as num).toDouble(),
        d2Pct: (j['d2_pct'] as num).toDouble(),
        d3Pct: (j['d3_pct'] as num).toDouble(),
        d4Pct: (j['d4_pct'] as num).toDouble(),
        anyDroughtPct: (j['any_drought_pct'] as num).toDouble(),
      );
}

class WeatherImpact {
  final String headline;
  final String summary;
  final List<WeatherStateImpact> states;

  const WeatherImpact({
    required this.headline,
    required this.summary,
    required this.states,
  });

  factory WeatherImpact.fromJson(Map<String, dynamic> j) => WeatherImpact(
        headline: (j['headline'] ?? '') as String,
        summary: (j['summary'] ?? '') as String,
        states: ((j['states'] as List?) ?? [])
            .map((e) => WeatherStateImpact.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class CropTourYear {
  final int year;
  final double proFarmer;
  final double usda;
  final bool usdaIsFinal;
  final double diff;

  const CropTourYear({
    required this.year,
    required this.proFarmer,
    required this.usda,
    required this.usdaIsFinal,
    required this.diff,
  });

  factory CropTourYear.fromJson(Map<String, dynamic> j) => CropTourYear(
        year: (j['year'] as num).toInt(),
        proFarmer: (j['pro_farmer'] as num).toDouble(),
        usda: (j['usda'] as num).toDouble(),
        usdaIsFinal: (j['usda_is_final'] as bool?) ?? false,
        diff: (j['diff'] as num).toDouble(),
      );
}

class CropTourComparison {
  final String commodity;
  final String headline;
  final String summary;
  final String trackRecord;
  final List<CropTourYear> years;

  const CropTourComparison({
    required this.commodity,
    required this.headline,
    required this.summary,
    required this.trackRecord,
    required this.years,
  });

  factory CropTourComparison.fromJson(Map<String, dynamic> j) =>
      CropTourComparison(
        commodity: j['commodity'] as String,
        headline: (j['headline'] ?? '') as String,
        summary: (j['summary'] ?? '') as String,
        trackRecord: (j['track_record'] ?? '') as String,
        years: ((j['years'] as List?) ?? [])
            .map((e) => CropTourYear.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class CrushLegs {
  final double soybeansCentsBu;
  final double oilCentsLb;
  final double mealUsdTon;
  final double oilValueUsdBu;
  final double mealValueUsdBu;

  const CrushLegs({
    required this.soybeansCentsBu,
    required this.oilCentsLb,
    required this.mealUsdTon,
    required this.oilValueUsdBu,
    required this.mealValueUsdBu,
  });

  factory CrushLegs.fromJson(Map<String, dynamic> j) => CrushLegs(
        soybeansCentsBu: (j['soybeans_cents_bu'] as num).toDouble(),
        oilCentsLb: (j['oil_cents_lb'] as num).toDouble(),
        mealUsdTon: (j['meal_usd_ton'] as num).toDouble(),
        oilValueUsdBu: (j['oil_value_usd_bu'] as num).toDouble(),
        mealValueUsdBu: (j['meal_value_usd_bu'] as num).toDouble(),
      );
}

class CrushHistoryPoint {
  final DateTime date;
  final double crush;

  const CrushHistoryPoint({required this.date, required this.crush});

  factory CrushHistoryPoint.fromJson(Map<String, dynamic> j) =>
      CrushHistoryPoint(
        date: DateTime.parse(j['date'] as String),
        crush: (j['crush'] as num).toDouble(),
      );
}

class CrushSpread {
  final DateTime date;
  final double crush;
  final double change1w;
  final double avgPeriod;
  final CrushLegs legs;
  final List<CrushHistoryPoint> history;

  const CrushSpread({
    required this.date,
    required this.crush,
    required this.change1w,
    required this.avgPeriod,
    required this.legs,
    required this.history,
  });

  factory CrushSpread.fromJson(Map<String, dynamic> j) => CrushSpread(
        date: DateTime.parse(j['date'] as String),
        crush: (j['crush'] as num).toDouble(),
        change1w: (j['change_1w'] as num).toDouble(),
        avgPeriod: (j['avg_period'] as num).toDouble(),
        legs: CrushLegs.fromJson(j['legs'] as Map<String, dynamic>),
        history: ((j['history'] as List?) ?? [])
            .map((e) => CrushHistoryPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ── Personalization: Watchlist, Custom Alert Rules, Price Targets,
//    Portfolio ───────────────────────────────────────────────────────

class WatchlistItem {
  final int id;
  final String commodity;
  final String state;

  const WatchlistItem({
    required this.id,
    required this.commodity,
    required this.state,
  });

  factory WatchlistItem.fromJson(Map<String, dynamic> j) => WatchlistItem(
        id: j['id'] as int,
        commodity: j['commodity'] as String,
        state: j['state'] as String,
      );
}

class CustomAlertRule {
  final int id;
  final String ruleType; // 'BASIS_THRESHOLD' | 'FUTURES_MOVE_THRESHOLD'
  final String commodity;
  final String? state;
  final String comparison; // 'BELOW' | 'ABOVE'
  final double thresholdValue;
  final bool isActive;

  const CustomAlertRule({
    required this.id,
    required this.ruleType,
    required this.commodity,
    this.state,
    required this.comparison,
    required this.thresholdValue,
    required this.isActive,
  });

  factory CustomAlertRule.fromJson(Map<String, dynamic> j) => CustomAlertRule(
        id: j['id'] as int,
        ruleType: j['rule_type'] as String,
        commodity: j['commodity'] as String,
        state: j['state'] as String?,
        comparison: j['comparison'] as String,
        thresholdValue: (j['threshold_value'] as num).toDouble(),
        isActive: (j['is_active'] as bool?) ?? true,
      );
}

class PriceTarget {
  final int id;
  final String symbol;
  final double targetPrice;
  final String direction; // 'ABOVE' | 'BELOW'
  final bool isActive;
  final DateTime? triggeredAt;

  const PriceTarget({
    required this.id,
    required this.symbol,
    required this.targetPrice,
    required this.direction,
    required this.isActive,
    this.triggeredAt,
  });

  factory PriceTarget.fromJson(Map<String, dynamic> j) => PriceTarget(
        id: j['id'] as int,
        symbol: j['symbol'] as String,
        targetPrice: (j['target_price'] as num).toDouble(),
        direction: j['direction'] as String,
        isActive: (j['is_active'] as bool?) ?? true,
        triggeredAt: j['triggered_at'] != null
            ? DateTime.parse(j['triggered_at'] as String)
            : null,
      );
}

class SellWindowSignal {
  final String label; // 'FAVORABLE' | 'UNFAVORABLE' | 'NEUTRAL' | 'UNKNOWN'
  final String detail;

  const SellWindowSignal({required this.label, required this.detail});

  factory SellWindowSignal.fromJson(Map<String, dynamic> j) => SellWindowSignal(
        label: j['label'] as String,
        detail: (j['detail'] ?? '') as String,
      );
}

class PortfolioPosition {
  final int id;
  final String commodity;
  final double bushels;
  final DateTime storedDate;
  final double breakEvenPrice;
  final String? state;
  final double? currentCashPrice;
  final double? plPerBushel;
  final double? totalPl;
  final SellWindowSignal sellWindow;
  final String hedgeNote;

  const PortfolioPosition({
    required this.id,
    required this.commodity,
    required this.bushels,
    required this.storedDate,
    required this.breakEvenPrice,
    this.state,
    this.currentCashPrice,
    this.plPerBushel,
    this.totalPl,
    required this.sellWindow,
    required this.hedgeNote,
  });

  factory PortfolioPosition.fromJson(Map<String, dynamic> j) => PortfolioPosition(
        id: j['id'] as int,
        commodity: j['commodity'] as String,
        bushels: (j['bushels'] as num).toDouble(),
        storedDate: DateTime.parse(j['stored_date'] as String),
        breakEvenPrice: (j['break_even_price'] as num).toDouble(),
        state: j['state'] as String?,
        currentCashPrice: (j['current_cash_price'] as num?)?.toDouble(),
        plPerBushel: (j['pl_per_bushel'] as num?)?.toDouble(),
        totalPl: (j['total_pl'] as num?)?.toDouble(),
        sellWindow:
            SellWindowSignal.fromJson(j['sell_window'] as Map<String, dynamic>),
        hedgeNote: (j['hedge_note'] ?? '') as String,
      );
}

// ── Forward Curve, Calendar Spread, Ethanol Margin, Dollar Index ────

class ForwardCurveContract {
  final String contractMonth;
  final DateTime expiryDate;
  final double price;

  const ForwardCurveContract({
    required this.contractMonth,
    required this.expiryDate,
    required this.price,
  });

  factory ForwardCurveContract.fromJson(Map<String, dynamic> j) => ForwardCurveContract(
        contractMonth: j['contract_month'] as String,
        expiryDate: DateTime.parse(j['expiry_date'] as String),
        price: (j['price'] as num).toDouble(),
      );
}

class ForwardCurve {
  final String symbol;
  final String structure; // 'CARRY' | 'INVERSION' | 'FLAT' | 'UNKNOWN'
  final List<ForwardCurveContract> contracts;
  final String note;

  const ForwardCurve({
    required this.symbol,
    required this.structure,
    required this.contracts,
    required this.note,
  });

  factory ForwardCurve.fromJson(Map<String, dynamic> j) => ForwardCurve(
        symbol: j['symbol'] as String,
        structure: j['structure'] as String,
        contracts: ((j['contracts'] as List?) ?? [])
            .map((e) => ForwardCurveContract.fromJson(e as Map<String, dynamic>))
            .toList(),
        note: (j['note'] ?? '') as String,
      );
}

class CalendarSpreadPoint {
  final DateTime date;
  final String nearMonth;
  final String farMonth;
  final double spread;

  const CalendarSpreadPoint({
    required this.date,
    required this.nearMonth,
    required this.farMonth,
    required this.spread,
  });

  factory CalendarSpreadPoint.fromJson(Map<String, dynamic> j) => CalendarSpreadPoint(
        date: DateTime.parse(j['date'] as String),
        nearMonth: j['near_month'] as String,
        farMonth: j['far_month'] as String,
        spread: (j['spread'] as num).toDouble(),
      );
}

class EthanolMarginPoint {
  final DateTime date;
  final double margin;

  const EthanolMarginPoint({required this.date, required this.margin});

  factory EthanolMarginPoint.fromJson(Map<String, dynamic> j) => EthanolMarginPoint(
        date: DateTime.parse(j['date'] as String),
        margin: (j['margin'] as num).toDouble(),
      );
}

class EthanolMargin {
  final DateTime date;
  final double margin;
  final double change1w;
  final double avgPeriod;
  final double cornPriceUsdBu;
  final double ethanolPriceUsdGal;
  final List<EthanolMarginPoint> history;

  const EthanolMargin({
    required this.date,
    required this.margin,
    required this.change1w,
    required this.avgPeriod,
    required this.cornPriceUsdBu,
    required this.ethanolPriceUsdGal,
    required this.history,
  });

  factory EthanolMargin.fromJson(Map<String, dynamic> j) => EthanolMargin(
        date: DateTime.parse(j['date'] as String),
        margin: (j['margin'] as num).toDouble(),
        change1w: (j['change_1w'] as num).toDouble(),
        avgPeriod: (j['avg_period'] as num).toDouble(),
        cornPriceUsdBu: (j['corn_price_usd_bu'] as num).toDouble(),
        ethanolPriceUsdGal: (j['ethanol_price_usd_gal'] as num).toDouble(),
        history: ((j['history'] as List?) ?? [])
            .map((e) => EthanolMarginPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class DollarIndexPoint {
  final DateTime date;
  final double dollarIndex;
  final double cornPrice;

  const DollarIndexPoint({
    required this.date,
    required this.dollarIndex,
    required this.cornPrice,
  });

  factory DollarIndexPoint.fromJson(Map<String, dynamic> j) => DollarIndexPoint(
        date: DateTime.parse(j['date'] as String),
        dollarIndex: (j['dollar_index'] as num).toDouble(),
        cornPrice: (j['corn_price'] as num).toDouble(),
      );
}

class DollarIndexSnapshot {
  final DateTime date;
  final double dollarIndex;
  final double change30dPct;
  final double correlationWithCorn1y;
  final String note;
  final List<DollarIndexPoint> history;

  const DollarIndexSnapshot({
    required this.date,
    required this.dollarIndex,
    required this.change30dPct,
    required this.correlationWithCorn1y,
    required this.note,
    required this.history,
  });

  factory DollarIndexSnapshot.fromJson(Map<String, dynamic> j) => DollarIndexSnapshot(
        date: DateTime.parse(j['date'] as String),
        dollarIndex: (j['dollar_index'] as num).toDouble(),
        change30dPct: (j['change_30d_pct'] as num).toDouble(),
        correlationWithCorn1y: (j['correlation_with_corn_1y'] as num).toDouble(),
        note: (j['note'] ?? '') as String,
        history: ((j['history'] as List?) ?? [])
            .map((e) => DollarIndexPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Real futures-price reaction after a WASDE-equivalent NASS release,
/// at a given horizon (24h/48h/1 week).
class WasdeReaction {
  final double absolute;
  final double pct;

  const WasdeReaction({required this.absolute, required this.pct});

  factory WasdeReaction.fromJson(Map<String, dynamic> j) => WasdeReaction(
        absolute: (j['absolute'] as num).toDouble(),
        pct: (j['pct'] as num).toDouble(),
      );
}

class WasdeSurprise {
  final int id;
  final String commodity;
  final DateTime releaseDate;
  final String metric;
  final double previousValue;
  final double currentValue;
  final double surprisePct;
  final WasdeReaction? reaction24h;
  final WasdeReaction? reaction48h;
  final WasdeReaction? reaction1w;

  const WasdeSurprise({
    required this.id,
    required this.commodity,
    required this.releaseDate,
    required this.metric,
    required this.previousValue,
    required this.currentValue,
    required this.surprisePct,
    this.reaction24h,
    this.reaction48h,
    this.reaction1w,
  });

  factory WasdeSurprise.fromJson(Map<String, dynamic> j) => WasdeSurprise(
        id: j['id'] as int,
        commodity: j['commodity'] as String,
        releaseDate: DateTime.parse(j['release_date'] as String),
        metric: j['metric'] as String,
        previousValue: (j['previous_value'] as num).toDouble(),
        currentValue: (j['current_value'] as num).toDouble(),
        surprisePct: (j['surprise_pct'] as num).toDouble(),
        reaction24h: j['reaction_24h'] != null
            ? WasdeReaction.fromJson(j['reaction_24h'] as Map<String, dynamic>)
            : null,
        reaction48h: j['reaction_48h'] != null
            ? WasdeReaction.fromJson(j['reaction_48h'] as Map<String, dynamic>)
            : null,
        reaction1w: j['reaction_1w'] != null
            ? WasdeReaction.fromJson(j['reaction_1w'] as Map<String, dynamic>)
            : null,
      );
}

class WasdeSimilarSurprise {
  final WasdeSurprise latest;
  final WasdeSurprise mostSimilar;
  final double distancePct;

  const WasdeSimilarSurprise({
    required this.latest,
    required this.mostSimilar,
    required this.distancePct,
  });

  factory WasdeSimilarSurprise.fromJson(Map<String, dynamic> j) => WasdeSimilarSurprise(
        latest: WasdeSurprise.fromJson(j['latest'] as Map<String, dynamic>),
        mostSimilar: WasdeSurprise.fromJson(j['mostSimilar'] as Map<String, dynamic>),
        distancePct: (j['distancePct'] as num).toDouble(),
      );
}

class WasdeSurpriseReport {
  final List<WasdeSurprise> history;
  final WasdeSimilarSurprise? mostSimilar;

  const WasdeSurpriseReport({required this.history, this.mostSimilar});

  factory WasdeSurpriseReport.fromJson(Map<String, dynamic> j) => WasdeSurpriseReport(
        history: ((j['history'] as List?) ?? [])
            .map((e) => WasdeSurprise.fromJson(e as Map<String, dynamic>))
            .toList(),
        mostSimilar: j['most_similar'] != null
            ? WasdeSimilarSurprise.fromJson(j['most_similar'] as Map<String, dynamic>)
            : null,
      );
}

/// One week of real USDA FAS Export Sales world totals for a commodity
/// (all destination countries summed server-side).
class ExportSalesWeek {
  final DateTime date;
  final String marketingYear;
  final int weeklyExportsMt;
  final int netSalesMt;
  final int accumulatedExportsMt;
  final int outstandingSalesMt;
  final int totalCommitmentsMt;

  const ExportSalesWeek({
    required this.date,
    required this.marketingYear,
    required this.weeklyExportsMt,
    required this.netSalesMt,
    required this.accumulatedExportsMt,
    required this.outstandingSalesMt,
    required this.totalCommitmentsMt,
  });

  factory ExportSalesWeek.fromJson(Map<String, dynamic> j) => ExportSalesWeek(
        date: DateTime.parse(j['date'] as String),
        marketingYear: j['marketing_year'] as String,
        weeklyExportsMt: (j['weekly_exports_mt'] as num).toInt(),
        netSalesMt: (j['net_sales_mt'] as num).toInt(),
        accumulatedExportsMt: (j['accumulated_exports_mt'] as num).toInt(),
        outstandingSalesMt: (j['outstanding_sales_mt'] as num).toInt(),
        totalCommitmentsMt: (j['total_commitments_mt'] as num).toInt(),
      );
}

/// One destination country's rank in the latest week's Export Sales
/// leaderboard for a commodity.
class ExportSalesDestination {
  final String country;
  final int weeklyExportsMt;
  final int netSalesMt;
  final int outstandingSalesMt;
  final int rank;

  const ExportSalesDestination({
    required this.country,
    required this.weeklyExportsMt,
    required this.netSalesMt,
    required this.outstandingSalesMt,
    required this.rank,
  });

  factory ExportSalesDestination.fromJson(Map<String, dynamic> j) => ExportSalesDestination(
        country: j['country'] as String,
        weeklyExportsMt: (j['weekly_exports_mt'] as num).toInt(),
        netSalesMt: (j['net_sales_mt'] as num).toInt(),
        outstandingSalesMt: (j['outstanding_sales_mt'] as num).toInt(),
        rank: (j['rank'] as num).toInt(),
      );
}

class ExportSalesReport {
  final String commodity;
  final String symbol;
  final String? source;
  final List<ExportSalesWeek> history;
  final List<ExportSalesDestination> topDestinations;

  const ExportSalesReport({
    required this.commodity,
    required this.symbol,
    this.source,
    required this.history,
    required this.topDestinations,
  });

  ExportSalesWeek? get latest => history.isEmpty ? null : history.last;

  factory ExportSalesReport.fromJson(Map<String, dynamic> j) => ExportSalesReport(
        commodity: j['commodity'] as String,
        symbol: j['symbol'] as String,
        source: j['source'] as String?,
        history: ((j['history'] as List?) ?? [])
            .map((e) => ExportSalesWeek.fromJson(e as Map<String, dynamic>))
            .toList(),
        topDestinations: ((j['top_destinations'] as List?) ?? [])
            .map((e) => ExportSalesDestination.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// One upstream data source's live health, shown on the in-app Status
/// screen (mirrors the public /status page the backend serves).
class DataSourceStatus {
  final String label;
  final String detail;
  final String state; // 'operational' | 'stale' | 'no_data' | 'not_configured'
  final DateTime? lastUpdated;

  const DataSourceStatus({
    required this.label,
    required this.detail,
    required this.state,
    this.lastUpdated,
  });

  factory DataSourceStatus.fromJson(Map<String, dynamic> j) => DataSourceStatus(
        label: j['label'] as String,
        detail: (j['detail'] ?? '') as String,
        state: j['state'] as String,
        lastUpdated: j['last_updated'] != null
            ? DateTime.tryParse(j['last_updated'] as String)
            : null,
      );
}

class ReferralSignup {
  final String username;
  final String subscriptionTier;
  final DateTime joinedAt;

  const ReferralSignup({
    required this.username,
    required this.subscriptionTier,
    required this.joinedAt,
  });

  factory ReferralSignup.fromJson(Map<String, dynamic> j) => ReferralSignup(
        username: j['username'] as String,
        subscriptionTier: j['subscription_tier'] as String,
        joinedAt: DateTime.parse(j['joined_at'] as String),
      );
}

class ReferralCredit {
  final int amountCents;
  final DateTime createdAt;

  const ReferralCredit({required this.amountCents, required this.createdAt});

  factory ReferralCredit.fromJson(Map<String, dynamic> j) => ReferralCredit(
        amountCents: j['amount_cents'] as int,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

class ReferralSummary {
  final String code;
  final List<ReferralSignup> signups;
  final List<ReferralCredit> credits;
  final int totalCreditCents;

  const ReferralSummary({
    required this.code,
    required this.signups,
    required this.credits,
    required this.totalCreditCents,
  });

  factory ReferralSummary.fromJson(Map<String, dynamic> j) => ReferralSummary(
        code: j['code'] as String,
        signups: ((j['signups'] as List?) ?? [])
            .map((e) => ReferralSignup.fromJson(e as Map<String, dynamic>))
            .toList(),
        credits: ((j['credits'] as List?) ?? [])
            .map((e) => ReferralCredit.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalCreditCents: (j['total_credit_cents'] as num?)?.toInt() ?? 0,
      );
}

/// One EIA Weekly Petroleum Status Report snapshot — real US crude/
/// gasoline/distillate stocks and week-over-week change, published
/// Wednesdays ~10:30 ET. No market-consensus figure is included: EIA
/// doesn't publish one, and there's no free source for it.
class EiaInventorySnapshot {
  final DateTime reportDate;
  final double crudeStocksKbbl;
  final double gasolineStocksKbbl;
  final double distillateStocksKbbl;
  final double crudeChangeKbbl;
  final double gasolineChangeKbbl;
  final double distillateChangeKbbl;
  final String aiHeadline;
  final MarketDirection aiDirection;
  final String aiSummary;

  const EiaInventorySnapshot({
    required this.reportDate,
    required this.crudeStocksKbbl,
    required this.gasolineStocksKbbl,
    required this.distillateStocksKbbl,
    required this.crudeChangeKbbl,
    required this.gasolineChangeKbbl,
    required this.distillateChangeKbbl,
    required this.aiHeadline,
    required this.aiDirection,
    required this.aiSummary,
  });

  factory EiaInventorySnapshot.fromJson(Map<String, dynamic> j) => EiaInventorySnapshot(
        reportDate: DateTime.parse(j['report_date'] as String),
        crudeStocksKbbl: (j['crude_stocks_kbbl'] as num).toDouble(),
        gasolineStocksKbbl: (j['gasoline_stocks_kbbl'] as num).toDouble(),
        distillateStocksKbbl: (j['distillate_stocks_kbbl'] as num).toDouble(),
        crudeChangeKbbl: (j['crude_change_kbbl'] as num).toDouble(),
        gasolineChangeKbbl: (j['gasoline_change_kbbl'] as num).toDouble(),
        distillateChangeKbbl: (j['distillate_change_kbbl'] as num).toDouble(),
        aiHeadline: (j['ai_headline'] ?? '') as String,
        aiDirection: directionFromString((j['ai_direction'] ?? 'NEUTRAL') as String),
        aiSummary: (j['ai_summary'] ?? '') as String,
      );
}

class EiaInventoryReport {
  final EiaInventorySnapshot latest;
  final List<EiaInventorySnapshot> history;

  const EiaInventoryReport({required this.latest, required this.history});

  factory EiaInventoryReport.fromJson(Map<String, dynamic> j) => EiaInventoryReport(
        latest: EiaInventorySnapshot.fromJson(j['latest'] as Map<String, dynamic>),
        history: ((j['history'] as List?) ?? [])
            .map((e) => EiaInventorySnapshot.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// One EIA Weekly Natural Gas Storage Report snapshot — real US working
/// gas in storage, vs-last-year and vs-5yr-average deviation, and which
/// seasonal regime (injection/withdrawal) it fell in. No market-
/// consensus figure: EIA doesn't publish one, and there's no free source
/// for analyst forecasts.
class NgStorageSnapshot {
  final DateTime reportDate;
  final double storageBcf;
  final double weeklyChangeBcf;
  final double vsLastYearPct;
  final double vs5yAvgPct;
  final String season; // 'INJECTION_SEASON' | 'WITHDRAWAL_SEASON'
  final String aiHeadline;
  final MarketDirection aiDirection;
  final String aiSummary;

  const NgStorageSnapshot({
    required this.reportDate,
    required this.storageBcf,
    required this.weeklyChangeBcf,
    required this.vsLastYearPct,
    required this.vs5yAvgPct,
    required this.season,
    required this.aiHeadline,
    required this.aiDirection,
    required this.aiSummary,
  });

  factory NgStorageSnapshot.fromJson(Map<String, dynamic> j) => NgStorageSnapshot(
        reportDate: DateTime.parse(j['report_date'] as String),
        storageBcf: (j['storage_bcf'] as num).toDouble(),
        weeklyChangeBcf: (j['weekly_change_bcf'] as num).toDouble(),
        vsLastYearPct: (j['vs_last_year_pct'] as num).toDouble(),
        vs5yAvgPct: (j['vs_5y_avg_pct'] as num).toDouble(),
        season: (j['season'] ?? '') as String,
        aiHeadline: (j['ai_headline'] ?? '') as String,
        aiDirection: directionFromString((j['ai_direction'] ?? 'NEUTRAL') as String),
        aiSummary: (j['ai_summary'] ?? '') as String,
      );

  bool get isInjectionSeason => season == 'INJECTION_SEASON';
}

class CrackSpreadPoint {
  final DateTime date;
  final double crackSpreadUsdBbl;

  const CrackSpreadPoint({required this.date, required this.crackSpreadUsdBbl});

  factory CrackSpreadPoint.fromJson(Map<String, dynamic> j) => CrackSpreadPoint(
        date: DateTime.parse(j['date'] as String),
        crackSpreadUsdBbl: (j['crack_spread_usd_bbl'] as num).toDouble(),
      );
}

/// 3:2:1 crack spread (oil refining margin) from real CL/RB/HO futures
/// closes. Claude only comments (`aiHeadline`/`aiSummary`) when a
/// reading is unusually wide/narrow vs its own trailing average — most
/// of the time there's no AI read at all, just the real numbers.
class CrackSpread {
  final DateTime date;
  final double crackSpreadUsdBbl;
  final double change1w;
  final double avgPeriodUsdBbl;
  final double crudeUsdBbl;
  final double gasolineUsdGal;
  final double heatingOilUsdGal;
  final String aiHeadline;
  final MarketDirection? aiDirection;
  final String aiSummary;
  final List<CrackSpreadPoint> history;

  const CrackSpread({
    required this.date,
    required this.crackSpreadUsdBbl,
    required this.change1w,
    required this.avgPeriodUsdBbl,
    required this.crudeUsdBbl,
    required this.gasolineUsdGal,
    required this.heatingOilUsdGal,
    this.aiHeadline = '',
    this.aiDirection,
    this.aiSummary = '',
    required this.history,
  });

  factory CrackSpread.fromJson(Map<String, dynamic> j) {
    final legs = j['legs'] as Map<String, dynamic>;
    return CrackSpread(
      date: DateTime.parse(j['date'] as String),
      crackSpreadUsdBbl: (j['crack_spread_usd_bbl'] as num).toDouble(),
      change1w: (j['change_1w'] as num).toDouble(),
      avgPeriodUsdBbl: (j['avg_period_usd_bbl'] as num).toDouble(),
      crudeUsdBbl: (legs['crude_usd_bbl'] as num).toDouble(),
      gasolineUsdGal: (legs['gasoline_usd_gal'] as num).toDouble(),
      heatingOilUsdGal: (legs['heating_oil_usd_gal'] as num).toDouble(),
      aiHeadline: (j['ai_headline'] ?? '') as String,
      aiDirection:
          j['ai_direction'] != null ? directionFromString(j['ai_direction'] as String) : null,
      aiSummary: (j['ai_summary'] ?? '') as String,
      history: ((j['history'] as List?) ?? [])
          .map((e) => CrackSpreadPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class NgStorageReport {
  final NgStorageSnapshot latest;
  final List<NgStorageSnapshot> history;

  const NgStorageReport({required this.latest, required this.history});

  factory NgStorageReport.fromJson(Map<String, dynamic> j) => NgStorageReport(
        latest: NgStorageSnapshot.fromJson(j['latest'] as Map<String, dynamic>),
        history: ((j['history'] as List?) ?? [])
            .map((e) => NgStorageSnapshot.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ── Macro: Forex ─────────────────────────────────────────────────────

class ForexRatePoint {
  final DateTime date;
  final double rate;

  const ForexRatePoint({required this.date, required this.rate});

  factory ForexRatePoint.fromJson(Map<String, dynamic> j) => ForexRatePoint(
        date: DateTime.parse(j['date'] as String),
        rate: (j['rate'] as num).toDouble(),
      );
}

class ForexPair {
  final String pair;
  final double rate;
  final double change1dPct;
  final double change30dPct;

  const ForexPair({
    required this.pair,
    required this.rate,
    required this.change1dPct,
    required this.change30dPct,
  });

  factory ForexPair.fromJson(Map<String, dynamic> j) => ForexPair(
        pair: j['pair'] as String,
        rate: (j['rate'] as num).toDouble(),
        change1dPct: (j['change_1d_pct'] as num).toDouble(),
        change30dPct: (j['change_30d_pct'] as num).toDouble(),
      );
}

class ForexSnapshot {
  final DateTime date;
  final double avgDollarMove1dPct;
  final String note;
  final List<ForexPair> pairs;
  final List<ForexRatePoint> history;

  const ForexSnapshot({
    required this.date,
    required this.avgDollarMove1dPct,
    required this.note,
    required this.pairs,
    required this.history,
  });

  factory ForexSnapshot.fromJson(Map<String, dynamic> j) => ForexSnapshot(
        date: DateTime.parse(j['date'] as String),
        avgDollarMove1dPct: (j['avg_dollar_move_1d_pct'] as num).toDouble(),
        note: (j['note'] ?? '') as String,
        pairs: ((j['pairs'] as List?) ?? [])
            .map((e) => ForexPair.fromJson(e as Map<String, dynamic>))
            .toList(),
        history: ((j['history'] as List?) ?? [])
            .map((e) => ForexRatePoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ── Macro: Crypto ────────────────────────────────────────────────────

class CryptoCoin {
  final String id;
  final String symbol;
  final String name;
  final double price;
  final double change24hPct;
  final double marketCapUsd;
  final double volume24hUsd;
  final List<double> sparkline7d;

  const CryptoCoin({
    required this.id,
    required this.symbol,
    required this.name,
    required this.price,
    required this.change24hPct,
    required this.marketCapUsd,
    required this.volume24hUsd,
    required this.sparkline7d,
  });

  factory CryptoCoin.fromJson(Map<String, dynamic> j) => CryptoCoin(
        id: j['id'] as String,
        symbol: j['symbol'] as String,
        name: j['name'] as String,
        price: (j['price'] as num).toDouble(),
        change24hPct: (j['change_24h_pct'] as num).toDouble(),
        marketCapUsd: (j['market_cap_usd'] as num).toDouble(),
        volume24hUsd: (j['volume_24h_usd'] as num).toDouble(),
        sparkline7d: ((j['sparkline_7d'] as List?) ?? [])
            .map((e) => (e as num).toDouble())
            .toList(),
      );
}

class CryptoSnapshot {
  final DateTime asOf;
  final List<CryptoCoin> coins;

  const CryptoSnapshot({required this.asOf, required this.coins});

  factory CryptoSnapshot.fromJson(Map<String, dynamic> j) => CryptoSnapshot(
        asOf: DateTime.parse(j['as_of'] as String),
        coins: ((j['coins'] as List?) ?? [])
            .map((e) => CryptoCoin.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ── Macro: Yield Curve ───────────────────────────────────────────────

class YieldPoint {
  final String tenor;
  final double yieldPct;

  const YieldPoint({required this.tenor, required this.yieldPct});

  factory YieldPoint.fromJson(Map<String, dynamic> j) => YieldPoint(
        tenor: j['tenor'] as String,
        yieldPct: (j['yield_pct'] as num).toDouble(),
      );
}

class YieldCurveSnapshot {
  final DateTime date;
  final List<YieldPoint> current;
  final List<YieldPoint> oneYearAgo;
  final List<YieldPoint> twoYearsAgo;
  final double spread2s10s;
  final bool inverted;
  final String note;

  const YieldCurveSnapshot({
    required this.date,
    required this.current,
    required this.oneYearAgo,
    required this.twoYearsAgo,
    required this.spread2s10s,
    required this.inverted,
    required this.note,
  });

  factory YieldCurveSnapshot.fromJson(Map<String, dynamic> j) => YieldCurveSnapshot(
        date: DateTime.parse(j['date'] as String),
        current: ((j['current'] as List?) ?? [])
            .map((e) => YieldPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        oneYearAgo: ((j['one_year_ago'] as List?) ?? [])
            .map((e) => YieldPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        twoYearsAgo: ((j['two_years_ago'] as List?) ?? [])
            .map((e) => YieldPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        spread2s10s: (j['spread_2s10s'] as num).toDouble(),
        inverted: (j['inverted'] as bool?) ?? false,
        note: (j['note'] ?? '') as String,
      );
}

// ── Macro: Economic Indicators ───────────────────────────────────────

class EconomicIndicator {
  final String seriesId;
  final String label;
  final String unit;
  final DateTime latestDate;
  final double latestValue;
  final double? priorValue;
  final double change;
  final double changePct;

  const EconomicIndicator({
    required this.seriesId,
    required this.label,
    required this.unit,
    required this.latestDate,
    required this.latestValue,
    required this.priorValue,
    required this.change,
    required this.changePct,
  });

  factory EconomicIndicator.fromJson(Map<String, dynamic> j) => EconomicIndicator(
        seriesId: j['series_id'] as String,
        label: j['label'] as String,
        unit: j['unit'] as String,
        latestDate: DateTime.parse(j['latest_date'] as String),
        latestValue: (j['latest_value'] as num).toDouble(),
        priorValue: (j['prior_value'] as num?)?.toDouble(),
        change: (j['change'] as num).toDouble(),
        changePct: (j['change_pct'] as num).toDouble(),
      );
}

class EconomicIndicatorsSnapshot {
  final List<EconomicIndicator> indicators;
  final String mostRecentSeriesId;
  final String note;

  const EconomicIndicatorsSnapshot({
    required this.indicators,
    required this.mostRecentSeriesId,
    required this.note,
  });

  factory EconomicIndicatorsSnapshot.fromJson(Map<String, dynamic> j) =>
      EconomicIndicatorsSnapshot(
        indicators: ((j['indicators'] as List?) ?? [])
            .map((e) => EconomicIndicator.fromJson(e as Map<String, dynamic>))
            .toList(),
        mostRecentSeriesId: (j['most_recent_series_id'] ?? '') as String,
        note: (j['note'] ?? '') as String,
      );
}

// ── Macro: Earnings Calendar ─────────────────────────────────────────

class EarningsEvent {
  final String symbol;
  final DateTime date;
  final double? epsEstimate;
  final double? revenueEstimate;

  const EarningsEvent({
    required this.symbol,
    required this.date,
    required this.epsEstimate,
    required this.revenueEstimate,
  });

  factory EarningsEvent.fromJson(Map<String, dynamic> j) => EarningsEvent(
        symbol: j['symbol'] as String,
        date: DateTime.parse(j['date'] as String),
        epsEstimate: (j['eps_estimate'] as num?)?.toDouble(),
        revenueEstimate: (j['revenue_estimate'] as num?)?.toDouble(),
      );
}

class EarningsCalendar {
  final List<EarningsEvent> events;
  final String note;

  const EarningsCalendar({required this.events, required this.note});

  factory EarningsCalendar.fromJson(Map<String, dynamic> j) => EarningsCalendar(
        events: ((j['events'] as List?) ?? [])
            .map((e) => EarningsEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
        note: (j['note'] ?? '') as String,
      );
}

// ── Macro: Economic Calendar ─────────────────────────────────────────

class EconCalendarEvent {
  final String event;
  final DateTime date;
  final String country;
  final double? previous;
  final double? estimate;
  final String impact;

  const EconCalendarEvent({
    required this.event,
    required this.date,
    required this.country,
    required this.previous,
    required this.estimate,
    required this.impact,
  });

  factory EconCalendarEvent.fromJson(Map<String, dynamic> j) => EconCalendarEvent(
        event: j['event'] as String,
        date: DateTime.parse(j['date'] as String),
        country: (j['country'] ?? '') as String,
        previous: (j['previous'] as num?)?.toDouble(),
        estimate: (j['estimate'] as num?)?.toDouble(),
        impact: (j['impact'] ?? '') as String,
      );
}

class EconomicCalendar {
  final List<EconCalendarEvent> events;
  final String note;

  const EconomicCalendar({required this.events, required this.note});

  factory EconomicCalendar.fromJson(Map<String, dynamic> j) => EconomicCalendar(
        events: ((j['events'] as List?) ?? [])
            .map((e) => EconCalendarEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
        note: (j['note'] ?? '') as String,
      );
}

// ── Macro: News Terminal ─────────────────────────────────────────────

enum NewsTag { grain, energy, macro, other }

NewsTag? newsTagFromString(String? s) => switch (s?.toUpperCase()) {
      'GRAIN' => NewsTag.grain,
      'ENERGY' => NewsTag.energy,
      'MACRO' => NewsTag.macro,
      'OTHER' => NewsTag.other,
      _ => null,
    };

class NewsHeadline {
  final String source;
  final String title;
  final String link;
  final DateTime publishedAt;
  final NewsTag? tag;

  const NewsHeadline({
    required this.source,
    required this.title,
    required this.link,
    required this.publishedAt,
    required this.tag,
  });

  factory NewsHeadline.fromJson(Map<String, dynamic> j) => NewsHeadline(
        source: j['source'] as String,
        title: j['title'] as String,
        link: j['link'] as String,
        publishedAt: DateTime.parse(j['published_at'] as String),
        tag: newsTagFromString(j['tag'] as String?),
      );
}

// ── Markets: Sector Heatmap ──────────────────────────────────────────

class SectorPerformance {
  final String symbol;
  final String label;
  final double price;
  final double changePct;

  const SectorPerformance({
    required this.symbol,
    required this.label,
    required this.price,
    required this.changePct,
  });

  factory SectorPerformance.fromJson(Map<String, dynamic> j) => SectorPerformance(
        symbol: j['symbol'] as String,
        label: j['label'] as String,
        price: (j['price'] as num).toDouble(),
        changePct: (j['change_pct'] as num).toDouble(),
      );
}

class SectorHeatmap {
  final DateTime asOf;
  final List<SectorPerformance> sectors;

  const SectorHeatmap({required this.asOf, required this.sectors});

  factory SectorHeatmap.fromJson(Map<String, dynamic> j) => SectorHeatmap(
        asOf: DateTime.parse(j['as_of'] as String),
        sectors: ((j['sectors'] as List?) ?? [])
            .map((e) => SectorPerformance.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ── CullyAI: Memory + Cross-Asset Synthesis + Proactive Insights ────

class CullyAiContext {
  final String? welcomeBack;

  const CullyAiContext({required this.welcomeBack});

  factory CullyAiContext.fromJson(Map<String, dynamic> j) =>
      CullyAiContext(welcomeBack: j['welcome_back'] as String?);
}

class CrossAssetSynthesis {
  final String date;
  final double? dollarMove1dPct;
  final double? crudeMovePct;
  final bool? yieldCurveInverted;
  final Map<String, String> commentary;

  const CrossAssetSynthesis({
    required this.date,
    required this.dollarMove1dPct,
    required this.crudeMovePct,
    required this.yieldCurveInverted,
    required this.commentary,
  });

  factory CrossAssetSynthesis.fromJson(Map<String, dynamic> j) {
    final inputs = (j['inputs'] as Map<String, dynamic>?) ?? {};
    final commentary = (j['commentary'] as Map<String, dynamic>?) ?? {};
    return CrossAssetSynthesis(
      date: j['date'] as String,
      dollarMove1dPct: (inputs['dollar_move_1d_pct'] as num?)?.toDouble(),
      crudeMovePct: (inputs['crude_move_pct'] as num?)?.toDouble(),
      yieldCurveInverted: inputs['yield_curve_inverted'] as bool?,
      commentary: commentary.map((k, v) => MapEntry(k, v as String)),
    );
  }
}

class DailyInsights {
  final String date;
  final List<String> insights;

  const DailyInsights({required this.date, required this.insights});

  factory DailyInsights.fromJson(Map<String, dynamic> j) => DailyInsights(
        date: j['date'] as String,
        insights: ((j['insights'] as List?) ?? []).map((e) => e as String).toList(),
      );
}

// ── Analytics: Intermarket / Volatility / Relative Value / Spreads ──

class IntermarketPair {
  final String a;
  final String b;
  final int bestLagDays;
  final double correlationAtBestLag;
  final String? leader;

  const IntermarketPair({
    required this.a,
    required this.b,
    required this.bestLagDays,
    required this.correlationAtBestLag,
    required this.leader,
  });

  factory IntermarketPair.fromJson(Map<String, dynamic> j) => IntermarketPair(
        a: j['a'] as String,
        b: j['b'] as String,
        bestLagDays: j['best_lag_days'] as int,
        correlationAtBestLag: (j['correlation_at_best_lag'] as num).toDouble(),
        leader: j['leader'] as String?,
      );
}

class IntermarketAnalysis {
  final String date;
  final List<IntermarketPair> pairs;

  const IntermarketAnalysis({required this.date, required this.pairs});

  factory IntermarketAnalysis.fromJson(Map<String, dynamic> j) => IntermarketAnalysis(
        date: j['date'] as String,
        pairs: ((j['pairs'] as List?) ?? [])
            .map((e) => IntermarketPair.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class VolatilityReading {
  final String commodity;
  final double realizedVol20d;
  final int volPercentile1y;

  const VolatilityReading({
    required this.commodity,
    required this.realizedVol20d,
    required this.volPercentile1y,
  });

  factory VolatilityReading.fromJson(Map<String, dynamic> j) => VolatilityReading(
        commodity: j['commodity'] as String,
        realizedVol20d: (j['realized_vol_20d_pct'] as num).toDouble(),
        volPercentile1y: j['vol_percentile_1y'] as int,
      );
}

class VolatilityMonitor {
  final String date;
  final String note;
  final List<VolatilityReading> commodities;

  const VolatilityMonitor({required this.date, required this.note, required this.commodities});

  factory VolatilityMonitor.fromJson(Map<String, dynamic> j) => VolatilityMonitor(
        date: j['date'] as String,
        note: (j['note'] ?? '') as String,
        commodities: ((j['commodities'] as List?) ?? [])
            .map((e) => VolatilityReading.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class RelativeValueRow {
  final String commodity;
  final double? from52wHighPct;
  final double? from52wLowPct;
  final double? seasonalDeviationPct;
  final int? cotPercentile3y;
  final int? basisPercentile52w;

  const RelativeValueRow({
    required this.commodity,
    required this.from52wHighPct,
    required this.from52wLowPct,
    required this.seasonalDeviationPct,
    required this.cotPercentile3y,
    required this.basisPercentile52w,
  });

  factory RelativeValueRow.fromJson(Map<String, dynamic> j) => RelativeValueRow(
        commodity: j['commodity'] as String,
        from52wHighPct: (j['from_52w_high_pct'] as num?)?.toDouble(),
        from52wLowPct: (j['from_52w_low_pct'] as num?)?.toDouble(),
        seasonalDeviationPct: (j['seasonal_deviation_pct'] as num?)?.toDouble(),
        cotPercentile3y: j['cot_percentile_3y'] as int?,
        basisPercentile52w: j['basis_percentile_52w'] as int?,
      );
}

class RelativeValueScreener {
  final String date;
  final List<RelativeValueRow> commodities;

  const RelativeValueScreener({required this.date, required this.commodities});

  factory RelativeValueScreener.fromJson(Map<String, dynamic> j) => RelativeValueScreener(
        date: j['date'] as String,
        commodities: ((j['commodities'] as List?) ?? [])
            .map((e) => RelativeValueRow.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class SpreadPoint {
  final DateTime date;
  final double value;

  const SpreadPoint({required this.date, required this.value});

  factory SpreadPoint.fromJson(Map<String, dynamic> j) => SpreadPoint(
        date: DateTime.parse(j['date'] as String),
        value: (j['value'] as num).toDouble(),
      );
}

class SpreadSeries {
  final String key;
  final String label;
  final String formula;
  final String unit;
  final String signal;
  final double latest;
  final List<SpreadPoint> history;

  const SpreadSeries({
    required this.key,
    required this.label,
    required this.formula,
    required this.unit,
    required this.signal,
    required this.latest,
    required this.history,
  });

  factory SpreadSeries.fromJson(Map<String, dynamic> j) => SpreadSeries(
        key: j['key'] as String,
        label: j['label'] as String,
        formula: j['formula'] as String,
        unit: j['unit'] as String,
        signal: j['signal'] as String,
        latest: (j['latest'] as num).toDouble(),
        history: ((j['history'] as List?) ?? [])
            .map((e) => SpreadPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class SpreadTerminal {
  final String date;
  final List<String> omitted;
  final List<SpreadSeries> spreads;

  const SpreadTerminal({required this.date, required this.omitted, required this.spreads});

  factory SpreadTerminal.fromJson(Map<String, dynamic> j) => SpreadTerminal(
        date: j['date'] as String,
        omitted: ((j['omitted'] as List?) ?? []).map((e) => e as String).toList(),
        spreads: ((j['spreads'] as List?) ?? [])
            .map((e) => SpreadSeries.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ── Stocks ────────────────────────────────────────────────────────

class StockSearchResult {
  final String symbol;
  final String name;
  final String exchange;

  const StockSearchResult({required this.symbol, required this.name, required this.exchange});

  factory StockSearchResult.fromJson(Map<String, dynamic> j) => StockSearchResult(
        symbol: j['symbol'] as String,
        name: j['name'] as String,
        exchange: (j['exchange'] ?? '') as String,
      );
}

class StockPoint {
  final DateTime date;
  final double close;

  const StockPoint({required this.date, required this.close});

  factory StockPoint.fromJson(Map<String, dynamic> j) => StockPoint(
        date: DateTime.parse(j['date'] as String),
        close: (j['close'] as num).toDouble(),
      );
}

class StockQuote {
  final String symbol;
  final String name;
  final double price;
  final double changePct;
  final double? fiftyTwoWeekHigh;
  final double? fiftyTwoWeekLow;
  final List<StockPoint> history;

  const StockQuote({
    required this.symbol,
    required this.name,
    required this.price,
    required this.changePct,
    required this.fiftyTwoWeekHigh,
    required this.fiftyTwoWeekLow,
    required this.history,
  });

  factory StockQuote.fromJson(Map<String, dynamic> j) => StockQuote(
        symbol: j['symbol'] as String,
        name: j['name'] as String,
        price: (j['price'] as num).toDouble(),
        changePct: (j['change_pct'] as num).toDouble(),
        fiftyTwoWeekHigh: (j['fifty_two_week_high'] as num?)?.toDouble(),
        fiftyTwoWeekLow: (j['fifty_two_week_low'] as num?)?.toDouble(),
        history: ((j['history'] as List?) ?? [])
            .map((e) => StockPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ── Audit Trail / Decision Log ───────────────────────────────────────

class DecisionLogEntry {
  final int id;
  final String commodity;
  final String? cullyaiContext;
  final String userNote;
  final double? priceAtLog;
  final double? price7d;
  final double? price30d;
  final DateTime createdAt;

  const DecisionLogEntry({
    required this.id,
    required this.commodity,
    required this.cullyaiContext,
    required this.userNote,
    required this.priceAtLog,
    required this.price7d,
    required this.price30d,
    required this.createdAt,
  });

  factory DecisionLogEntry.fromJson(Map<String, dynamic> j) => DecisionLogEntry(
        id: j['id'] as int,
        commodity: j['commodity'] as String,
        cullyaiContext: j['cullyai_context'] as String?,
        userNote: j['user_note'] as String,
        priceAtLog: (j['price_at_log'] as num?)?.toDouble(),
        price7d: (j['price_7d'] as num?)?.toDouble(),
        price30d: (j['price_30d'] as num?)?.toDouble(),
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

// ── Custom Dashboards ────────────────────────────────────────────────

class DashboardLayout {
  final int id;
  final String name;
  final List<String> widgetIds;

  const DashboardLayout({required this.id, required this.name, required this.widgetIds});

  factory DashboardLayout.fromJson(Map<String, dynamic> j) => DashboardLayout(
        id: j['id'] as int,
        name: j['name'] as String,
        widgetIds:
            ((j['widget_ids'] as List?) ?? []).map((e) => e as String).toList(),
      );
}

// ── Intraday Futures ──────────────────────────────────────────────────

class IntradayBar {
  final DateTime time;
  final double close;

  const IntradayBar({required this.time, required this.close});

  factory IntradayBar.fromJson(Map<String, dynamic> j) => IntradayBar(
        time: DateTime.parse(j['time'] as String),
        close: (j['close'] as num).toDouble(),
      );
}

class IntradaySnapshot {
  final String symbol;
  final List<IntradayBar> bars;

  const IntradaySnapshot({required this.symbol, required this.bars});

  factory IntradaySnapshot.fromJson(Map<String, dynamic> j) => IntradaySnapshot(
        symbol: j['symbol'] as String,
        bars: ((j['bars'] as List?) ?? [])
            .map((e) => IntradayBar.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ── Community Insights ───────────────────────────────────────────────

class CommunityInsight {
  final int id;
  final String username;
  final String commodity;
  final String body;
  final String? factCheck;
  final String factCheckVerdict;
  final DateTime createdAt;

  const CommunityInsight({
    required this.id,
    required this.username,
    required this.commodity,
    required this.body,
    required this.factCheck,
    required this.factCheckVerdict,
    required this.createdAt,
  });

  factory CommunityInsight.fromJson(Map<String, dynamic> j) => CommunityInsight(
        id: j['id'] as int,
        username: j['username'] as String,
        commodity: j['commodity'] as String,
        body: j['body'] as String,
        factCheck: j['fact_check'] as String?,
        factCheckVerdict: (j['fact_check_verdict'] ?? 'UNVERIFIED') as String,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

// ── Croploo Learn ──────────────────────────────────────────────────────

class LearnArticleSummary {
  final int id;
  final String slug;
  final String title;

  const LearnArticleSummary({required this.id, required this.slug, required this.title});

  factory LearnArticleSummary.fromJson(Map<String, dynamic> j) => LearnArticleSummary(
        id: j['id'] as int,
        slug: j['slug'] as String,
        title: j['title'] as String,
      );
}

class LearnArticle {
  final String slug;
  final String title;
  final String body;

  const LearnArticle({required this.slug, required this.title, required this.body});

  factory LearnArticle.fromJson(Map<String, dynamic> j) => LearnArticle(
        slug: j['slug'] as String,
        title: j['title'] as String,
        body: j['body'] as String,
      );
}

// ── Newsletter ────────────────────────────────────────────────────────

class NewsletterIssue {
  final String issueDate;
  final List<String> signals;

  const NewsletterIssue({required this.issueDate, required this.signals});

  factory NewsletterIssue.fromJson(Map<String, dynamic> j) => NewsletterIssue(
        issueDate: j['issue_date'] as String,
        signals: ((j['signals'] as List?) ?? []).map((e) => e as String).toList(),
      );
}

// ── Public Profile ────────────────────────────────────────────────────

class PublicProfileSettings {
  final String username;
  final bool isPublic;
  final List<String> trackedCommodities;

  const PublicProfileSettings({
    required this.username,
    required this.isPublic,
    required this.trackedCommodities,
  });

  factory PublicProfileSettings.fromJson(Map<String, dynamic> j) => PublicProfileSettings(
        username: j['username'] as String,
        isPublic: (j['is_public'] as bool?) ?? false,
        trackedCommodities: ((j['tracked_commodities'] as List?) ?? [])
            .map((e) => e as String)
            .toList(),
      );
}
