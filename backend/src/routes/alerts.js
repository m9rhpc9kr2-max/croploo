import { Router } from "express";

import { asyncHandler } from "../asyncHandler.js";
import { pool } from "../db.js";
import * as alertsEngine from "../alertsEngine.js";
import * as usdaBasis from "../usdaBasis.js";
import { decodeToken } from "../security.js";
import { sendCsv, toCsv } from "../csv.js";

export const router = Router();

/** Best-effort auth: returns the user id if a valid bearer token is
 * present, otherwise null — GET /alerts works both logged out (global
 * alerts only) and logged in (global + this user's personal alerts). */
function softUserId(req) {
  const header = req.headers.authorization;
  if (!header?.toLowerCase().startsWith("bearer ")) return null;
  try {
    return decodeToken(header.slice(7));
  } catch {
    return null;
  }
}

/**
 * Proves the alert's value with a real, current comparison against the
 * value it fired on — e.g. "Corn Basis Alert 15. März — 3 Wochen später
 * war Basis 12 Cent enger." Uses only data already captured in the
 * alert's own metadata plus the current live snapshot, so nothing here
 * is fabricated after the fact.
 */
async function computeOutcome(row) {
  const meta = row.metadata || {};
  if (row.type === "BASIS_ANOMALY" && meta.state && meta.symbol && typeof meta.basis === "number") {
    const current = await usdaBasis.latest(meta.state, meta.symbol);
    if (!current) return null;
    return {
      metric: "basis",
      value_at_alert: meta.basis,
      value_now: current.basis,
      change: current.basis - meta.basis,
      as_of: current.snapshot_date.toISOString().slice(0, 10),
    };
  }
  if (row.type === "FUTURES_MOVE" && meta.symbol && typeof meta.priceAtAlert === "number") {
    const [rows] = await pool.query("SELECT * FROM futures_prices WHERE symbol = ?", [meta.symbol]);
    const current = rows[0];
    if (!current) return null;
    return {
      metric: "price",
      value_at_alert: meta.priceAtAlert,
      value_now: current.price,
      change: current.price - meta.priceAtAlert,
      as_of: new Date(current.updated_at).toISOString(),
    };
  }
  return null;
}

async function serialize(row) {
  return {
    id: row.id,
    type: row.type,
    commodity: row.commodity,
    title: row.title,
    body: row.body,
    severity: row.severity,
    is_read: !!row.is_read,
    metadata: row.metadata,
    created_at: row.created_at.toISOString(),
    outcome: await computeOutcome(row),
  };
}

router.get("/alerts", asyncHandler(async (req, res) => {
  await alertsEngine.ensureFresh();

  const userId = softUserId(req);
  const conditions = [userId === null ? "user_id IS NULL" : "(user_id IS NULL OR user_id = ?)"];
  const params = userId === null ? [] : [userId];
  if (req.query.read !== undefined) {
    conditions.push("is_read = ?");
    params.push(req.query.read === "true" ? 1 : 0);
  }
  if (req.query.commodity) {
    conditions.push("commodity = ?");
    params.push(String(req.query.commodity).toUpperCase());
  }
  const where = `WHERE ${conditions.join(" AND ")}`;

  const [rows] = await pool.query(
    `SELECT * FROM alerts ${where} ORDER BY created_at DESC LIMIT 200`,
    params
  );
  res.json(await Promise.all(rows.map(serialize)));
}));

router.get("/alerts/export", asyncHandler(async (req, res) => {
  await alertsEngine.ensureFresh();
  const [rows] = await pool.query("SELECT * FROM alerts ORDER BY created_at DESC LIMIT 1000");
  const serialized = await Promise.all(rows.map(serialize));
  const csv = toCsv(
    serialized.map((a) => ({
      ...a,
      outcome_change: a.outcome ? a.outcome.change.toFixed(2) : "",
      outcome_metric: a.outcome ? a.outcome.metric : "",
    })),
    [
      { key: "created_at", header: "Triggered At" },
      { key: "type", header: "Type" },
      { key: "commodity", header: "Commodity" },
      { key: "severity", header: "Severity" },
      { key: "title", header: "Title" },
      { key: "body", header: "Body" },
      { key: "is_read", header: "Read" },
      { key: "outcome_metric", header: "Outcome Metric" },
      { key: "outcome_change", header: "Outcome Change" },
    ]
  );
  sendCsv(res, "croploo-alert-log.csv", csv);
}));

router.put("/alerts/read-all", asyncHandler(async (req, res) => {
  await pool.query("UPDATE alerts SET is_read = TRUE WHERE is_read = FALSE");
  res.json({ ok: true });
}));

router.put("/alerts/:id/read", asyncHandler(async (req, res) => {
  await pool.query("UPDATE alerts SET is_read = TRUE WHERE id = ?", [req.params.id]);
  res.json({ ok: true });
}));

// Describes alertsEngine.js's actual live scan rules — not example data,
// the real thresholds the running system enforces.
router.get("/alert-rules", asyncHandler(async (req, res) => {
  res.json([
    {
      id: 1,
      rule_type: "basis_deviation",
      description: "Basis Deviation — Any Elevator, All Commodities",
      detail: `Alert when basis deviates more than ${alertsEngine.BASIS_DEVIATION_THRESHOLD_PCT}% from its 5-year average`,
      is_active: true,
    },
    {
      id: 2,
      rule_type: "futures_move",
      description: "Futures Move — Corn, Wheat, Soybeans",
      detail: `Alert when a daily futures price change exceeds ${alertsEngine.FUTURES_MOVE_THRESHOLD_PCT}%`,
      is_active: true,
    },
    {
      id: 3,
      rule_type: "usda_release",
      description: "USDA Release — WASDE & Crop Progress",
      detail: "Alert on each scheduled WASDE and Crop Progress release date",
      is_active: true,
    },
  ]);
}));
