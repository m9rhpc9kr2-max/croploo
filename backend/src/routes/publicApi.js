import express from "express";

import { asyncHandler } from "../asyncHandler.js";
import { requireApiKey, requireApiRateLimit } from "../requireApiKey.js";
import { pool } from "../db.js";

const router = express.Router();

/**
 * GET /v1/public/futures
 * Get current futures prices.
 */
router.get(
  "/futures",
  requireApiKey,
  requireApiRateLimit,
  asyncHandler(async (req, res) => {
    const { commodity } = req.query ?? {};

    let query = `
      SELECT * FROM futures_prices 
      WHERE as_of >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
      ORDER BY as_of DESC
    `;
    const params = [];

    if (commodity) {
      query += " AND symbol = ?";
      params.push(commodity);
    }

    query += " LIMIT 100";

    const [rows] = await pool.query(query, params);
    res.json(rows);
  })
);

/**
 * GET /v1/public/basis
 * Get current basis data.
 */
router.get(
  "/basis",
  requireApiKey,
  requireApiRateLimit,
  asyncHandler(async (req, res) => {
    const { state, commodity } = req.query ?? {};

    let query = `
      SELECT b.*, e.name as elevator_name, e.city, e.state 
      FROM basis_snapshots b
      JOIN elevators e ON b.elevator_id = e.id
      WHERE b.snapshot_date >= DATE_SUB(NOW(), INTERVAL 7 DAY)
    `;
    const params = [];

    if (state) {
      query += " AND e.state = ?";
      params.push(state);
    }

    if (commodity) {
      query += " AND b.commodity = ?";
      params.push(commodity);
    }

    query += " ORDER BY b.snapshot_date DESC LIMIT 500";

    const [rows] = await pool.query(query, params);
    res.json(rows);
  })
);

/**
 * GET /v1/public/wasde
 * Get latest WASDE reports with AI analysis.
 */
router.get(
  "/wasde",
  requireApiKey,
  requireApiRateLimit,
  asyncHandler(async (req, res) => {
    const { commodity } = req.query ?? {};

    let query = `
      SELECT * FROM usda_reports 
      WHERE report_type = 'WASDE' AND ai_processed_at IS NOT NULL
    `;
    const params = [];

    if (commodity) {
      query += " AND commodity_impacts LIKE ?";
      params.push(`%${commodity}%`);
    }

    query += " ORDER BY release_date DESC LIMIT 50";

    const [rows] = await pool.query(query, params);
    res.json(rows);
  })
);

/**
 * GET /v1/public/cot
 * Get COT positioning data.
 */
router.get(
  "/cot",
  requireApiKey,
  requireApiRateLimit,
  asyncHandler(async (req, res) => {
    const { commodity } = req.query ?? {};

    let query = `
      SELECT * FROM cot_commodity_snapshots 
      WHERE report_date >= DATE_SUB(NOW(), INTERVAL 90 DAY)
    `;
    const params = [];

    if (commodity) {
      query += " AND commodity = ?";
      params.push(commodity);
    }

    query += " ORDER BY report_date DESC LIMIT 100";

    const [rows] = await pool.query(query, params);
    res.json(rows);
  })
);

/**
 * GET /v1/public/alerts
 * Get recent alerts.
 */
router.get(
  "/alerts",
  requireApiKey,
  requireApiRateLimit,
  asyncHandler(async (req, res) => {
    const { type } = req.query ?? {};

    let query = `
      SELECT * FROM alerts 
      WHERE created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
    `;
    const params = [];

    if (type) {
      query += " AND type = ?";
      params.push(type);
    }

    query += " ORDER BY created_at DESC LIMIT 200";

    const [rows] = await pool.query(query, params);
    res.json(rows);
  })
);

/**
 * GET /v1/public/energy
 * Get energy data (EIA).
 */
router.get(
  "/energy",
  requireApiKey,
  requireApiRateLimit,
  asyncHandler(async (req, res) => {
    const { series } = req.query ?? {};

    let query = `
      SELECT * FROM energy_data 
      WHERE as_of >= DATE_SUB(NOW(), INTERVAL 30 DAY)
    `;
    const params = [];

    if (series) {
      query += " AND series_id = ?";
      params.push(series);
    }

    query += " ORDER BY as_of DESC LIMIT 100";

    const [rows] = await pool.query(query, params);
    res.json(rows);
  })
);

/**
 * GET /v1/public/seasonals
 * Get seasonal patterns.
 */
router.get(
  "/seasonals",
  requireApiKey,
  requireApiRateLimit,
  asyncHandler(async (req, res) => {
    const { symbol } = req.query ?? {};

    let query = "SELECT * FROM seasonal_patterns";
    const params = [];

    if (symbol) {
      query += " WHERE symbol = ?";
      params.push(symbol);
    }

    query += " LIMIT 50";

    const [rows] = await pool.query(query, params);
    res.json(rows);
  })
);

/**
 * GET /v1/public/macro
 * Get macro indicators (FRED).
 */
router.get(
  "/macro",
  requireApiKey,
  requireApiRateLimit,
  asyncHandler(async (req, res) => {
    const { series } = req.query ?? {};

    let query = `
      SELECT * FROM fred_data 
      WHERE as_of >= DATE_SUB(NOW(), INTERVAL 90 DAY)
    `;
    const params = [];

    if (series) {
      query += " AND series_id = ?";
      params.push(series);
    }

    query += " ORDER BY as_of DESC LIMIT 200";

    const [rows] = await pool.query(query, params);
    res.json(rows);
  })
);

export { router };
