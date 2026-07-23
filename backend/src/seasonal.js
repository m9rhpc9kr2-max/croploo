/**
 * Seasonal price patterns from ~10 years of real weekly continuous-
 * futures closes (Yahoo Finance chart API, free, no key). Alpha
 * Vantage's free tier no longer allows outputsize=full (it became a
 * premium-only param), so this sources independently of marketData.js
 * rather than reusing futures_price_history.
 *
 * For each ISO week of the year (1..52) we average the past 5 and 10
 * calendar years, normalized as an index (% of each year's own mean) so
 * different price levels are comparable across years. The current year
 * is overlaid the same way, so the classic patterns — corn's October
 * harvest low, the February rally — are directly visible against where
 * price sits right now.
 */
import { pool } from "./db.js";

export class SeasonalError extends Error {}

const YAHOO_CHART = "https://query1.finance.yahoo.com/v8/finance/chart";
const YAHOO_SYMBOLS = { ZC: "ZC=F", ZW: "ZW=F", ZS: "ZS=F" };
const REFRESH_STALE_MS = 6 * 24 * 60 * 60 * 1000;

async function fetchWeeklySeries(yahooSymbol) {
  const url = `${YAHOO_CHART}/${encodeURIComponent(yahooSymbol)}?range=10y&interval=1wk`;
  const resp = await fetch(url, {
    headers: { "user-agent": "Mozilla/5.0 (croploo-backend)" },
    signal: AbortSignal.timeout(20000),
  });
  if (!resp.ok) throw new SeasonalError(`Yahoo HTTP ${resp.status} for ${yahooSymbol}`);
  const json = await resp.json();
  const result = json.chart?.result?.[0];
  const timestamps = result?.timestamp ?? [];
  const closes = result?.indicators?.quote?.[0]?.close ?? [];
  if (timestamps.length === 0) {
    throw new SeasonalError(`Yahoo returned no bars for ${yahooSymbol}`);
  }

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

async function isStale(symbol) {
  const [rows] = await pool.query(
    "SELECT MAX(bar_date) AS latest FROM seasonal_price_history WHERE symbol = ?",
    [symbol]
  );
  const latest = rows[0]?.latest;
  if (!latest) return true;
  return Date.now() - new Date(latest).getTime() > REFRESH_STALE_MS;
}

async function refresh(symbol) {
  const bars = await fetchWeeklySeries(YAHOO_SYMBOLS[symbol]);
  for (const bar of bars) {
    await pool.query(
      `INSERT INTO seasonal_price_history (symbol, bar_date, close)
       VALUES (?, ?, ?)
       ON DUPLICATE KEY UPDATE close = VALUES(close)`,
      [symbol, bar.date, bar.close]
    );
  }
}

async function ensureFresh(symbol) {
  try {
    if (await isStale(symbol)) await refresh(symbol);
  } catch (err) {
    console.error(`seasonal refresh failed for ${symbol}:`, err);
    // Best-effort: fall through to whatever is already cached.
  }
}

function isoWeek(date) {
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const dayNum = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - dayNum);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  return Math.ceil(((d - yearStart) / 86400000 + 1) / 7);
}

/** year -> week -> mean close (bars are already ~weekly, but average in
 * case Yahoo ever returns more than one bar in the same ISO week). */
function weeklyMeansByYear(bars) {
  const acc = new Map();
  for (const { bar_date, close } of bars) {
    const date = new Date(bar_date);
    const year = date.getUTCFullYear();
    const week = Math.min(isoWeek(date), 52);
    const key = `${year}-${week}`;
    const cur = acc.get(key) ?? { year, week, sum: 0, n: 0 };
    cur.sum += close;
    cur.n += 1;
    acc.set(key, cur);
  }
  const byYear = new Map();
  for (const { year, week, sum, n } of acc.values()) {
    const weeks = byYear.get(year) ?? new Map();
    weeks.set(week, sum / n);
    byYear.set(year, weeks);
  }
  return byYear;
}

/** Normalize a year's weekly closes to % of that year's mean. */
function indexed(weeks) {
  const values = [...weeks.values()];
  const mean = values.reduce((a, b) => a + b, 0) / values.length;
  const out = new Map();
  for (const [week, close] of weeks) out.set(week, (close / mean) * 100);
  return out;
}

function averageAcrossYears(byYear, years, currentYear) {
  const perWeek = new Map();
  for (const [year, weeks] of byYear) {
    if (year >= currentYear || year < currentYear - years) continue;
    for (const [week, value] of indexed(weeks)) {
      const list = perWeek.get(week) ?? [];
      list.push(value);
      perWeek.set(week, list);
    }
  }
  const out = [];
  for (let week = 1; week <= 52; week++) {
    const list = perWeek.get(week);
    out.push(list ? list.reduce((a, b) => a + b, 0) / list.length : null);
  }
  return out;
}

export async function seasonalPattern(symbol) {
  await ensureFresh(symbol);

  const [bars] = await pool.query(
    "SELECT bar_date, close FROM seasonal_price_history WHERE symbol = ? ORDER BY bar_date",
    [symbol]
  );
  if (bars.length === 0) {
    throw new SeasonalError(`No seasonal history cached yet for ${symbol}`);
  }

  const byYear = weeklyMeansByYear(bars);
  const currentYear = new Date().getUTCFullYear();

  const avg5 = averageAcrossYears(byYear, 5, currentYear);
  const avg10 = averageAcrossYears(byYear, 10, currentYear);

  const currentWeeks = byYear.get(currentYear) ?? new Map();
  const currentIndexed = currentWeeks.size > 0 ? indexed(currentWeeks) : new Map();

  const weeks = [];
  for (let week = 1; week <= 52; week++) {
    weeks.push({
      week,
      avg_5y: avg5[week - 1] != null ? Number(avg5[week - 1].toFixed(2)) : null,
      avg_10y: avg10[week - 1] != null ? Number(avg10[week - 1].toFixed(2)) : null,
      current: currentIndexed.has(week)
        ? Number(currentIndexed.get(week).toFixed(2))
        : null,
      current_price: currentWeeks.has(week)
        ? Number(currentWeeks.get(week).toFixed(2))
        : null,
    });
  }

  const yearsAvailable = [...byYear.keys()].filter((y) => y < currentYear).length;
  return {
    symbol,
    current_year: currentYear,
    years_available: yearsAvailable,
    weeks,
  };
}
