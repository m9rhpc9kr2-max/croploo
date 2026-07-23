import { Router } from "express";

import { asyncHandler } from "../asyncHandler.js";
import * as forex from "../forex.js";
import * as crypto from "../crypto.js";
import * as yieldCurve from "../yieldCurve.js";
import * as economicIndicators from "../economicIndicators.js";
import * as earningsCalendar from "../earningsCalendar.js";
import * as economicCalendar from "../economicCalendar.js";
import * as newsTerminal from "../newsTerminal.js";
import * as sectorHeatmap from "../sectorHeatmap.js";

export const router = Router();

// Major USD pairs (EUR/USD, GBP/USD, USD/JPY, USD/CNY) — dollar strength
// feeds directly into US grain export competitiveness.
router.get("/macro/forex", asyncHandler(async (req, res) => {
  res.json(await forex.snapshot());
}));

// Top-10 crypto by market cap — a risk-off sentiment proxy.
router.get("/macro/crypto", asyncHandler(async (req, res) => {
  res.json(await crypto.snapshot());
}));

// US Treasury yield curve (3M..30Y) + 2s/10s inversion flag.
router.get("/macro/yield-curve", asyncHandler(async (req, res) => {
  res.json(await yieldCurve.snapshot());
}));

// CPI, GDP, unemployment, Fed funds rate, and other headline FRED series.
router.get("/macro/indicators", asyncHandler(async (req, res) => {
  res.json(await economicIndicators.snapshot());
}));

// Upcoming agribusiness earnings (ADM, Bunge, Tyson, etc).
router.get("/macro/earnings-calendar", asyncHandler(async (req, res) => {
  res.json(await earningsCalendar.snapshot());
}));

// Upcoming high-impact macro releases (CPI, NFP, FOMC, etc).
router.get("/macro/economic-calendar", asyncHandler(async (req, res) => {
  res.json(await economicCalendar.snapshot());
}));

// Live headline feed (Reuters/USDA/AgWeb/DTN/WSJ/FT), CullyAI-tagged as
// GRAIN/ENERGY/MACRO/OTHER. Optional ?tag= filter and ?limit=.
router.get("/macro/news", asyncHandler(async (req, res) => {
  const limit = Number(req.query.limit || 60);
  const tag = typeof req.query.tag === "string" ? req.query.tag : null;
  res.json(await newsTerminal.snapshot({ limit, tag }));
}));

// Sector-ETF performance grid (Energy/Ag/Tech/Financial/Industrial/
// Consumer Staples/Gold/Silver/Oil/Natural Gas).
router.get("/macro/sector-heatmap", asyncHandler(async (req, res) => {
  res.json(await sectorHeatmap.snapshot());
}));
