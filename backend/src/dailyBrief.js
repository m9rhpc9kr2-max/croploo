/**
 * Daily brief: Claude synthesizes a short narrative from that day's real
 * basis deviations, futures moves, and active alerts. keyEventsThisWeek
 * is computed deterministically from the real USDA release calendar
 * (usdaCalendar.js) rather than generated, since it's just dates.
 */
import { pool } from "./db.js";
import { ELEVATORS } from "./elevators.js";
import * as usdaBasis from "./usdaBasis.js";
import * as usdaCalendar from "./usdaCalendar.js";
import { complete } from "./anthropicClient.js";

const SYMBOL_COMMODITY = { ZC: "Corn", ZW: "Wheat", ZS: "Soybeans" };

function todayDate() {
  return new Date().toISOString().slice(0, 10);
}

async function gatherBasisSignals(watchlist = null) {
  const states = [...new Set(ELEVATORS.map((e) => e.state))];
  const signals = [];
  for (const state of states) {
    for (const symbol of Object.keys(SYMBOL_COMMODITY)) {
      const snap = await usdaBasis.latest(state, symbol);
      if (!snap) continue;
      const avg = await usdaBasis.avg5yr(state, symbol);
      if (avg === null || avg === 0) continue;
      const deviationPct = ((snap.basis - avg) / Math.abs(avg)) * 100;
      const commodity = SYMBOL_COMMODITY[symbol];
      const watched = watchlist?.some(
        (w) => w.state === state && w.commodity === commodity.toUpperCase()
      );
      signals.push({ state, commodity, basis: snap.basis, avg5yr: avg, deviationPct, watched });
    }
  }
  // Watchlist hits always surface first, then by deviation magnitude.
  signals.sort((a, b) => {
    if (!!b.watched !== !!a.watched) return b.watched ? 1 : -1;
    return Math.abs(b.deviationPct) - Math.abs(a.deviationPct);
  });
  return watchlist ? signals.slice(0, 10) : signals.slice(0, 8);
}

async function gatherFuturesSignals() {
  const [rows] = await pool.query("SELECT * FROM futures_prices ORDER BY ABS(change_pct) DESC");
  return rows.map((r) => ({
    symbol: r.symbol,
    name: r.name,
    price: r.price,
    changePct: r.change_pct,
  }));
}

async function gatherRecentAlerts() {
  const [rows] = await pool.query(
    "SELECT type, commodity, title, severity FROM alerts ORDER BY created_at DESC LIMIT 10"
  );
  return rows;
}

async function synthesizeWithClaude({ basisSignals, futuresSignals, recentAlerts, watchlist }) {
  const personalized = watchlist && watchlist.length > 0;
  const system =
    "You are CullyAI writing the morning market brief for grain basis and futures traders. " +
    "Given today's real basis deviations, futures moves, and system alerts, respond with " +
    'STRICT JSON only matching exactly this shape: {"summary": string, "topOpportunities": ' +
    'string[], "riskFactors": string[]}. summary is 2-4 sentences. topOpportunities and ' +
    "riskFactors are each 2-4 short bullet strings citing specific real numbers from the data " +
    "given. Never give financial advice — describe what the data shows and historical context only." +
    (personalized
      ? " This trader has a watchlist (marked \"watched\": true in the basis data) — lead " +
        "the summary and bullets with what's happening in their watched combos specifically, " +
        "then broader market context second."
      : "");

  const userContent =
    (personalized
      ? `This trader's watchlist: ${JSON.stringify(watchlist)}\n\n`
      : "") +
    `Today's basis deviations (state, commodity, basis¢, 5yr avg¢, deviation%, watched):\n` +
    `${JSON.stringify(basisSignals)}\n\n` +
    `Futures moves (symbol, name, price, change%):\n${JSON.stringify(futuresSignals)}\n\n` +
    `Recent system alerts:\n${JSON.stringify(recentAlerts)}`;

  const text = await complete({
    system,
    messages: [{ role: "user", content: userContent }],
    maxTokens: 1024,
  });
  const jsonText = text.slice(text.indexOf("{"), text.lastIndexOf("}") + 1);
  const parsed = JSON.parse(jsonText);
  return {
    summary: parsed.summary ?? "",
    topOpportunities: parsed.topOpportunities ?? [],
    riskFactors: parsed.riskFactors ?? [],
  };
}

function formatKeyEvents() {
  return usdaCalendar.upcomingReleases(7).map((r) => {
    const label = r.report_type === "WASDE" ? "WASDE" : "Crop Progress";
    return `${label} — ${r.release_date}`;
  });
}

export async function ensureToday() {
  const briefDate = todayDate();
  const [existing] = await pool.query("SELECT * FROM daily_briefs WHERE brief_date = ?", [briefDate]);
  if (existing[0]) return existing[0];

  const [basisSignals, futuresSignals, recentAlerts] = await Promise.all([
    gatherBasisSignals(),
    gatherFuturesSignals(),
    gatherRecentAlerts(),
  ]);

  const narrative = await synthesizeWithClaude({ basisSignals, futuresSignals, recentAlerts });
  const aiJson = { ...narrative, keyEventsThisWeek: formatKeyEvents() };

  await pool.query(
    `INSERT INTO daily_briefs (brief_date, ai_json) VALUES (?, ?)
     ON DUPLICATE KEY UPDATE ai_json = VALUES(ai_json)`,
    [briefDate, JSON.stringify(aiJson)]
  );

  const [rows] = await pool.query("SELECT * FROM daily_briefs WHERE brief_date = ?", [briefDate]);
  return rows[0];
}

export async function ensureForUser(userId) {
  const briefDate = todayDate();
  const [watchlistRows] = await pool.query(
    "SELECT commodity, state FROM watchlist_items WHERE user_id = ?",
    [userId]
  );
  if (watchlistRows.length === 0) return ensureToday();

  const [existing] = await pool.query(
    "SELECT * FROM personalized_daily_briefs WHERE user_id = ? AND brief_date = ?",
    [userId, briefDate]
  );
  if (existing[0]) return existing[0];

  const [basisSignals, futuresSignals, recentAlerts] = await Promise.all([
    gatherBasisSignals(watchlistRows),
    gatherFuturesSignals(),
    gatherRecentAlerts(),
  ]);

  const narrative = await synthesizeWithClaude({
    basisSignals,
    futuresSignals,
    recentAlerts,
    watchlist: watchlistRows,
  });
  const aiJson = { ...narrative, keyEventsThisWeek: formatKeyEvents() };

  await pool.query(
    `INSERT INTO personalized_daily_briefs (user_id, brief_date, ai_json) VALUES (?, ?, ?)
     ON DUPLICATE KEY UPDATE ai_json = VALUES(ai_json)`,
    [userId, briefDate, JSON.stringify(aiJson)]
  );

  const [rows] = await pool.query(
    "SELECT * FROM personalized_daily_briefs WHERE user_id = ? AND brief_date = ?",
    [userId, briefDate]
  );
  return rows[0];
}

export function serialize(row) {
  const ai = row.ai_json || {};
  return {
    date: row.brief_date.toISOString().slice(0, 10),
    summary: ai.summary ?? "",
    top_opportunities: ai.topOpportunities ?? [],
    risk_factors: ai.riskFactors ?? [],
    key_events_this_week: ai.keyEventsThisWeek ?? [],
  };
}
