/**
 * Real USDA FAS Export Sales data (weekly net sales, exports, and
 * outstanding sales commitments, by commodity and destination country).
 *
 * OVERVIEW.md previously listed this as blocked on the USDA FAS ESR
 * OpenData API, which requires a registered API key. It turns out the
 * same underlying Export Sales Report is also mirrored on USDA's
 * AgTransport Socrata platform (dataset wnn7-29tu) — the same keyless,
 * no-registration endpoint style already used by usdaBasis.js — so no
 * API key is needed after all. World totals are computed server-side via
 * SoQL sum() across all ~150 destination countries; the top-10 buyers
 * for the latest week are kept separately for the "who's buying" view.
 */
import { pool } from "./db.js";

const AGTRANSPORT_EXPORT_SALES_URL =
  "https://agtransport.usda.gov/resource/wnn7-29tu.json";

export const SYMBOL_NAMES = { ZC: "Corn", ZW: "Wheat", ZS: "Soybeans" };

const COMMODITY_MAP = { ZC: "Corn", ZW: "Wheat", ZS: "Soybeans" };

// USDA FAS publishes new Export Sales figures every Thursday ~8:30 ET, so
// recheck at most once a day rather than once per request.
const REFRESH_STALE_MS = 24 * 60 * 60 * 1000;

export class ExportSalesError extends Error {}

function toInt(v) {
  const n = Number(v);
  return Number.isFinite(n) ? Math.round(n) : 0;
}

async function fetchWorldTotals(symbol) {
  const commodity = COMMODITY_MAP[symbol];
  if (!commodity) throw new ExportSalesError(`No export-sales mapping for symbol=${symbol}`);

  const url = new URL(AGTRANSPORT_EXPORT_SALES_URL);
  url.searchParams.set(
    "$select",
    "date,myear,sum(wkexportscmy) as weekly_exports,sum(netsalescmy) as net_sales," +
      "sum(accexportscmy) as accumulated_exports,sum(outstanding_sales_total) as outstanding_sales," +
      "sum(totcommcmy) as total_commitments"
  );
  url.searchParams.set("$where", `commodity='${commodity}'`);
  url.searchParams.set("$group", "date,myear");
  url.searchParams.set("$order", "date DESC");
  url.searchParams.set("$limit", "104"); // ~2 years of weekly data

  const resp = await fetch(url, { signal: AbortSignal.timeout(20000) });
  if (!resp.ok) throw new ExportSalesError(`USDA AgTransport Export Sales HTTP ${resp.status}`);
  const rows = await resp.json();
  return rows.map((r) => ({
    date: r.date.slice(0, 10),
    marketingYear: r.myear,
    weeklyExports: toInt(r.weekly_exports),
    netSales: toInt(r.net_sales),
    accumulatedExports: toInt(r.accumulated_exports),
    outstandingSales: toInt(r.outstanding_sales),
    totalCommitments: toInt(r.total_commitments),
  }));
}

async function fetchTopDestinations(symbol, snapshotDate) {
  const commodity = COMMODITY_MAP[symbol];
  const url = new URL(AGTRANSPORT_EXPORT_SALES_URL);
  url.searchParams.set(
    "$where",
    `commodity='${commodity}' AND date='${snapshotDate}T00:00:00.000' AND country != 'UNKNOWN'`
  );
  url.searchParams.set("$order", "netsalescmy DESC");
  url.searchParams.set("$limit", "10");

  const resp = await fetch(url, { signal: AbortSignal.timeout(20000) });
  if (!resp.ok) throw new ExportSalesError(`USDA AgTransport Export Sales HTTP ${resp.status}`);
  const rows = await resp.json();
  return rows.map((r, i) => ({
    country: r.country,
    weeklyExports: toInt(r.wkexportscmy),
    netSales: toInt(r.netsalescmy),
    outstandingSales: toInt(r.outstanding_sales_total),
    rank: i + 1,
  }));
}

async function isStale(symbol) {
  const [rows] = await pool.query(
    `SELECT MAX(snapshot_date) AS latest FROM export_sales_snapshots WHERE symbol = ?`,
    [symbol]
  );
  const latest = rows[0]?.latest;
  if (!latest) return true;
  return Date.now() - new Date(latest).getTime() > REFRESH_STALE_MS;
}

export async function refreshSymbol(symbol) {
  const weeks = await fetchWorldTotals(symbol);
  for (const w of weeks) {
    await pool.query(
      `INSERT INTO export_sales_snapshots
         (symbol, snapshot_date, marketing_year, weekly_exports, net_sales,
          accumulated_exports, outstanding_sales, total_commitments)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         marketing_year = VALUES(marketing_year),
         weekly_exports = VALUES(weekly_exports),
         net_sales = VALUES(net_sales),
         accumulated_exports = VALUES(accumulated_exports),
         outstanding_sales = VALUES(outstanding_sales),
         total_commitments = VALUES(total_commitments)`,
      [
        symbol,
        w.date,
        w.marketingYear,
        w.weeklyExports,
        w.netSales,
        w.accumulatedExports,
        w.outstandingSales,
        w.totalCommitments,
      ]
    );
  }

  const latestDate = weeks[0]?.date;
  if (latestDate) {
    const destinations = await fetchTopDestinations(symbol, latestDate);
    for (const d of destinations) {
      await pool.query(
        `INSERT INTO export_sales_destinations
           (symbol, snapshot_date, country, weekly_exports, net_sales, outstanding_sales, rank_order)
         VALUES (?, ?, ?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
           weekly_exports = VALUES(weekly_exports),
           net_sales = VALUES(net_sales),
           outstanding_sales = VALUES(outstanding_sales),
           rank_order = VALUES(rank_order)`,
        [symbol, latestDate, d.country, d.weeklyExports, d.netSales, d.outstandingSales, d.rank]
      );
    }
  }
}

export async function ensureFresh(symbols) {
  // Same resilience principle as usdaBasis.ensureFresh: one commodity's
  // failure (timeout, transient 5xx, ...) never blocks the others.
  await Promise.all(
    symbols.map(async (symbol) => {
      try {
        if (await isStale(symbol)) {
          await refreshSymbol(symbol);
        }
      } catch (err) {
        console.error(`exportSales refresh failed for ${symbol}:`, err);
      }
    })
  );
}

export async function history(symbol, weeks = 52) {
  const [rows] = await pool.query(
    `SELECT snapshot_date, marketing_year, weekly_exports, net_sales,
            accumulated_exports, outstanding_sales, total_commitments
     FROM export_sales_snapshots
     WHERE symbol = ?
     ORDER BY snapshot_date DESC LIMIT ?`,
    [symbol, weeks]
  );
  return rows.reverse();
}

export async function latest(symbol) {
  const [rows] = await pool.query(
    `SELECT * FROM export_sales_snapshots WHERE symbol = ? ORDER BY snapshot_date DESC LIMIT 1`,
    [symbol]
  );
  return rows[0] ?? null;
}

export async function topDestinations(symbol) {
  const [rows] = await pool.query(
    `SELECT country, weekly_exports, net_sales, outstanding_sales, rank_order
     FROM export_sales_destinations
     WHERE symbol = ? AND snapshot_date = (
       SELECT MAX(snapshot_date) FROM export_sales_destinations WHERE symbol = ?
     )
     ORDER BY rank_order ASC`,
    [symbol, symbol]
  );
  return rows;
}
