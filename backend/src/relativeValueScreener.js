/**
 * Relative Value Screener — corn/wheat/soybeans side by side on four
 * real, independently-computed axes: distance from the 52-week
 * high/low, seasonal deviation from the 5-year average, COT fund
 * positioning percentile (reused from cotData.js), and a basis
 * percentile (today's average absolute basis vs its own trailing
 * 52-week distribution). All four numbers already exist elsewhere in
 * the app individually — this just puts them on one screen.
 */
import { pool } from "./db.js";
import * as seasonal from "./seasonal.js";
import * as cotData from "./cotData.js";

export class RelativeValueError extends Error {}

const SYMBOLS = { CORN: "ZC", WHEAT: "ZW", SOYBEANS: "ZS" };

function isoWeek(date) {
  const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
  d.setUTCDate(d.getUTCDate() + 4 - (d.getUTCDay() || 7));
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  return Math.ceil(((d - yearStart) / 86400000 + 1) / 7);
}

async function fiftyTwoWeekRange(symbol) {
  const [rows] = await pool.query(
    `SELECT close, bar_date FROM futures_price_history WHERE symbol = ?
     ORDER BY bar_date DESC LIMIT 1`,
    [symbol]
  );
  const latest = rows[0];
  if (!latest) return null;

  const [range] = await pool.query(
    `SELECT MAX(close) AS hi, MIN(close) AS lo FROM futures_price_history
     WHERE symbol = ? AND bar_date >= DATE_SUB(CURDATE(), INTERVAL 52 WEEK)`,
    [symbol]
  );
  const { hi, lo } = range[0];
  if (hi == null || lo == null) return null;

  return {
    latest: latest.close,
    from52wHighPct: Number((((latest.close - hi) / hi) * 100).toFixed(1)),
    from52wLowPct: Number((((latest.close - lo) / lo) * 100).toFixed(1)),
  };
}

async function seasonalDeviation(symbol) {
  const pattern = await seasonal.seasonalPattern(symbol).catch(() => null);
  if (!pattern) return null;
  const week = isoWeek(new Date());
  const entry = pattern.weeks.find((w) => w.week === week && w.current != null) ??
    [...pattern.weeks].reverse().find((w) => w.current != null);
  if (!entry || entry.avg_5y == null) return null;
  return Number((entry.current - entry.avg_5y).toFixed(1));
}

async function basisPercentile(symbol) {
  const [rows] = await pool.query(
    `SELECT snapshot_date, AVG(ABS(basis)) AS avg_abs_basis FROM basis_snapshots
     WHERE symbol = ? GROUP BY snapshot_date ORDER BY snapshot_date`,
    [symbol]
  );
  if (rows.length < 4) return null;
  const current = rows[rows.length - 1].avg_abs_basis;
  const below = rows.filter((r) => r.avg_abs_basis < current).length;
  return Math.round((below / rows.length) * 100);
}

async function cotPercentiles() {
  try {
    const data = cotData.serialize(await cotData.ensureLatest());
    return new Map(data.commodities.map((c) => [c.commodity, c.net_percentile_3y]));
  } catch {
    return new Map();
  }
}

export async function snapshot() {
  const cotPercentileByCommodity = await cotPercentiles();

  const rows = await Promise.all(
    Object.entries(SYMBOLS).map(async ([commodity, symbol]) => {
      const [range, seasonalDev, basisPctile] = await Promise.all([
        fiftyTwoWeekRange(symbol),
        seasonalDeviation(symbol),
        basisPercentile(symbol),
      ]);
      return {
        commodity,
        symbol,
        from_52w_high_pct: range?.from52wHighPct ?? null,
        from_52w_low_pct: range?.from52wLowPct ?? null,
        seasonal_deviation_pct: seasonalDev,
        cot_percentile_3y: cotPercentileByCommodity.get(commodity) ?? null,
        basis_percentile_52w: basisPctile,
      };
    })
  );

  const hasAnyData = rows.some((r) =>
    [r.from_52w_high_pct, r.seasonal_deviation_pct, r.cot_percentile_3y, r.basis_percentile_52w]
      .some((v) => v != null)
  );
  if (!hasAnyData) throw new RelativeValueError("Not enough data cached yet");

  return { date: new Date().toISOString().slice(0, 10), commodities: rows };
}
