/**
 * Audit Trail / Decision Log — a user can log a note against a CullyAI
 * recommendation ("sold 40% at $4.82"), and the app tracks the real
 * futures price 7 and 30 days later so the log becomes evidence of
 * whether following CullyAI's read would have worked out. This is the
 * single strongest trust signal to show an institutional buyer.
 */
import { pool } from "./db.js";

export class DecisionLogError extends Error {}

const SYMBOL_BY_COMMODITY = { CORN: "ZC", WHEAT: "ZW", SOYBEANS: "ZS" };

async function currentPrice(commodity) {
  const symbol = SYMBOL_BY_COMMODITY[commodity];
  if (!symbol) return null;
  const [rows] = await pool.query(
    "SELECT price FROM futures_prices WHERE symbol = ?",
    [symbol]
  );
  return rows[0]?.price ?? null;
}

export async function create(userId, { commodity, userNote, cullyaiContext }) {
  if (!commodity || !userNote) {
    throw new DecisionLogError("commodity and userNote are required");
  }
  const priceAtLog = await currentPrice(commodity.toUpperCase());
  const [result] = await pool.query(
    `INSERT INTO decision_log (user_id, commodity, cullyai_context, user_note, price_at_log)
     VALUES (?, ?, ?, ?, ?)`,
    [userId, commodity.toUpperCase(), cullyaiContext ?? null, userNote, priceAtLog]
  );
  return get(userId, result.insertId);
}

async function get(userId, id) {
  const [rows] = await pool.query(
    "SELECT * FROM decision_log WHERE id = ? AND user_id = ?",
    [id, userId]
  );
  return rows[0] ? serialize(rows[0]) : null;
}

/** Backfills price_7d/price_30d for entries old enough that haven't been filled yet. */
export async function backfillOutcomes() {
  const [pending] = await pool.query(
    `SELECT id, commodity, created_at FROM decision_log
     WHERE price_7d IS NULL OR price_30d IS NULL
     ORDER BY created_at ASC LIMIT 50`
  );
  for (const row of pending) {
    const ageDays = (Date.now() - new Date(row.created_at).getTime()) / (24 * 60 * 60 * 1000);
    const price = ageDays >= 7 ? await currentPrice(row.commodity) : null;
    if (ageDays >= 30) {
      await pool.query("UPDATE decision_log SET price_7d = COALESCE(price_7d, ?), price_30d = ? WHERE id = ?",
        [price, price, row.id]);
    } else if (ageDays >= 7) {
      await pool.query("UPDATE decision_log SET price_7d = COALESCE(price_7d, ?) WHERE id = ?",
        [price, row.id]);
    }
  }
}

export async function list(userId) {
  await backfillOutcomes().catch((err) => console.error("decision log backfill failed:", err));
  const [rows] = await pool.query(
    "SELECT * FROM decision_log WHERE user_id = ? ORDER BY created_at DESC LIMIT 100",
    [userId]
  );
  return rows.map(serialize);
}

export function serialize(row) {
  return {
    id: row.id,
    commodity: row.commodity,
    cullyai_context: row.cullyai_context,
    user_note: row.user_note,
    price_at_log: row.price_at_log,
    price_7d: row.price_7d,
    price_30d: row.price_30d,
    created_at: row.created_at.toISOString(),
  };
}
