import { Router } from "express";

import { asyncHandler } from "../asyncHandler.js";
import * as usdaReports from "../usdaReports.js";
import * as usdaCalendar from "../usdaCalendar.js";
import * as wasdeSurprises from "../wasdeSurprises.js";
import * as exportSales from "../exportSales.js";
import { SOURCES } from "../dataSources.js";
import { sendCsv, toCsv } from "../csv.js";

export const router = Router();

const SOURCED_REPORT_TYPES = ["WASDE", "CROP_PROGRESS"];
const COMMODITIES = ["CORN", "WHEAT", "SOYBEANS"];

router.get("/usda/reports", asyncHandler(async (req, res) => {
  const typeFilter = req.query.type ? String(req.query.type).toUpperCase() : null;
  const types = (typeFilter ? [typeFilter] : SOURCED_REPORT_TYPES).filter((t) =>
    SOURCED_REPORT_TYPES.includes(t)
  );

  // Each report needs its own NASS fetch + Claude call, so a cold cache
  // (up to 6 combinations) is run in parallel rather than serially —
  // otherwise a fully-uncached request can take well over a minute.
  const jobs = types.flatMap((type) => COMMODITIES.map((commodity) => ({ type, commodity })));
  const results = await Promise.all(
    jobs.map(async ({ type, commodity }) => {
      try {
        return usdaReports.serialize(await usdaReports.ensureReport(type, commodity));
      } catch (err) {
        console.error(`usda report ${type}/${commodity} failed:`, err);
        return null;
      }
    })
  );
  res.json(results.filter((r) => r !== null));
}));

router.get("/usda/reports/:id/analyze", asyncHandler(async (req, res) => {
  const row = await usdaReports.reanalyze(Number(req.params.id));
  if (!row) {
    return res.status(404).json({ detail: "Report not found" });
  }
  res.json(usdaReports.serialize(row));
}));

router.get("/usda/calendar", asyncHandler(async (req, res) => {
  res.json(usdaCalendar.upcomingReleases(30));
}));

const COMMODITY_TO_SYMBOL = { CORN: "ZC", WHEAT: "ZW", SOYBEANS: "ZS" };

router.get("/usda/export-sales", asyncHandler(async (req, res) => {
  const commodity = String(req.query.commodity || "CORN").toUpperCase();
  const symbol = COMMODITY_TO_SYMBOL[commodity];
  if (!symbol) {
    return res.status(404).json({ detail: `Unknown commodity ${commodity}` });
  }

  await exportSales.ensureFresh([symbol]);
  const weeks = Math.min(Number(req.query.weeks) || 52, 104);
  const [rows, destinations] = await Promise.all([
    exportSales.history(symbol, weeks),
    exportSales.topDestinations(symbol),
  ]);

  res.json({
    commodity,
    symbol,
    source: SOURCES.USDA_FAS.label,
    history: rows.map((r) => ({
      date: r.snapshot_date.toISOString().slice(0, 10),
      marketing_year: r.marketing_year,
      weekly_exports_mt: r.weekly_exports,
      net_sales_mt: r.net_sales,
      accumulated_exports_mt: r.accumulated_exports,
      outstanding_sales_mt: r.outstanding_sales,
      total_commitments_mt: r.total_commitments,
    })),
    top_destinations: destinations.map((d) => ({
      country: d.country,
      weekly_exports_mt: d.weekly_exports,
      net_sales_mt: d.net_sales,
      outstanding_sales_mt: d.outstanding_sales,
      rank: d.rank_order,
    })),
  });
}));

router.get("/usda/wasde-surprises", asyncHandler(async (req, res) => {
  const commodity = String(req.query.commodity || "CORN").toUpperCase();
  const rows = await wasdeSurprises.history(commodity);
  const similar = await wasdeSurprises.mostSimilarToLatest(commodity);
  res.json({
    history: rows.map(wasdeSurprises.serialize),
    most_similar: similar,
  });
}));

router.get("/usda/wasde-surprises/export", asyncHandler(async (req, res) => {
  const commodity = String(req.query.commodity || "CORN").toUpperCase();
  const rows = (await wasdeSurprises.history(commodity)).map(wasdeSurprises.serialize);
  const csv = toCsv(
    rows.map((r) => ({
      release_date: r.release_date,
      commodity: r.commodity,
      metric: r.metric,
      previous_value: r.previous_value,
      current_value: r.current_value,
      surprise_pct: r.surprise_pct.toFixed(2),
      reaction_24h: r.reaction_24h ? r.reaction_24h.absolute.toFixed(2) : "",
      reaction_48h: r.reaction_48h ? r.reaction_48h.absolute.toFixed(2) : "",
      reaction_1w: r.reaction_1w ? r.reaction_1w.absolute.toFixed(2) : "",
    })),
    [
      { key: "release_date", header: "Release Date" },
      { key: "commodity", header: "Commodity" },
      { key: "metric", header: "Metric" },
      { key: "previous_value", header: "Previous" },
      { key: "current_value", header: "Current" },
      { key: "surprise_pct", header: "Surprise %" },
      { key: "reaction_24h", header: "Reaction 24h" },
      { key: "reaction_48h", header: "Reaction 48h" },
      { key: "reaction_1w", header: "Reaction 1w" },
    ]
  );
  sendCsv(res, `croploo-wasde-surprises-${commodity}.csv`, csv);
}));
