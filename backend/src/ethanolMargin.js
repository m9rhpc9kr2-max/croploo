/**
 * Corn-to-Ethanol Board Margin — the gross margin implied by real CME
 * futures: ethanol (EH=F, $/gal) times ~2.8 gal/bu minus corn (ZC=F,
 * cents/bu). Same simplified two-leg approach as the soybean board
 * crush (crushSpread.js): no DDGS byproduct credit or processing-cost
 * deduction, just the raw revenue-vs-input spread.
 *
 * EH=F (CBOT ethanol futures) is thinly traded — Yahoo has no daily
 * history for it, only a live snapshot quote. So unlike the soy crush,
 * this can't backfill a year of history in one request: it stores
 * today's real snapshot once a day and the chart builds up organically.
 */
import { pool } from "./db.js";

export class EthanolError extends Error {}

const YAHOO_CHART = "https://query1.finance.yahoo.com/v8/finance/chart";
const LEGS = { CORN: "ZC=F", ETHANOL: "EH=F" };
const REFRESH_MINUTES = 60;
const GALLONS_PER_BUSHEL = 2.8;

async function fetchSnapshotPrice(yahooSymbol) {
  const url = `${YAHOO_CHART}/${encodeURIComponent(yahooSymbol)}?range=5d&interval=1d`;
  const resp = await fetch(url, {
    headers: { "user-agent": "Mozilla/5.0 (croploo-backend)" },
    signal: AbortSignal.timeout(15000),
  });
  if (!resp.ok) throw new EthanolError(`Yahoo HTTP ${resp.status} for ${yahooSymbol}`);
  const json = await resp.json();
  const price = json.chart?.result?.[0]?.meta?.regularMarketPrice;
  if (typeof price !== "number") {
    throw new EthanolError(`Yahoo returned no snapshot price for ${yahooSymbol}`);
  }
  return price;
}

// ZC=F is quoted in cents/bushel; ethanol margin is conventionally $/bu.
function computeMargin(cornCentsPerBu, ethanolDollarsPerGal) {
  return ethanolDollarsPerGal * GALLONS_PER_BUSHEL - cornCentsPerBu / 100;
}

async function isStale() {
  const [rows] = await pool.query("SELECT MAX(updated_at) AS latest FROM ethanol_margin_history");
  if (!rows[0]?.latest) return true;
  return Date.now() - new Date(rows[0].latest).getTime() > REFRESH_MINUTES * 60_000;
}

async function refresh() {
  const [cornClose, ethanolClose] = await Promise.all([
    fetchSnapshotPrice(LEGS.CORN),
    fetchSnapshotPrice(LEGS.ETHANOL),
  ]);
  const today = new Date().toISOString().slice(0, 10);
  await pool.query(
    `INSERT INTO ethanol_margin_history (bar_date, corn_close, ethanol_close, margin, updated_at)
     VALUES (?, ?, ?, ?, NOW())
     ON DUPLICATE KEY UPDATE
       corn_close = VALUES(corn_close), ethanol_close = VALUES(ethanol_close),
       margin = VALUES(margin), updated_at = NOW()`,
    [today, cornClose, ethanolClose, computeMargin(cornClose, ethanolClose)]
  );
}

export async function ensureFresh() {
  try {
    if (await isStale()) await refresh();
  } catch (err) {
    console.error("ethanol margin refresh failed:", err);
  }
}

export async function current(days = 180) {
  await ensureFresh();
  const [rows] = await pool.query(
    `SELECT bar_date, corn_close, ethanol_close, margin FROM ethanol_margin_history
     ORDER BY bar_date DESC LIMIT ?`,
    [days]
  );
  if (rows.length === 0) throw new EthanolError("No ethanol margin data cached yet");

  const history = rows.reverse();
  const latest = history[history.length - 1];
  const weekAgo = history[Math.max(0, history.length - 6)];
  const avg = history.reduce((a, r) => a + r.margin, 0) / history.length;

  return {
    date: latest.bar_date.toISOString().slice(0, 10),
    margin: Number(latest.margin.toFixed(2)),
    change_1w: Number((latest.margin - weekAgo.margin).toFixed(2)),
    avg_period: Number(avg.toFixed(2)),
    corn_price_usd_bu: Number((latest.corn_close / 100).toFixed(2)),
    ethanol_price_usd_gal: Number(latest.ethanol_close.toFixed(2)),
    history: history.map((r) => ({
      date: r.bar_date.toISOString().slice(0, 10),
      margin: Number(r.margin.toFixed(2)),
    })),
  };
}
