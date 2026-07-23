/**
 * Community Insights Feed — short user-submitted market notes,
 * automatically fact-checked by CullyAI against real cached data
 * (current futures price/basis) before being shown, so the feed can't
 * silently host confident-sounding nonsense.
 */
import { pool } from "./db.js";
import { complete } from "./anthropicClient.js";

export class CommunityInsightsError extends Error {}

const SYMBOL_BY_COMMODITY = { CORN: "ZC", WHEAT: "ZW", SOYBEANS: "ZS" };

async function currentContext(commodity) {
  const symbol = SYMBOL_BY_COMMODITY[commodity];
  if (!symbol) return null;
  const [rows] = await pool.query(
    "SELECT price, change_pct FROM futures_prices WHERE symbol = ?",
    [symbol]
  );
  return rows[0] ?? null;
}

async function factCheck(commodity, body) {
  const context = await currentContext(commodity);
  const system =
    "You are CullyAI fact-checking a trader's community post against real market data. " +
    "Reply with exactly two lines: line 1 is one of CONSISTENT, QUESTIONABLE, or UNVERIFIED " +
    "(UNVERIFIED if the post makes no checkable factual claim), line 2 is a one-sentence " +
    "reason. No markdown, no other text.";
  const dataLine = context
    ? `Current ${commodity} futures: ${context.price}, today's change ${context.change_pct}%.`
    : `No current market data cached for ${commodity}.`;
  const text = await complete({
    system,
    messages: [{ role: "user", content: `${dataLine}\nPost: "${body}"` }],
    maxTokens: 200,
  });
  const [verdictLine, ...rest] = text.split("\n").map((l) => l.trim()).filter(Boolean);
  const verdict = ["CONSISTENT", "QUESTIONABLE", "UNVERIFIED"].includes(verdictLine)
    ? verdictLine
    : "UNVERIFIED";
  return { verdict, reason: rest.join(" ") || "" };
}

export async function create(userId, { commodity, body }) {
  if (!commodity || !body) throw new CommunityInsightsError("commodity and body are required");
  let verdict = "UNVERIFIED";
  let reason = "";
  try {
    ({ verdict, reason } = await factCheck(commodity.toUpperCase(), body));
  } catch (err) {
    console.error("community insight fact-check failed:", err);
  }
  const [result] = await pool.query(
    `INSERT INTO community_insights (user_id, commodity, body, fact_check, fact_check_verdict)
     VALUES (?, ?, ?, ?, ?)`,
    [userId, commodity.toUpperCase(), body.slice(0, 500), reason, verdict]
  );
  return { id: result.insertId, commodity: commodity.toUpperCase(), body, fact_check: reason, fact_check_verdict: verdict };
}

export async function list({ commodity, limit = 50 } = {}) {
  const params = [];
  let where = "";
  if (commodity) {
    where = "WHERE ci.commodity = ?";
    params.push(commodity.toUpperCase());
  }
  params.push(limit);
  const [rows] = await pool.query(
    `SELECT ci.id, ci.commodity, ci.body, ci.fact_check, ci.fact_check_verdict, ci.created_at,
            u.username
     FROM community_insights ci JOIN users u ON u.id = ci.user_id
     ${where} ORDER BY ci.created_at DESC LIMIT ?`,
    params
  );
  return rows.map((r) => ({
    id: r.id,
    username: r.username,
    commodity: r.commodity,
    body: r.body,
    fact_check: r.fact_check,
    fact_check_verdict: r.fact_check_verdict,
    created_at: r.created_at.toISOString(),
  }));
}
