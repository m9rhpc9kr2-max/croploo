/**
 * Rolling Pearson correlation between six real markets: Corn, Wheat,
 * Soybeans (marketData.js's daily futures-proxy closes), Crude Oil
 * (crack_spread_history's real CL=F close), the Dollar Index
 * (dollarIndex.js's UUP proxy), and Natural Gas (ngPrice.js's real
 * NG=F close). Every series is already collected for another feature —
 * this module does no new fetching of its own, just joins on date and
 * computes correlation over the trailing 30/60/90 days.
 *
 * A pair only gets a number if there are enough overlapping trading
 * days in the window; otherwise it's reported as null rather than a
 * correlation computed from too few points to mean anything.
 */
import { pool } from "./db.js";
import * as marketData from "./marketData.js";
import * as dollarIndex from "./dollarIndex.js";
import * as crackSpreadModule from "./crackSpread.js";
import * as ngPrice from "./ngPrice.js";

export const ASSETS = ["CORN", "WHEAT", "SOYBEANS", "CRUDE", "DOLLAR", "NATURAL_GAS"];
export const WINDOWS = [30, 60, 90];

const MIN_OVERLAP_FRACTION = 0.5;

async function seriesFor(asset) {
  switch (asset) {
    case "CORN":
      return toMap(await marketData.history("ZC", 400), "bar_date", "close");
    case "WHEAT":
      return toMap(await marketData.history("ZW", 400), "bar_date", "close");
    case "SOYBEANS":
      return toMap(await marketData.history("ZS", 400), "bar_date", "close");
    case "CRUDE": {
      const [rows] = await pool.query(
        `SELECT bar_date, crude_close FROM crack_spread_history
         ORDER BY bar_date ASC LIMIT 400`
      );
      return toMap(rows, "bar_date", "crude_close");
    }
    case "DOLLAR": {
      const [rows] = await pool.query(
        `SELECT bar_date, dollar_index FROM dollar_index_history
         ORDER BY bar_date ASC LIMIT 400`
      );
      return toMap(rows, "bar_date", "dollar_index");
    }
    case "NATURAL_GAS":
      return toMap(await ngPrice.history(400), "bar_date", "close");
    default:
      throw new Error(`Unknown asset ${asset}`);
  }
}

function toMap(rows, dateKey, valueKey) {
  const map = new Map();
  for (const row of rows) {
    const date = row[dateKey] instanceof Date
      ? row[dateKey].toISOString().slice(0, 10)
      : String(row[dateKey]).slice(0, 10);
    map.set(date, row[valueKey]);
  }
  return map;
}

function pearson(xs, ys) {
  const n = xs.length;
  const mx = xs.reduce((a, b) => a + b, 0) / n;
  const my = ys.reduce((a, b) => a + b, 0) / n;
  let cov = 0;
  let vx = 0;
  let vy = 0;
  for (let i = 0; i < n; i++) {
    cov += (xs[i] - mx) * (ys[i] - my);
    vx += (xs[i] - mx) ** 2;
    vy += (ys[i] - my) ** 2;
  }
  if (vx === 0 || vy === 0) return null;
  return cov / Math.sqrt(vx * vy);
}

/** Correlation over the most recent `windowDays` dates present in both
 * series — null if fewer than half that many overlapping points exist. */
function correlate(seriesA, seriesB, windowDays) {
  const commonDates = [...seriesA.keys()]
    .filter((d) => seriesB.has(d))
    .sort()
    .slice(-windowDays);

  const minPoints = Math.max(5, Math.floor(windowDays * MIN_OVERLAP_FRACTION));
  if (commonDates.length < minPoints) return null;

  const xs = commonDates.map((d) => seriesA.get(d));
  const ys = commonDates.map((d) => seriesB.get(d));
  const r = pearson(xs, ys);
  return r === null ? null : Number(r.toFixed(2));
}

export async function ensureFresh() {
  await Promise.all([
    marketData.ensureFresh(),
    dollarIndex.ensureFresh(),
    crackSpreadModule.ensureFresh(),
    ngPrice.ensureFresh(),
  ]);
}

export async function build() {
  await ensureFresh();

  const seriesByAsset = new Map();
  for (const asset of ASSETS) {
    seriesByAsset.set(asset, await seriesFor(asset));
  }

  const windows = {};
  for (const windowDays of WINDOWS) {
    const matrix = ASSETS.map((rowAsset) =>
      ASSETS.map((colAsset) => {
        if (rowAsset === colAsset) return 1;
        return correlate(seriesByAsset.get(rowAsset), seriesByAsset.get(colAsset), windowDays);
      })
    );
    windows[windowDays] = matrix;
  }

  return { assets: ASSETS, windows };
}
