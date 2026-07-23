/**
 * Real forward curve — current prices across upcoming CME contract
 * months for a symbol, via Yahoo Finance's individual contract-month
 * tickers (e.g. ZCZ26.CBT = Dec 2026 corn), free and keyless. Whether
 * the curve is in carry (later months priced higher — storage is
 * rewarded) or inversion (later months cheaper — sell now) is read
 * directly off the real front vs back-month prices.
 */
import { pool } from "./db.js";
import { complete } from "./anthropicClient.js";

export class ForwardCurveError extends Error {}

const YAHOO_CHART = "https://query1.finance.yahoo.com/v8/finance/chart";

// Real CME delivery months per commodity.
const ACTIVE_MONTHS = {
  ZC: ["H", "K", "N", "U", "Z"],
  ZW: ["H", "K", "N", "U", "Z"],
  ZS: ["F", "H", "K", "N", "Q", "U", "X"],
};
const MONTH_NUM = { F: 0, G: 1, H: 2, J: 3, K: 4, M: 5, N: 6, Q: 7, U: 8, V: 9, X: 10, Z: 11 };
const REFRESH_STALE_MS = 12 * 60 * 60 * 1000;

function upcomingContracts(symbol, count = 6) {
  const months = ACTIVE_MONTHS[symbol];
  const now = new Date();
  const monthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
  const candidates = [];
  for (let y = now.getUTCFullYear(); y <= now.getUTCFullYear() + 2; y++) {
    for (const code of months) {
      const date = new Date(Date.UTC(y, MONTH_NUM[code], 1));
      if (date >= monthStart) candidates.push({ year: y, code, date });
    }
  }
  candidates.sort((a, b) => a.date - b.date);
  return candidates.slice(0, count);
}

async function fetchContractPrice(symbol, code, year) {
  const yy = String(year).slice(-2);
  const yahooSymbol = `${symbol}${code}${yy}.CBT`;
  const url = `${YAHOO_CHART}/${encodeURIComponent(yahooSymbol)}?range=5d&interval=1d`;
  const resp = await fetch(url, {
    headers: { "user-agent": "Mozilla/5.0 (croploo-backend)" },
    signal: AbortSignal.timeout(15000),
  });
  if (!resp.ok) return null;
  const json = await resp.json();
  const price = json.chart?.result?.[0]?.meta?.regularMarketPrice;
  return typeof price === "number" ? price : null;
}

async function isStale(symbol) {
  const [rows] = await pool.query(
    "SELECT MAX(updated_at) AS latest FROM forward_curve WHERE symbol = ?",
    [symbol]
  );
  const latest = rows[0]?.latest;
  if (!latest) return true;
  return Date.now() - new Date(latest).getTime() > REFRESH_STALE_MS;
}

async function refresh(symbol) {
  const contracts = upcomingContracts(symbol);
  await Promise.all(
    contracts.map(async (c) => {
      const price = await fetchContractPrice(symbol, c.code, c.year);
      if (price === null) return;
      const contractMonth = `${c.code}${String(c.year).slice(-2)}`;
      await pool.query(
        `INSERT INTO forward_curve (symbol, contract_month, expiry_date, price, updated_at)
         VALUES (?, ?, ?, ?, NOW())
         ON DUPLICATE KEY UPDATE price = VALUES(price), updated_at = NOW()`,
        [symbol, contractMonth, c.date.toISOString().slice(0, 10), price]
      );
    })
  );

  const [rows] = await pool.query(
    "SELECT contract_month, price FROM forward_curve WHERE symbol = ? ORDER BY expiry_date ASC LIMIT 2",
    [symbol]
  );
  if (rows.length === 2) {
    const spread = rows[0].price - rows[1].price;
    const today = new Date().toISOString().slice(0, 10);
    await pool.query(
      `INSERT INTO calendar_spread_history (symbol, near_month, far_month, spread, bar_date)
       VALUES (?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         near_month = VALUES(near_month), far_month = VALUES(far_month), spread = VALUES(spread)`,
      [symbol, rows[0].contract_month, rows[1].contract_month, spread, today]
    );
  }
}

async function ensureFresh(symbol) {
  try {
    if (await isStale(symbol)) await refresh(symbol);
  } catch (err) {
    console.error(`forward curve refresh failed for ${symbol}:`, err);
  }
}

function serializeContract(r) {
  return {
    contract_month: r.contract_month,
    expiry_date: r.expiry_date.toISOString().slice(0, 10),
    price: r.price,
  };
}

async function analyzeWithClaude(symbol, structure, contracts) {
  const system =
    "You are CullyAI explaining a grain futures forward curve to a merchandiser deciding " +
    "whether to store grain or sell now. Given real contract-month prices, respond with " +
    "1-2 plain sentences, no markdown, no JSON, explaining what the curve shape (carry or " +
    "inversion) implies for storage economics. Never give financial advice.";
  const text = await complete({
    system,
    messages: [
      {
        role: "user",
        content:
          `Commodity: ${symbol}\nCurve structure: ${structure}\n` +
          `Contracts (month, price cents/bu): ${JSON.stringify(contracts)}`,
      },
    ],
    maxTokens: 300,
  });
  return text.trim();
}

export async function curve(symbol) {
  await ensureFresh(symbol);
  const [rows] = await pool.query(
    "SELECT contract_month, expiry_date, price FROM forward_curve WHERE symbol = ? ORDER BY expiry_date ASC",
    [symbol]
  );
  const contracts = rows.map(serializeContract);
  if (rows.length < 2) {
    return { symbol, structure: "UNKNOWN", contracts, note: "" };
  }

  const first = rows[0].price;
  const last = rows[rows.length - 1].price;
  const structure = last > first ? "CARRY" : last < first ? "INVERSION" : "FLAT";

  const today = new Date().toISOString().slice(0, 10);
  const [existing] = await pool.query(
    "SELECT ai_json FROM forward_curve_analysis WHERE symbol = ? AND analysis_date = ?",
    [symbol, today]
  );
  let note = existing[0]?.ai_json?.note ?? "";
  if (!note) {
    try {
      note = await analyzeWithClaude(symbol, structure, contracts);
      await pool.query(
        `INSERT INTO forward_curve_analysis (symbol, analysis_date, ai_json) VALUES (?, ?, ?)
         ON DUPLICATE KEY UPDATE ai_json = VALUES(ai_json)`,
        [symbol, today, JSON.stringify({ note })]
      );
    } catch (err) {
      console.error("forward curve Claude analysis failed:", err);
    }
  }

  return { symbol, structure, contracts, note };
}

export async function calendarSpreadHistory(symbol, days = 180) {
  await ensureFresh(symbol);
  const [rows] = await pool.query(
    `SELECT bar_date, near_month, far_month, spread FROM calendar_spread_history
     WHERE symbol = ? AND bar_date >= DATE_SUB(CURDATE(), INTERVAL ? DAY)
     ORDER BY bar_date ASC`,
    [symbol, days]
  );
  return rows.map((r) => ({
    date: r.bar_date.toISOString().slice(0, 10),
    near_month: r.near_month,
    far_month: r.far_month,
    spread: r.spread,
  }));
}
