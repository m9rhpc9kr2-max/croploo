/**
 * Proactive CullyAI Insights — instead of only answering when asked,
 * once a day CullyAI reads real market data and writes 3 unprompted
 * insights for the Dashboard. Every input here is a genuine computed
 * number (no invented statistics): the corn/soy ratio's percentile
 * within its own ~10y history, the yield curve's inversion trend
 * year-over-year, and natural gas storage vs its 5-year average.
 */
import { pool } from "./db.js";
import { complete } from "./anthropicClient.js";
import * as yieldCurve from "./yieldCurve.js";
import * as ngStorage from "./ngStorage.js";

export class ProactiveInsightsError extends Error {}

async function cornSoyRatioPercentile() {
  const [corn] = await pool.query(
    "SELECT bar_date, close FROM seasonal_price_history WHERE symbol = 'ZC' ORDER BY bar_date"
  );
  const [soy] = await pool.query(
    "SELECT bar_date, close FROM seasonal_price_history WHERE symbol = 'ZS' ORDER BY bar_date"
  );
  if (corn.length < 20 || soy.length < 20) return null;

  const soyByDate = new Map(soy.map((r) => [r.bar_date.toISOString().slice(0, 10), r.close]));
  const ratios = [];
  for (const row of corn) {
    const date = row.bar_date.toISOString().slice(0, 10);
    const soyClose = soyByDate.get(date);
    if (soyClose) ratios.push({ date, ratio: row.close / soyClose });
  }
  if (ratios.length < 20) return null;

  const current = ratios[ratios.length - 1].ratio;
  const below = ratios.filter((r) => r.ratio < current).length;
  const percentile = (below / ratios.length) * 100;
  return { current: Number(current.toFixed(4)), percentile: Number(percentile.toFixed(1)) };
}

async function yieldCurveTrend() {
  const curve = await yieldCurve.snapshot().catch(() => null);
  if (!curve) return null;
  const y2Ago = curve.one_year_ago.find((p) => p.tenor === "2Y")?.yield_pct;
  const y10Ago = curve.one_year_ago.find((p) => p.tenor === "10Y")?.yield_pct;
  const spreadOneYearAgo = y2Ago != null && y10Ago != null ? y10Ago - y2Ago : null;
  return {
    spreadNow: curve.spread_2s10s,
    spreadOneYearAgo,
    inverted: curve.inverted,
    deepening: spreadOneYearAgo != null && curve.spread_2s10s < spreadOneYearAgo,
  };
}

async function ngStorageVsAvg() {
  const latest = await ngStorage.latest().catch(() => null);
  if (!latest) return null;
  return { vs5yAvgPct: latest.vs_5y_avg_pct, season: latest.season };
}

async function analyzeWithClaude({ cornSoy, curve, ng }) {
  const system =
    "You are CullyAI writing exactly 3 short, unprompted daily insights for a grain " +
    "trader's dashboard, each grounded ONLY in the real numbers given — never invent a " +
    "statistic. Each insight starts with one emoji: ⚡ for a notable pattern, ⚠️ for a " +
    "risk/watch item, ✅ for an opportunity. One sentence each, no markdown besides the " +
    "emoji, no financial advice. If a fact isn't provided, don't write an insight about it. " +
    "Respond with exactly 3 lines, one insight per line, nothing else.";

  const facts = [];
  if (cornSoy) {
    facts.push(
      `Corn/Soybean price ratio is currently at the ${cornSoy.percentile}th percentile of its ` +
        `own ~10-year history (current ratio ${cornSoy.current}).`
    );
  }
  if (curve) {
    facts.push(
      `Yield curve 2s/10s spread is ${curve.spreadNow} today vs ${curve.spreadOneYearAgo ?? "n/a"} ` +
        `a year ago (${curve.inverted ? "currently inverted" : "currently normal"}, ` +
        `${curve.deepening ? "deepening" : "not deepening"} vs a year ago).`
    );
  }
  if (ng) {
    facts.push(
      `Natural gas storage is ${ng.vs5yAvgPct}% vs its 5-year average, during the ` +
        `${ng.season.toLowerCase().replace("_", " ")}.`
    );
  }
  if (facts.length === 0) throw new ProactiveInsightsError("No inputs available for insights");

  const text = await complete({
    system,
    messages: [{ role: "user", content: facts.join("\n") }],
    maxTokens: 400,
  });

  return text
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l.length > 0)
    .slice(0, 3);
}

async function generate() {
  const [cornSoy, curve, ng] = await Promise.all([
    cornSoyRatioPercentile(),
    yieldCurveTrend(),
    ngStorageVsAvg(),
  ]);
  const insights = await analyzeWithClaude({ cornSoy, curve, ng });
  const today = new Date().toISOString().slice(0, 10);
  await pool.query(
    `INSERT INTO daily_insights (insight_date, ai_json)
     VALUES (?, ?)
     ON DUPLICATE KEY UPDATE ai_json = VALUES(ai_json)`,
    [today, JSON.stringify(insights)]
  );
  return { date: today, insights };
}

export async function today() {
  const todayDate = new Date().toISOString().slice(0, 10);
  const [rows] = await pool.query(
    "SELECT ai_json FROM daily_insights WHERE insight_date = ?",
    [todayDate]
  );
  if (rows.length > 0) return { date: todayDate, insights: rows[0].ai_json };

  try {
    return await generate();
  } catch (err) {
    console.error("proactive insights generation failed:", err);
    throw new ProactiveInsightsError("No insights available yet");
  }
}
