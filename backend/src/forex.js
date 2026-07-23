/**
 * Forex Terminal — major USD pairs via Alpha Vantage FX_DAILY (free,
 * keyless-tier-compatible with the same key already used for
 * marketData.js). Dollar strength/weakness across majors matters here
 * because it feeds directly into US grain export competitiveness (see
 * dollarIndex.js for the same theme against corn futures specifically).
 */
import { pool } from "./db.js";
import { complete } from "./anthropicClient.js";
import * as config from "./config.js";

export class ForexError extends Error {}

const REFRESH_STALE_MS = 12 * 60 * 60 * 1000;

// pair -> [from, to]. USD is the base for JPY/CNY, quote for EUR/GBP —
// matches how these pairs actually trade.
const PAIRS = {
  EURUSD: ["EUR", "USD"],
  GBPUSD: ["GBP", "USD"],
  USDJPY: ["USD", "JPY"],
  USDCNY: ["USD", "CNY"],
  USDCHF: ["USD", "CHF"],
};

async function fetchDailySeries(from, to) {
  if (!config.ALPHA_VANTAGE_API_KEY) {
    throw new ForexError("ALPHA_VANTAGE_API_KEY is not configured");
  }
  const url = new URL(config.ALPHA_VANTAGE_BASE_URL);
  url.searchParams.set("function", "FX_DAILY");
  url.searchParams.set("from_symbol", from);
  url.searchParams.set("to_symbol", to);
  url.searchParams.set("apikey", config.ALPHA_VANTAGE_API_KEY);

  const resp = await fetch(url, { signal: AbortSignal.timeout(15000) });
  if (!resp.ok) throw new ForexError(`Alpha Vantage HTTP ${resp.status} for ${from}${to}`);
  const json = await resp.json();
  const series = json["Time Series FX (Daily)"];
  if (!series) throw new ForexError(`No FX_DAILY data for ${from}${to}`);
  return Object.entries(series).map(([date, bar]) => ({
    date,
    close: Number(bar["4. close"]),
  }));
}

async function isStale(pair) {
  const [rows] = await pool.query(
    "SELECT MAX(bar_date) AS latest FROM forex_rates_history WHERE pair = ?",
    [pair]
  );
  const latest = rows[0]?.latest;
  if (!latest) return true;
  return Date.now() - new Date(latest).getTime() > REFRESH_STALE_MS;
}

async function refresh(pair) {
  const [from, to] = PAIRS[pair];
  const bars = await fetchDailySeries(from, to);
  for (const bar of bars) {
    await pool.query(
      `INSERT INTO forex_rates_history (pair, bar_date, rate)
       VALUES (?, ?, ?)
       ON DUPLICATE KEY UPDATE rate = VALUES(rate)`,
      [pair, bar.date, bar.close]
    );
  }
}

async function ensureFresh(pair) {
  try {
    if (await isStale(pair)) await refresh(pair);
  } catch (err) {
    console.error(`forex refresh failed for ${pair}:`, err);
  }
}

async function pairSnapshot(pair, days) {
  await ensureFresh(pair);
  const [rows] = await pool.query(
    `SELECT bar_date, rate FROM forex_rates_history
     WHERE pair = ? AND bar_date >= DATE_SUB(CURDATE(), INTERVAL ? DAY)
     ORDER BY bar_date ASC`,
    [pair, days]
  );
  if (rows.length === 0) return null;
  const latestRow = rows[rows.length - 1];
  const dayAgo = rows[Math.max(0, rows.length - 2)];
  const monthAgo = rows[Math.max(0, rows.length - 22)];
  return {
    pair,
    date: latestRow.bar_date.toISOString().slice(0, 10),
    rate: Number(latestRow.rate.toFixed(4)),
    change_1d_pct: Number((((latestRow.rate - dayAgo.rate) / dayAgo.rate) * 100).toFixed(2)),
    change_30d_pct: Number((((latestRow.rate - monthAgo.rate) / monthAgo.rate) * 100).toFixed(2)),
    history: rows.map((r) => ({
      date: r.bar_date.toISOString().slice(0, 10),
      rate: r.rate,
    })),
  };
}

async function analyzeWithClaude(pairs) {
  const system =
    "You are CullyAI explaining how a US Dollar move across major currency pairs relates " +
    "to US grain export competitiveness. Respond with 1-3 plain sentences, no markdown, " +
    "no JSON. Never give financial advice — describe what the data shows only.";
  const summary = pairs
    .map((p) => `${p.pair}: ${p.rate}, 1-day change ${p.change_1d_pct}%`)
    .join("; ");
  const text = await complete({
    system,
    messages: [{ role: "user", content: `Major USD pairs today: ${summary}.` }],
    maxTokens: 300,
  });
  return text.trim();
}

export async function snapshot(days = 180) {
  const results = await Promise.all(
    Object.keys(PAIRS).map((pair) => pairSnapshot(pair, days))
  );
  const pairs = results.filter((r) => r !== null);
  if (pairs.length === 0) throw new ForexError("Not enough forex data cached yet");

  // USD strength proxy: average of USD-is-quote pairs (inverted, since a
  // rising EUR/USD or GBP/USD means a *weaker* dollar) plus USD-is-base
  // pairs directly.
  const usdMoves = pairs.map((p) =>
    ["EURUSD", "GBPUSD"].includes(p.pair) ? -p.change_1d_pct : p.change_1d_pct
  );
  const avgDollarMove = usdMoves.reduce((a, b) => a + b, 0) / usdMoves.length;

  let note = "";
  if (Math.abs(avgDollarMove) > 1) {
    try {
      note = await analyzeWithClaude(pairs);
    } catch (err) {
      console.error("forex Claude analysis failed:", err);
    }
  }

  return {
    date: pairs[0].date,
    avg_dollar_move_1d_pct: Number(avgDollarMove.toFixed(2)),
    note,
    pairs: pairs.map(({ history, ...rest }) => rest),
    history: pairs.find((p) => p.pair === "EURUSD")?.history ?? [],
  };
}
