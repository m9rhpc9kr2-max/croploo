import { Router } from "express";

import { asyncHandler } from "../asyncHandler.js";
import { pool } from "../db.js";
import { requireAuth } from "../requireAuth.js";

export const router = Router();

function serialize(row) {
  return {
    id: row.id,
    commodity: row.commodity,
    state: row.state,
    created_at: row.created_at.toISOString(),
  };
}

router.get("/watchlist", requireAuth, asyncHandler(async (req, res) => {
  const [rows] = await pool.query(
    "SELECT * FROM watchlist_items WHERE user_id = ? ORDER BY created_at ASC",
    [req.user.id]
  );
  res.json(rows.map(serialize));
}));

router.post("/watchlist", requireAuth, asyncHandler(async (req, res) => {
  const commodity = String(req.body?.commodity || "").toUpperCase();
  const state = String(req.body?.state || "").toUpperCase();
  if (!commodity || !state) {
    return res.status(400).json({ detail: "commodity and state are required" });
  }

  await pool.query(
    `INSERT INTO watchlist_items (user_id, commodity, state)
     VALUES (?, ?, ?)
     ON DUPLICATE KEY UPDATE commodity = VALUES(commodity)`,
    [req.user.id, commodity, state]
  );
  const [rows] = await pool.query(
    "SELECT * FROM watchlist_items WHERE user_id = ? AND commodity = ? AND state = ?",
    [req.user.id, commodity, state]
  );
  res.json(serialize(rows[0]));
}));

router.delete("/watchlist/:id", requireAuth, asyncHandler(async (req, res) => {
  await pool.query("DELETE FROM watchlist_items WHERE id = ? AND user_id = ?", [
    req.params.id,
    req.user.id,
  ]);
  res.json({ ok: true });
}));
