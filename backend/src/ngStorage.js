/**
 * Real EIA Natural Gas Storage Report — US working gas in underground
 * storage (api.eia.gov, "natural-gas/stor/wkly" — Weekly Natural Gas
 * Storage Report). EIA publishes this every Thursday ~10:30 ET.
 * Seasonality is extreme: storage builds through the injection season
 * (April–October) and draws down through the withdrawal season
 * (November–March), so the number only means something in context of
 * last year and the 5-year average — never in isolation.
 *
 * As with eiaInventory.js, there's no free source for the market's
 * consensus estimate (that's a paid analyst-survey product), so this
 * only reports real vs-last-year and vs-5yr-average deviations and lets
 * Claude describe the historical market reaction, never a fabricated
 * "market expected" figure.
 */
import { pool } from "./db.js";
import * as config from "./config.js";
import { complete } from "./anthropicClient.js";

export class NgStorageError extends Error {}

const EIA_BASE_URL = "https://api.eia.gov/v2/natural-gas/stor/wkly/data/";
// Confirmed live against EIA's own facet metadata endpoint — "NUS" and
// "SAO" (the previous values here) don't exist in this dataset at all,
// which is why every request silently matched zero rows instead of
// erroring. R48 = Lower 48 States; SWO = total (non-salt + salt)
// underground storage working gas.
const LOWER_48 = "R48"; // EIA duoarea code for the Lower 48 States total

// Enough weekly points to look back 5 years for the same-week average.
const HISTORY_WEEKS = 5 * 52 + 12;

async function fetchStorageSeries() {
  if (!config.EIA_API_KEY) {
    throw new NgStorageError("EIA_API_KEY is not configured");
  }

  const url = new URL(EIA_BASE_URL);
  url.searchParams.set("api_key", config.EIA_API_KEY);
  url.searchParams.set("frequency", "weekly");
  url.searchParams.append("data[0]", "value");
  url.searchParams.append("facets[duoarea][]", LOWER_48);
  url.searchParams.append("facets[process][]", "SWO"); // Working gas in underground storage (total)
  url.searchParams.set("sort[0][column]", "period");
  url.searchParams.set("sort[0][direction]", "desc");
  url.searchParams.set("length", String(HISTORY_WEEKS));

  const resp = await fetch(url, { signal: AbortSignal.timeout(20000) });
  if (!resp.ok) {
    throw new NgStorageError(`EIA API HTTP ${resp.status}`);
  }
  const json = await resp.json();
  const rows = json.response?.data ?? [];
  return rows
    .filter((r) => r.value != null)
    .map((r) => ({ date: r.period, storageBcf: Number(r.value) }))
    .sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : 0)); // newest first
}

async function isStale() {
  const [rows] = await pool.query(
    "SELECT MAX(report_date) AS latest FROM ng_storage_snapshots"
  );
  const latest = rows[0]?.latest;
  if (!latest) return true;
  // Published weekly; recheck after 6 days so a same-week repeat call
  // doesn't burn API quota for no new data.
  return Date.now() - new Date(latest).getTime() > 6 * 24 * 60 * 60 * 1000;
}

/** Injection season (storage builds) April–October, withdrawal season
 * (storage draws down) November–March — standard EIA/industry terms. */
function seasonFor(dateStr) {
  const month = Number(dateStr.slice(5, 7));
  return month >= 4 && month <= 10 ? "INJECTION_SEASON" : "WITHDRAWAL_SEASON";
}

function pctDeviation(current, reference) {
  if (!reference) return 0;
  return ((current - reference) / Math.abs(reference)) * 100;
}

/** series is newest-first, weekly. Index 52 is ~1 year back, 104/156/
 * 208/260 are the prior 4 years at the same week for the 5yr average. */
function computeDeviations(series) {
  const current = series[0].storageBcf;
  const lastYear = series[52]?.storageBcf ?? null;
  const fiveYearPoints = [52, 104, 156, 208, 260]
    .map((offset) => series[offset]?.storageBcf)
    .filter((v) => typeof v === "number");
  const fiveYearAvg =
    fiveYearPoints.length > 0
      ? fiveYearPoints.reduce((sum, v) => sum + v, 0) / fiveYearPoints.length
      : null;

  return {
    vsLastYearPct: lastYear !== null ? pctDeviation(current, lastYear) : 0,
    vs5yAvgPct: fiveYearAvg !== null ? pctDeviation(current, fiveYearAvg) : 0,
  };
}

async function analyzeWithClaude({ current, weeklyChange, season, vsLastYearPct, vs5yAvgPct }) {
  const system =
    "You are CullyAI translating the EIA Weekly Natural Gas Storage Report for grain/energy " +
    "traders. Given the real current US working-gas-in-storage level and its deviation vs " +
    "last year and the 5-year average, respond with STRICT JSON only matching exactly this " +
    'shape: {"headline": string, "direction": "BULLISH"|"BEARISH"|"NEUTRAL", "summary": ' +
    'string}. direction refers to natural gas price direction (storage below last year/5yr ' +
    "average is typically bullish for price, above is typically bearish — and note that " +
    "the current season, injection vs withdrawal, changes how much a given deviation " +
    "matters). summary is 2-3 sentences citing the real numbers. Never state a market " +
    "consensus/expectation figure — none is available here — and never give financial " +
    "advice, describe historical relationships only.";

  const userContent = JSON.stringify({
    storage_bcf: current,
    weekly_change_bcf: weeklyChange,
    season,
    vs_last_year_pct: Number(vsLastYearPct.toFixed(1)),
    vs_5y_avg_pct: Number(vs5yAvgPct.toFixed(1)),
  });

  const text = await complete({
    system,
    messages: [{ role: "user", content: userContent }],
    maxTokens: 512,
  });
  const jsonText = text.slice(text.indexOf("{"), text.lastIndexOf("}") + 1);
  const parsed = JSON.parse(jsonText);
  return {
    headline: parsed.headline ?? "",
    direction: parsed.direction ?? "NEUTRAL",
    summary: parsed.summary ?? "",
  };
}

async function refresh() {
  const series = await fetchStorageSeries();
  if (series.length === 0) throw new NgStorageError("EIA returned no storage data");

  const reportDate = series[0].date;
  const weeklyChange = series.length > 1 ? series[0].storageBcf - series[1].storageBcf : 0;
  const { vsLastYearPct, vs5yAvgPct } = computeDeviations(series);
  const season = seasonFor(reportDate);

  let analysis = { headline: "", direction: "NEUTRAL", summary: "" };
  try {
    analysis = await analyzeWithClaude({
      current: series[0].storageBcf,
      weeklyChange,
      season,
      vsLastYearPct,
      vs5yAvgPct,
    });
  } catch (err) {
    console.error("ngStorage Claude analysis failed:", err);
  }

  await pool.query(
    `INSERT INTO ng_storage_snapshots
       (report_date, storage_bcf, weekly_change_bcf, vs_last_year_pct, vs_5y_avg_pct, season, ai_json)
     VALUES (?, ?, ?, ?, ?, ?, ?)
     ON DUPLICATE KEY UPDATE
       storage_bcf = VALUES(storage_bcf),
       weekly_change_bcf = VALUES(weekly_change_bcf),
       vs_last_year_pct = VALUES(vs_last_year_pct),
       vs_5y_avg_pct = VALUES(vs_5y_avg_pct),
       season = VALUES(season),
       ai_json = VALUES(ai_json)`,
    [reportDate, series[0].storageBcf, weeklyChange, vsLastYearPct, vs5yAvgPct, season, JSON.stringify(analysis)]
  );
}

export async function ensureFresh() {
  if (!(await isStale())) return;
  try {
    await refresh();
  } catch (err) {
    console.error("ngStorage refresh failed:", err);
  }
}

export async function latest() {
  const [rows] = await pool.query(
    "SELECT * FROM ng_storage_snapshots ORDER BY report_date DESC LIMIT 1"
  );
  return rows[0] ?? null;
}

export async function history(weeks = 12) {
  const [rows] = await pool.query(
    "SELECT * FROM ng_storage_snapshots ORDER BY report_date DESC LIMIT ?",
    [weeks]
  );
  return rows.reverse();
}

export function serialize(row) {
  const ai = row.ai_json || {};
  return {
    report_date: row.report_date.toISOString().slice(0, 10),
    storage_bcf: row.storage_bcf,
    weekly_change_bcf: row.weekly_change_bcf,
    vs_last_year_pct: row.vs_last_year_pct,
    vs_5y_avg_pct: row.vs_5y_avg_pct,
    season: row.season,
    ai_headline: ai.headline ?? "",
    ai_direction: ai.direction ?? "NEUTRAL",
    ai_summary: ai.summary ?? "",
  };
}
