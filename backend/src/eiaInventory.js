/**
 * Real EIA Weekly Petroleum Status Report — US crude oil, gasoline and
 * distillate stocks (api.eia.gov, "stoc/wstk" — Weekly Petroleum Stocks).
 * EIA publishes this every Wednesday ~10:30 ET; it's the oil-market
 * equivalent of WASDE for grain and moves crude/product prices
 * immediately on release.
 *
 * There is no free, public source of the market's *consensus estimate*
 * for these numbers (that comes from paid analyst-survey services like
 * Bloomberg/Reuters polls) — so unlike a real "beat/miss" read, this
 * only reports the real week-over-week change and lets Claude describe
 * the historical market reaction to a change of that size, never a
 * fabricated "market expected X" figure.
 */
import { pool } from "./db.js";
import * as config from "./config.js";
import { complete } from "./anthropicClient.js";

export class EiaInventoryError extends Error {}

const EIA_BASE_URL = "https://api.eia.gov/v2/petroleum/stoc/wstk/data/";

// EIA product codes for the three headline weekly stock series, all in
// thousand barrels, US total (duoarea NUS).
const PRODUCTS = {
  crude: "EPC0",
  gasoline: "EPM0",
  distillate: "EPD0",
};

async function fetchStockSeries(productCode, points) {
  if (!config.EIA_API_KEY) {
    throw new EiaInventoryError("EIA_API_KEY is not configured");
  }

  const url = new URL(EIA_BASE_URL);
  url.searchParams.set("api_key", config.EIA_API_KEY);
  url.searchParams.set("frequency", "weekly");
  url.searchParams.append("data[0]", "value");
  url.searchParams.append("facets[duoarea][]", "NUS");
  url.searchParams.append("facets[product][]", productCode);
  url.searchParams.set("sort[0][column]", "period");
  url.searchParams.set("sort[0][direction]", "desc");
  url.searchParams.set("length", String(points));

  const resp = await fetch(url, { signal: AbortSignal.timeout(20000) });
  if (!resp.ok) {
    throw new EiaInventoryError(`EIA API HTTP ${resp.status}`);
  }
  const json = await resp.json();
  const rows = json.response?.data ?? [];
  return rows
    .filter((r) => r.value != null)
    .map((r) => ({ date: r.period, stocksKbbl: Number(r.value) }))
    .sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : 0)); // newest first
}

async function isStale() {
  const [rows] = await pool.query(
    "SELECT MAX(report_date) AS latest FROM eia_inventory_snapshots"
  );
  const latest = rows[0]?.latest;
  if (!latest) return true;
  // Published weekly; recheck after 6 days so a same-week repeat call
  // doesn't burn API quota for no new data.
  return Date.now() - new Date(latest).getTime() > 6 * 24 * 60 * 60 * 1000;
}

function change(series) {
  if (series.length < 2) return 0;
  return series[0].stocksKbbl - series[1].stocksKbbl;
}

async function analyzeWithClaude({ crude, gasoline, distillate }) {
  const system =
    "You are CullyAI translating the EIA Weekly Petroleum Status Report for grain-basis " +
    "and freight-cost traders (diesel/crude moves feed directly into freight rates). Given " +
    "the real week-over-week change in US crude, gasoline and distillate stocks (thousand " +
    "barrels), respond with STRICT JSON only matching exactly this shape: " +
    '{"headline": string, "direction": "BULLISH"|"BEARISH"|"NEUTRAL", "summary": string}. ' +
    "direction refers to crude oil price direction implied by the stock change (a stock " +
    "draw is typically bullish for price, a build typically bearish). summary is 2-3 " +
    "sentences citing the real numbers and, if relevant, the freight-cost angle. Never " +
    "state a market consensus/expectation figure — none is available here — and never give " +
    "financial advice, describe historical relationships only.";

  const userContent = `Weekly US petroleum stock changes (thousand barrels):\n${JSON.stringify(
    {
      crude_change_kbbl: change(crude),
      crude_stocks_kbbl: crude[0]?.stocksKbbl ?? null,
      gasoline_change_kbbl: change(gasoline),
      gasoline_stocks_kbbl: gasoline[0]?.stocksKbbl ?? null,
      distillate_change_kbbl: change(distillate),
      distillate_stocks_kbbl: distillate[0]?.stocksKbbl ?? null,
    }
  )}`;

  const text = await complete({
    system,
    messages: [{ role: "user", content: userContent }],
    // 512 was too tight — the model's completion was getting cut off
    // mid-JSON (no closing brace), which made JSON.parse fail with
    // "Unexpected end of JSON input" on every single call.
    maxTokens: 900,
  });
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start === -1 || end === -1 || end < start) {
    throw new EiaInventoryError(`Claude response had no parseable JSON: ${text.slice(0, 200)}`);
  }
  const parsed = JSON.parse(text.slice(start, end + 1));
  return {
    headline: parsed.headline ?? "",
    direction: parsed.direction ?? "NEUTRAL",
    summary: parsed.summary ?? "",
  };
}

async function refresh() {
  const [crude, gasoline, distillate] = await Promise.all([
    fetchStockSeries(PRODUCTS.crude, 8),
    fetchStockSeries(PRODUCTS.gasoline, 8),
    fetchStockSeries(PRODUCTS.distillate, 8),
  ]);
  if (crude.length === 0) throw new EiaInventoryError("EIA returned no crude stock data");

  const reportDate = crude[0].date;
  let analysis = { headline: "", direction: "NEUTRAL", summary: "" };
  try {
    analysis = await analyzeWithClaude({ crude, gasoline, distillate });
  } catch (err) {
    console.error("eiaInventory Claude analysis failed:", err);
  }

  await pool.query(
    `INSERT INTO eia_inventory_snapshots
       (report_date, crude_stocks_kbbl, gasoline_stocks_kbbl, distillate_stocks_kbbl,
        crude_change_kbbl, gasoline_change_kbbl, distillate_change_kbbl, ai_json)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)
     ON DUPLICATE KEY UPDATE
       crude_stocks_kbbl = VALUES(crude_stocks_kbbl),
       gasoline_stocks_kbbl = VALUES(gasoline_stocks_kbbl),
       distillate_stocks_kbbl = VALUES(distillate_stocks_kbbl),
       crude_change_kbbl = VALUES(crude_change_kbbl),
       gasoline_change_kbbl = VALUES(gasoline_change_kbbl),
       distillate_change_kbbl = VALUES(distillate_change_kbbl),
       ai_json = VALUES(ai_json)`,
    [
      reportDate,
      crude[0]?.stocksKbbl ?? null,
      gasoline[0]?.stocksKbbl ?? null,
      distillate[0]?.stocksKbbl ?? null,
      change(crude),
      change(gasoline),
      change(distillate),
      JSON.stringify(analysis),
    ]
  );
}

export async function ensureFresh() {
  if (!(await isStale())) return;
  try {
    await refresh();
  } catch (err) {
    console.error("eiaInventory refresh failed:", err);
  }
}

export async function latest() {
  const [rows] = await pool.query(
    "SELECT * FROM eia_inventory_snapshots ORDER BY report_date DESC LIMIT 1"
  );
  return rows[0] ?? null;
}

export async function history(weeks = 12) {
  const [rows] = await pool.query(
    "SELECT * FROM eia_inventory_snapshots ORDER BY report_date DESC LIMIT ?",
    [weeks]
  );
  return rows.reverse();
}

export function serialize(row) {
  const ai = row.ai_json || {};
  return {
    report_date: row.report_date.toISOString().slice(0, 10),
    crude_stocks_kbbl: row.crude_stocks_kbbl,
    gasoline_stocks_kbbl: row.gasoline_stocks_kbbl,
    distillate_stocks_kbbl: row.distillate_stocks_kbbl,
    crude_change_kbbl: row.crude_change_kbbl,
    gasoline_change_kbbl: row.gasoline_change_kbbl,
    distillate_change_kbbl: row.distillate_change_kbbl,
    ai_headline: ai.headline ?? "",
    ai_direction: ai.direction ?? "NEUTRAL",
    ai_summary: ai.summary ?? "",
  };
}
