import { Router } from "express";

import { asyncHandler } from "../asyncHandler.js";
import { pool } from "../db.js";
import { requireAuth } from "../requireAuth.js";
import * as portfolio from "../portfolio.js";

export const router = Router();

const COMMODITIES = ["CORN", "WHEAT", "SOYBEANS"];

router.get("/portfolio", requireAuth, asyncHandler(async (req, res) => {
  res.json(await portfolio.positionsForUser(req.user.id));
}));

router.post("/portfolio", requireAuth, asyncHandler(async (req, res) => {
  const commodity = String(req.body?.commodity || "").toUpperCase();
  const bushels = Number(req.body?.bushels);
  const storedDate = String(req.body?.stored_date || "");
  const breakEvenPrice = Number(req.body?.break_even_price);
  const state = req.body?.state ? String(req.body.state).toUpperCase() : null;

  if (!COMMODITIES.includes(commodity)) {
    return res.status(400).json({ detail: `commodity must be one of ${COMMODITIES.join(", ")}` });
  }
  if (!Number.isFinite(bushels) || bushels <= 0) {
    return res.status(400).json({ detail: "bushels must be a positive number" });
  }
  if (!Number.isFinite(breakEvenPrice)) {
    return res.status(400).json({ detail: "break_even_price is required" });
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(storedDate)) {
    return res.status(400).json({ detail: "stored_date must be YYYY-MM-DD" });
  }

  const [result] = await pool.query(
    `INSERT INTO portfolio_positions (user_id, commodity, bushels, stored_date, break_even_price, state)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [req.user.id, commodity, bushels, storedDate, breakEvenPrice, state]
  );
  res.json(await portfolio.positionById(req.user.id, result.insertId));
}));

router.delete("/portfolio/:id", requireAuth, asyncHandler(async (req, res) => {
  await pool.query("DELETE FROM portfolio_positions WHERE id = ? AND user_id = ?", [
    req.params.id,
    req.user.id,
  ]);
  res.json({ ok: true });
}));
