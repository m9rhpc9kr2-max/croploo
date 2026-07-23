/**
 * WASDE Surprise Tracker: each time a fresh WASDE-equivalent NASS number
 * comes in (see usdaReports.buildWasdeReport), records how far it
 * deviated from the previous release ("the surprise") plus the real
 * futures price reaction at 24h/48h/1 week after that release date,
 * backfilled once enough time and cached price history exist.
 *
 * There's no free source of futures ticks going back to 2015 (Alpha
 * Vantage's free tier only returns ~100 recent daily bars), so this
 * can't retroactively build a 2015-present database. Instead it starts
 * accumulating real surprises the moment this ships, and every new one
 * is compared against whatever real history has built up since.
 */
import { pool } from "./db.js";

const STOCKS_METRIC = "Stocks";

function pctChange(current, previous) {
  if (!previous) return 0;
  return ((current - previous) / Math.abs(previous)) * 100;
}

/** Record the stocks-vs-previous surprise for a just-built WASDE report. */
export async function recordSurprise(commodity, releaseDate, wasdeData) {
  const [current, previous] = wasdeData.stocks;
  if (!current || !previous) return;

  const surprisePct = pctChange(current.value, previous.value);

  const [priceRow] = await pool.query(
    `SELECT close FROM futures_price_history
     WHERE symbol = ? AND bar_date <= ? ORDER BY bar_date DESC LIMIT 1`,
    [commoditySymbol(commodity), releaseDate]
  );

  await pool.query(
    `INSERT INTO wasde_surprises
       (commodity, release_date, metric, previous_value, current_value, surprise_pct, price_at_release)
     VALUES (?, ?, ?, ?, ?, ?, ?)
     ON DUPLICATE KEY UPDATE
       previous_value = VALUES(previous_value),
       current_value = VALUES(current_value),
       surprise_pct = VALUES(surprise_pct),
       price_at_release = COALESCE(price_at_release, VALUES(price_at_release))`,
    [
      commodity,
      releaseDate,
      STOCKS_METRIC,
      previous.value,
      current.value,
      surprisePct,
      priceRow[0]?.close ?? null,
    ]
  );
}

function commoditySymbol(commodity) {
  return { CORN: "ZC", WHEAT: "ZW", SOYBEANS: "ZS" }[commodity];
}

/** Fills in price_24h/48h/1w for any surprise old enough to have that data now. */
export async function backfillReactions() {
  const [rows] = await pool.query(
    `SELECT * FROM wasde_surprises
     WHERE price_at_release IS NOT NULL AND price_1w IS NULL
       AND release_date <= DATE_SUB(CURDATE(), INTERVAL 1 DAY)`
  );

  for (const row of rows) {
    const symbol = commoditySymbol(row.commodity);
    const closeAt = async (daysAfter) => {
      const [r] = await pool.query(
        `SELECT close FROM futures_price_history
         WHERE symbol = ? AND bar_date >= DATE_ADD(?, INTERVAL ? DAY)
         ORDER BY bar_date ASC LIMIT 1`,
        [symbol, row.release_date, daysAfter]
      );
      return r[0]?.close ?? null;
    };

    const price24h = row.price_24h ?? (await closeAt(1));
    const price48h = row.price_48h ?? (await closeAt(2));
    const price1w = await closeAt(7);

    await pool.query(
      `UPDATE wasde_surprises SET price_24h = ?, price_48h = ?, price_1w = ? WHERE id = ?`,
      [price24h, price48h, price1w, row.id]
    );
  }
}

function reaction(row, field) {
  if (row.price_at_release == null || row[field] == null) return null;
  return {
    absolute: row[field] - row.price_at_release,
    pct: ((row[field] - row.price_at_release) / row.price_at_release) * 100,
  };
}

export function serialize(row) {
  return {
    id: row.id,
    commodity: row.commodity,
    release_date: row.release_date.toISOString().slice(0, 10),
    metric: row.metric,
    previous_value: row.previous_value,
    current_value: row.current_value,
    surprise_pct: row.surprise_pct,
    reaction_24h: reaction(row, "price_24h"),
    reaction_48h: reaction(row, "price_48h"),
    reaction_1w: reaction(row, "price_1w"),
  };
}

/** All recorded surprises for a commodity, most recent first. */
export async function history(commodity) {
  const [rows] = await pool.query(
    `SELECT * FROM wasde_surprises WHERE commodity = ? ORDER BY release_date DESC`,
    [commodity]
  );
  return rows;
}

/**
 * Finds the past surprise (excluding the latest one itself) whose
 * surprise_pct is closest in magnitude to the latest — "this surprise
 * most resembles <date>" — using only real, previously recorded data.
 */
export async function mostSimilarToLatest(commodity) {
  const rows = await history(commodity);
  if (rows.length < 2) return null;
  const [latest, ...past] = rows;
  let best = null;
  let bestDist = Infinity;
  for (const row of past) {
    const dist = Math.abs(row.surprise_pct - latest.surprise_pct);
    if (dist < bestDist) {
      bestDist = dist;
      best = row;
    }
  }
  if (!best) return null;
  return { latest: serialize(latest), mostSimilar: serialize(best), distancePct: bestDist };
}
