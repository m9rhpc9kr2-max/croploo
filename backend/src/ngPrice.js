/**
 * Real Henry Hub natural gas futures (NG=F) daily closes via Yahoo
 * Finance's public chart API (free, no key — same source already used
 * by dollarIndex.js/crushSpread.js/crackSpread.js). This is a plain
 * price series (not the storage level in ngStorage.js) — kept separate
 * because correlationMatrix.js needs an actual tradeable price to
 * correlate against corn/wheat/soy/crude/dollar, which the weekly
 * storage-in-Bcf figure isn't.
 */
import { pool } from "./db.js";

export class NgPriceError extends Error {}

const YAHOO_CHART = "https://query1.finance.yahoo.com/v8/finance/chart";
const REFRESH_STALE_MS = 12 * 60 * 60 * 1000;

async function fetchDailySeries() {
  const url = `${YAHOO_CHART}/${encodeURIComponent("NG=F")}?range=1y&interval=1d`;
  const resp = await fetch(url, {
    headers: { "user-agent": "Mozilla/5.0 (croploo-backend)" },
    signal: AbortSignal.timeout(15000),
  });
  if (!resp.ok) throw new NgPriceError(`Yahoo HTTP ${resp.status} for NG=F`);
  const json = await resp.json();
  const result = json.chart?.result?.[0];
  const timestamps = result?.timestamp ?? [];
  const closes = result?.indicators?.quote?.[0]?.close ?? [];
  const byDate = new Map();
  for (let i = 0; i < timestamps.length; i++) {
    if (closes[i] == null) continue;
    byDate.set(new Date(timestamps[i] * 1000).toISOString().slice(0, 10), closes[i]);
  }
  return byDate;
}

async function isStale() {
  const [rows] = await pool.query("SELECT MAX(bar_date) AS latest FROM ng_price_history");
  const latest = rows[0]?.latest;
  if (!latest) return true;
  return Date.now() - new Date(latest).getTime() > REFRESH_STALE_MS;
}

async function refresh() {
  const series = await fetchDailySeries();
  for (const [day, close] of series) {
    await pool.query(
      `INSERT INTO ng_price_history (bar_date, close)
       VALUES (?, ?)
       ON DUPLICATE KEY UPDATE close = VALUES(close)`,
      [day, close]
    );
  }
}

export async function ensureFresh() {
  try {
    if (await isStale()) await refresh();
  } catch (err) {
    console.error("ngPrice refresh failed:", err);
  }
}

export async function history(days = 400) {
  const [rows] = await pool.query(
    `SELECT bar_date, close FROM ng_price_history
     WHERE bar_date >= DATE_SUB(CURDATE(), INTERVAL ? DAY) ORDER BY bar_date ASC`,
    [days]
  );
  return rows;
}
