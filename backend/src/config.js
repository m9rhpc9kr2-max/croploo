export const DB_HOST = process.env.CROPLOO_DB_HOST || "127.0.0.1";
export const DB_PORT = Number(process.env.CROPLOO_DB_PORT || 3306);
export const DB_USER = process.env.CROPLOO_DB_USER || "root";
export const DB_PASSWORD = process.env.CROPLOO_DB_PASSWORD || "";
export const DB_NAME = process.env.CROPLOO_DB_NAME || "croploo";
// Set on Cloud Run to connect via the Cloud SQL Auth Proxy's Unix socket
// (mounted at /cloudsql/<connection-name>) instead of TCP host/port.
export const DB_SOCKET_PATH = process.env.CROPLOO_DB_SOCKET_PATH || "";

export const JWT_SECRET =
  process.env.CROPLOO_JWT_SECRET || "dev-secret-change-in-production";
export const JWT_EXPIRES_IN = "7d";

export const PORT = Number(process.env.PORT || 8000);

// Alpha Vantage — real market data (free tier: 25 requests/day, 1 req/sec).
export const ALPHA_VANTAGE_API_KEY = process.env.ALPHA_VANTAGE_API_KEY || "";
export const ALPHA_VANTAGE_BASE_URL = "https://www.alphavantage.co/query";

// Minimum time between live refreshes per symbol, to stay within the
// free-tier daily request budget.
export const MARKET_DATA_REFRESH_MINUTES = Number(
  process.env.CROPLOO_MARKET_REFRESH_MINUTES || 60
);

// Anthropic — CullyAI chat and USDA report analysis.
export const ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY || "";
export const ANTHROPIC_MODEL = process.env.ANTHROPIC_MODEL || "claude-sonnet-5";

// Gemini — automatic fallback for CullyAI chat when Claude is rate-limited
// or otherwise unavailable (see geminiClient.js / routes/cullyai.js).
export const GEMINI_API_KEY = process.env.GEMINI_API_KEY || "";
export const GEMINI_MODEL = process.env.GEMINI_MODEL || "gemini-2.5-flash";

// EIA — diesel price proxy for freight rates (eia.gov/opendata).
export const EIA_API_KEY = process.env.EIA_API_KEY || "";

// USDA NASS Quick Stats — real crop production/stocks/yield/progress data.
export const NASS_API_KEY = process.env.NASS_API_KEY || "";

// FRED (Federal Reserve Bank of St. Louis) — Treasury yields + macro
// indicators (CPI, GDP, unemployment, Fed funds rate, etc).
export const FRED_API_KEY = process.env.FRED_API_KEY || "";
export const FRED_BASE_URL = "https://api.stlouisfed.org/fred/series/observations";

// Financial Modeling Prep — earnings calendar (free tier: 250
// requests/day). FMP retired the /api/v3 "legacy" endpoints for keys
// issued after Aug 2025 in favor of /stable — see earningsCalendar.js.
// Note: /stable/economic-calendar is a *paid-tier-only* endpoint as of
// 2026 (confirmed via a live 402 response), so economicCalendar.js
// can't be made to work on a free FMP key — see its doc comment.
export const FMP_API_KEY = process.env.FMP_API_KEY || "";
export const FMP_BASE_URL = "https://financialmodelingprep.com/stable";

// Email verification (Mailgun SMTP).
export const SMTP_HOST = process.env.SMTP_HOST || "";
export const SMTP_PORT = Number(process.env.SMTP_PORT || 587);
export const SMTP_USER = process.env.SMTP_USER || "";
export const SMTP_PASS = process.env.SMTP_PASS || "";
export const MAIL_FROM = process.env.MAIL_FROM || SMTP_USER;

export const VERIFICATION_CODE_TTL_MINUTES = 15;

// Shared secret for the daily-brief send-now endpoint, so only Cloud
// Scheduler's 7:30am cron hit (not the general public) can trigger a
// mass email send. Set CROPLOO_CRON_SECRET and configure Cloud Scheduler
// to send it as the X-Cron-Secret header.
export const CRON_SECRET = process.env.CROPLOO_CRON_SECRET || "";

// Stripe billing.
export const STRIPE_SECRET_KEY = process.env.STRIPE_SECRET_KEY || "";
export const STRIPE_WEBHOOK_SECRET = process.env.STRIPE_WEBHOOK_SECRET || "";
// Desktop app has no web frontend to redirect back to — Checkout just
// needs *some* success/cancel URL; the app itself polls/refreshes the
// user's tier after sending them to Checkout.
export const APP_URL = process.env.APP_URL || "http://localhost:8000";

// Grandfathering cutoff — users whose accounts were created before this
// timestamp are eligible for the legacy (pre-price-increase) price when
// they first subscribe. Set to the moment the new prices went live.
export const GRANDFATHER_CUTOFF = new Date("2026-07-07T00:00:00.000Z");

// Current prices. Individual-plan prices were cut well below their old
// (pre-increase) LEGACY_PLAN_PRICES below to lower the barrier to a first
// purchase — see getOrCreatePriceId's isGrandfathered handling, which
// only ever applies whichever of the two prices is actually lower.
export const PLANS = {
  basic:         { name: "Croploo Basic",        amountCents: 1900,  seats: 1,  apiAccess: false },
  pro:           { name: "Croploo Pro",           amountCents: 4900,  seats: 1,  apiAccess: false },
  desk:          { name: "Croploo Desk",          amountCents: 9900,  seats: 1,  apiAccess: true  },
  // team / institutional are multi-seat plans; amountCents is the total
  // monthly charge (not per-seat). Default seat counts match the plan.
  team:          { name: "Croploo Team",          amountCents: 39900, seats: 5,  apiAccess: true  },
  institutional: { name: "Croploo Institutional", amountCents: 79900, seats: 10, apiAccess: true  },
};

// Legacy prices for grandfathered users (pre-increase individual plans only).
// Now higher than PLANS' current prices above — see getOrCreatePriceId.
export const LEGACY_PLAN_PRICES = {
  basic: 3900,
  pro:   7900,
  desk:  14900,
};

// Additional seats can be purchased for team/institutional plans.
export const ADDITIONAL_SEAT_PRICE_CENTS = 7900; // $79 per additional seat/month

// API rate limits per plan (calls per day).
export const API_RATE_LIMITS = {
  desk: 1000,
  institutional: 5000,
  team: 10000,
};
