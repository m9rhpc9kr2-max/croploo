/**
 * Soybean Board Crush — the processing margin implied by CME futures:
 *
 *   crush ($/bu) = 0.022 × Soybean Meal ($/short ton)
 *                + 0.11  × Soybean Oil (¢/lb)
 *                − Soybeans (¢/bu) / 100
 *
 * (a 60-lb bushel of beans yields ~44 lb meal = 0.022 short tons and
 * ~11 lb oil). Front-month ZS/ZL/ZM daily closes come from Yahoo
 * Finance's public chart API (free, no key) and are cached in
 * crush_history so the endpoint keeps working if Yahoo hiccups.
 */
import { pool } from "./db.js";

export class CrushError extends Error {}

const YAHOO_CHART = "https://query1.finance.yahoo.com/v8/finance/chart";
const LEGS = { ZS: "ZS=F", ZL: "ZL=F", ZM: "ZM=F" };
const REFRESH_MINUTES = 60;

async function fetchLeg(yahooSymbol) {
  const url = `${YAHOO_CHART}/${encodeURIComponent(yahooSymbol)}?range=1y&interval=1d`;
  const resp = await fetch(url, {
    headers: { "user-agent": "Mozilla/5.0 (croploo-backend)" },
    signal: AbortSignal.timeout(15000),
  });
  if (!resp.ok) throw new CrushError(`Yahoo HTTP ${resp.status} for ${yahooSymbol}`);
  const json = await resp.json();
  const result = json.chart?.result?.[0];
  const timestamps = result?.timestamp ?? [];
  const closes = result?.indicators?.quote?.[0]?.close ?? [];
  if (timestamps.length === 0) {
    throw new CrushError(`Yahoo returned no bars for ${yahooSymbol}`);
  }

  const byDate = new Map();
  for (let i = 0; i < timestamps.length; i++) {
    if (closes[i] == null) continue;
    const day = new Date(timestamps[i] * 1000).toISOString().slice(0, 10);
    byDate.set(day, closes[i]);
  }
  return byDate;
}

function computeCrush(zs, zl, zm) {
  return 0.022 * zm + 0.11 * zl - zs / 100;
}

async function isStale() {
  const [rows] = await pool.query(
    "SELECT MAX(updated_at) AS latest FROM crush_history"
  );
  if (!rows[0]?.latest) return true;
  return Date.now() - new Date(rows[0].latest).getTime() > REFRESH_MINUTES * 60_000;
}

async function refresh() {
  const [zs, zl, zm] = await Promise.all(
    Object.values(LEGS).map(fetchLeg)
  );

  for (const [day, zsClose] of zs) {
    const zlClose = zl.get(day);
    const zmClose = zm.get(day);
    if (zlClose == null || zmClose == null) continue;
    await pool.query(
      `INSERT INTO crush_history (bar_date, zs_close, zl_close, zm_close, crush, updated_at)
       VALUES (?, ?, ?, ?, ?, NOW())
       ON DUPLICATE KEY UPDATE
         zs_close = VALUES(zs_close), zl_close = VALUES(zl_close),
         zm_close = VALUES(zm_close), crush = VALUES(crush), updated_at = NOW()`,
      [day, zsClose, zlClose, zmClose, computeCrush(zsClose, zlClose, zmClose)]
    );
  }
}

export async function ensureFresh() {
  try {
    if (await isStale()) await refresh();
  } catch (err) {
    console.error("crush refresh failed:", err);
  }
}

export async function current(days = 180) {
  await ensureFresh();
  const [rows] = await pool.query(
    `SELECT bar_date, zs_close, zl_close, zm_close, crush
     FROM crush_history ORDER BY bar_date DESC LIMIT ?`,
    [days]
  );
  if (rows.length === 0) throw new CrushError("No crush data cached yet");

  const history = rows.reverse();
  const latest = history[history.length - 1];
  const weekAgo = history[Math.max(0, history.length - 6)];
  const yearValues = history.map((r) => r.crush);
  const yearAvg = yearValues.reduce((a, b) => a + b, 0) / yearValues.length;

  return {
    date: latest.bar_date.toISOString().slice(0, 10),
    crush: Number(latest.crush.toFixed(2)),
    change_1w: Number((latest.crush - weekAgo.crush).toFixed(2)),
    avg_period: Number(yearAvg.toFixed(2)),
    legs: {
      soybeans_cents_bu: Number(latest.zs_close.toFixed(2)),
      oil_cents_lb: Number(latest.zl_close.toFixed(2)),
      meal_usd_ton: Number(latest.zm_close.toFixed(2)),
      oil_value_usd_bu: Number((0.11 * latest.zl_close).toFixed(2)),
      meal_value_usd_bu: Number((0.022 * latest.zm_close).toFixed(2)),
    },
    history: history.map((r) => ({
      date: r.bar_date.toISOString().slice(0, 10),
      crush: Number(r.crush.toFixed(2)),
    })),
  };
}
