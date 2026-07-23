/**
 * Real USDA crop statistics via the NASS Quick Stats API
 * (quickstats.nass.usda.gov). NASS doesn't publish WASDE itself (that's
 * WAOB, PDF-only, no API) — instead this pulls the same underlying
 * production/yield/stocks survey data WASDE is built from, and real
 * weekly Crop Progress/Condition survey data.
 */
import * as config from "./config.js";

export class NassError extends Error {}

const NASS_BASE_URL = "https://quickstats.nass.usda.gov/api/api_GET/";

// Representative state per commodity for weekly progress/condition
// data, matching the elevator network's concentration (see
// elevators.js): IL for corn/soy, KS for winter wheat.
export const PROGRESS_STATE = { CORN: "IL", SOYBEANS: "IL", WHEAT: "KS" };

function parseValue(raw) {
  const n = Number(String(raw).replace(/,/g, ""));
  return Number.isFinite(n) ? n : null;
}

async function query(params) {
  if (!config.NASS_API_KEY) {
    throw new NassError("NASS_API_KEY is not configured");
  }
  const url = new URL(NASS_BASE_URL);
  url.searchParams.set("key", config.NASS_API_KEY);
  url.searchParams.set("format", "JSON");
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined) url.searchParams.set(k, v);
  }

  const resp = await fetch(url, { signal: AbortSignal.timeout(20000) });
  // NASS returns 400 for filter combinations with no matching series —
  // that's a legitimate "no data", not a hard failure.
  if (resp.status === 400) return [];
  if (!resp.ok) {
    throw new NassError(`NASS API HTTP ${resp.status}`);
  }
  const json = await resp.json();
  return json.data ?? [];
}

function toPoints(rows) {
  return rows
    .map((r) => ({
      value: parseValue(r.Value),
      shortDesc: r.short_desc,
      period: r.week_ending || r.reference_period_desc,
      year: r.year,
    }))
    .filter((p) => p.value !== null)
    .sort((a, b) => `${b.year}${b.period}`.localeCompare(`${a.year}${a.period}`));
}

/**
 * Latest two annual national points for a BU-based series. NASS returns
 * separate on-farm/off-farm/total breakdowns for the same statisticcat
 * (e.g. stocks) — group by short_desc and keep only the plain
 * commodity-total series, not a farm-storage subset.
 */
async function nationalSeries(commodity, statisticcat, unit) {
  const rows = await query({
    commodity_desc: commodity,
    statisticcat_desc: statisticcat,
    unit_desc: unit,
    agg_level_desc: "NATIONAL",
    class_desc: "ALL CLASSES",
  });

  const totalOnly = toPoints(rows).filter(
    (p) => !p.shortDesc.includes("ON FARM") && !p.shortDesc.includes("OFF FARM")
  );
  const byMetric = new Map();
  for (const p of totalOnly) {
    const list = byMetric.get(p.shortDesc) ?? [];
    list.push(p);
    byMetric.set(p.shortDesc, list);
  }
  const longestSeries = [...byMetric.values()].sort((a, b) => b.length - a.length)[0] ?? [];
  return longestSeries.slice(0, 2);
}

/** Most recent weekly readings for a commodity's representative state,
 * grouped by metric (planted/silking/dented/condition/...), two most
 * recent points per metric so each can show a week-over-week change. */
async function stateWeeklySeries(commodity, statisticcat) {
  const state = PROGRESS_STATE[commodity];
  const currentYear = new Date().getFullYear();

  let rows = await query({
    commodity_desc: commodity,
    statisticcat_desc: statisticcat,
    agg_level_desc: "STATE",
    state_alpha: state,
    class_desc: "ALL CLASSES",
    freq_desc: "WEEKLY",
    year: String(currentYear),
  });
  if (rows.length === 0) {
    // Off-season (e.g. before planting starts) — fall back to last year.
    rows = await query({
      commodity_desc: commodity,
      statisticcat_desc: statisticcat,
      agg_level_desc: "STATE",
      state_alpha: state,
      class_desc: "ALL CLASSES",
      freq_desc: "WEEKLY",
      year: String(currentYear - 1),
    });
  }

  const byMetric = new Map();
  for (const p of toPoints(rows)) {
    const list = byMetric.get(p.shortDesc) ?? [];
    if (list.length < 2) list.push(p);
    byMetric.set(p.shortDesc, list);
  }
  return [...byMetric.values()].flat();
}

export async function wasdeData(commodity) {
  const [production, yieldPoints, stocks] = await Promise.all([
    nationalSeries(commodity, "PRODUCTION", "BU"),
    nationalSeries(commodity, "YIELD", "BU / ACRE"),
    nationalSeries(commodity, "STOCKS", "BU"),
  ]);
  return { production, yield: yieldPoints, stocks };
}

/**
 * National yield (BU/ACRE) by crop year for the crop-tour comparison.
 * NASS carries both the annual (final) estimate and the monthly
 * in-season forecasts; per year we keep the final where available,
 * otherwise the latest forecast — which is exactly what "USDA's current
 * number" means during tour season.
 */
export async function nationalYieldByYear(commodity, years = 6) {
  const currentYear = new Date().getFullYear();
  const rows = await query({
    commodity_desc: commodity,
    statisticcat_desc: "YIELD",
    unit_desc: "BU / ACRE",
    agg_level_desc: "NATIONAL",
    class_desc: "ALL CLASSES",
    year__GE: String(currentYear - years),
  });

  const byYear = new Map();
  for (const p of toPoints(rows)) {
    const year = Number(p.year);
    const isFinal = String(p.period).toUpperCase() === "YEAR";
    const existing = byYear.get(year);
    if (!existing || (isFinal && !existing.isFinal)) {
      byYear.set(year, { year, value: p.value, isFinal, period: p.period });
    }
  }
  return [...byYear.values()].sort((a, b) => b.year - a.year);
}

export async function cropProgressData(commodity) {
  const [progress, condition] = await Promise.all([
    stateWeeklySeries(commodity, "PROGRESS"),
    stateWeeklySeries(commodity, "CONDITION"),
  ]);
  return { state: PROGRESS_STATE[commodity], progress, condition };
}
