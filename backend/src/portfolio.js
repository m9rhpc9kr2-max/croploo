/**
 * Grain inventory positions — P&L, sell-window, and hedge context are
 * computed live every time (never stored), from data already in the
 * system: real cash prices (usdaBasis.js), the seasonal price pattern
 * (seasonal.js) for a sell-window read, and COT positioning (cotData.js)
 * for hedge context.
 */
import { pool } from "./db.js";
import * as usdaBasis from "./usdaBasis.js";
import * as seasonal from "./seasonal.js";
import * as cotData from "./cotData.js";
import { complete } from "./anthropicClient.js";

const COMMODITY_SYMBOL = { CORN: "ZC", WHEAT: "ZW", SOYBEANS: "ZS" };

function currentIsoWeek() {
  const now = new Date();
  const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  const dayNum = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - dayNum);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  return Math.min(Math.ceil(((d - yearStart) / 86400000 + 1) / 7), 52);
}

async function sellWindowSignal(symbol) {
  try {
    const pattern = await seasonal.seasonalPattern(symbol);
    const point = pattern.weeks.find((w) => w.week === currentIsoWeek());
    if (point?.current == null || point?.avg_5y == null) {
      return { label: "UNKNOWN", detail: "Not enough seasonal data for this week yet." };
    }
    const diff = point.current - point.avg_5y;
    if (diff > 3) {
      return {
        label: "FAVORABLE",
        detail:
          `Current price is ${diff.toFixed(1)} points above the 5-year seasonal average ` +
          "for this week of the year — historically a stronger-than-usual pricing window.",
      };
    }
    if (diff < -3) {
      return {
        label: "UNFAVORABLE",
        detail:
          `Current price is ${Math.abs(diff).toFixed(1)} points below the 5-year seasonal ` +
          "average for this week — historically a weaker pricing window.",
      };
    }
    return {
      label: "NEUTRAL",
      detail: "Current price is close to the 5-year seasonal average for this week.",
    };
  } catch (err) {
    return { label: "UNKNOWN", detail: "Seasonal data unavailable." };
  }
}

async function hedgeNote(commodity, plPerBushel) {
  try {
    const { snapshots } = await cotData.ensureLatest();
    const snap = snapshots.find((s) => s.commodity === commodity);
    const system =
      "You are CullyAI giving a grain merchandiser brief hedge context for an existing " +
      "stored position, given real CFTC COT fund positioning. Respond with 1-2 plain " +
      "sentences, no markdown, no JSON. Never give financial advice or tell them what to " +
      "do — describe what the current fund positioning has historically implied and let " +
      "them decide.";
    const text = await complete({
      system,
      messages: [
        {
          role: "user",
          content:
            `Commodity: ${commodity}\nCurrent unrealized P&L per bushel: $${plPerBushel.toFixed(2)}\n` +
            `COT snapshot (managedMoney = funds, commercials = hedgers): ${JSON.stringify(snap ?? {})}`,
        },
      ],
      maxTokens: 300,
    });
    return text.trim();
  } catch (err) {
    console.error("hedge note failed:", err);
    return "";
  }
}

function serialize(row, { cashPrice, plPerBushel, totalPl, sellWindow, hedge }) {
  return {
    id: row.id,
    commodity: row.commodity,
    bushels: row.bushels,
    stored_date: row.stored_date.toISOString().slice(0, 10),
    break_even_price: row.break_even_price,
    state: row.state,
    current_cash_price: cashPrice,
    pl_per_bushel: plPerBushel,
    total_pl: totalPl,
    sell_window: sellWindow,
    hedge_note: hedge,
  };
}

async function enrich(row) {
  const symbol = COMMODITY_SYMBOL[row.commodity];
  let cashPrice = null;
  if (symbol && row.state) {
    const snap = await usdaBasis.latest(row.state, symbol);
    cashPrice = snap ? snap.cash_price : null;
  }
  const plPerBushel = cashPrice !== null ? cashPrice - row.break_even_price : null;
  const totalPl = plPerBushel !== null ? plPerBushel * row.bushels : null;

  const [sellWindow, hedge] = await Promise.all([
    symbol ? sellWindowSignal(symbol) : { label: "UNKNOWN", detail: "" },
    plPerBushel !== null ? hedgeNote(row.commodity, plPerBushel) : Promise.resolve(""),
  ]);

  return serialize(row, { cashPrice, plPerBushel, totalPl, sellWindow, hedge });
}

export async function positionsForUser(userId) {
  const [rows] = await pool.query(
    "SELECT * FROM portfolio_positions WHERE user_id = ? ORDER BY created_at DESC",
    [userId]
  );
  return Promise.all(rows.map(enrich));
}

export async function positionById(userId, id) {
  const [rows] = await pool.query(
    "SELECT * FROM portfolio_positions WHERE id = ? AND user_id = ?",
    [id, userId]
  );
  if (!rows[0]) return null;
  return enrich(rows[0]);
}
