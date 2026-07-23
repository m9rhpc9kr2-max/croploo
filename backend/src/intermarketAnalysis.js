/**
 * Intermarket Analysis — rolling cross-correlation with lag 1-10 days
 * across grains, the dollar, crude, and natural gas, all from data
 * already cached in MySQL by other modules. Unlike a static correlation
 * matrix (see correlationMatrix.js), this finds which lag maximizes the
 * correlation between two series, which is what actually makes a
 * lead-lag relationship tradable ("corn leads soy by N days") instead
 * of just "these two move together".
 */
import { pool } from "./db.js";

export class IntermarketError extends Error {}

const MAX_LAG = 10;

const SERIES = {
  CORN: {
    query: "SELECT bar_date AS d, close AS v FROM futures_price_history WHERE symbol = 'ZC'",
  },
  WHEAT: {
    query: "SELECT bar_date AS d, close AS v FROM futures_price_history WHERE symbol = 'ZW'",
  },
  SOYBEANS: {
    query: "SELECT bar_date AS d, close AS v FROM futures_price_history WHERE symbol = 'ZS'",
  },
  DOLLAR: {
    query: "SELECT bar_date AS d, dollar_index AS v FROM dollar_index_history",
  },
  CRUDE: {
    query: "SELECT bar_date AS d, crude_close AS v FROM crack_spread_history",
  },
  NATURAL_GAS: {
    query: "SELECT bar_date AS d, close AS v FROM ng_price_history",
  },
};

// Curated pairs worth showing — the interesting cross-asset relationships,
// not all 15 combinations of 6 series.
const PAIRS = [
  ["CORN", "SOYBEANS"],
  ["CORN", "WHEAT"],
  ["DOLLAR", "CRUDE"],
  ["DOLLAR", "CORN"],
  ["CRUDE", "CORN"],
  ["CRUDE", "NATURAL_GAS"],
];

async function loadSeries(name) {
  const [rows] = await pool.query(SERIES[name].query);
  const map = new Map();
  for (const row of rows) {
    if (row.v == null) continue;
    map.set(row.d.toISOString().slice(0, 10), Number(row.v));
  }
  return map;
}

function pearson(xs, ys) {
  const n = xs.length;
  if (n < 2) return 0;
  const mx = xs.reduce((a, b) => a + b, 0) / n;
  const my = ys.reduce((a, b) => a + b, 0) / n;
  let cov = 0, vx = 0, vy = 0;
  for (let i = 0; i < n; i++) {
    cov += (xs[i] - mx) * (ys[i] - my);
    vx += (xs[i] - mx) ** 2;
    vy += (ys[i] - my) ** 2;
  }
  if (vx === 0 || vy === 0) return 0;
  return cov / Math.sqrt(vx * vy);
}

/**
 * Returns the lag (in trading-day observations, not necessarily
 * calendar days since these are daily/weekly series with gaps) that
 * maximizes |correlation| between A and a shifted B, searching
 * -MAX_LAG..MAX_LAG. Positive lag means A leads B (A's value at index i
 * correlates with B's value at index i+lag).
 */
function bestLag(datesA, valuesA, mapB) {
  const dates = datesA;
  let best = { lag: 0, correlation: 0 };
  for (let lag = -MAX_LAG; lag <= MAX_LAG; lag++) {
    const xs = [];
    const ys = [];
    for (let i = 0; i < dates.length; i++) {
      const j = i + lag;
      if (j < 0 || j >= dates.length) continue;
      const bVal = mapB.get(dates[j]);
      if (bVal == null) continue;
      xs.push(valuesA[i]);
      ys.push(bVal);
    }
    if (xs.length < 20) continue;
    const corr = pearson(xs, ys);
    if (Math.abs(corr) > Math.abs(best.correlation)) {
      best = { lag, correlation: Number(corr.toFixed(3)) };
    }
  }
  return best;
}

async function pairAnalysis(nameA, nameB) {
  const [mapA, mapB] = await Promise.all([loadSeries(nameA), loadSeries(nameB)]);
  const commonDates = [...mapA.keys()].filter((d) => mapB.has(d)).sort();
  if (commonDates.length < 40) return null;

  const valuesA = commonDates.map((d) => mapA.get(d));
  const result = bestLag(commonDates, valuesA, mapB);

  return {
    a: nameA,
    b: nameB,
    best_lag_days: result.lag,
    correlation_at_best_lag: result.correlation,
    // lag > 0: A's move today best explains B's move `lag` observations later (A leads B).
    // lag < 0: B leads A. lag = 0: contemporaneous / no clear lead-lag.
    leader: result.lag > 0 ? nameA : (result.lag < 0 ? nameB : null),
    lag_observations: Math.abs(result.lag),
  };
}

export async function snapshot() {
  const results = await Promise.all(PAIRS.map(([a, b]) => pairAnalysis(a, b)));
  const pairs = results.filter((r) => r !== null);
  if (pairs.length === 0) throw new IntermarketError("Not enough overlapping data cached yet");
  return { date: new Date().toISOString().slice(0, 10), pairs };
}
