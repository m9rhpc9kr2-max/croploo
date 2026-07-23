/**
 * Real US Drought Monitor state statistics (usdmdataservices.unl.edu,
 * free/keyless REST API) — the D0–D4 severity scale every grain trader
 * already reads, as a companion to the NOAA precipitation-anomaly panel
 * in weatherImpact.js. Updated weekly (Thursdays), one row per state per
 * week from the National Drought Mitigation Center.
 */
import { pool } from "./db.js";

const USDM_BASE =
  "https://usdmdataservices.unl.edu/api/StateStatistics/GetDroughtSeverityStatisticsByArea";

// US Census FIPS state codes for the Corn Belt states Croploo already
// tracks weather for (same set as weatherImpact.js's CORN_BELT_STATES).
const STATES = [
  { fips: "19", state: "IA", name: "Iowa" },
  { fips: "17", state: "IL", name: "Illinois" },
  { fips: "31", state: "NE", name: "Nebraska" },
  { fips: "18", state: "IN", name: "Indiana" },
  { fips: "27", state: "MN", name: "Minnesota" },
  { fips: "20", state: "KS", name: "Kansas" },
];

const REFRESH_STALE_MS = 24 * 60 * 60 * 1000; // USDM refreshes weekly (Thursdays); daily recheck is enough

export class DroughtMonitorError extends Error {}

function fmtDate(d) {
  return `${d.getMonth() + 1}/${d.getDate()}/${d.getFullYear()}`;
}

async function fetchLatestWeek(fips) {
  const end = new Date();
  const start = new Date(end.getTime() - 21 * 24 * 60 * 60 * 1000); // 3-week lookback so a slow-to-post week doesn't come up empty
  const url = new URL(USDM_BASE);
  url.searchParams.set("aoi", fips);
  url.searchParams.set("startdate", fmtDate(start));
  url.searchParams.set("enddate", fmtDate(end));
  url.searchParams.set("statisticsType", "1");

  const resp = await fetch(url, {
    headers: { Accept: "application/json" },
    signal: AbortSignal.timeout(20000),
  });
  if (!resp.ok) throw new DroughtMonitorError(`US Drought Monitor HTTP ${resp.status}`);
  const rows = await resp.json();
  if (rows.length === 0) return null;

  // API returns oldest→newest within the window; take the most recent.
  const latest = rows[rows.length - 1];
  const none = Number(latest.none);
  const d0 = Number(latest.d0);
  const d1 = Number(latest.d1);
  const d2 = Number(latest.d2);
  const d3 = Number(latest.d3);
  const d4 = Number(latest.d4);
  const total = none + d0 + d1 + d2 + d3 + d4;
  const pct = (v) => (total > 0 ? Number(((v / total) * 100).toFixed(1)) : 0);

  return {
    mapDate: latest.mapDate.slice(0, 10),
    noneP: pct(none),
    d0Pct: pct(d0),
    d1Pct: pct(d1),
    d2Pct: pct(d2),
    d3Pct: pct(d3),
    d4Pct: pct(d4),
    // "abnormally dry or worse" — the headline number most drought
    // coverage cites, since D0 alone isn't drought, just a watch flag.
    anyDroughtPct: pct(d0 + d1 + d2 + d3 + d4),
  };
}

async function isStale(state) {
  const [rows] = await pool.query(
    `SELECT MAX(map_date) AS latest FROM drought_monitor_snapshots WHERE state = ?`,
    [state]
  );
  const latest = rows[0]?.latest;
  if (!latest) return true;
  return Date.now() - new Date(latest).getTime() > REFRESH_STALE_MS;
}

async function refreshState({ fips, state }) {
  const week = await fetchLatestWeek(fips);
  if (!week) return;
  await pool.query(
    `INSERT INTO drought_monitor_snapshots
       (state, map_date, none_pct, d0_pct, d1_pct, d2_pct, d3_pct, d4_pct, any_drought_pct)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON DUPLICATE KEY UPDATE
       none_pct = VALUES(none_pct), d0_pct = VALUES(d0_pct), d1_pct = VALUES(d1_pct),
       d2_pct = VALUES(d2_pct), d3_pct = VALUES(d3_pct), d4_pct = VALUES(d4_pct),
       any_drought_pct = VALUES(any_drought_pct)`,
    [state, week.mapDate, week.noneP, week.d0Pct, week.d1Pct, week.d2Pct, week.d3Pct, week.d4Pct, week.anyDroughtPct]
  );
}

export async function ensureFresh() {
  await Promise.all(
    STATES.map(async (s) => {
      try {
        if (await isStale(s.state)) {
          await refreshState(s);
        }
      } catch (err) {
        console.error(`droughtMonitor refresh failed for ${s.state}:`, err);
      }
    })
  );
}

export async function latestAll() {
  const out = [];
  for (const s of STATES) {
    const [rows] = await pool.query(
      `SELECT * FROM drought_monitor_snapshots WHERE state = ? ORDER BY map_date DESC LIMIT 1`,
      [s.state]
    );
    if (rows[0]) out.push({ state: s.state, name: s.name, ...rows[0] });
  }
  return out;
}
