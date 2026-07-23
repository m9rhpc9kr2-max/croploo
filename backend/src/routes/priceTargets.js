import { Router } from "express";

import { asyncHandler } from "../asyncHandler.js";
import { pool } from "../db.js";
import { requireAuth } from "../requireAuth.js";
import { PROXY_SYMBOLS } from "../marketData.js";

export const router = Router();

const DIRECTIONS = ["ABOVE", "BELOW"];

function serialize(row) {
  return {
    id: row.id,
    symbol: row.symbol,
    target_price: row.target_price,
    direction: row.direction,
    is_active: !!row.is_active,
    triggered_at: row.triggered_at ? row.triggered_at.toISOString() : null,
    created_at: row.created_at.toISOString(),
  };
}

router.get("/price-targets", requireAuth, asyncHandler(async (req, res) => {
  const [rows] = await pool.query(
    "SELECT * FROM price_targets WHERE user_id = ? ORDER BY created_at DESC",
    [req.user.id]
  );
  res.json(rows.map(serialize));
}));

router.post("/price-targets", requireAuth, asyncHandler(async (req, res) => {
  const symbol = String(req.body?.symbol || "").toUpperCase();
  const targetPrice = Number(req.body?.target_price);
  const direction = String(req.body?.direction || "").toUpperCase();

  if (!(symbol in PROXY_SYMBOLS)) {
    return res.status(400).json({ detail: `Unknown symbol ${symbol}` });
  }
  if (!DIRECTIONS.includes(direction)) {
    return res.status(400).json({ detail: `direction must be one of ${DIRECTIONS.join(", ")}` });
  }
  if (!Number.isFinite(targetPrice)) {
    return res.status(400).json({ detail: "target_price is required" });
  }

  const [result] = await pool.query(
    `INSERT INTO price_targets (user_id, symbol, target_price, direction)
     VALUES (?, ?, ?, ?)`,
    [req.user.id, symbol, targetPrice, direction]
  );
  const [rows] = await pool.query("SELECT * FROM price_targets WHERE id = ?", [
    result.insertId,
  ]);
  res.json(serialize(rows[0]));
}));

router.delete("/price-targets/:id", requireAuth, asyncHandler(async (req, res) => {
  await pool.query("DELETE FROM price_targets WHERE id = ? AND user_id = ?", [
    req.params.id,
    req.user.id,
  ]);
  res.json({ ok: true });
}));
