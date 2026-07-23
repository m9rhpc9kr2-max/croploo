/**
 * Intraday futures snapshots — real 15-minute bars from Yahoo Finance's
 * keyless chart API (same approach as dollarIndex.js/sectorHeatmap.js).
 * Alpha Vantage's free tier (25 req/day) can't sustain 15-minute polling
 * for even one symbol, so this deliberately doesn't touch marketData.js
 * — it's a separate, additive "today" view, not a replacement for the
 * daily-close history used elsewhere.
 */
import { pool } from "./db.js";

export class IntradayFuturesError extends Error {}

const YAHOO_CHART = "https://query1.finance.yahoo.com/v8/finance/chart";
const REFRESH_STALE_MS = 15 * 60 * 1000;

const YAHOO_SYMBOLS = { ZC: "ZC=F", ZW: "ZW=F", ZS: "ZS=F" };

async function fetchIntraday(symbol) {
  const yahooSymbol = YAHOO_SYMBOLS[symbol];
  if (!yahooSymbol) throw new IntradayFuturesError(`Unknown symbol ${symbol}`);
  const url = `${YAHOO_CHART}/${encodeURIComponent(yahooSymbol)}?range=1d&interval=15m`;
  const resp = await fetch(url, {
    headers: { "user-agent": "Mozilla/5.0 (croploo-backend)" },
    signal: AbortSignal.timeout(15000),
  });
  if (!resp.ok) throw new IntradayFuturesError(`Yahoo HTTP ${resp.status} for ${symbol}`);
  const json = await resp.json();
  const result = json.chart?.result?.[0];
  const timestamps = result?.timestamp ?? [];
  const closes = result?.indicators?.quote?.[0]?.close ?? [];
  const bars = [];
  for (let i = 0; i < timestamps.length; i++) {
    if (closes[i] == null) continue;
    bars.push({ time: new Date(timestamps[i] * 1000).toISOString(), close: closes[i] });
  }
  return bars;
}

async function isStale(symbol) {
  const [rows] = await pool.query(
    "SELECT updated_at FROM intraday_futures_cache WHERE symbol = ?",
    [symbol]
  );
  const updatedAt = rows[0]?.updated_at;
  if (!updatedAt) return true;
  return Date.now() - new Date(updatedAt).getTime() > REFRESH_STALE_MS;
}

async function refresh(symbol) {
  const bars = await fetchIntraday(symbol);
  await pool.query(
    `INSERT INTO intraday_futures_cache (symbol, payload, updated_at)
     VALUES (?, ?, NOW())
     ON DUPLICATE KEY UPDATE payload = VALUES(payload), updated_at = NOW()`,
    [symbol, JSON.stringify(bars)]
  );
  return bars;
}

export async function snapshot(symbol) {
  const sym = symbol.toUpperCase();
  if (!YAHOO_SYMBOLS[sym]) throw new IntradayFuturesError(`Unknown symbol ${sym}`);
  if (await isStale(sym)) {
    try {
      const bars = await refresh(sym);
      return { symbol: sym, bars };
    } catch (err) {
      console.error(`intraday refresh failed for ${sym}:`, err);
    }
  }
  const [rows] = await pool.query(
    "SELECT payload FROM intraday_futures_cache WHERE symbol = ?",
    [sym]
  );
  if (rows.length === 0) throw new IntradayFuturesError(`No intraday data cached yet for ${sym}`);
  return { symbol: sym, bars: rows[0].payload };
}
