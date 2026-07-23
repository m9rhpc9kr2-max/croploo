/**
 * Real futures price data via Alpha Vantage.
 *
 * Alpha Vantage has no direct CME futures-tick endpoint on the free
 * tier, so each commodity is tracked through a liquid, commodity-holding
 * ETF as a real-market proxy (genuine daily market prices, not
 * simulated):
 *
 *   ZC (Corn)     -> CORN  (Teucrium Corn Fund)
 *   ZW (Wheat)    -> WEAT  (Teucrium Wheat Fund)
 *   ZS (Soybeans) -> SOYB  (Teucrium Soybean Fund)
 *
 * Daily bars are cached in futures_price_history / futures_prices so we
 * stay within the free tier's 25-requests/day budget (see
 * config.MARKET_DATA_REFRESH_MINUTES).
 */

import { pool } from "./db.js";
import * as config from "./config.js";

export const PROXY_SYMBOLS = {
  ZC: ["CORN", "Corn"],
  ZW: ["WEAT", "Wheat"],
  ZS: ["SOYB", "Soybeans"],
};

const MONTHS = [
  "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
  "JUL", "AUG", "SEP", "OCT", "NOV", "DEC",
];

function contractMonthLabel(date) {
  const yy = String(date.getUTCFullYear()).slice(-2);
  return `${MONTHS[date.getUTCMonth()]}${yy}`;
}

export class MarketDataError extends Error {}

async function fetchDailySeries(proxySymbol) {
  if (!config.ALPHA_VANTAGE_API_KEY) {
    throw new MarketDataError("ALPHA_VANTAGE_API_KEY is not configured");
  }

  const url = new URL(config.ALPHA_VANTAGE_BASE_URL);
  url.searchParams.set("function", "TIME_SERIES_DAILY");
  url.searchParams.set("symbol", proxySymbol);
  url.searchParams.set("apikey", config.ALPHA_VANTAGE_API_KEY);

  const resp = await fetch(url, { signal: AbortSignal.timeout(15000) });
  if (!resp.ok) {
    throw new MarketDataError(`Alpha Vantage HTTP ${resp.status}`);
  }
  const payload = await resp.json();
  const series = payload["Time Series (Daily)"];
  if (!series) {
    throw new MarketDataError(
      `Alpha Vantage returned no series for ${proxySymbol}: ${JSON.stringify(payload)}`
    );
  }

  return Object.entries(series)
    .map(([day, bar]) => [day, Number(bar["4. close"])])
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
}

async function isStale(symbol) {
  const [rows] = await pool.query(
    "SELECT updated_at FROM futures_prices WHERE symbol = ?",
    [symbol]
  );
  if (rows.length === 0) return true;
  const ageMs = Date.now() - new Date(rows[0].updated_at).getTime();
  return ageMs > config.MARKET_DATA_REFRESH_MINUTES * 60_000;
}

export async function refreshSymbol(symbol) {
  const [proxySymbol, name] = PROXY_SYMBOLS[symbol];
  const ordered = await fetchDailySeries(proxySymbol);

  for (const [day, close] of ordered) {
    await pool.query(
      `INSERT INTO futures_price_history (symbol, bar_date, close)
       VALUES (?, ?, ?)
       ON DUPLICATE KEY UPDATE close = VALUES(close)`,
      [symbol, day, close]
    );
  }

  const [latestDate, latestClose] = ordered[ordered.length - 1];
  const prevClose = ordered.length > 1 ? ordered[ordered.length - 2][1] : latestClose;
  const change = latestClose - prevClose;
  const changePct = prevClose ? (change / prevClose) * 100 : 0;

  await pool.query(
    `INSERT INTO futures_prices (symbol, name, contract_month, price, \`change\`, change_pct, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, NOW())
     ON DUPLICATE KEY UPDATE
       name = VALUES(name),
       contract_month = VALUES(contract_month),
       price = VALUES(price),
       \`change\` = VALUES(\`change\`),
       change_pct = VALUES(change_pct),
       updated_at = NOW()`,
    [symbol, name, contractMonthLabel(new Date(latestDate)), latestClose, change, changePct]
  );
}

export async function ensureFresh() {
  // Concurrent, best-effort per symbol — a slow/failing Alpha Vantage
  // call (rate limit, timeout, ...) must not block the whole request;
  // callers just get whatever is already cached for that symbol.
  await Promise.all(
    Object.keys(PROXY_SYMBOLS).map(async (symbol) => {
      try {
        if (await isStale(symbol)) {
          await refreshSymbol(symbol);
        }
      } catch (err) {
        console.error(`marketData refresh failed for ${symbol}:`, err);
      }
    })
  );
}

export async function history(symbol, days = 180) {
  const [rows] = await pool.query(
    `SELECT bar_date, close FROM futures_price_history
     WHERE symbol = ? ORDER BY bar_date DESC LIMIT ?`,
    [symbol, days]
  );
  return rows.reverse();
}
