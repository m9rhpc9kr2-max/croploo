/**
 * Real cash-grain basis data via USDA AMS's AgTransport open dataset
 * (Socrata dataset v85y-3hep, "Grain Basis"), sourced from USDA AMS
 * Market News "Elevator Bid" reports. No API key required — this is a
 * public Socrata endpoint, unlike the MARS API.
 *
 * The dataset reports one bid/futures/basis bar per state-level market
 * per commodity per week (not per individual elevator), so every
 * elevator in ELEVATORS shares its state's weekly basis bar.
 */
import { pool } from "./db.js";

const AGTRANSPORT_BASE_URL = "https://agtransport.usda.gov/resource/v85y-3hep.json";

// USDA AgTransport reports wheat by class, not as one generic "wheat" —
// Illinois/Indiana/Ohio report Soft Red Winter, the Plains/Mountain
// states report Hard Red Winter, and the northern Spring Wheat belt
// reports Hard Red Spring. These are real, distinct cash markets (and
// real, distinct CME/MGEX futures contracts — KE and MWE — not
// approximated against ZW's SRW futures), so they're modeled as separate
// symbols rather than one wheat basket that only ever half-matches.
export const SYMBOL_NAMES = {
  ZC: "Corn",
  ZW: "Wheat (Soft Red Winter)",
  ZS: "Soybeans",
  KE: "Wheat (Hard Red Winter)",
  MWE: "Wheat (Hard Red Spring)",
};

const COMMODITY_MAP = {
  ZC: "Corn",
  ZW: "Soft Red Winter Wheat",
  ZS: "Soybeans",
  KE: "Hard Red Winter Wheat",
  MWE: "Hard Red Spring Wheat",
};

// Verified directly against the live v85y-3hep endpoint (market_type=
// 'Elevator Bid', current as of Jul 2026). Every state below reports at
// least one of Corn/Soybeans/a wheat class for real — states that only
// ever grow one or two of the three no longer need to be left out, since
// a request for a commodity a state doesn't report just returns an empty
// (not fake) result rather than erroring.
//   Corn + Soybeans: IL, IA, MN, IN, OH, KS, NE, SD, ND, NC
//   Hard Red Winter Wheat (KE): KS, MT, NE, OK, SD, WA
//   Hard Red Spring Wheat (MWE): MT, ND, WA
const STATE_MARKET_NAMES = {
  IL: "Illinois",
  IA: "Iowa",
  MN: "Minnesota",
  IN: "Indiana",
  OH: "Ohio",
  KS: "Kansas",
  NE: "Nebraska",
  SD: "South Dakota",
  ND: "North Dakota",
  NC: "North Carolina",
  MT: "Montana",
  OK: "Oklahoma",
  WA: "Washington",
};

// USDA AMS refreshes these bids roughly weekly, so recheck at most once
// every 6 days rather than hammering the endpoint on every request.
const REFRESH_STALE_MS = 6 * 24 * 60 * 60 * 1000;

export class UsdaBasisError extends Error {}

async function fetchStateSeries(stateAbbr, symbol) {
  const marketName = STATE_MARKET_NAMES[stateAbbr];
  const commodity = COMMODITY_MAP[symbol];
  if (!marketName || !commodity) {
    throw new UsdaBasisError(`No USDA mapping for state=${stateAbbr} symbol=${symbol}`);
  }

  const url = new URL(AGTRANSPORT_BASE_URL);
  url.searchParams.set(
    "$where",
    `market_name='${marketName}' AND commodity='${commodity}' AND market_type='Elevator Bid'`
  );
  url.searchParams.set("$order", "date DESC");
  url.searchParams.set("$limit", "500");

  const resp = await fetch(url, { signal: AbortSignal.timeout(20000) });
  if (!resp.ok) {
    throw new UsdaBasisError(`USDA AgTransport HTTP ${resp.status}`);
  }
  const rows = await resp.json();
  return rows
    .filter((r) => r.bid != null && r.futures_price != null && r.basis != null)
    .map((r) => ({
      date: r.date.slice(0, 10),
      cashPrice: Number(r.bid),
      futuresPrice: Number(r.futures_price),
      // AgTransport reports basis in $/bu; the app works in cents/bu.
      basis: Number(r.basis) * 100,
    }));
}

async function isStale(state, symbol) {
  const [rows] = await pool.query(
    `SELECT MAX(snapshot_date) AS latest FROM basis_snapshots WHERE state = ? AND symbol = ?`,
    [state, symbol]
  );
  const latest = rows[0]?.latest;
  if (!latest) return true;
  return Date.now() - new Date(latest).getTime() > REFRESH_STALE_MS;
}

export async function refreshStateSymbol(state, symbol) {
  const series = await fetchStateSeries(state, symbol);
  for (const bar of series) {
    await pool.query(
      `INSERT INTO basis_snapshots (state, symbol, cash_price, futures_price, basis, snapshot_date)
       VALUES (?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         cash_price = VALUES(cash_price),
         futures_price = VALUES(futures_price),
         basis = VALUES(basis)`,
      [state, symbol, bar.cashPrice, bar.futuresPrice, bar.basis, bar.date]
    );
  }
}

export async function ensureFresh(states, symbols) {
  const pairs = states.flatMap((state) => symbols.map((symbol) => [state, symbol]));
  // Run refreshes concurrently and swallow ANY failure per pair (timeout,
  // rate limit, transient 5xx, ...) — one slow/unavailable state-commodity
  // combo must never block the whole request; callers just get whatever
  // is already cached for that pair.
  await Promise.all(
    pairs.map(async ([state, symbol]) => {
      try {
        if (await isStale(state, symbol)) {
          await refreshStateSymbol(state, symbol);
        }
      } catch (err) {
        console.error(`usdaBasis refresh failed for ${state}/${symbol}:`, err);
      }
    })
  );
}

export async function latest(state, symbol) {
  const [rows] = await pool.query(
    `SELECT * FROM basis_snapshots
     WHERE state = ? AND symbol = ?
     ORDER BY snapshot_date DESC LIMIT 1`,
    [state, symbol]
  );
  return rows[0] ?? null;
}

export async function avg5yr(state, symbol) {
  const [rows] = await pool.query(
    `SELECT AVG(basis) AS avg FROM basis_snapshots
     WHERE state = ? AND symbol = ?
       AND snapshot_date >= DATE_SUB(CURDATE(), INTERVAL 5 YEAR)`,
    [state, symbol]
  );
  const avg = rows[0]?.avg;
  return avg === null || avg === undefined ? null : Number(avg);
}

export async function history(state, symbol, days) {
  const [rows] = await pool.query(
    `SELECT snapshot_date, basis FROM basis_snapshots
     WHERE state = ? AND symbol = ?
       AND snapshot_date >= DATE_SUB(CURDATE(), INTERVAL ? DAY)
     ORDER BY snapshot_date ASC`,
    [state, symbol, days]
  );
  return rows;
}
