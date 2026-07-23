/**
 * Real CFTC Commitments of Traders data via the CFTC's public Socrata
 * API (publicreporting.cftc.gov — free, no API key). Uses the
 * Disaggregated Futures-Only report, published every Friday (data as of
 * Tuesday).
 *
 * For each grain we track Managed Money (funds) and Producer/Merchant
 * (commercials) positioning: net position, week-over-week change, and a
 * 3-year percentile of the fund net position as a historical contrarian
 * signal. Claude then translates the positioning into plain trader
 * language, cached per report date in cot_reports.
 */
import { pool } from "./db.js";
import { complete } from "./anthropicClient.js";

export class CotError extends Error {}

const CFTC_URL = "https://publicreporting.cftc.gov/resource/72hh-3qpy.json";

export const COT_MARKETS = {
  CORN: "CORN - CHICAGO BOARD OF TRADE",
  WHEAT: "WHEAT-SRW - CHICAGO BOARD OF TRADE",
  SOYBEANS: "SOYBEANS - CHICAGO BOARD OF TRADE",
};

const HISTORY_WEEKS = 156; // ~3 years for the contrarian percentile

async function fetchSeries(marketName) {
  const url = new URL(CFTC_URL);
  url.searchParams.set("market_and_exchange_names", marketName);
  url.searchParams.set("$order", "report_date_as_yyyy_mm_dd DESC");
  url.searchParams.set("$limit", String(HISTORY_WEEKS));

  const resp = await fetch(url, { signal: AbortSignal.timeout(20000) });
  if (!resp.ok) throw new CotError(`CFTC API HTTP ${resp.status}`);
  const rows = await resp.json();
  if (!Array.isArray(rows) || rows.length === 0) {
    throw new CotError(`CFTC returned no rows for ${marketName}`);
  }
  return rows.map((r) => ({
    date: String(r.report_date_as_yyyy_mm_dd).slice(0, 10),
    mmLong: Number(r.m_money_positions_long_all ?? 0),
    mmShort: Number(r.m_money_positions_short_all ?? 0),
    prodLong: Number(r.prod_merc_positions_long ?? 0),
    prodShort: Number(r.prod_merc_positions_short ?? 0),
    openInterest: Number(r.open_interest_all ?? 0),
  }));
}

function percentile(values, target) {
  if (values.length === 0) return 0.5;
  const below = values.filter((v) => v < target).length;
  return below / values.length;
}

function buildSnapshot(commodity, series) {
  const [cur, prev] = series;
  const mmNet = cur.mmLong - cur.mmShort;
  const mmNetPrev = prev ? prev.mmLong - prev.mmShort : mmNet;
  const commNet = cur.prodLong - cur.prodShort;
  const commNetPrev = prev ? prev.prodLong - prev.prodShort : commNet;
  const netHistory = series.map((r) => r.mmLong - r.mmShort);
  const pct = percentile(netHistory, mmNet);

  // Contrarian read: crowded fund longs historically precede corrections
  // and crowded shorts precede short-covering rallies.
  let contrarian = "NEUTRAL";
  if (pct >= 0.9) contrarian = "CROWDED_LONG";
  else if (pct >= 0.75) contrarian = "STRETCHED_LONG";
  else if (pct <= 0.1) contrarian = "CROWDED_SHORT";
  else if (pct <= 0.25) contrarian = "STRETCHED_SHORT";

  return {
    commodity,
    reportDate: cur.date,
    openInterest: cur.openInterest,
    managedMoney: {
      long: cur.mmLong,
      short: cur.mmShort,
      net: mmNet,
      netChange: mmNet - mmNetPrev,
    },
    commercials: {
      long: cur.prodLong,
      short: cur.prodShort,
      net: commNet,
      netChange: commNet - commNetPrev,
    },
    netPercentile3y: Math.round(pct * 100),
    contrarianSignal: contrarian,
    netHistory: series
      .slice(0, 52)
      .map((r) => ({ date: r.date, net: r.mmLong - r.mmShort }))
      .reverse(),
  };
}

async function analyzeWithClaude(snapshots) {
  const system =
    "You are CullyAI translating the weekly CFTC Commitments of Traders report for " +
    "grain merchandisers who have never read one. Given real disaggregated " +
    "futures-only positioning data, respond with STRICT JSON only matching exactly " +
    'this shape: {"summary": string, "perCommodity": [{"commodity": string, ' +
    '"readout": string, "contrarianNote": string}]}. summary is 2-3 sentences on the ' +
    "overall fund flow picture. readout is 1-2 plain-language sentences on what funds " +
    "and commercials did that week, citing the real numbers. contrarianNote is one " +
    "sentence on what the 3-year percentile has historically implied. Never give " +
    "financial advice — describe what the data shows and historical context only.";

  const userContent =
    "This week's COT positioning (contracts; managedMoney = funds, commercials = " +
    "producer/merchant hedgers; netPercentile3y = where the fund net position ranks " +
    "vs the past 3 years):\n" +
    JSON.stringify(
      snapshots.map(({ netHistory, ...rest }) => rest)
    );

  const text = await complete({
    system,
    messages: [{ role: "user", content: userContent }],
    maxTokens: 1024,
  });
  const jsonText = text.slice(text.indexOf("{"), text.lastIndexOf("}") + 1);
  const parsed = JSON.parse(jsonText);
  return {
    summary: parsed.summary ?? "",
    perCommodity: parsed.perCommodity ?? [],
  };
}

export async function ensureLatest() {
  const seriesByCommodity = await Promise.all(
    Object.entries(COT_MARKETS).map(async ([commodity, market]) => ({
      commodity,
      series: await fetchSeries(market),
    }))
  );

  const snapshots = seriesByCommodity.map(({ commodity, series }) =>
    buildSnapshot(commodity, series)
  );
  const reportDate = snapshots[0].reportDate;

  const [existing] = await pool.query(
    "SELECT * FROM cot_reports WHERE report_date = ?",
    [reportDate]
  );
  if (existing[0]?.ai_json) {
    return { snapshots, analysis: existing[0].ai_json };
  }

  let analysis = { summary: "", perCommodity: [] };
  try {
    analysis = await analyzeWithClaude(snapshots);
  } catch (err) {
    console.error("COT Claude analysis failed:", err);
  }

  await pool.query(
    `INSERT INTO cot_reports (report_date, raw_data, ai_json)
     VALUES (?, ?, ?)
     ON DUPLICATE KEY UPDATE raw_data = VALUES(raw_data), ai_json = VALUES(ai_json)`,
    [reportDate, JSON.stringify(snapshots), JSON.stringify(analysis)]
  );

  return { snapshots, analysis };
}

export function serialize({ snapshots, analysis }) {
  const readouts = new Map(
    (analysis.perCommodity ?? []).map((p) => [p.commodity, p])
  );
  return {
    report_date: snapshots[0]?.reportDate ?? null,
    summary: analysis.summary ?? "",
    commodities: snapshots.map((s) => ({
      commodity: s.commodity,
      report_date: s.reportDate,
      open_interest: s.openInterest,
      managed_money: s.managedMoney,
      commercials: s.commercials,
      net_percentile_3y: s.netPercentile3y,
      contrarian_signal: s.contrarianSignal,
      readout: readouts.get(s.commodity)?.readout ?? "",
      contrarian_note: readouts.get(s.commodity)?.contrarianNote ?? "",
      net_history: s.netHistory,
    })),
  };
}
