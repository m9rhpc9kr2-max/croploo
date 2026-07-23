/**
 * Volatility Monitor — realized volatility (annualized stdev of daily
 * log returns × √252) for corn/wheat/soybeans, plus where today's
 * 20-day realized vol sits within its own trailing-year distribution.
 *
 * Honest limitation: there is no free data source for CBOT options
 * implied volatility (that's a paid CME/Barchart product), so this
 * shows realized vol only — not the "realized vs implied" comparison
 * described in the spec. `implied_vol` is always null; treat the vol
 * percentile as the practical substitute (high percentile ≈ vol
 * historically expensive to buy, low percentile ≈ historically cheap).
 */
import { pool } from "./db.js";

export class VolatilityError extends Error {}

const SYMBOLS = { CORN: "ZC", WHEAT: "ZW", SOYBEANS: "ZS" };
const WINDOW_DAYS = 20;
const TRADING_DAYS_PER_YEAR = 252;

function stdev(values) {
  const n = values.length;
  if (n < 2) return 0;
  const mean = values.reduce((a, b) => a + b, 0) / n;
  const variance = values.reduce((a, b) => a + (b - mean) ** 2, 0) / (n - 1);
  return Math.sqrt(variance);
}

function dailyLogReturns(closes) {
  const returns = [];
  for (let i = 1; i < closes.length; i++) {
    if (closes[i - 1] > 0 && closes[i] > 0) {
      returns.push(Math.log(closes[i] / closes[i - 1]));
    }
  }
  return returns;
}

async function symbolVol(symbol) {
  const [rows] = await pool.query(
    `SELECT bar_date, close FROM futures_price_history WHERE symbol = ?
     ORDER BY bar_date DESC LIMIT ?`,
    [symbol, TRADING_DAYS_PER_YEAR + WINDOW_DAYS + 1]
  );
  if (rows.length < WINDOW_DAYS + 10) return null;
  const closesDesc = rows.map((r) => r.close);
  const closes = closesDesc.slice().reverse(); // oldest first

  const allReturns = dailyLogReturns(closes);
  if (allReturns.length < WINDOW_DAYS) return null;

  // Rolling 20-day annualized vol for each point we have enough history for.
  const rolling = [];
  for (let i = WINDOW_DAYS; i <= allReturns.length; i++) {
    const window = allReturns.slice(i - WINDOW_DAYS, i);
    rolling.push(stdev(window) * Math.sqrt(TRADING_DAYS_PER_YEAR) * 100);
  }
  const current = rolling[rolling.length - 1];
  const below = rolling.filter((v) => v < current).length;
  const percentile = Math.round((below / rolling.length) * 100);

  return {
    realized_vol_20d_pct: Number(current.toFixed(1)),
    vol_percentile_1y: percentile,
    implied_vol: null,
  };
}

export async function snapshot() {
  const rows = await Promise.all(
    Object.entries(SYMBOLS).map(async ([commodity, symbol]) => ({
      commodity,
      symbol,
      ...(await symbolVol(symbol)),
    }))
  );
  const commodities = rows.filter((r) => r.realized_vol_20d_pct != null);
  if (commodities.length === 0) throw new VolatilityError("Not enough price history cached yet");
  return {
    date: new Date().toISOString().slice(0, 10),
    note: "No free source for CBOT options implied volatility — realized vol and its 1y percentile only.",
    commodities,
  };
}
