/**
 * Shared FRED (Federal Reserve Bank of St. Louis) series client — backs
 * both the Treasury yield curve (src/yieldCurve.js) and the macro
 * indicators panel (src/economicIndicators.js), which are both just
 * different FRED series IDs read and cached the same way.
 */
import { pool } from "./db.js";
import * as config from "./config.js";

export class FredError extends Error {}

const REFRESH_STALE_MS = 12 * 60 * 60 * 1000;

async function isStale(seriesId) {
  const [rows] = await pool.query(
    "SELECT MAX(obs_date) AS latest FROM fred_series_history WHERE series_id = ?",
    [seriesId]
  );
  const latest = rows[0]?.latest;
  if (!latest) return true;
  return Date.now() - new Date(latest).getTime() > REFRESH_STALE_MS;
}

async function fetchObservations(seriesId, { limit = 260 } = {}) {
  if (!config.FRED_API_KEY) {
    throw new FredError("FRED_API_KEY is not configured");
  }
  const url = new URL(config.FRED_BASE_URL);
  url.searchParams.set("series_id", seriesId);
  url.searchParams.set("api_key", config.FRED_API_KEY);
  url.searchParams.set("file_type", "json");
  url.searchParams.set("sort_order", "desc");
  url.searchParams.set("limit", String(limit));

  const resp = await fetch(url, { signal: AbortSignal.timeout(15000) });
  if (!resp.ok) throw new FredError(`FRED HTTP ${resp.status} for ${seriesId}`);
  const json = await resp.json();
  return (json.observations ?? []).filter((o) => o.value !== ".");
}

async function refresh(seriesId) {
  const observations = await fetchObservations(seriesId);
  for (const obs of observations) {
    await pool.query(
      `INSERT INTO fred_series_history (series_id, obs_date, value)
       VALUES (?, ?, ?)
       ON DUPLICATE KEY UPDATE value = VALUES(value)`,
      [seriesId, obs.date, Number(obs.value)]
    );
  }
}

export async function ensureFresh(seriesId) {
  try {
    if (await isStale(seriesId)) await refresh(seriesId);
  } catch (err) {
    console.error(`FRED refresh failed for ${seriesId}:`, err);
  }
}

/** Cached observations for one series, most recent first. */
export async function history(seriesId, limit = 260) {
  await ensureFresh(seriesId);
  const [rows] = await pool.query(
    `SELECT obs_date, value FROM fred_series_history
     WHERE series_id = ? ORDER BY obs_date DESC LIMIT ?`,
    [seriesId, limit]
  );
  return rows;
}

/** Most recent cached observation for one series, or null. */
export async function latest(seriesId) {
  const rows = await history(seriesId, 1);
  return rows[0] ?? null;
}
