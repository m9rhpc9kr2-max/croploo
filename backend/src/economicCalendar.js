/**
 * Economic calendar — high-impact macro events over the next two weeks
 * (CPI, NFP, FOMC, etc), the general-macro counterpart to the USDA
 * report calendar (see src/usdaCalendar.js).
 *
 * BLOCKED on the free tier: FMP's /stable/economic-calendar returns
 * HTTP 402 "Restricted Endpoint" for non-paid keys (confirmed live,
 * 2026) — this only works with a paid FMP subscription. The code below
 * is otherwise correct and will start working the moment the
 * configured FMP_API_KEY is upgraded; until then this always throws.
 */
import { pool } from "./db.js";
import { complete } from "./anthropicClient.js";
import * as config from "./config.js";

export class EconomicCalendarError extends Error {}

const REFRESH_STALE_MS = 6 * 60 * 60 * 1000;
const WINDOW_DAYS = 14;

function isoDate(d) {
  return d.toISOString().slice(0, 10);
}

async function fetchCalendar() {
  if (!config.FMP_API_KEY) {
    throw new EconomicCalendarError("FMP_API_KEY is not configured");
  }
  const from = isoDate(new Date());
  const to = isoDate(new Date(Date.now() + WINDOW_DAYS * 24 * 60 * 60 * 1000));
  const url = new URL(`${config.FMP_BASE_URL}/economic-calendar`);
  url.searchParams.set("from", from);
  url.searchParams.set("to", to);
  url.searchParams.set("apikey", config.FMP_API_KEY);

  const resp = await fetch(url, { signal: AbortSignal.timeout(15000) });
  if (!resp.ok) throw new EconomicCalendarError(`FMP HTTP ${resp.status}`);
  const json = await resp.json();
  return (Array.isArray(json) ? json : [])
    .filter((e) => (e.impact ?? "").toLowerCase() === "high")
    .map((e) => ({
      event: e.event,
      date: e.date,
      country: e.country ?? "",
      previous: e.previous ?? null,
      estimate: e.estimate ?? null,
      impact: e.impact,
    }))
    .sort((a, b) => a.date.localeCompare(b.date));
}

async function isStale() {
  const [rows] = await pool.query(
    "SELECT updated_at FROM economic_calendar_cache WHERE id = 1"
  );
  const updatedAt = rows[0]?.updated_at;
  if (!updatedAt) return true;
  return Date.now() - new Date(updatedAt).getTime() > REFRESH_STALE_MS;
}

async function refresh() {
  const events = await fetchCalendar();
  await pool.query(
    `INSERT INTO economic_calendar_cache (id, payload, updated_at)
     VALUES (1, ?, NOW())
     ON DUPLICATE KEY UPDATE payload = VALUES(payload), updated_at = NOW()`,
    [JSON.stringify(events)]
  );
  return events;
}

async function analyzeWithClaude(nextEvent) {
  const system =
    "You are CullyAI giving a short pre-read on the next high-impact macro release, and " +
    "what a surprise vs consensus would likely mean for the dollar and grain exports. " +
    "Respond with 1-2 plain sentences, no markdown, no JSON. Never give financial advice.";
  const text = await complete({
    system,
    messages: [
      {
        role: "user",
        content:
          `Next high-impact event: ${nextEvent.event} (${nextEvent.country}) on ` +
          `${nextEvent.date}, consensus estimate ${nextEvent.estimate ?? "n/a"}, previous ` +
          `${nextEvent.previous ?? "n/a"}.`,
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
      console.error("economic calendar refresh failed:", err);
    }
  }
  if (!events) {
    const [rows] = await pool.query(
      "SELECT payload FROM economic_calendar_cache WHERE id = 1"
    );
    if (rows.length === 0) throw new EconomicCalendarError("No economic calendar data available yet");
    events = rows[0].payload;
  }

  let note = "";
  if (events.length > 0) {
    try {
      note = await analyzeWithClaude(events[0]);
    } catch (err) {
      console.error("economic calendar Claude analysis failed:", err);
    }
  }

  return { events, note };
}
