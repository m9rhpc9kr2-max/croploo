import { Router } from "express";

import { asyncHandler } from "../asyncHandler.js";
import { requireAuth } from "../requireAuth.js";
import * as eiaFreight from "../eiaFreight.js";
import * as usdaBasis from "../usdaBasis.js";
import * as grainRailCars from "../grainRailCars.js";
import * as mississippiGauges from "../mississippiGauges.js";
import { SOURCES } from "../dataSources.js";

export const router = Router();

function hasProAccess(user) {
  return user.subscription_tier === "pro" || user.subscription_tier === "desk";
}

router.get("/freight/rates", requireAuth, asyncHandler(async (req, res) => {
  if (!hasProAccess(req.user)) {
    return res.status(403).json({ detail: "Freight data requires a Pro or Desk plan" });
  }

  const regions = [...new Set(eiaFreight.CORRIDORS.map((c) => c.region))];
  await eiaFreight.ensureFresh(regions);

  const out = [];
  for (const cfg of eiaFreight.CORRIDORS) {
    const bars = await eiaFreight.latestTwo(cfg.region);
    if (bars.length === 0) continue;
    const current = eiaFreight.freightIndex(cfg, bars[0].price);
    const previous = bars.length > 1 ? eiaFreight.freightIndex(cfg, bars[1].price) : current;
    const weekChangePct = previous !== 0 ? ((current - previous) / previous) * 100 : 0;
    out.push({
      corridor: cfg.corridor,
      mode: cfg.mode,
      rate_value: current,
      unit: "¢/bu",
      week_change_pct: weekChangePct,
    });
  }
  res.json(out);
}));

router.get("/freight/rail-carloadings", requireAuth, asyncHandler(async (req, res) => {
  if (!hasProAccess(req.user)) {
    return res.status(403).json({ detail: "Freight data requires a Pro or Desk plan" });
  }

  const state = String(req.query.state || "IL").toUpperCase();
  const weeks = Math.min(Number(req.query.weeks) || 26, 104);

  await grainRailCars.ensureFresh([state]);
  const rows = await grainRailCars.history(state, weeks);

  res.json({
    state,
    source: SOURCES.USDA_AMS_RAIL.label,
    history: rows.map((r) => ({
      week: r.week_date.toISOString().slice(0, 10),
      total_cars: r.total_cars,
      shuttle_cars: r.shuttle_cars,
    })),
  });
}));

router.get("/freight/river-gauges", requireAuth, asyncHandler(async (req, res) => {
  if (!hasProAccess(req.user)) {
    return res.status(403).json({ detail: "Freight data requires a Pro or Desk plan" });
  }

  const lids = mississippiGauges.GAUGES.map((g) => g.lid);
  await mississippiGauges.ensureFresh(lids);

  const out = [];
  for (const g of mississippiGauges.GAUGES) {
    const rows = await mississippiGauges.history(g.lid, 30);
    out.push({
      lid: g.lid,
      name: g.name,
      state: g.state,
      lat: g.lat,
      lng: g.lng,
      source: SOURCES.NOAA_NWPS.label,
      history: rows.map((r) => ({
        date: r.reading_date.toISOString().slice(0, 10),
        stage_ft: Number(r.stage_ft),
        flow_kcfs: Number(r.flow_kcfs),
      })),
    });
  }
  res.json(out);
}));

router.get("/freight/correlation", requireAuth, asyncHandler(async (req, res) => {
  if (!hasProAccess(req.user)) {
    return res.status(403).json({ detail: "Freight data requires a Pro or Desk plan" });
  }

  const corridorName = String(req.query.corridor || "");
  const cfg = eiaFreight.CORRIDORS.find((c) => c.corridor === corridorName);
  if (!cfg) {
    return res.status(404).json({ detail: `Unknown corridor ${corridorName}` });
  }

  const days = Number(req.query.days || 180);
  await eiaFreight.ensureFresh([cfg.region]);
  await usdaBasis.ensureFresh([cfg.state], ["ZC"]);

  const dieselBars = await eiaFreight.history(cfg.region, days);
  const basisBars = await usdaBasis.history(cfg.state, "ZC", days);

  const out = dieselBars.map((d) => {
    const dTime = new Date(d.bar_date).getTime();
    let closest = null;
    let closestDiff = Infinity;
    for (const b of basisBars) {
      const diff = Math.abs(new Date(b.snapshot_date).getTime() - dTime);
      if (diff < closestDiff) {
        closestDiff = diff;
        closest = b;
      }
    }
    return {
      date: d.bar_date.toISOString().slice(0, 10),
      freight: eiaFreight.freightIndex(cfg, d.price),
      basis: closest ? closest.basis : 0,
    };
  });

  res.json(out);
}));
