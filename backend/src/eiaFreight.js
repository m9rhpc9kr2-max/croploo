/**
 * Real freight-rate proxy via the EIA's weekly retail diesel price
 * series (api.eia.gov, "gnd" — Gasoline and Diesel Retail Prices). EIA
 * has no public trucking/rail/barge rate feed, so each corridor/mode's
 * freight index is modeled as a base rate plus a diesel-price
 * sensitivity, driven by the real regional diesel price.
 */
import { pool } from "./db.js";
import * as config from "./config.js";

export class EiaError extends Error {}

const EIA_BASE_URL = "https://api.eia.gov/v2/petroleum/pri/gnd/data/";
const DIESEL_PRODUCT = "EPD2D"; // On-Highway Diesel Fuel, all types

// Diesel price ($/gal) this rate model is calibrated against (~5yr
// national average). Real EIA prices above/below this shift rateValue.
const BASELINE_DIESEL_PRICE = 4.0;

// duoarea = EIA PADD region code for that corridor's origin; state =
// the ELEVATORS state used to pair this corridor with real basis data.
export const CORRIDORS = [
  { corridor: "Midwest–Gulf", mode: "truck", region: "R20", state: "IL", baseRate: 30.0, dieselSensitivity: 9.5 },
  { corridor: "Midwest–Gulf", mode: "barge", region: "R20", state: "IL", baseRate: 14.0, dieselSensitivity: 4.0 },
  { corridor: "PNW Export", mode: "rail", region: "R50", state: "MN", baseRate: 46.0, dieselSensitivity: 6.5 },
  { corridor: "Eastern Corn Belt", mode: "truck", region: "R20", state: "IN", baseRate: 22.0, dieselSensitivity: 8.0 },
  { corridor: "IL River North", mode: "barge", region: "R20", state: "IL", baseRate: 12.0, dieselSensitivity: 3.5 },
  { corridor: "KS–TX Gulf", mode: "rail", region: "R30", state: "KS", baseRate: 40.0, dieselSensitivity: 6.0 },
];

async function fetchDieselSeries(region, weeks) {
  if (!config.EIA_API_KEY) {
    throw new EiaError("EIA_API_KEY is not configured");
  }

  const url = new URL(EIA_BASE_URL);
  url.searchParams.set("api_key", config.EIA_API_KEY);
  url.searchParams.set("frequency", "weekly");
  url.searchParams.append("data[0]", "value");
  url.searchParams.append("facets[duoarea][]", region);
  url.searchParams.append("facets[product][]", DIESEL_PRODUCT);
  url.searchParams.set("sort[0][column]", "period");
  url.searchParams.set("sort[0][direction]", "desc");
  url.searchParams.set("length", String(weeks));

  const resp = await fetch(url, { signal: AbortSignal.timeout(20000) });
  if (!resp.ok) {
    throw new EiaError(`EIA API HTTP ${resp.status}`);
  }
  const json = await resp.json();
  const rows = json.response?.data ?? [];
  return rows
    .filter((r) => r.value != null)
    .map((r) => ({ date: r.period, price: Number(r.value) }))
    .sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));
}

async function isStale(region) {
  const [rows] = await pool.query(
    "SELECT MAX(bar_date) AS latest FROM diesel_prices WHERE region = ?",
    [region]
  );
  const latest = rows[0]?.latest;
  if (!latest) return true;
  return Date.now() - new Date(latest).getTime() > 6 * 24 * 60 * 60 * 1000;
}

async function refreshRegion(region) {
  const series = await fetchDieselSeries(region, 300);
  for (const bar of series) {
    await pool.query(
      `INSERT INTO diesel_prices (region, bar_date, price)
       VALUES (?, ?, ?)
       ON DUPLICATE KEY UPDATE price = VALUES(price)`,
      [region, bar.date, bar.price]
    );
  }
}

export async function ensureFresh(regions) {
  // Concurrent, best-effort per region — a slow/failing EIA call for one
  // region must not block the whole request (see usdaBasis.ensureFresh).
  await Promise.all(
    regions.map(async (region) => {
      try {
        if (await isStale(region)) {
          await refreshRegion(region);
        }
      } catch (err) {
        console.error(`eiaFreight refresh failed for ${region}:`, err);
      }
    })
  );
}

export async function history(region, days) {
  const [rows] = await pool.query(
    `SELECT bar_date, price FROM diesel_prices
     WHERE region = ? AND bar_date >= DATE_SUB(CURDATE(), INTERVAL ? DAY)
     ORDER BY bar_date ASC`,
    [region, days]
  );
  return rows;
}

export async function latestTwo(region) {
  const [rows] = await pool.query(
    `SELECT bar_date, price FROM diesel_prices
     WHERE region = ? ORDER BY bar_date DESC LIMIT 2`,
    [region]
  );
  return rows;
}

export function freightIndex(corridorConfig, dieselPrice) {
  return (
    corridorConfig.baseRate +
    corridorConfig.dieselSensitivity * (dieselPrice - BASELINE_DIESEL_PRICE)
  );
}
