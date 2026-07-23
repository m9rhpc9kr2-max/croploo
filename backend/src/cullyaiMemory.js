/**
 * CullyAI conversation memory — persists every chat turn per user and
 * extracts which commodities/topics they've asked about, so CullyAI can
 * reference prior sessions ("Last week you asked about Iowa corn
 * basis...") instead of starting cold every time.
 */
import { pool } from "./db.js";

const COMMODITY_KEYWORDS = {
  CORN: ["corn", "zc"],
  WHEAT: ["wheat", "zw"],
  SOYBEANS: ["soybean", "soy", "zs"],
};

function extractCommodities(text) {
  const lower = text.toLowerCase();
  return Object.entries(COMMODITY_KEYWORDS)
    .filter(([, keywords]) => keywords.some((k) => lower.includes(k)))
    .map(([commodity]) => commodity);
}

/** Recent turns for this user, oldest first, capped to keep prompts small. */
export async function recentHistory(userId, limit = 12) {
  const [rows] = await pool.query(
    `SELECT role, content, created_at FROM cullyai_messages
     WHERE user_id = ? ORDER BY created_at DESC LIMIT ?`,
    [userId, limit]
  );
  return rows.reverse().map((r) => ({
    role: r.role,
    content: r.content,
    createdAt: r.created_at,
  }));
}

export async function context(userId) {
  const [rows] = await pool.query(
    "SELECT last_commodities, last_topics, updated_at FROM cullyai_user_context WHERE user_id = ?",
    [userId]
  );
  const row = rows[0];
  return {
    lastCommodities: row?.last_commodities ?? [],
    lastTopics: row?.last_topics ?? [],
    updatedAt: row?.updated_at ?? null,
  };
}

/** Persists one user turn + the assistant's reply, and updates rolling context. */
export async function recordTurn(userId, userText, assistantText) {
  await pool.query(
    "INSERT INTO cullyai_messages (user_id, role, content) VALUES (?, 'user', ?)",
    [userId, userText]
  );
  await pool.query(
    "INSERT INTO cullyai_messages (user_id, role, content) VALUES (?, 'assistant', ?)",
    [userId, assistantText]
  );

  const mentioned = extractCommodities(userText);
  if (mentioned.length === 0) return;

  const existing = await context(userId);
  const commodities = [...new Set([...mentioned, ...existing.lastCommodities])].slice(0, 5);
  const topics = [userText.slice(0, 200), ...existing.lastTopics].slice(0, 5);

  await pool.query(
    `INSERT INTO cullyai_user_context (user_id, last_commodities, last_topics, updated_at)
     VALUES (?, ?, ?, NOW())
     ON DUPLICATE KEY UPDATE
       last_commodities = VALUES(last_commodities),
       last_topics = VALUES(last_topics),
       updated_at = NOW()`,
    [userId, JSON.stringify(commodities), JSON.stringify(topics)]
  );
}

/**
 * "Welcome back" nudge shown when a returning user opens CullyAI after
 * being away — only fires if we have real prior context, and only
 * references the actual last-asked commodity, never a fabricated claim.
 */
export async function welcomeBack(userId) {
  const ctx = await context(userId);
  if (!ctx.updatedAt || ctx.lastCommodities.length === 0) return null;

  const hoursSince = (Date.now() - new Date(ctx.updatedAt).getTime()) / 3_600_000;
  if (hoursSince < 12) return null; // still the same session, no need to recap

  const commodity = ctx.lastCommodities[0];
  const daysSince = Math.round(hoursSince / 24);
  const when = daysSince <= 1 ? "recently" : `${daysSince} days ago`;
  return `You asked about ${commodity.toLowerCase()} ${when} — want a refresh on what's changed since?`;
}
