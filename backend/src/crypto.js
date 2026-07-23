/**
 * Crypto Terminal — top-10 coins by market cap via CoinGecko's markets
 * endpoint (free, keyless, 30 req/min). Included because crypto
 * volatility tracks broad risk-off sentiment, which also spills into
 * commodities.
 */
import { pool } from "./db.js";

export class CryptoError extends Error {}

const COINGECKO_MARKETS = "https://api.coingecko.com/api/v3/coins/markets";
const REFRESH_STALE_MS = 5 * 60 * 1000;

async function fetchMarkets() {
  const url = new URL(COINGECKO_MARKETS);
  url.searchParams.set("vs_currency", "usd");
  url.searchParams.set("order", "market_cap_desc");
  url.searchParams.set("per_page", "10");
  url.searchParams.set("page", "1");
  url.searchParams.set("sparkline", "true");
  url.searchParams.set("price_change_percentage", "24h");

  const resp = await fetch(url, { signal: AbortSignal.timeout(15000) });
  if (!resp.ok) throw new CryptoError(`CoinGecko HTTP ${resp.status}`);
  const json = await resp.json();
  return json.map((c) => ({
    id: c.id,
    symbol: c.symbol.toUpperCase(),
    name: c.name,
    price: c.current_price,
    change_24h_pct: c.price_change_percentage_24h ?? 0,
    market_cap_usd: c.market_cap,
    volume_24h_usd: c.total_volume,
    sparkline_7d: c.sparkline_in_7d?.price ?? [],
  }));
}

async function isStale() {
  const [rows] = await pool.query(
    "SELECT updated_at FROM crypto_snapshot_cache WHERE id = 1"
  );
  const updatedAt = rows[0]?.updated_at;
  if (!updatedAt) return true;
  return Date.now() - new Date(updatedAt).getTime() > REFRESH_STALE_MS;
}

async function refresh() {
  const coins = await fetchMarkets();
  await pool.query(
    `INSERT INTO crypto_snapshot_cache (id, payload, updated_at)
     VALUES (1, ?, NOW())
     ON DUPLICATE KEY UPDATE payload = VALUES(payload), updated_at = NOW()`,
    [JSON.stringify(coins)]
  );
  return coins;
}

export async function snapshot() {
  if (await isStale()) {
    try {
      const coins = await refresh();
      return { as_of: new Date().toISOString(), coins };
    } catch (err) {
      console.error("crypto refresh failed:", err);
    }
  }
  const [rows] = await pool.query(
    "SELECT payload, updated_at FROM crypto_snapshot_cache WHERE id = 1"
  );
  if (rows.length === 0) throw new CryptoError("No crypto data available yet");
  return { as_of: rows[0].updated_at.toISOString(), coins: rows[0].payload };
}
