/**
 * Real Corn Belt precipitation anomalies via NOAA NCEI's Climate at a
 * Glance statewide time-series JSON (free, no API key), translated into
 * grain-market implications by Claude and cached per day in
 * weather_impacts.
 *
 * NCEI publishes statewide monthly precipitation with anomalies vs the
 * 1991–2020 normal; we pull the trailing 1-month and 3-month scales for
 * the core Corn Belt states and compute % departure from normal.
 */
import { pool } from "./db.js";
import { complete } from "./anthropicClient.js";

export class WeatherError extends Error {}

// NCEI statewide time-series state codes.
const CORN_BELT_STATES = [
  { code: 13, state: "IA", name: "Iowa" },
  { code: 11, state: "IL", name: "Illinois" },
  { code: 25, state: "NE", name: "Nebraska" },
  { code: 12, state: "IN", name: "Indiana" },
  { code: 21, state: "MN", name: "Minnesota" },
  { code: 14, state: "KS", name: "Kansas" },
];

const NCEI_BASE =
  "https://www.ncei.noaa.gov/access/monitoring/climate-at-a-glance/statewide/time-series";

/** Latest available point for a state at a given trailing scale (months). */
async function fetchPrecipAnomaly(stateCode, scaleMonths) {
  const year = new Date().getUTCFullYear();
  const url =
    `${NCEI_BASE}/${stateCode}/pcp/${scaleMonths}/12/${year - 1}-${year}.json` +
    `?base_prd=true&begbaseyear=1991&endbaseyear=2020`;

  const resp = await fetch(url, {
    headers: { accept: "application/json" },
    signal: AbortSignal.timeout(20000),
  });
  if (!resp.ok) throw new WeatherError(`NCEI HTTP ${resp.status}`);
  const json = await resp.json();
  const entries = Object.entries(json.data ?? {}).sort(([a], [b]) =>
    a < b ? -1 : 1
  );
  if (entries.length === 0) throw new WeatherError("NCEI returned no data");

  const [period, point] = entries[entries.length - 1];
  const value = Number(point.value);
  const anomaly = Number(point.anomaly);
  const normal = value - anomaly;
  return {
    period, // YYYYMM of the trailing window's end
    inches: value,
    normalInches: Number(normal.toFixed(2)),
    departurePct: normal > 0 ? Number(((anomaly / normal) * 100).toFixed(1)) : 0,
  };
}

function severityOf(departurePct) {
  const d = Math.abs(departurePct);
  if (d >= 40) return "HIGH";
  if (d >= 20) return "MEDIUM";
  return "LOW";
}

async function buildStates() {
  const results = await Promise.all(
    CORN_BELT_STATES.map(async ({ code, state, name }) => {
      try {
        const [oneMonth, threeMonth] = await Promise.all([
          fetchPrecipAnomaly(code, 1),
          fetchPrecipAnomaly(code, 3),
        ]);
        return {
          state,
          name,
          period: threeMonth.period,
          precip_1m: oneMonth,
          precip_3m: threeMonth,
          severity: severityOf(threeMonth.departurePct),
        };
      } catch (err) {
        console.error(`weather fetch failed for ${state}:`, err);
        return null;
      }
    })
  );
  return results.filter((r) => r !== null);
}

async function analyzeWithClaude(states) {
  const system =
    "You are CullyAI translating Corn Belt weather anomalies into grain-market " +
    "implications for basis traders — not a weather report. Given real NOAA statewide " +
    "precipitation departures from the 1991-2020 normal, respond with STRICT JSON only " +
    'matching exactly this shape: {"headline": string, "summary": string, ' +
    '"perState": [{"state": string, "implication": string}]}. headline is one short ' +
    "sentence naming the dominant anomaly. summary is 2-3 sentences on the market " +
    "implication (e.g. how sustained dryness historically feeds into crop condition " +
    "ratings with a 2-3 week lag, and what that means for basis/futures). implication " +
    "is one sentence per state citing its real departure number. Never give financial " +
    "advice — describe historical relationships and what the data shows only.";

  const text = await complete({
    system,
    messages: [
      {
        role: "user",
        content:
          "Corn Belt precipitation departures vs 1991-2020 normal (1-month and " +
          "trailing 3-month windows):\n" + JSON.stringify(states),
      },
    ],
    maxTokens: 1024,
  });
  const jsonText = text.slice(text.indexOf("{"), text.lastIndexOf("}") + 1);
  const parsed = JSON.parse(jsonText);
  return {
    headline: parsed.headline ?? "",
    summary: parsed.summary ?? "",
    perState: parsed.perState ?? [],
  };
}

export async function ensureToday() {
  const day = new Date().toISOString().slice(0, 10);
  const [existing] = await pool.query(
    "SELECT * FROM weather_impacts WHERE impact_date = ?",
    [day]
  );
  if (existing[0]?.ai_json) {
    return { states: existing[0].raw_data ?? [], analysis: existing[0].ai_json };
  }

  const states = await buildStates();
  if (states.length === 0) throw new WeatherError("No NOAA state data available");

  let analysis = { headline: "", summary: "", perState: [] };
  try {
    analysis = await analyzeWithClaude(states);
  } catch (err) {
    console.error("weather Claude analysis failed:", err);
  }

  await pool.query(
    `INSERT INTO weather_impacts (impact_date, raw_data, ai_json)
     VALUES (?, ?, ?)
     ON DUPLICATE KEY UPDATE raw_data = VALUES(raw_data), ai_json = VALUES(ai_json)`,
    [day, JSON.stringify(states), JSON.stringify(analysis)]
  );
  return { states, analysis };
}

export function serialize({ states, analysis }) {
  const implications = new Map(
    (analysis.perState ?? []).map((p) => [p.state, p.implication])
  );
  return {
    headline: analysis.headline ?? "",
    summary: analysis.summary ?? "",
    states: states.map((s) => ({
      state: s.state,
      name: s.name,
      period: s.period,
      precip_1m_departure_pct: s.precip_1m.departurePct,
      precip_3m_departure_pct: s.precip_3m.departurePct,
      precip_3m_inches: s.precip_3m.inches,
      precip_3m_normal_inches: s.precip_3m.normalInches,
      severity: s.severity,
      implication: implications.get(s.state) ?? "",
    })),
  };
}
