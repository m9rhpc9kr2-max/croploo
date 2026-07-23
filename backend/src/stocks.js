/**
 * Stocks — search + detail quotes via Yahoo Finance's keyless endpoints
 * (same approach as dollarIndex.js/sectorHeatmap.js). No MySQL caching
 * needed here — an in-memory TTL cache is enough since this is a live
 * lookup tool, not a historical series.
 */
export class StocksError extends Error {}

const YAHOO_SEARCH = "https://query1.finance.yahoo.com/v1/finance/search";
const YAHOO_CHART = "https://query1.finance.yahoo.com/v8/finance/chart";
const CACHE_TTL_MS = 60_000;

const cache = new Map();

function cached(key, compute) {
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < CACHE_TTL_MS) return hit.value;
  return compute().then((value) => {
    cache.set(key, { value, at: Date.now() });
    return value;
  });
}

export async function search(query) {
  if (!query || query.trim().length === 0) return [];
  return cached(`search:${query}`, async () => {
    const url = new URL(YAHOO_SEARCH);
    url.searchParams.set("q", query);
    url.searchParams.set("quotesCount", "10");
    url.searchParams.set("newsCount", "0");
    const resp = await fetch(url, {
      headers: { "user-agent": "Mozilla/5.0 (croploo-backend)" },
      signal: AbortSignal.timeout(10000),
    });
    if (!resp.ok) throw new StocksError(`Yahoo search HTTP ${resp.status}`);
    const json = await resp.json();
    return (json.quotes ?? [])
      .filter((q) => q.symbol && (q.shortname || q.longname))
      .map((q) => ({
        symbol: q.symbol,
        name: q.shortname ?? q.longname,
        exchange: q.exchange ?? "",
        type: q.quoteType ?? "",
      }));
  });
}

export async function quote(symbol) {
  return cached(`quote:${symbol}`, async () => {
    // 5y of daily closes (not just 6mo) so the client's time-range selector
    // (1W/1M/3M/6M/YTD/1Y/All) has real data behind every option instead of
    // re-slicing the same few months.
    const url = `${YAHOO_CHART}/${encodeURIComponent(symbol)}?range=5y&interval=1d`;
    const resp = await fetch(url, {
      headers: { "user-agent": "Mozilla/5.0 (croploo-backend)" },
      signal: AbortSignal.timeout(15000),
    });
    if (!resp.ok) throw new StocksError(`Yahoo HTTP ${resp.status} for ${symbol}`);
    const json = await resp.json();
    const result = json.chart?.result?.[0];
    const meta = result?.meta;
    if (!meta?.regularMarketPrice) throw new StocksError(`No quote data for ${symbol}`);

    const timestamps = result?.timestamp ?? [];
    const closes = result?.indicators?.quote?.[0]?.close ?? [];
    const history = [];
    for (let i = 0; i < timestamps.length; i++) {
      if (closes[i] == null) continue;
      history.push({
        date: new Date(timestamps[i] * 1000).toISOString().slice(0, 10),
        close: closes[i],
      });
    }

    const previousClose = meta.previousClose ?? meta.chartPreviousClose;
    const changePct = previousClose
      ? ((meta.regularMarketPrice - previousClose) / previousClose) * 100
      : 0;

    return {
      symbol: meta.symbol,
      name: meta.longName ?? meta.shortName ?? meta.symbol,
      currency: meta.currency ?? "USD",
      price: meta.regularMarketPrice,
      change_pct: Number(changePct.toFixed(2)),
      day_high: meta.regularMarketDayHigh ?? null,
      day_low: meta.regularMarketDayLow ?? null,
      fifty_two_week_high: meta.fiftyTwoWeekHigh ?? null,
      fifty_two_week_low: meta.fiftyTwoWeekLow ?? null,
      volume: meta.regularMarketVolume ?? null,
      history,
    };
  });
}
