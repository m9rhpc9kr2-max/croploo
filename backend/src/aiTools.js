/**
 * CullyAI's tool-use allowlist: fixed, read-only, parameterized query
 * templates (no free-form SQL), plus the `render_chart` display directive
 * and the backtest/portfolio-stress-test compute tools.
 *
 * Every tool here reuses data/logic already used elsewhere in the app
 * (usdaBasis.js, marketData.js, wasdeSurprises.js, cotData.js, seasonal.js,
 * portfolio.js) — this module adds no new data sources, it exposes the
 * existing real numbers/functions to CullyAI's tool loop.
 *
 * Every executor receives `(input, ctx)` where `ctx = { userId }` comes from
 * the authenticated request in cullyai.js — NEVER from the model's tool-call
 * input — so tools that touch per-user data (portfolio) can't be pointed at
 * another user's data via prompt injection.
 */
import { pool } from "./db.js";
import * as cotData from "./cotData.js";
import * as seasonal from "./seasonal.js";
import * as portfolio from "./portfolio.js";
import { runBacktest, BACKTEST_CONDITIONS } from "./backtestEngine.js";

const MAX_ROWS = 250;

function clampDate(value, fallbackDaysAgo) {
  if (typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value)) return value;
  const d = new Date();
  d.setDate(d.getDate() - fallbackDaysAgo);
  return d.toISOString().slice(0, 10);
}

async function queryBasisHistory({ state, symbol, start_date, end_date }) {
  const start = clampDate(start_date, 180);
  const end = clampDate(end_date, 0);
  const [rows] = await pool.query(
    `SELECT state, symbol, cash_price, futures_price, basis, snapshot_date
     FROM basis_snapshots
     WHERE state = ? AND symbol = ? AND snapshot_date BETWEEN ? AND ?
     ORDER BY snapshot_date ASC
     LIMIT ?`,
    [String(state).toUpperCase(), String(symbol).toUpperCase(), start, end, MAX_ROWS]
  );
  return rows;
}

async function queryFuturesHistory({ symbol, start_date, end_date }) {
  const start = clampDate(start_date, 180);
  const end = clampDate(end_date, 0);
  const [rows] = await pool.query(
    `SELECT symbol, bar_date, close
     FROM futures_price_history
     WHERE symbol = ? AND bar_date BETWEEN ? AND ?
     ORDER BY bar_date ASC
     LIMIT ?`,
    [String(symbol).toUpperCase(), start, end, MAX_ROWS]
  );
  return rows;
}

async function queryWasdeSurprises({ commodity, since }) {
  const sinceDate = clampDate(since, 3650);
  const [rows] = await pool.query(
    `SELECT commodity, release_date, metric, previous_value, current_value,
            surprise_pct, price_at_release, price_24h, price_48h, price_1w
     FROM wasde_surprises
     WHERE commodity = ? AND release_date >= ?
     ORDER BY release_date DESC
     LIMIT ?`,
    [String(commodity).toUpperCase(), sinceDate, MAX_ROWS]
  );
  return rows;
}

async function queryCotSummary({ commodity }) {
  const { snapshots, analysis } = await cotData.ensureLatest();
  const serialized = cotData.serialize({ snapshots, analysis });
  if (!commodity) return serialized;
  const wanted = String(commodity).toUpperCase();
  return {
    ...serialized,
    per_commodity: (serialized.per_commodity ?? []).filter(
      (c) => c.commodity === wanted
    ),
  };
}

async function querySeasonalPattern({ symbol }) {
  return seasonal.seasonalPattern(String(symbol).toUpperCase());
}

function periodStats(rows) {
  if (rows.length === 0) return null;
  const closes = rows.map((r) => r.close);
  const first = closes[0];
  const last = closes[closes.length - 1];
  return {
    start_date: rows[0].bar_date,
    end_date: rows[rows.length - 1].bar_date,
    first_close: first,
    last_close: last,
    min_close: Math.min(...closes),
    max_close: Math.max(...closes),
    avg_close: closes.reduce((a, b) => a + b, 0) / closes.length,
    pct_change: first ? ((last - first) / first) * 100 : null,
    sample_count: closes.length,
  };
}

async function comparePeriods({
  symbol,
  period_a_start,
  period_a_end,
  period_b_start,
  period_b_end,
}) {
  const sym = String(symbol).toUpperCase();
  const [a, b] = await Promise.all([
    queryFuturesHistory({ symbol: sym, start_date: period_a_start, end_date: period_a_end }),
    queryFuturesHistory({ symbol: sym, start_date: period_b_start, end_date: period_b_end }),
  ]);
  return { symbol: sym, period_a: periodStats(a), period_b: periodStats(b) };
}

/** User-scoped — userId comes from ctx (the authenticated request), never from `input`. */
async function stressTestPortfolio({ price_shock_pct = 0, basis_shock_cents = 0 }, ctx) {
  const positions = await portfolio.positionsForUser(ctx.userId);
  const shocked = positions.map((p) => {
    if (p.current_cash_price == null) {
      return { ...p, shocked_cash_price: null, shocked_pl_per_bushel: null, shocked_total_pl: null };
    }
    const shockedPrice =
      p.current_cash_price * (1 + price_shock_pct / 100) + basis_shock_cents / 100;
    const shockedPlPerBushel = shockedPrice - p.break_even_price;
    const shockedTotalPl = shockedPlPerBushel * p.bushels;
    return {
      commodity: p.commodity,
      bushels: p.bushels,
      break_even_price: p.break_even_price,
      current_cash_price: p.current_cash_price,
      current_total_pl: p.total_pl,
      shocked_cash_price: shockedPrice,
      shocked_pl_per_bushel: shockedPlPerBushel,
      shocked_total_pl: shockedTotalPl,
      pl_delta: p.total_pl != null ? shockedTotalPl - p.total_pl : null,
    };
  });
  const totalCurrentPl = positions.reduce((sum, p) => sum + (p.total_pl ?? 0), 0);
  const totalShockedPl = shocked.reduce((sum, p) => sum + (p.shocked_total_pl ?? 0), 0);
  return {
    scenario: { price_shock_pct, basis_shock_cents },
    positions: shocked,
    total_current_pl: totalCurrentPl,
    total_shocked_pl: totalShockedPl,
    total_pl_delta: totalShockedPl - totalCurrentPl,
  };
}

/** Anthropic `tools` array — passed straight into agenticComplete(). */
export const AI_TOOLS = [
  {
    name: "query_basis_history",
    description:
      "Real weekly cash-minus-futures basis history for one US state and one commodity symbol (ZC=corn, ZW=wheat, ZS=soybeans), from USDA AMS AgTransport data.",
    input_schema: {
      type: "object",
      properties: {
        state: { type: "string", description: "Two-letter US state code, e.g. IA" },
        symbol: { type: "string", description: "ZC, ZW, or ZS" },
        start_date: { type: "string", description: "YYYY-MM-DD, defaults to 180 days ago" },
        end_date: { type: "string", description: "YYYY-MM-DD, defaults to today" },
      },
      required: ["state", "symbol"],
    },
  },
  {
    name: "query_futures_history",
    description: "Real daily futures closing prices for a symbol (ZC, ZW, ZS).",
    input_schema: {
      type: "object",
      properties: {
        symbol: { type: "string", description: "ZC, ZW, or ZS" },
        start_date: { type: "string", description: "YYYY-MM-DD, defaults to 180 days ago" },
        end_date: { type: "string", description: "YYYY-MM-DD, defaults to today" },
      },
      required: ["symbol"],
    },
  },
  {
    name: "query_wasde_surprises",
    description:
      "Real historical WASDE stocks-surprise records for a commodity: how much the number deviated from the prior period, and the real futures-price reaction 24h/48h/1 week later. Also useful for scenario questions ('what if WASDE surprises by X%') — find the closest historical surprise_pct and report its real reaction.",
    input_schema: {
      type: "object",
      properties: {
        commodity: { type: "string", description: "CORN, WHEAT, or SOYBEANS" },
        since: { type: "string", description: "YYYY-MM-DD, defaults to 10 years ago" },
      },
      required: ["commodity"],
    },
  },
  {
    name: "query_cot_summary",
    description:
      "Latest real CFTC Commitments of Traders positioning: managed-money (funds) vs. commercials net position, 3-year percentile, and a contrarian signal (CROWDED_LONG/STRETCHED_LONG/CROWDED_SHORT/STRETCHED_SHORT/NEUTRAL) per commodity.",
    input_schema: {
      type: "object",
      properties: {
        commodity: {
          type: "string",
          description: "CORN, WHEAT, or SOYBEANS — omit for all three",
        },
      },
    },
  },
  {
    name: "query_seasonal_pattern",
    description:
      "Real 5-year and 10-year seasonal weekly price pattern for a futures symbol, plus the current year's price overlaid week-by-week — for 'is this a good time of year to sell' type questions.",
    input_schema: {
      type: "object",
      properties: {
        symbol: { type: "string", description: "ZC, ZW, or ZS" },
      },
      required: ["symbol"],
    },
  },
  {
    name: "compare_periods",
    description:
      "Compare real futures-price statistics (first/last/min/max/avg close, % change) between two date ranges for the same symbol — use for 'how does now compare to period X' questions instead of eyeballing two separate query_futures_history calls.",
    input_schema: {
      type: "object",
      properties: {
        symbol: { type: "string", description: "ZC, ZW, or ZS" },
        period_a_start: { type: "string", description: "YYYY-MM-DD" },
        period_a_end: { type: "string", description: "YYYY-MM-DD" },
        period_b_start: { type: "string", description: "YYYY-MM-DD" },
        period_b_end: { type: "string", description: "YYYY-MM-DD" },
      },
      required: ["symbol", "period_a_start", "period_a_end", "period_b_start", "period_b_end"],
    },
  },
  {
    name: "run_backtest",
    description:
      `Backtest a simple rule against real historical basis + futures data: ${BACKTEST_CONDITIONS.join(", ")}. ` +
      "Returns signal count, win rate, average return, max drawdown, best/worst signal, an equity curve, and the top historical examples. Always tell the user the exact date range and sample size — small samples mean low confidence.",
    input_schema: {
      type: "object",
      properties: {
        condition: { type: "string", enum: BACKTEST_CONDITIONS },
        state: { type: "string", description: "Two-letter state code (for basis-deviation conditions)" },
        symbol: { type: "string", description: "ZC, ZW, or ZS" },
        threshold_pct: {
          type: "number",
          description: "Deviation threshold in percent, e.g. 20 for 'basis 20% below its historical average'",
        },
        holding_days: { type: "number", description: "Days held after the signal, default 14" },
      },
      required: ["condition", "symbol"],
    },
  },
  {
    name: "stress_test_portfolio",
    description:
      "Apply a hypothetical price and/or basis shock to the current user's real stored portfolio positions and report the P&L impact per position and in total. Operates only on the current user's own portfolio.",
    input_schema: {
      type: "object",
      properties: {
        price_shock_pct: { type: "number", description: "e.g. -15 for a 15% price drop" },
        basis_shock_cents: { type: "number", description: "e.g. -10 for basis widening 10 cents" },
      },
    },
  },
  {
    name: "render_chart",
    description:
      "Render a chart in the chat for the user. Call this with real data points you already have (e.g. from a query tool) — never invent numbers.",
    input_schema: {
      type: "object",
      properties: {
        chart_type: { type: "string", enum: ["line", "bar", "area"] },
        title: { type: "string" },
        x_label: { type: "string" },
        y_label: { type: "string" },
        series: {
          type: "array",
          items: {
            type: "object",
            properties: {
              label: { type: "string" },
              points: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    x: { type: "string", description: "date or category label" },
                    y: { type: "number" },
                  },
                  required: ["x", "y"],
                },
              },
            },
            required: ["label", "points"],
          },
        },
      },
      required: ["chart_type", "title", "series"],
    },
  },
];

/** name -> executor(input, ctx). Used to build the `executeTool` dispatcher in cullyai.js. */
export const AI_TOOL_EXECUTORS = {
  query_basis_history: (input) => queryBasisHistory(input),
  query_futures_history: (input) => queryFuturesHistory(input),
  query_wasde_surprises: (input) => queryWasdeSurprises(input),
  query_cot_summary: (input) => queryCotSummary(input),
  query_seasonal_pattern: (input) => querySeasonalPattern(input),
  compare_periods: (input) => comparePeriods(input),
  run_backtest: (input) => runBacktest(input),
  stress_test_portfolio: (input, ctx) => stressTestPortfolio(input, ctx),
};
