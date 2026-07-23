/**
 * US Dollar strength vs corn futures — a strong dollar makes US grain
 * exports less competitive. Uses UUP (Invesco DB US Dollar Index
 * Bullish Fund) as a free, keyless dollar-index proxy via Yahoo
 * Finance, paired daily with corn futures (ZC=F) to compute a real
 * trailing correlation, then has Claude explain the relationship.
 */
import { pool } from "./db.js";
import { complete } from "./anthropicClient.js";

export class DollarIndexError extends Error {}

const YAHOO_CHART = "https://query1.finance.yahoo.com/v8/finance/chart";
const REFRESH_STALE_MS = 12 * 60 * 60 * 1000;

async function fetchDailySeries(yahooSymbol) {
  const url = `${YAHOO_CHART}/${encodeURIComponent(yahooSymbol)}?range=1y&interval=1d`;
  const resp = await fetch(url, {
    headers: { "user-agent": "Mozilla/5.0 (croploo-backend)" },
    signal: AbortSignal.timeout(15000),
  });
  if (!resp.ok) throw new DollarIndexError(`Yahoo HTTP ${resp.status} for ${yahooSymbol}`);
  const json = await resp.json();
  const result = json.chart?.result?.[0];
  const timestamps = result?.timestamp ?? [];
  const closes = result?.indicators?.quote?.[0]?.close ?? [];
  const byDate = new Map();
  for (let i = 0; i < timestamps.length; i++) {
    if (closes[i] == null) continue;
    byDate.set(new Date(timestamps[i] * 1000).toISOString().slice(0, 10), closes[i]);
  }
  return byDate;
}

async function isStale() {
  const [rows] = await pool.query("SELECT MAX(bar_date) AS latest FROM dollar_index_history");
  const latest = rows[0]?.latest;
  if (!latest) return true;
  return Date.now() - new Date(latest).getTime() > REFRESH_STALE_MS;
}

async function refresh() {
  const [dollar, corn] = await Promise.all([
    fetchDailySeries("UUP"),
    fetchDailySeries("ZC=F"),
  ]);
  for (const [day, dollarClose] of dollar) {
    const cornClose = corn.get(day);
    if (cornClose == null) continue;
    await pool.query(
      `INSERT INTO dollar_index_history (bar_date, dollar_index, corn_price)
       VALUES (?, ?, ?)
       ON DUPLICATE KEY UPDATE dollar_index = VALUES(dollar_index), corn_price = VALUES(corn_price)`,
      [day, dollarClose, cornClose]
    );
  }
}

export async function ensureFresh() {
  try {
    if (await isStale()) await refresh();
  } catch (err) {
    console.error("dollar index refresh failed:", err);
  }
}

function pearson(xs, ys) {
  const n = xs.length;
  if (n < 2) return 0;
  const mx = xs.reduce((a, b) => a + b, 0) / n;
  const my = ys.reduce((a, b) => a + b, 0) / n;
  let cov = 0;
  let vx = 0;
  let vy = 0;
  for (let i = 0; i < n; i++) {
    cov += (xs[i] - mx) * (ys[i] - my);
    vx += (xs[i] - mx) ** 2;
    vy += (ys[i] - my) ** 2;
  }
  if (vx === 0 || vy === 0) return 0;
  return cov / Math.sqrt(vx * vy);
}

async function analyzeWithClaude({ latestDollar, changePct, correlation }) {
  const system =
    "You are CullyAI explaining how the US Dollar Index relates to grain export " +
    "competitiveness and basis, given the real current dollar level, its recent change, " +
    "and its real correlation with corn futures over the past year. Respond with 1-3 plain " +
    "sentences, no markdown, no JSON. Never give financial advice — describe the historical " +
    "relationship and what the data shows only.";
  const text = await complete({
    system,
    messages: [
      {
        role: "user",
        content:
          `Dollar index proxy (UUP) level: ${latestDollar.toFixed(2)}, 30-day change: ` +
          `${changePct.toFixed(1)}%, correlation with corn futures over the past year: ` +
          `${correlation.toFixed(2)}.`,
      },
    ],
    maxTokens: 300,
  });
  return text.trim();
}

export async function snapshot(days = 365) {
  await ensureFresh();
  const [rows] = await pool.query(
    `SELECT bar_date, dollar_index, corn_price FROM dollar_index_history
     WHERE bar_date >= DATE_SUB(CURDATE(), INTERVAL ? DAY) ORDER BY bar_date ASC`,
    [days]
  );
  if (rows.length < 2) throw new DollarIndexError("Not enough dollar index data cached yet");

  const correlation = pearson(
    rows.map((r) => r.dollar_index),
    rows.map((r) => r.corn_price)
  );

  const latest = rows[rows.length - 1];
  const monthAgo = rows[Math.max(0, rows.length - 22)];
  const changePct =
    ((latest.dollar_index - monthAgo.dollar_index) / monthAgo.dollar_index) * 100;

  let note = "";
  try {
    note = await analyzeWithClaude({ latestDollar: latest.dollar_index, changePct, correlation });
  } catch (err) {
    console.error("dollar index Claude analysis failed:", err);
  }

  return {
    date: latest.bar_date.toISOString().slice(0, 10),
    dollar_index: Number(latest.dollar_index.toFixed(2)),
    change_30d_pct: Number(changePct.toFixed(1)),
    correlation_with_corn_1y: Number(correlation.toFixed(2)),
    note,
    history: rows.map((r) => ({
      date: r.bar_date.toISOString().slice(0, 10),
      dollar_index: r.dollar_index,
      corn_price: r.corn_price,
    })),
  };
}
