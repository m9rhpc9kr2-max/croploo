import { Router } from "express";

import { asyncHandler } from "../asyncHandler.js";
import { pool } from "../db.js";
import { requireAuth } from "../requireAuth.js";

export const router = Router();

const RULE_TYPES = ["BASIS_THRESHOLD", "FUTURES_MOVE_THRESHOLD"];
const COMPARISONS = ["BELOW", "ABOVE"];

function serialize(row) {
  return {
    id: row.id,
    rule_type: row.rule_type,
    commodity: row.commodity,
    state: row.state,
    comparison: row.comparison,
    threshold_value: row.threshold_value,
    is_active: !!row.is_active,
    created_at: row.created_at.toISOString(),
  };
}

router.get("/custom-alert-rules", requireAuth, asyncHandler(async (req, res) => {
  const [rows] = await pool.query(
    "SELECT * FROM custom_alert_rules WHERE user_id = ? ORDER BY created_at DESC",
    [req.user.id]
  );
  res.json(rows.map(serialize));
}));

router.post("/custom-alert-rules", requireAuth, asyncHandler(async (req, res) => {
  const ruleType = String(req.body?.rule_type || "").toUpperCase();
  const commodity = String(req.body?.commodity || "").toUpperCase();
  const state = req.body?.state ? String(req.body.state).toUpperCase() : null;
  const comparison = String(req.body?.comparison || "").toUpperCase();
  const thresholdValue = Number(req.body?.threshold_value);

  if (!RULE_TYPES.includes(ruleType)) {
    return res.status(400).json({ detail: `rule_type must be one of ${RULE_TYPES.join(", ")}` });
  }
  if (!COMPARISONS.includes(comparison)) {
    return res.status(400).json({ detail: `comparison must be one of ${COMPARISONS.join(", ")}` });
  }
  if (!commodity || !Number.isFinite(thresholdValue)) {
    return res.status(400).json({ detail: "commodity and threshold_value are required" });
  }
  if (ruleType === "BASIS_THRESHOLD" && !state) {
    return res.status(400).json({ detail: "state is required for BASIS_THRESHOLD rules" });
  }

  const [result] = await pool.query(
    `INSERT INTO custom_alert_rules (user_id, rule_type, commodity, state, comparison, threshold_value)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [req.user.id, ruleType, commodity, state, comparison, thresholdValue]
  );
  const [rows] = await pool.query("SELECT * FROM custom_alert_rules WHERE id = ?", [
    result.insertId,
  ]);
  res.json(serialize(rows[0]));
}));

router.delete("/custom-alert-rules/:id", requireAuth, asyncHandler(async (req, res) => {
  await pool.query("DELETE FROM custom_alert_rules WHERE id = ? AND user_id = ?", [
    req.params.id,
    req.user.id,
  ]);
  res.json({ ok: true });
}));
