/**
 * Earnings calendar, filtered to agribusiness-relevant tickers — ADM,
 * Bunge, Tyson, ConAgra, Kellanova, General Mills, Deere. Sourced from
 * Financial Modeling Prep's free tier (250 req/day), cached for a few
 * hours since the window barely changes intraday.
 */
import { pool } from "./db.js";
import { complete } from "./anthropicClient.js";
import * as config from "./config.js";

export class EarningsCalendarError extends Error {}

const REFRESH_STALE_MS = 6 * 60 * 60 * 1000;
const WINDOW_DAYS = 14;

const AGRI_TICKERS = new Set(["ADM", "BG", "TSN", "CAG", "K", "GIS", "DE"]);

function isoDate(d) {
  return d.toISOString().slice(0, 10);
}

async function fetchCalendar() {
  if (!config.FMP_API_KEY) {
    throw new EarningsCalendarError("FMP_API_KEY is not configured");
  }
  const from = isoDate(new Date());
  const to = isoDate(new Date(Date.now() + WINDOW_DAYS * 24 * 60 * 60 * 1000));
  const url = new URL(`${config.FMP_BASE_URL}/earnings-calendar`);
  url.searchParams.set("from", from);
  url.searchParams.set("to", to);
  url.searchParams.set("apikey", config.FMP_API_KEY);

  const resp = await fetch(url, { signal: AbortSignal.timeout(15000) });
  if (!resp.ok) throw new EarningsCalendarError(`FMP HTTP ${resp.status}`);
  const json = await resp.json();
  return (Array.isArray(json) ? json : [])
    .filter((e) => AGRI_TICKERS.has(e.symbol))
    .map((e) => ({
      symbol: e.symbol,
      date: e.date,
      eps_estimate: e.epsEstimated ?? null,
      revenue_estimate: e.revenueEstimated ?? null,
    }))
    .sort((a, b) => a.date.localeCompare(b.date));
}

async function isStale() {
  const [rows] = await pool.query(
    "SELECT updated_at FROM earnings_calendar_cache WHERE id = 1"
  );
  const updatedAt = rows[0]?.updated_at;
  if (!updatedAt) return true;
  return Date.now() - new Date(updatedAt).getTime() > REFRESH_STALE_MS;
}

async function refresh() {
  const events = await fetchCalendar();
  await pool.query(
    `INSERT INTO earnings_calendar_cache (id, payload, updated_at)
     VALUES (1, ?, NOW())
     ON DUPLICATE KEY UPDATE payload = VALUES(payload), updated_at = NOW()`,
    [JSON.stringify(events)]
  );
  return events;
}

async function analyzeWithClaude(nextEvent) {
  const system =
    "You are CullyAI flagging an upcoming agribusiness earnings report and what to watch " +
    "for in it from a grain-trading perspective. Respond with 1-2 plain sentences, no " +
    "markdown, no JSON. Never give financial advice.";
  const text = await complete({
    system,
    messages: [
      {
        role: "user",
        content: `${nextEvent.symbol} reports earnings on ${nextEvent.date}, EPS estimate ${nextEvent.eps_estimate ?? "n/a"}.`,
      },
    ],
    maxTokens: 200,
  });
  return text.trim();
}

export async function snapshot() {
  let events;
  if (await isStale()) {
    try {
      events = await refresh();
    } catch (err) {
      console.error("earnings calendar refresh failed:", err);
    }
  }
  if (!events) {
    const [rows] = await pool.query(
      "SELECT payload FROM earnings_calendar_cache WHERE id = 1"
    );
    if (rows.length === 0) throw new EarningsCalendarError("No earnings calendar data available yet");
    events = rows[0].payload;
  }

  let note = "";
  if (events.length > 0) {
    try {
      note = await analyzeWithClaude(events[0]);
    } catch (err) {
      console.error("earnings calendar Claude analysis failed:", err);
    }
  }

  return { events, note };
}
