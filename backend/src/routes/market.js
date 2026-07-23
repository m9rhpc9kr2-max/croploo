import { Router } from "express";

import { asyncHandler } from "../asyncHandler.js";
import { pool } from "../db.js";
import * as marketData from "../marketData.js";
import * as intradayFutures from "../intradayFutures.js";
import { SOURCES } from "../dataSources.js";

export const router = Router();

function serializeFutures(row) {
  return {
    symbol: row.symbol,
    name: row.name,
    contract_month: row.contract_month,
    price: row.price,
    change: row.change,
    change_pct: row.change_pct,
    source: SOURCES.ALPHA_VANTAGE.label,
    as_of: new Date(row.updated_at).toISOString(),
  };
}

router.get("/futures-prices", asyncHandler(async (req, res) => {
  await marketData.ensureFresh();
  const [rows] = await pool.query("SELECT * FROM futures_prices");
  res.json(rows.map(serializeFutures));
}));

router.get("/futures-history/:symbol", asyncHandler(async (req, res) => {
  const symbol = req.params.symbol.toUpperCase();
  if (!(symbol in marketData.PROXY_SYMBOLS)) {
    return res.status(404).json({ detail: `Unknown symbol ${symbol}` });
  }
  await marketData.ensureFresh();
  const days = Number(req.query.days || 180);
  const bars = await marketData.history(symbol, days);
  res.json(
    bars.map((b) => ({
      date: b.bar_date.toISOString().slice(0, 10),
      close: b.close,
    }))
  );
}));

// Real 15-minute intraday bars (today only) from Yahoo Finance —
// separate from the Alpha Vantage-backed daily-close history above,
// since Alpha Vantage's free tier can't sustain 15-minute polling.
router.get("/futures-intraday/:symbol", asyncHandler(async (req, res) => {
  const symbol = req.params.symbol.toUpperCase();
  if (!["ZC", "ZW", "ZS"].includes(symbol)) {
    return res.status(404).json({ detail: `Unknown symbol ${symbol}` });
  }
  res.json(await intradayFutures.snapshot(symbol));
}));
