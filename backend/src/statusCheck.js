/**
 * Public status page data: is each real upstream data source live?
 * Rather than pinging Alpha Vantage/NASS/etc. on every status-page load
 * (which would burn their tight free-tier quotas for a page nobody
 * "needs" data from), this reads the freshness of what's already cached
 * from each source and compares it to that source's own expected
 * refresh cadence — the same signal the resilience design in
 * marketData.js/usdaBasis.js/eiaFreight.js already relies on.
 */
import { pool } from "./db.js";
import * as config from "./config.js";
import { SOURCES } from "./dataSources.js";

const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;

async function latestTimestamp(query) {
  const [rows] = await pool.query(query);
  const value = rows[0]?.latest;
  return value ? new Date(value) : null;
}

function status(lastUpdated, staleAfterMs, configured = true) {
  if (!configured) {
    return { state: "not_configured", last_updated: null };
  }
  if (!lastUpdated) {
    return { state: "no_data", last_updated: null };
  }
  const age = Date.now() - lastUpdated.getTime();
  return {
    state: age > staleAfterMs ? "stale" : "operational",
    last_updated: lastUpdated.toISOString(),
  };
}

export async function checkAll() {
  const [amsLatest, fasLatest, avLatest, nassLatest, eiaLatest, anthropicLatest] = await Promise.all([
    latestTimestamp("SELECT MAX(snapshot_date) AS latest FROM basis_snapshots"),
    latestTimestamp("SELECT MAX(snapshot_date) AS latest FROM export_sales_snapshots"),
    latestTimestamp("SELECT MAX(updated_at) AS latest FROM futures_prices"),
    latestTimestamp("SELECT MAX(ai_processed_at) AS latest FROM usda_reports"),
    latestTimestamp("SELECT MAX(bar_date) AS latest FROM diesel_prices"),
    latestTimestamp("SELECT MAX(ai_processed_at) AS latest FROM usda_reports"),
  ]);

  return [
    {
      ...SOURCES.USDA_AMS,
      ...status(amsLatest, 10 * DAY),
    },
    {
      ...SOURCES.USDA_FAS,
      ...status(fasLatest, 10 * DAY),
    },
    {
      ...SOURCES.ALPHA_VANTAGE,
      ...status(avLatest, 4 * DAY, !!config.ALPHA_VANTAGE_API_KEY),
    },
    {
      ...SOURCES.NASS,
      ...status(nassLatest, 14 * DAY, !!config.NASS_API_KEY),
    },
    {
      ...SOURCES.EIA,
      ...status(eiaLatest, 14 * DAY, !!config.EIA_API_KEY),
    },
    {
      ...SOURCES.ANTHROPIC,
      ...status(anthropicLatest, 14 * DAY, !!config.ANTHROPIC_API_KEY),
    },
  ];
}
