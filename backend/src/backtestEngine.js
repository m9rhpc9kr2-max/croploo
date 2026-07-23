/**
 * Backtests a basis mean-reversion rule against real historical data —
 * `basis_snapshots` (USDA AMS AgTransport, weekly cadence). No new data
 * source: this only computes over numbers already in the database.
 *
 * Honesty note (surfaced in the tool output, not just this comment): the
 * "average" used as a baseline is the *full available history's* mean for
 * that state+symbol, not a true rolling 5-year window — basis_snapshots
 * doesn't go back far enough everywhere to always support a real 5-year
 * rolling calculation. Small sample sizes should be treated as low
 * confidence; the tool always reports sample_count so CullyAI (and the
 * user) can judge that.
 */
import { pool } from "./db.js";

export const BACKTEST_CONDITIONS = ["basis_below_average", "basis_above_average"];

const MAX_HISTORY_ROWS = 500;

async function loadHistory(state, symbol) {
  const [rows] = await pool.query(
    `SELECT basis, snapshot_date
     FROM basis_snapshots
     WHERE state = ? AND symbol = ?
     ORDER BY snapshot_date ASC
     LIMIT ?`,
    [String(state).toUpperCase(), String(symbol).toUpperCase(), MAX_HISTORY_ROWS]
  );
  return rows;
}

function mean(values) {
  return values.reduce((a, b) => a + b, 0) / values.length;
}

function findExitIndex(rows, fromIndex, holdingDays) {
  const target = new Date(rows[fromIndex].snapshot_date);
  target.setDate(target.getDate() + holdingDays);
  for (let i = fromIndex + 1; i < rows.length; i++) {
    if (new Date(rows[i].snapshot_date) >= target) return i;
  }
  return -1;
}

export async function runBacktest({
  condition,
  state,
  symbol,
  threshold_pct = 15,
  holding_days = 14,
}) {
  if (!BACKTEST_CONDITIONS.includes(condition)) {
    throw new Error(`Unknown backtest condition: ${condition}`);
  }
  if (!state) {
    throw new Error("state is required for basis-deviation backtests");
  }

  const rows = await loadHistory(state, symbol);
  if (rows.length < 10) {
    return {
      condition,
      state,
      symbol,
      sample_count: 0,
      note: `Only ${rows.length} historical basis snapshots available for ${state}/${symbol} — too few to backtest.`,
    };
  }

  const basisValues = rows.map((r) => r.basis);
  const baseline = mean(basisValues);
  const scale = Math.max(Math.abs(baseline), 1);
  const offset = (scale * threshold_pct) / 100;

  const signals = [];
  for (let i = 0; i < rows.length; i++) {
    const flagged =
      condition === "basis_below_average"
        ? rows[i].basis <= baseline - offset
        : rows[i].basis >= baseline + offset;
    if (!flagged) continue;

    const exitIdx = findExitIndex(rows, i, holding_days);
    if (exitIdx === -1) continue; // incomplete — not enough future data yet

    const entry = rows[i];
    const exit = rows[exitIdx];
    const change = exit.basis - entry.basis;
    const favorable = condition === "basis_below_average" ? change : -change;
    signals.push({
      signal_date: entry.snapshot_date,
      exit_date: exit.snapshot_date,
      entry_basis: entry.basis,
      exit_basis: exit.basis,
      change,
      favorable,
    });
  }

  if (signals.length === 0) {
    return {
      condition,
      state,
      symbol,
      baseline_mean_basis: baseline,
      sample_count: 0,
      note: "No historical signals matched this threshold with complete forward data.",
    };
  }

  const wins = signals.filter((s) => s.favorable > 0).length;
  const favorableValues = signals.map((s) => s.favorable);
  const worstMove = Math.min(...favorableValues);
  const bestMove = Math.max(...favorableValues);

  let cumulative = 0;
  const equityCurve = signals.map((s) => {
    cumulative += s.favorable;
    return { date: s.signal_date, cumulative_change: cumulative };
  });

  const topExamples = [...signals]
    .sort((a, b) => b.favorable - a.favorable)
    .slice(0, 5);

  return {
    condition,
    state,
    symbol,
    threshold_pct,
    holding_days,
    baseline_mean_basis: baseline,
    baseline_note:
      "Baseline is the full-history average basis for this state+symbol, not a rolling 5-year window.",
    sample_count: signals.length,
    win_rate_pct: (wins / signals.length) * 100,
    avg_favorable_change: mean(favorableValues),
    best_signal: topExamples[0],
    worst_signal: signals.find((s) => s.favorable === worstMove),
    equity_curve: equityCurve,
    top_examples: topExamples,
  };
}
