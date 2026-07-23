/**
 * Generates real alerts from data already in the system — basis
 * deviations (usdaBasis.js) and futures moves (futures_prices, from
 * marketData.js) — instead of a scheduled worker. Cloud Run here has no
 * standalone cron runner, so this mirrors the same lazy-refresh pattern
 * already used by marketData.ensureFresh()/usdaBasis.ensureFresh(): the
 * scan only re-runs if an hour has passed since the last call.
 */
import { pool } from "./db.js";
import { ELEVATORS } from "./elevators.js";
import * as usdaBasis from "./usdaBasis.js";
import * as usdaCalendar from "./usdaCalendar.js";

const SYMBOL_COMMODITY = { ZC: "CORN", ZW: "WHEAT", ZS: "SOYBEANS" };
const COMMODITY_SYMBOL = { CORN: "ZC", WHEAT: "ZW", SOYBEANS: "ZS" };
const SCAN_INTERVAL_MS = 60 * 60 * 1000;
const DEDUPE_WINDOW_HOURS = 24;

// Exported so routes/alerts.js's /alert-rules endpoint can describe the
// system's actual live thresholds instead of duplicating the numbers.
export const BASIS_DEVIATION_THRESHOLD_PCT = 15;
export const FUTURES_MOVE_THRESHOLD_PCT = 2;

let lastScanAt = 0;

async function alreadyAlerted(type, commodity, key, userId = null) {
  const [rows] = await pool.query(
    `SELECT id FROM alerts
     WHERE type = ? AND commodity = ? AND metadata->>'$.key' = ?
       AND created_at >= DATE_SUB(NOW(), INTERVAL ? HOUR)
       AND user_id ${userId === null ? "IS NULL" : "= ?"}
     LIMIT 1`,
    userId === null
      ? [type, commodity, key, DEDUPE_WINDOW_HOURS]
      : [type, commodity, key, DEDUPE_WINDOW_HOURS, userId]
  );
  return rows.length > 0;
}

async function insertAlert({ type, commodity, title, body, severity, metadata, userId = null }) {
  await pool.query(
    `INSERT INTO alerts (type, commodity, title, body, severity, metadata, user_id)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
    [type, commodity, title, body, severity, JSON.stringify(metadata), userId]
  );
}

async function scanBasisAnomalies() {
  const states = [...new Set(ELEVATORS.map((e) => e.state))];
  for (const state of states) {
    for (const symbol of Object.keys(SYMBOL_COMMODITY)) {
      const snap = await usdaBasis.latest(state, symbol);
      if (!snap) continue;
      const avg = await usdaBasis.avg5yr(state, symbol);
      if (avg === null || avg === 0) continue;

      const deviationPct = ((snap.basis - avg) / Math.abs(avg)) * 100;
      if (Math.abs(deviationPct) <= BASIS_DEVIATION_THRESHOLD_PCT) continue;

      const commodity = SYMBOL_COMMODITY[symbol];
      const dateKey = snap.snapshot_date.toISOString().slice(0, 10);
      const key = `${state}:${symbol}:${dateKey}`;
      if (await alreadyAlerted("BASIS_ANOMALY", commodity, key)) continue;

      const elevatorNames = ELEVATORS.filter((e) => e.state === state).map((e) => e.name);
      const direction = deviationPct > 0 ? "above" : "below";
      await insertAlert({
        type: "BASIS_ANOMALY",
        commodity,
        title: `${commodity} Basis Anomaly — ${state}`,
        body:
          `Basis is ${Math.abs(deviationPct).toFixed(1)}% ${direction} its 5-year average ` +
          `(${snap.basis.toFixed(1)}¢ vs ${avg.toFixed(1)}¢ avg). Affects ${elevatorNames.join(", ")}.`,
        severity: Math.abs(deviationPct) > 25 ? "HIGH" : "MEDIUM",
        metadata: { key, state, symbol, deviationPct, basis: snap.basis, avg5yr: avg },
      });
    }
  }
}

async function scanFuturesMoves() {
  const [rows] = await pool.query("SELECT * FROM futures_prices");
  for (const row of rows) {
    if (Math.abs(row.change_pct) <= FUTURES_MOVE_THRESHOLD_PCT) continue;

    const commodity = SYMBOL_COMMODITY[row.symbol] ?? "ALL";
    const dateKey = new Date(row.updated_at).toISOString().slice(0, 10);
    const key = `${row.symbol}:${dateKey}`;
    if (await alreadyAlerted("FUTURES_MOVE", commodity, key)) continue;

    const direction = row.change_pct > 0 ? "Up" : "Down";
    await insertAlert({
      type: "FUTURES_MOVE",
      commodity,
      title: `${row.name} Futures ${direction} ${Math.abs(row.change_pct).toFixed(1)}%`,
      body: `${row.name} (${row.symbol}) moved ${row.change_pct.toFixed(2)}% to ${row.price.toFixed(2)}.`,
      severity: Math.abs(row.change_pct) > 4 ? "HIGH" : "MEDIUM",
      metadata: { key, symbol: row.symbol, changePct: row.change_pct, priceAtAlert: row.price },
    });
  }
}

async function scanUsdaReleases() {
  const releases = usdaCalendar.upcomingReleases(1); // today + next 24h
  for (const release of releases) {
    const key = `${release.report_type}:${release.release_date}`;
    if (await alreadyAlerted("USDA_RELEASE", "ALL", key)) continue;

    await insertAlert({
      type: "USDA_RELEASE",
      commodity: "ALL",
      title: `${release.report_type === "WASDE" ? "WASDE" : "Crop Progress"} Releases Today`,
      body: `USDA ${release.report_type === "WASDE" ? "WASDE" : "Crop Progress"} report scheduled for ${release.release_date}.`,
      severity: "MEDIUM",
      metadata: { key, reportType: release.report_type, releaseDate: release.release_date },
    });
  }
}

async function scanCustomAlertRules() {
  const [rules] = await pool.query("SELECT * FROM custom_alert_rules WHERE is_active = TRUE");
  for (const rule of rules) {
    const symbol = COMMODITY_SYMBOL[rule.commodity];
    if (!symbol) continue;

    if (rule.rule_type === "BASIS_THRESHOLD") {
      if (!rule.state) continue;
      const snap = await usdaBasis.latest(rule.state, symbol);
      if (!snap) continue;
      const hit =
        rule.comparison === "BELOW"
          ? snap.basis <= rule.threshold_value
          : snap.basis >= rule.threshold_value;
      if (!hit) continue;

      const dateKey = snap.snapshot_date.toISOString().slice(0, 10);
      const key = `custom:${rule.id}:${dateKey}`;
      if (await alreadyAlerted("BASIS_ANOMALY", rule.commodity, key, rule.user_id)) continue;

      await insertAlert({
        type: "BASIS_ANOMALY",
        commodity: rule.commodity,
        title: `${rule.commodity} Basis Alert — ${rule.state}`,
        body:
          `Your alert triggered: basis is ${snap.basis.toFixed(1)}¢, ` +
          `${rule.comparison.toLowerCase()} your threshold of ${rule.threshold_value}¢.`,
        severity: "HIGH",
        metadata: { key, ruleId: rule.id, basis: snap.basis, threshold: rule.threshold_value },
        userId: rule.user_id,
      });
    } else if (rule.rule_type === "FUTURES_MOVE_THRESHOLD") {
      const [rows] = await pool.query("SELECT * FROM futures_prices WHERE symbol = ?", [symbol]);
      const row = rows[0];
      if (!row) continue;

      const hit =
        rule.comparison === "ABOVE"
          ? row.change_pct >= rule.threshold_value
          : row.change_pct <= -Math.abs(rule.threshold_value);
      if (!hit) continue;

      const dateKey = new Date(row.updated_at).toISOString().slice(0, 10);
      const key = `custom:${rule.id}:${dateKey}`;
      if (await alreadyAlerted("FUTURES_MOVE", rule.commodity, key, rule.user_id)) continue;

      await insertAlert({
        type: "FUTURES_MOVE",
        commodity: rule.commodity,
        title: `${row.name} Alert — ${rule.comparison === "ABOVE" ? "Up" : "Down"} ${Math.abs(rule.threshold_value)}%+`,
        body: `Your alert triggered: ${row.name} moved ${row.change_pct.toFixed(2)}% to ${row.price.toFixed(2)}.`,
        severity: "HIGH",
        metadata: { key, ruleId: rule.id, changePct: row.change_pct, priceAtAlert: row.price },
        userId: rule.user_id,
      });
    }
  }
}

async function scanPriceTargets() {
  const [targets] = await pool.query("SELECT * FROM price_targets WHERE is_active = TRUE");
  for (const target of targets) {
    const [rows] = await pool.query("SELECT * FROM futures_prices WHERE symbol = ?", [
      target.symbol,
    ]);
    const row = rows[0];
    if (!row) continue;

    const hit =
      target.direction === "ABOVE"
        ? row.price >= target.target_price
        : row.price <= target.target_price;
    if (!hit) continue;

    await insertAlert({
      type: "FUTURES_MOVE",
      commodity: SYMBOL_COMMODITY[target.symbol] ?? "ALL",
      title: `Price Target Hit — ${row.name}`,
      body:
        `${row.name} reached your target: ${row.price.toFixed(2)} ` +
        `(${target.direction.toLowerCase()} ${target.target_price}).`,
      severity: "HIGH",
      metadata: { key: `target:${target.id}`, targetId: target.id, price: row.price },
      userId: target.user_id,
    });

    await pool.query(
      "UPDATE price_targets SET is_active = FALSE, triggered_at = NOW() WHERE id = ?",
      [target.id]
    );
  }
}

export async function ensureFresh() {
  if (Date.now() - lastScanAt < SCAN_INTERVAL_MS) return;
  lastScanAt = Date.now();
  await scanBasisAnomalies();
  await scanFuturesMoves();
  await scanUsdaReleases();
  await scanCustomAlertRules();
  await scanPriceTargets();
}
