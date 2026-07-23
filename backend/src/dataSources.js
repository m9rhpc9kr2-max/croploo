/**
 * Central registry of upstream data sources, so the "where did this
 * number come from" label shown in the UI (see routes/basis.js,
 * routes/market.js, usdaReports.js) and the /status page describe the
 * exact same sources instead of drifting apart.
 */
export const SOURCES = {
  USDA_AMS: {
    id: "usda_ams",
    label: "USDA AMS AgTransport",
    detail: "Elevator Bid grain basis data, refreshed weekly",
  },
  USDA_FAS: {
    id: "usda_fas",
    label: "USDA FAS Export Sales",
    detail: "Weekly net sales/exports by destination country, refreshed Thursdays",
  },
  USDA_AMS_RAIL: {
    id: "usda_ams_rail",
    label: "USDA AgTransport / STB Rail Service Metrics",
    detail: "Weekly grain rail cars loaded and billed, by state",
  },
  NOAA_NWPS: {
    id: "noaa_nwps",
    label: "NOAA National Water Prediction Service",
    detail: "Mississippi River stage/flow readings at grain corridor gauges",
  },
  USDM: {
    id: "usdm",
    label: "US Drought Monitor",
    detail: "Weekly D0–D4 drought severity by state, National Drought Mitigation Center",
  },
  ALPHA_VANTAGE: {
    id: "alpha_vantage",
    label: "Alpha Vantage",
    detail: "Real futures-proxy ETF closes (CORN/WEAT/SOYB)",
  },
  NASS: {
    id: "nass",
    label: "USDA NASS Quick Stats",
    detail: "Production/yield/stocks/progress survey data",
  },
  ANTHROPIC: {
    id: "anthropic",
    label: "Anthropic Claude",
    detail: "Report analysis, Daily Brief, CullyAI chat",
  },
  EIA: {
    id: "eia",
    label: "EIA",
    detail: "Weekly retail diesel prices by PADD region",
  },
  FRED: {
    id: "fred",
    label: "FRED (St. Louis Fed)",
    detail: "Treasury yield curve and macro indicators",
  },
  COINGECKO: {
    id: "coingecko",
    label: "CoinGecko",
    detail: "Top-10 crypto markets by market cap",
  },
  FMP: {
    id: "fmp",
    label: "Financial Modeling Prep",
    detail: "Earnings calendar and economic calendar",
  },
  NEWS_RSS: {
    id: "news_rss",
    label: "Reuters / USDA / AgWeb / DTN / WSJ / FT",
    detail: "Public RSS headline feeds, CullyAI-tagged",
  },
  YAHOO_FINANCE: {
    id: "yahoo_finance",
    label: "Yahoo Finance",
    detail: "Sector ETF quotes for the sector heatmap",
  },
};

/** "Basis-Daten: USDA AMS AgTransport, letzte Aktualisierung: ..." style label. */
export function formatAsOf(source, date) {
  const iso = date instanceof Date ? date.toISOString() : date;
  return { source: source.label, as_of: iso };
}
