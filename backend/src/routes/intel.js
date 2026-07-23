import { Router } from "express";

import { asyncHandler } from "../asyncHandler.js";
import * as cotData from "../cotData.js";
import * as seasonal from "../seasonal.js";
import * as weatherImpact from "../weatherImpact.js";
import * as droughtMonitor from "../droughtMonitor.js";
import * as cropTour from "../cropTour.js";
import * as crushSpread from "../crushSpread.js";
import * as forwardCurve from "../forwardCurve.js";
import * as ethanolMargin from "../ethanolMargin.js";
import * as dollarIndex from "../dollarIndex.js";
import * as eiaInventory from "../eiaInventory.js";
import * as ngStorage from "../ngStorage.js";
import * as crackSpread from "../crackSpread.js";
import * as correlationMatrix from "../correlationMatrix.js";
import * as proactiveInsights from "../proactiveInsights.js";
import { PROXY_SYMBOLS } from "../marketData.js";

export const router = Router();

// Weekly CFTC COT positioning with CullyAI translation.
router.get("/intel/cot", asyncHandler(async (req, res) => {
  res.json(cotData.serialize(await cotData.ensureLatest()));
}));

// 5y/10y seasonal pattern (indexed weekly averages) + current year.
router.get("/intel/seasonal/:symbol", asyncHandler(async (req, res) => {
  const symbol = req.params.symbol.toUpperCase();
  if (!(symbol in PROXY_SYMBOLS)) {
    return res.status(404).json({ detail: `Unknown symbol ${symbol}` });
  }
  res.json(await seasonal.seasonalPattern(symbol));
}));

// NOAA Corn Belt precipitation anomalies as market implications.
router.get("/intel/weather", asyncHandler(async (req, res) => {
  res.json(weatherImpact.serialize(await weatherImpact.ensureToday()));
}));

// US Drought Monitor D0–D4 severity, real weekly state statistics.
router.get("/intel/drought", asyncHandler(async (req, res) => {
  await droughtMonitor.ensureFresh();
  res.json(await droughtMonitor.latestAll());
}));

// Pro Farmer Crop Tour vs USDA NASS yield comparison.
router.get("/intel/crop-tour", asyncHandler(async (req, res) => {
  const results = await cropTour.ensureAll();
  res.json(results.map(cropTour.serialize));
}));

// Soybean board crush computed from front-month ZS/ZL/ZM.
router.get("/intel/crush", asyncHandler(async (req, res) => {
  res.json(await crushSpread.current());
}));

// Forward curve across upcoming contract months — carry vs inversion.
router.get("/intel/forward-curve/:symbol", asyncHandler(async (req, res) => {
  const symbol = req.params.symbol.toUpperCase();
  if (!(symbol in PROXY_SYMBOLS)) {
    return res.status(404).json({ detail: `Unknown symbol ${symbol}` });
  }
  res.json(await forwardCurve.curve(symbol));
}));

// Near/far calendar-spread history for the same symbol.
router.get("/intel/calendar-spread/:symbol", asyncHandler(async (req, res) => {
  const symbol = req.params.symbol.toUpperCase();
  if (!(symbol in PROXY_SYMBOLS)) {
    return res.status(404).json({ detail: `Unknown symbol ${symbol}` });
  }
  const days = Number(req.query.days || 180);
  res.json(await forwardCurve.calendarSpreadHistory(symbol, days));
}));

// Corn-to-ethanol board margin computed from front-month EH=F/ZC=F.
router.get("/intel/ethanol-margin", asyncHandler(async (req, res) => {
  res.json(await ethanolMargin.current());
}));

// US Dollar Index proxy vs corn futures, with a real trailing correlation.
router.get("/intel/dollar-index", asyncHandler(async (req, res) => {
  res.json(await dollarIndex.snapshot());
}));

// EIA Weekly Petroleum Status Report — US crude/gasoline/distillate
// stocks and week-over-week change, published Wednesdays ~10:30 ET.
router.get("/intel/eia-inventory", asyncHandler(async (req, res) => {
  await eiaInventory.ensureFresh();
  const latest = await eiaInventory.latest();
  if (!latest) {
    return res.status(503).json({ detail: "EIA inventory data not available yet" });
  }
  const weeks = Number(req.query.weeks || 12);
  const rows = await eiaInventory.history(weeks);
  res.json({
    latest: eiaInventory.serialize(latest),
    history: rows.map(eiaInventory.serialize),
  });
}));

// EIA Weekly Natural Gas Storage Report — US working gas in storage vs
// last year and the 5-year average, published Thursdays ~10:30 ET.
router.get("/intel/ng-storage", asyncHandler(async (req, res) => {
  await ngStorage.ensureFresh();
  const latest = await ngStorage.latest();
  if (!latest) {
    return res.status(503).json({ detail: "Natural gas storage data not available yet" });
  }
  const weeks = Number(req.query.weeks || 12);
  const rows = await ngStorage.history(weeks);
  res.json({
    latest: ngStorage.serialize(latest),
    history: rows.map(ngStorage.serialize),
  });
}));

// 3:2:1 crack spread (oil refining margin) from real CL/RB/HO closes.
router.get("/intel/crack-spread", asyncHandler(async (req, res) => {
  res.json(await crackSpread.current());
}));

// CullyAI's 3 unprompted daily insights (corn/soy ratio percentile,
// yield-curve trend, NG storage vs 5y avg), generated once per day.
router.get("/intel/insights", asyncHandler(async (req, res) => {
  res.json(await proactiveInsights.today());
}));
