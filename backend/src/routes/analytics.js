import { Router } from "express";

import { asyncHandler } from "../asyncHandler.js";
import * as intermarketAnalysis from "../intermarketAnalysis.js";
import * as volatilityMonitor from "../volatilityMonitor.js";
import * as relativeValueScreener from "../relativeValueScreener.js";
import * as spreadTerminal from "../spreadTerminal.js";

export const router = Router();

// Rolling cross-correlation with lag 1-10 days across grains/dollar/crude/NG.
router.get("/analytics/intermarket", asyncHandler(async (req, res) => {
  res.json(await intermarketAnalysis.snapshot());
}));

// Realized volatility (annualized) + its 1y percentile per grain.
router.get("/analytics/volatility", asyncHandler(async (req, res) => {
  res.json(await volatilityMonitor.snapshot());
}));

// 52w high/low, seasonal deviation, COT percentile, basis percentile.
router.get("/analytics/relative-value", asyncHandler(async (req, res) => {
  res.json(await relativeValueScreener.snapshot());
}));

// Corn-Wheat, Soy-Corn ratio, WTI-Brent, Soybean Crush.
router.get("/analytics/spreads", asyncHandler(async (req, res) => {
  res.json(await spreadTerminal.snapshot());
}));
