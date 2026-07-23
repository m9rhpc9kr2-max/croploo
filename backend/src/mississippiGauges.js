/**
 * Real Mississippi River stage/flow readings from NOAA's National Water
 * Prediction Service (api.water.noaa.gov/nwps — no key required), at
 * five gauges along the grain export corridor from St. Louis to the
 * Gulf. Low water here directly constrains barge loading depth and
 * tow size, which is a real, grain-specific signal no generic finance
 * terminal tracks.
 */
import { pool } from "./db.js";

const NWPS_BASE_URL = "https://api.water.noaa.gov/nwps/v1/gauges";

// Curated, verified-live gauge stations along the grain barge corridor.
// Each maps to a real NOAA Location ID (LID) — verified directly against
// the live API, not guessed.
export const GAUGES = [
  { lid: "EADM7", name: "St. Louis, MO", state: "MO", lat: 38.63, lng: -90.18 },
  { lid: "CPGM7", name: "Cape Girardeau, MO", state: "MO", lat: 37.3, lng: -89.52 },
  { lid: "MEMT1", name: "Memphis, TN", state: "TN", lat: 35.15, lng: -90.05 },
  { lid: "BTRL1", name: "Baton Rouge, LA", state: "LA", lat: 30.45, lng: -91.15 },
  { lid: "NORL1", name: "New Orleans, LA", state: "LA", lat: 29.95, lng: -90.07 },
];

const REFRESH_STALE_MS = 12 * 60 * 60 * 1000; // NWPS updates ~every 30 min; recheck twice daily is plenty for a daily-resolution cache

export class MississippiGaugeError extends Error {}

async function fetchGaugeSeries(lid) {
  const resp = await fetch(`${NWPS_BASE_URL}/${lid}/stageflow`, {
    headers: { Accept: "application/json" },
    signal: AbortSignal.timeout(20000),
  });
  if (!resp.ok) throw new MississippiGaugeError(`NOAA NWPS HTTP ${resp.status} for ${lid}`);
  const body = await resp.json();
  const points = body?.observed?.data ?? [];

  // Downsample 30-min readings to one (the last) reading per calendar day.
  const byDay = new Map();
  for (const p of points) {
    if (p.primary == null) continue;
    const day = p.validTime.slice(0, 10);
    byDay.set(day, { day, stageFt: Number(p.primary), flowKcfs: Number(p.secondary ?? 0) });
  }
  return [...byDay.values()];
}

async function isStale(lid) {
  const [rows] = await pool.query(
    `SELECT MAX(reading_date) AS latest FROM mississippi_gauge_readings WHERE lid = ?`,
    [lid]
  );
  const latest = rows[0]?.latest;
  if (!latest) return true;
  return Date.now() - new Date(latest).getTime() > REFRESH_STALE_MS;
}

export async function refreshGauge(lid) {
  const days = await fetchGaugeSeries(lid);
  for (const d of days) {
    await pool.query(
      `INSERT INTO mississippi_gauge_readings (lid, reading_date, stage_ft, flow_kcfs)
       VALUES (?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE stage_ft = VALUES(stage_ft), flow_kcfs = VALUES(flow_kcfs)`,
      [lid, d.day, d.stageFt, d.flowKcfs]
    );
  }
}

export async function ensureFresh(lids) {
  await Promise.all(
    lids.map(async (lid) => {
      try {
        if (await isStale(lid)) {
          await refreshGauge(lid);
        }
      } catch (err) {
        console.error(`mississippiGauges refresh failed for ${lid}:`, err);
      }
    })
  );
}

export async function history(lid, days = 30) {
  const [rows] = await pool.query(
    `SELECT reading_date, stage_ft, flow_kcfs FROM mississippi_gauge_readings
     WHERE lid = ? ORDER BY reading_date DESC LIMIT ?`,
    [lid, days]
  );
  return rows.reverse();
}

export async function latest(lid) {
  const [rows] = await pool.query(
    `SELECT * FROM mississippi_gauge_readings WHERE lid = ? ORDER BY reading_date DESC LIMIT 1`,
    [lid]
  );
  return rows[0] ?? null;
}
