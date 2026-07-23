/**
 * Sector Heatmap — today's performance for 10 sector-proxy ETFs via
 * Yahoo Finance's keyless chart API (same approach as dollarIndex.js):
 * Energy, Agriculture, Technology, Financial, Industrial, Consumer
 * Staples, Gold, Silver, Oil, and Natural Gas.
 */
import { pool } from "./db.js";

export class SectorHeatmapError extends Error {}

const YAHOO_CHART = "https://query1.finance.yahoo.com/v8/finance/chart";
const REFRESH_STALE_MS = 15 * 60 * 1000;

const SECTORS = [
  { symbol: "XLE", label: "Energy" },
  { symbol: "MOO", label: "Agriculture" },
  { symbol: "XLK", label: "Technology" },
  { symbol: "XLF", label: "Financial" },
  { symbol: "XLI", label: "Industrial" },
  { symbol: "XLP", label: "Consumer Staples" },
  { symbol: "GLD", label: "Gold" },
  { symbol: "SLV", label: "Silver" },
  { symbol: "USO", label: "Oil" },
  { symbol: "UNG", label: "Natural Gas" },
];

async function fetchQuote(symbol) {
  const url = `${YAHOO_CHART}/${encodeURIComponent(symbol)}?range=1d&interval=1d`;
  const resp = await fetch(url, {
    headers: { "user-agent": "Mozilla/5.0 (croploo-backend)" },
    signal: AbortSignal.timeout(15000),
  });
  if (!resp.ok) throw new SectorHeatmapError(`Yahoo HTTP ${resp.status} for ${symbol}`);
  const json = await resp.json();
  const meta = json.chart?.result?.[0]?.meta;
  const previousClose = meta?.previousClose ?? meta?.chartPreviousClose;
  if (!meta?.regularMarketPrice || !previousClose) {
    throw new SectorHeatmapError(`No quote data for ${symbol}`);
  }
  const changePct =
    ((meta.regularMarketPrice - previousClose) / previousClose) * 100;
  return {
    price: meta.regularMarketPrice,
    change_pct: Number(changePct.toFixed(2)),
  };
}

async function fetchAll() {
  const results = await Promise.all(
    SECTORS.map(async (s) => {
      try {
        const quote = await fetchQuote(s.symbol);
        return { symbol: s.symbol, label: s.label, ...quote };
      } catch (err) {
        console.error(`sector heatmap fetch failed for ${s.symbol}:`, err);
        return null;
      }
    })
  );
  return results.filter((r) => r !== null);
}

async function isStale() {
  const [rows] = await pool.query(
    "SELECT updated_at FROM sector_heatmap_cache WHERE id = 1"
  );
  const updatedAt = rows[0]?.updated_at;
  if (!updatedAt) return true;
  return Date.now() - new Date(updatedAt).getTime() > REFRESH_STALE_MS;
}

async function refresh() {
  const sectors = await fetchAll();
  if (sectors.length === 0) throw new SectorHeatmapError("No sector data available");
  await pool.query(
    `INSERT INTO sector_heatmap_cache (id, payload, updated_at)
     VALUES (1, ?, NOW())
     ON DUPLICATE KEY UPDATE payload = VALUES(payload), updated_at = NOW()`,
    [JSON.stringify(sectors)]
  );
  return sectors;
}

export async function snapshot() {
  if (await isStale()) {
    try {
      const sectors = await refresh();
      return { as_of: new Date().toISOString(), sectors };
    } catch (err) {
      console.error("sector heatmap refresh failed:", err);
    }
  }
  const [rows] = await pool.query(
    "SELECT payload, updated_at FROM sector_heatmap_cache WHERE id = 1"
  );
  if (rows.length === 0) throw new SectorHeatmapError("No sector heatmap data available yet");
  return { as_of: rows[0].updated_at.toISOString(), sectors: rows[0].payload };
}
