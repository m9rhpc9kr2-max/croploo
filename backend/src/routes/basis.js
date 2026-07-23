import { Router } from "express";

import { asyncHandler } from "../asyncHandler.js";
import { ELEVATORS } from "../elevators.js";
import * as usdaBasis from "../usdaBasis.js";
import { SOURCES } from "../dataSources.js";
import { sendCsv, toCsv } from "../csv.js";

export const router = Router();

const RANGE_DAYS = {
  "1M": 30,
  "3M": 90,
  "6M": 180,
  "1Y": 365,
  "5Y": 1825,
  ALL: 20000, // AgTransport's basis dataset starts in 2007.
};

function serializeElevator(e) {
  return { id: e.id, name: e.name, city: e.city, state: e.state, lat: e.lat, lng: e.lng };
}

// Full elevator directory, independent of whether USDA AgTransport has
// live basis data wired for that elevator's state yet — so the map can
// show every real location, not just the ones with a live price behind
// them (which the frontend renders with an explicit "no data" state
// rather than hiding the pin entirely).
router.get("/elevators", asyncHandler(async (req, res) => {
  res.json(ELEVATORS.map(serializeElevator));
}));

router.get("/basis-overview", asyncHandler(async (req, res) => {
  const symbolFilter = req.query.commodity
    ? String(req.query.commodity).toUpperCase()
    : null;
  const stateFilter = req.query.state ? String(req.query.state).toUpperCase() : null;
  const symbols = symbolFilter ? [symbolFilter] : Object.keys(usdaBasis.SYMBOL_NAMES);
  const states = [...new Set(ELEVATORS.map((e) => e.state))];

  await usdaBasis.ensureFresh(states, symbols);

  const bySymbolState = new Map();
  for (const state of states) {
    for (const symbol of symbols) {
      const [snap, avg] = await Promise.all([
        usdaBasis.latest(state, symbol),
        usdaBasis.avg5yr(state, symbol),
      ]);
      bySymbolState.set(`${state}|${symbol}`, { snap, avg });
    }
  }

  const out = [];
  for (const elevator of ELEVATORS) {
    if (stateFilter && elevator.state !== stateFilter) continue;
    for (const symbol of symbols) {
      const { snap, avg } = bySymbolState.get(`${elevator.state}|${symbol}`) ?? {};
      if (!snap) continue;
      const avg5yr = avg ?? snap.basis;
      const deviationFromAvg = snap.basis - avg5yr;
      const deviationPct = avg5yr !== 0 ? (deviationFromAvg / Math.abs(avg5yr)) * 100 : 0;
      out.push({
        elevator: serializeElevator(elevator),
        commodity: { symbol, name: usdaBasis.SYMBOL_NAMES[symbol] },
        basis_value: snap.basis,
        cash_price: snap.cash_price,
        futures_price: snap.futures_price,
        avg_5yr: avg5yr,
        deviation_from_avg: deviationFromAvg,
        deviation_pct: deviationPct,
        snapshot_date: snap.snapshot_date.toISOString().slice(0, 10),
        source: SOURCES.USDA_AMS.label,
        as_of: snap.snapshot_date.toISOString().slice(0, 10),
      });
    }
  }
  res.json(out);
}));

router.get("/ticker", asyncHandler(async (req, res) => {
  const states = [...new Set(ELEVATORS.map((e) => e.state))];
  const out = [];
  for (const state of states) {
    for (const symbol of Object.keys(usdaBasis.SYMBOL_NAMES)) {
      const snap = await usdaBasis.latest(state, symbol);
      if (!snap) continue;
      const avg = await usdaBasis.avg5yr(state, symbol);
      const deviationPct = avg && avg !== 0 ? ((snap.basis - avg) / Math.abs(avg)) * 100 : 0;
      out.push({
        label: `${state} ${usdaBasis.SYMBOL_NAMES[symbol].toUpperCase()}`,
        basis: snap.basis,
        extreme: Math.abs(deviationPct) > 15,
      });
    }
  }
  res.json(out);
}));

router.get("/basis-history", asyncHandler(async (req, res) => {
  const elevatorId = Number(req.query.elevatorId);
  const symbol = String(req.query.commodity || "").toUpperCase();
  const elevator = ELEVATORS.find((e) => e.id === elevatorId);
  if (!elevator) {
    return res.status(404).json({ detail: `Unknown elevator ${elevatorId}` });
  }
  if (!usdaBasis.SYMBOL_NAMES[symbol]) {
    return res.status(404).json({ detail: `Unknown commodity ${symbol}` });
  }

  await usdaBasis.ensureFresh([elevator.state], [symbol]);

  const days = RANGE_DAYS[String(req.query.range || "1Y").toUpperCase()] ?? 365;
  const avg = (await usdaBasis.avg5yr(elevator.state, symbol)) ?? 0;
  const rows = await usdaBasis.history(elevator.state, symbol, days);

  res.json(
    rows.map((r) => ({
      date: r.snapshot_date.toISOString().slice(0, 10),
      basis: r.basis,
      avg_5yr: avg,
      source: SOURCES.USDA_AMS.label,
    }))
  );
}));

router.get("/basis-history/export", asyncHandler(async (req, res) => {
  const elevatorId = Number(req.query.elevatorId);
  const symbol = String(req.query.commodity || "").toUpperCase();
  const elevator = ELEVATORS.find((e) => e.id === elevatorId);
  if (!elevator) {
    return res.status(404).json({ detail: `Unknown elevator ${elevatorId}` });
  }
  if (!usdaBasis.SYMBOL_NAMES[symbol]) {
    return res.status(404).json({ detail: `Unknown commodity ${symbol}` });
  }

  await usdaBasis.ensureFresh([elevator.state], [symbol]);
  const days = RANGE_DAYS[String(req.query.range || "1Y").toUpperCase()] ?? 365;
  const avg = (await usdaBasis.avg5yr(elevator.state, symbol)) ?? 0;
  const rows = await usdaBasis.history(elevator.state, symbol, days);

  const csv = toCsv(
    rows.map((r) => ({
      date: r.snapshot_date.toISOString().slice(0, 10),
      basis_cents: r.basis,
      avg_5yr_cents: avg,
      elevator: elevator.name,
      state: elevator.state,
      commodity: usdaBasis.SYMBOL_NAMES[symbol],
    })),
    [
      { key: "date", header: "Date" },
      { key: "commodity", header: "Commodity" },
      { key: "elevator", header: "Elevator" },
      { key: "state", header: "State" },
      { key: "basis_cents", header: "Basis (c/bu)" },
      { key: "avg_5yr_cents", header: "5yr Avg (c/bu)" },
    ]
  );
  sendCsv(res, `croploo-basis-${elevator.name.replace(/\s+/g, "_")}-${symbol}.csv`, csv);
}));
