/**
 * US Treasury yield curve — 3mo/6mo/1y/2y/5y/10y/30y constant-maturity
 * yields from FRED. The 2s/10s inversion (2Y yield > 10Y yield) is the
 * most-watched recession indicator, so it's flagged explicitly and
 * explained by CullyAI whenever the curve is inverted.
 */
import * as fred from "./fredClient.js";
import { complete } from "./anthropicClient.js";

export class YieldCurveError extends Error {}

// series ID -> tenor label, in maturity order.
const TENORS = [
  ["DGS3MO", "3M"],
  ["DGS6MO", "6M"],
  ["DGS1", "1Y"],
  ["DGS2", "2Y"],
  ["DGS5", "5Y"],
  ["DGS10", "10Y"],
  ["DGS30", "30Y"],
];

const HISTORY_LIMIT = 800; // ~3y of daily observations, enough for 1y/2y-ago lookups

/** Most recent observation on or before `targetDate` (a Date). */
function closestOnOrBefore(rows, targetDate) {
  for (const row of rows) {
    if (new Date(row.obs_date) <= targetDate) return row;
  }
  return null;
}

async function curveAt(daysAgo) {
  const targetDate = new Date(Date.now() - daysAgo * 24 * 60 * 60 * 1000);
  const points = [];
  for (const [seriesId, tenor] of TENORS) {
    const rows = await fred.history(seriesId, HISTORY_LIMIT);
    const row = daysAgo === 0 ? rows[0] : closestOnOrBefore(rows, targetDate);
    if (row) points.push({ tenor, yield_pct: Number(row.value.toFixed(2)) });
  }
  return points;
}

async function analyzeWithClaude({ inverted, spread2s10s }) {
  const system =
    "You are CullyAI explaining the US Treasury yield curve and what a 2s/10s inversion " +
    "historically means for the economy and commodities. Respond with 1-3 plain sentences, " +
    "no markdown, no JSON. Never give financial advice — describe the historical pattern only.";
  const text = await complete({
    system,
    messages: [
      {
        role: "user",
        content: inverted
          ? `The 2-year Treasury yield is currently ${Math.abs(spread2s10s).toFixed(2)} points above the 10-year yield (inverted).`
          : `The yield curve is currently normal (not inverted); 10-year minus 2-year spread is ${spread2s10s.toFixed(2)} points.`,
      },
    ],
    maxTokens: 300,
  });
  return text.trim();
}

export async function snapshot() {
  const [current, oneYearAgo, twoYearsAgo] = await Promise.all([
    curveAt(0),
    curveAt(365),
    curveAt(730),
  ]);
  if (current.length === 0) throw new YieldCurveError("Not enough yield curve data cached yet");

  const y2 = current.find((p) => p.tenor === "2Y")?.yield_pct;
  const y10 = current.find((p) => p.tenor === "10Y")?.yield_pct;
  const spread2s10s = y2 != null && y10 != null ? y10 - y2 : 0;
  const inverted = spread2s10s < 0;

  let note = "";
  try {
    note = await analyzeWithClaude({ inverted, spread2s10s });
  } catch (err) {
    console.error("yield curve Claude analysis failed:", err);
  }

  return {
    date: new Date().toISOString().slice(0, 10),
    current,
    one_year_ago: oneYearAgo,
    two_years_ago: twoYearsAgo,
    spread_2s10s: Number(spread2s10s.toFixed(2)),
    inverted,
    note,
  };
}
