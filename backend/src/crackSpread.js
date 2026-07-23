/**
 * 3:2:1 Crack Spread — the refining margin implied by CME futures: how
 * profitable it currently is to turn crude oil into gasoline and
 * heating oil. A wide spread means refiners are pulling more crude
 * through the refinery (bullish for crude demand); a narrow/negative
 * spread means refining margins are squeezed.
 *
 *   crack ($/bbl) = ((2 × Gasoline($/gal) + 1 × Heating Oil($/gal)) × 42 − 3 × Crude($/bbl)) / 3
 *
 * (RB=F/HO=F are quoted in $/gallon, CL=F in $/barrel — the ×42
 * converts gallons to the 42-gal barrel so all three legs are in the
 * same unit before combining; the standard "3:2:1" ratio models 3
 * barrels of crude yielding 2 barrels of gasoline + 1 barrel of heating
 * oil, and the final /3 expresses the margin per barrel of crude
 * input — the number refiners and traders actually watch.)
 *
 * Front-month CL/RB/HO daily closes come from Yahoo Finance's public
 * chart API (free, no key, already used by crushSpread.js/
 * forwardCurve.js) and are cached in crack_spread_history so the
 * endpoint keeps working if Yahoo hiccups.
 */
import { pool } from "./db.js";
import { complete } from "./anthropicClient.js";

export class CrackSpreadError extends Error {}

const YAHOO_CHART = "https://query1.finance.yahoo.com/v8/finance/chart";
const LEGS = { CRUDE: "CL=F", GASOLINE: "RB=F", HEATING_OIL: "HO=F" };
const REFRESH_MINUTES = 60;
const GALLONS_PER_BARREL = 42;

// A reading more than this far from its own trailing average is
// "unusual" enough to spend a Claude call explaining — keeps most
// requests free of API cost while still surfacing genuine outliers.
const UNUSUAL_DEVIATION_PCT = 20;

async function fetchLeg(yahooSymbol) {
  const url = `${YAHOO_CHART}/${encodeURIComponent(yahooSymbol)}?range=1y&interval=1d`;
  const resp = await fetch(url, {
    headers: { "user-agent": "Mozilla/5.0 (croploo-backend)" },
    signal: AbortSignal.timeout(15000),
  });
  if (!resp.ok) throw new CrackSpreadError(`Yahoo HTTP ${resp.status} for ${yahooSymbol}`);
  const json = await resp.json();
  const result = json.chart?.result?.[0];
  const timestamps = result?.timestamp ?? [];
  const closes = result?.indicators?.quote?.[0]?.close ?? [];
  if (timestamps.length === 0) {
    throw new CrackSpreadError(`Yahoo returned no bars for ${yahooSymbol}`);
  }

  const byDate = new Map();
  for (let i = 0; i < timestamps.length; i++) {
    if (closes[i] == null) continue;
    const day = new Date(timestamps[i] * 1000).toISOString().slice(0, 10);
    byDate.set(day, closes[i]);
  }
  return byDate;
}

function computeCrack(crudeUsdBbl, gasolineUsdGal, heatingOilUsdGal) {
  const gasolineUsdBbl = gasolineUsdGal * GALLONS_PER_BARREL;
  const heatingOilUsdBbl = heatingOilUsdGal * GALLONS_PER_BARREL;
  return (2 * gasolineUsdBbl + heatingOilUsdBbl - 3 * crudeUsdBbl) / 3;
}

async function isStale() {
  const [rows] = await pool.query(
    "SELECT MAX(updated_at) AS latest FROM crack_spread_history"
  );
  if (!rows[0]?.latest) return true;
  return Date.now() - new Date(rows[0].latest).getTime() > REFRESH_MINUTES * 60_000;
}

async function analyzeWithClaude({ crack, avgPeriod, deviationPct }) {
  const system =
    "You are CullyAI explaining an unusually wide or narrow 3:2:1 crack spread (oil " +
    "refining margin) to grain/freight traders — refining economics feed into diesel and " +
    "freight costs. Given the real current crack spread vs its own trailing 1-year average, " +
    'respond with STRICT JSON only matching exactly this shape: {"headline": string, ' +
    '"direction": "BULLISH"|"BEARISH"|"NEUTRAL", "summary": string}. direction refers to ' +
    "crude oil demand/price implication (wide spread = refiners pull more crude = bullish " +
    "for crude; narrow/negative = margins squeezed = bearish for crude demand). summary is " +
    "2-3 sentences citing the real numbers. Never give financial advice, describe historical " +
    "relationships only.";

  const userContent = JSON.stringify({
    crack_spread_usd_bbl: Number(crack.toFixed(2)),
    trailing_1y_avg_usd_bbl: Number(avgPeriod.toFixed(2)),
    deviation_pct: Number(deviationPct.toFixed(1)),
  });

  const text = await complete({
    system,
    messages: [{ role: "user", content: userContent }],
    maxTokens: 512,
  });
  const jsonText = text.slice(text.indexOf("{"), text.lastIndexOf("}") + 1);
  const parsed = JSON.parse(jsonText);
  return {
    headline: parsed.headline ?? "",
    direction: parsed.direction ?? "NEUTRAL",
    summary: parsed.summary ?? "",
  };
}

async function refresh() {
  const [crude, gasoline, heatingOil] = await Promise.all(
    Object.values(LEGS).map(fetchLeg)
  );

  let latestDay = null;
  for (const [day, crudeClose] of crude) {
    const gasolineClose = gasoline.get(day);
    const heatingOilClose = heatingOil.get(day);
    if (gasolineClose == null || heatingOilClose == null) continue;
    await pool.query(
      `INSERT INTO crack_spread_history
         (bar_date, crude_close, gasoline_close, heating_oil_close, crack_spread, updated_at)
       VALUES (?, ?, ?, ?, ?, NOW())
       ON DUPLICATE KEY UPDATE
         crude_close = VALUES(crude_close), gasoline_close = VALUES(gasoline_close),
         heating_oil_close = VALUES(heating_oil_close), crack_spread = VALUES(crack_spread),
         updated_at = NOW()`,
      [day, crudeClose, gasolineClose, heatingOilClose,
        computeCrack(crudeClose, gasolineClose, heatingOilClose)]
    );
    if (!latestDay || day > latestDay) latestDay = day;
  }

  if (!latestDay) return;

  // Only spend a Claude call when today's reading is genuinely unusual
  // vs its own trailing average — most requests just show the numbers.
  const [rows] = await pool.query(
    `SELECT bar_date, crack_spread FROM crack_spread_history ORDER BY bar_date DESC LIMIT 260`
  );
  if (rows.length < 20) return;
  const avgPeriod = rows.reduce((sum, r) => sum + r.crack_spread, 0) / rows.length;
  const latest = rows[0];
  const deviationPct = avgPeriod !== 0 ? ((latest.crack_spread - avgPeriod) / Math.abs(avgPeriod)) * 100 : 0;

  if (Math.abs(deviationPct) < UNUSUAL_DEVIATION_PCT) return;

  try {
    const analysis = await analyzeWithClaude({ crack: latest.crack_spread, avgPeriod, deviationPct });
    await pool.query(
      "UPDATE crack_spread_history SET ai_json = ? WHERE bar_date = ?",
      [JSON.stringify(analysis), latest.bar_date]
    );
  } catch (err) {
    console.error("crackSpread Claude analysis failed:", err);
  }
}

export async function ensureFresh() {
  try {
    if (await isStale()) await refresh();
  } catch (err) {
    console.error("crackSpread refresh failed:", err);
  }
}

export async function current(days = 180) {
  await ensureFresh();
  const [rows] = await pool.query(
    `SELECT bar_date, crude_close, gasoline_close, heating_oil_close, crack_spread, ai_json
     FROM crack_spread_history ORDER BY bar_date DESC LIMIT ?`,
    [days]
  );
  if (rows.length === 0) throw new CrackSpreadError("No crack spread data cached yet");

  const history = rows.reverse();
  const latest = history[history.length - 1];
  const weekAgo = history[Math.max(0, history.length - 6)];
  const values = history.map((r) => r.crack_spread);
  const avgPeriod = values.reduce((a, b) => a + b, 0) / values.length;
  const ai = latest.ai_json ?? {};

  return {
    date: latest.bar_date.toISOString().slice(0, 10),
    crack_spread_usd_bbl: Number(latest.crack_spread.toFixed(2)),
    change_1w: Number((latest.crack_spread - weekAgo.crack_spread).toFixed(2)),
    avg_period_usd_bbl: Number(avgPeriod.toFixed(2)),
    legs: {
      crude_usd_bbl: Number(latest.crude_close.toFixed(2)),
      gasoline_usd_gal: Number(latest.gasoline_close.toFixed(2)),
      heating_oil_usd_gal: Number(latest.heating_oil_close.toFixed(2)),
    },
    ai_headline: ai.headline ?? "",
    ai_direction: ai.direction ?? null,
    ai_summary: ai.summary ?? "",
    history: history.map((r) => ({
      date: r.bar_date.toISOString().slice(0, 10),
      crack_spread_usd_bbl: Number(r.crack_spread.toFixed(2)),
    })),
  };
}
