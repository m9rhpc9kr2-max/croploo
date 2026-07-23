/**
 * Real weekly grain rail car loadings by state, from USDA AgTransport's
 * mirror of the Surface Transportation Board's Rail Service Metrics
 * (Socrata dataset 27k8-utc2, keyless — same platform as usdaBasis.js
 * and exportSales.js). Class I railroads report cars loaded and billed
 * per state per week; this sums across all reporting railroads for a
 * given state (or the dataset's own "Total" row for the US total).
 */
import { pool } from "./db.js";

const RAIL_CARS_URL = "https://agtransport.usda.gov/resource/27k8-utc2.json";

// USDA-reported free-tier refresh cadence: railroads submit weekly, so
// recheck at most once a day.
const REFRESH_STALE_MS = 24 * 60 * 60 * 1000;

export class GrainRailCarsError extends Error {}

function toInt(v) {
  const n = Number(v);
  return Number.isFinite(n) ? Math.round(n) : 0;
}

async function fetchStateSeries(state) {
  const url = new URL(RAIL_CARS_URL);
  url.searchParams.set(
    "$select",
    "date,sum(all) as total_cars,sum(dedicated_or_shuttle) as shuttle_cars"
  );
  url.searchParams.set("$where", `state='${state}'`);
  url.searchParams.set("$group", "date");
  url.searchParams.set("$order", "date DESC");
  url.searchParams.set("$limit", "104"); // ~2 years of weekly data

  const resp = await fetch(url, { signal: AbortSignal.timeout(20000) });
  if (!resp.ok) throw new GrainRailCarsError(`USDA AgTransport Rail Cars HTTP ${resp.status}`);
  const rows = await resp.json();
  return rows.map((r) => ({
    date: r.date.slice(0, 10),
    totalCars: toInt(r.total_cars),
    shuttleCars: toInt(r.shuttle_cars),
  }));
}

async function isStale(state) {
  const [rows] = await pool.query(
    `SELECT MAX(week_date) AS latest FROM rail_car_loadings WHERE state = ?`,
    [state]
  );
  const latest = rows[0]?.latest;
  if (!latest) return true;
  return Date.now() - new Date(latest).getTime() > REFRESH_STALE_MS;
}

export async function refreshState(state) {
  const weeks = await fetchStateSeries(state);
  for (const w of weeks) {
    await pool.query(
      `INSERT INTO rail_car_loadings (state, week_date, total_cars, shuttle_cars)
       VALUES (?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         total_cars = VALUES(total_cars),
         shuttle_cars = VALUES(shuttle_cars)`,
      [state, w.date, w.totalCars, w.shuttleCars]
    );
  }
}

export async function ensureFresh(states) {
  await Promise.all(
    states.map(async (state) => {
      try {
        if (await isStale(state)) {
          await refreshState(state);
        }
      } catch (err) {
        console.error(`grainRailCars refresh failed for ${state}:`, err);
      }
    })
  );
}

export async function history(state, weeks = 26) {
  const [rows] = await pool.query(
    `SELECT week_date, total_cars, shuttle_cars FROM rail_car_loadings
     WHERE state = ? ORDER BY week_date DESC LIMIT ?`,
    [state, weeks]
  );
  return rows.reverse();
}

export async function latest(state) {
  const [rows] = await pool.query(
    `SELECT * FROM rail_car_loadings WHERE state = ? ORDER BY week_date DESC LIMIT 1`,
    [state]
  );
  return rows[0] ?? null;
}
