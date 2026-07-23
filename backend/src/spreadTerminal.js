/**
 * Spread Trading Terminal — the commodity spreads that are actually
 * tradable signals, not just calendar spreads (see forwardCurve.js for
 * those). Corn-Wheat and Soy-Corn ratio are computed directly from
 * futures_price_history (already cached). WTI-Brent is fetched fresh
 * from Yahoo Finance (keyless) since no Brent series existed yet.
 * Soybean crush reuses crushSpread.js rather than duplicating it.
 *
 * Not included: Spark Spread (NG vs electricity) — there is no free
 * data source for wholesale power prices, so it's omitted rather than
 * faked.
 */
import { pool } from "./db.js";
import * as crushSpread from "./crushSpread.js";

export class SpreadTerminalError extends Error {}

const YAHOO_CHART = "https://query1.finance.yahoo.com/v8/finance/chart";
const REFRESH_STALE_MS = 12 * 60 * 60 * 1000;

async function fetchDailySeries(yahooSymbol) {
  const url = `${YAHOO_CHART}/${encodeURIComponent(yahooSymbol)}?range=1y&interval=1d`;
  const resp = await fetch(url, {
    headers: { "user-agent": "Mozilla/5.0 (croploo-backend)" },
    signal: AbortSignal.timeout(15000),
  });
  if (!resp.ok) throw new SpreadTerminalError(`Yahoo HTTP ${resp.status} for ${yahooSymbol}`);
  const json = await resp.json();
  const result = json.chart?.result?.[0];
  const timestamps = result?.timestamp ?? [];
  const closes = result?.indicators?.quote?.[0]?.close ?? [];
  const bars = [];
  for (let i = 0; i < timestamps.length; i++) {
    if (closes[i] == null) continue;
    bars.push({
      date: new Date(timestamps[i] * 1000).toISOString().slice(0, 10),
      close: closes[i],
    });
  }
  return bars;
}

async function isStale(spreadKey) {
  const [rows] = await pool.query(
    "SELECT MAX(bar_date) AS latest FROM spread_history WHERE spread_key = ?",
    [spreadKey]
  );
  const latest = rows[0]?.latest;
  if (!latest) return true;
  return Date.now() - new Date(latest).getTime() > REFRESH_STALE_MS;
}

async function refreshWtiBrent() {
  const [wti, brent] = await Promise.all([
    fetchDailySeries("CL=F"),
    fetchDailySeries("BZ=F"),
  ]);
  const brentByDate = new Map(brent.map((b) => [b.date, b.close]));
  for (const bar of wti) {
    const brentClose = brentByDate.get(bar.date);
    if (brentClose == null) continue;
    await pool.query(
      `INSERT INTO spread_history (spread_key, bar_date, value)
       VALUES ('WTI_BRENT', ?, ?)
       ON DUPLICATE KEY UPDATE value = VALUES(value)`,
      [bar.date, bar.close - brentClose]
    );
  }
}

async function wtiBrentHistory(days) {
  if (await isStale("WTI_BRENT")) {
    try {
      await refreshWtiBrent();
    } catch (err) {
      console.error("WTI-Brent refresh failed:", err);
    }
  }
  const [rows] = await pool.query(
    `SELECT bar_date, value FROM spread_history
     WHERE spread_key = 'WTI_BRENT' AND bar_date >= DATE_SUB(CURDATE(), INTERVAL ? DAY)
     ORDER BY bar_date ASC`,
    [days]
  );
  return rows.map((r) => ({ date: r.bar_date.toISOString().slice(0, 10), value: r.value }));
}

/** Corn-Wheat spread (ZC - ZW, ¢/bu) and Soy-Corn ratio (ZS / (2.5 × ZC)) from cached futures history. */
async function grainSpreadsHistory(days) {
  const [rows] = await pool.query(
    `SELECT symbol, bar_date, close FROM futures_price_history
     WHERE symbol IN ('ZC', 'ZW', 'ZS') AND bar_date >= DATE_SUB(CURDATE(), INTERVAL ? DAY)
     ORDER BY bar_date ASC`,
    [days]
  );
  const byDate = new Map();
  for (const row of rows) {
    const date = row.bar_date.toISOString().slice(0, 10);
    if (!byDate.has(date)) byDate.set(date, {});
    byDate.get(date)[row.symbol] = row.close;
  }
  const cornWheat = [];
  const soyCornRatio = [];
  for (const [date, prices] of [...byDate.entries()].sort()) {
    if (prices.ZC != null && prices.ZW != null) {
      cornWheat.push({ date, value: Number((prices.ZC - prices.ZW).toFixed(2)) });
    }
    if (prices.ZC != null && prices.ZS != null && prices.ZC !== 0) {
      soyCornRatio.push({ date, value: Number((prices.ZS / (2.5 * prices.ZC)).toFixed(3)) });
    }
  }
  return { cornWheat, soyCornRatio };
}

export async function snapshot(days = 365) {
  const [{ cornWheat, soyCornRatio }, wtiBrent, crush] = await Promise.all([
    grainSpreadsHistory(days),
    wtiBrentHistory(days).catch(() => []),
    crushSpread.current().catch(() => null),
  ]);

  const spreads = [];
  if (cornWheat.length > 1) {
    spreads.push({
      key: "CORN_WHEAT",
      label: "Corn-Wheat",
      formula: "ZC − ZW",
      unit: "¢/bu",
      signal: "Feed-substitution economics",
      latest: cornWheat[cornWheat.length - 1].value,
      history: cornWheat,
    });
  }
  if (soyCornRatio.length > 1) {
    spreads.push({
      key: "SOY_CORN_RATIO",
      label: "Soy-Corn Ratio",
      formula: "ZS ÷ (2.5 × ZC)",
      unit: "ratio",
      signal: "Planted-acreage decision",
      latest: soyCornRatio[soyCornRatio.length - 1].value,
      history: soyCornRatio,
    });
  }
  if (wtiBrent.length > 1) {
    spreads.push({
      key: "WTI_BRENT",
      label: "WTI-Brent",
      formula: "CL − BZ",
      unit: "$/bbl",
      signal: "US crude export premium/discount",
      latest: wtiBrent[wtiBrent.length - 1].value,
      history: wtiBrent,
    });
  }
  if (crush) {
    spreads.push({
      key: "SOYBEAN_CRUSH",
      label: "Soybean Crush",
      formula: "ZS vs ZL + ZM",
      unit: "$/bu",
      signal: "Processing margin",
      latest: crush.crush,
      history: (crush.history ?? []).map((h) => ({ date: h.date, value: h.crush })),
    });
  }

  if (spreads.length === 0) throw new SpreadTerminalError("Not enough data cached yet");
  return {
    date: new Date().toISOString().slice(0, 10),
    omitted: ["Spark Spread — no free wholesale electricity price source"],
    spreads,
  };
}
