/**
 * Custom Dashboards — named, per-user saved widget layouts. A "layout"
 * is an ordered list of widget IDs (strings the Flutter app already
 * knows how to render, e.g. "futures", "daily_brief", "insights") —
 * not a pixel-perfect drag-drop grid, which would need a canvas/grid
 * engine this Flutter desktop app doesn't have yet.
 */
import { Router } from "express";

import { asyncHandler } from "../asyncHandler.js";
import { pool } from "../db.js";
import { requireAuth } from "../requireAuth.js";

export const router = Router();

router.get("/dashboards", requireAuth, asyncHandler(async (req, res) => {
  const [rows] = await pool.query(
    "SELECT id, name, widget_ids, created_at FROM custom_dashboards WHERE user_id = ? ORDER BY created_at ASC",
    [req.user.id]
  );
  res.json(rows.map((r) => ({
    id: r.id,
    name: r.name,
    widget_ids: r.widget_ids,
    created_at: r.created_at.toISOString(),
  })));
}));

router.post("/dashboards", requireAuth, asyncHandler(async (req, res) => {
  const { name, widget_ids } = req.body ?? {};
  if (!name || !Array.isArray(widget_ids)) {
    return res.status(400).json({ detail: "name and widget_ids (array) are required" });
  }
  const [result] = await pool.query(
    `INSERT INTO custom_dashboards (user_id, name, widget_ids) VALUES (?, ?, ?)
     ON DUPLICATE KEY UPDATE widget_ids = VALUES(widget_ids)`,
    [req.user.id, name, JSON.stringify(widget_ids)]
  );
  res.json({ id: result.insertId, name, widget_ids });
}));

router.delete("/dashboards/:id", requireAuth, asyncHandler(async (req, res) => {
  await pool.query("DELETE FROM custom_dashboards WHERE id = ? AND user_id = ?", [
    req.params.id,
    req.user.id,
  ]);
  res.json({ status: "deleted" });
}));
