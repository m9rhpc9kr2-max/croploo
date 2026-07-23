/**
 * Cross-Asset Synthesis — the thing no other grain-trading tool does:
 * combines dollar strength, crude direction, yield-curve stance, and
 * the latest WASDE surprise into one net-effect read per commodity,
 * instead of reporting each in isolation. All inputs are real numbers
 * already computed by other modules (forex.js, sectorHeatmap.js,
 * yieldCurve.js, wasdeSurprises.js) — this module only combines them
 * and asks Claude to reason about the net effect.
 */
import { pool } from "./db.js";
import { complete } from "./anthropicClient.js";
import * as forex from "./forex.js";
import * as sectorHeatmap from "./sectorHeatmap.js";
import * as yieldCurve from "./yieldCurve.js";
import * as wasdeSurprises from "./wasdeSurprises.js";

export class SynthesisError extends Error {}

const REFRESH_STALE_MS = 4 * 60 * 60 * 1000;
const COMMODITIES = ["CORN", "WHEAT", "SOYBEANS"];

async function latestWasdeSurprise(commodity) {
  const rows = await wasdeSurprises.history(commodity).catch(() => []);
  return rows[0] ?? null;
}

async function gatherInputs() {
  const [forexSnap, sectors, curve] = await Promise.all([
    forex.snapshot().catch(() => null),
    sectorHeatmap.snapshot().catch(() => null),
    yieldCurve.snapshot().catch(() => null),
  ]);
  const crude = sectors?.sectors?.find((s) => s.symbol === "USO") ?? null;
  const surprises = {};
  for (const commodity of COMMODITIES) {
    surprises[commodity] = await latestWasdeSurprise(commodity);
  }
  return {
    dollarMove1dPct: forexSnap?.avg_dollar_move_1d_pct ?? null,
    crudeMovePct: crude?.change_pct ?? null,
    yieldCurveInverted: curve?.inverted ?? null,
    spread2s10s: curve?.spread_2s10s ?? null,
    surprises,
  };
}

async function analyzeWithClaude(inputs) {
  const system =
    "You are CullyAI performing cross-asset synthesis for a grain trader — combining " +
    "dollar strength, crude oil direction, the Treasury yield curve, and the latest WASDE " +
    "surprise into ONE net-effect read per commodity (corn, wheat, soybeans), not separate " +
    "commentary per input. Explicitly reason about whether the signals reinforce or " +
    "neutralize each other. For each commodity, respond with exactly one line in the form " +
    "'COMMODITY: <net-effect sentence, max 40 words>'. No markdown, no extra text. Never " +
    "give financial advice — describe what the data shows and a plausible near-term read only.";

  const parts = [];
  if (inputs.dollarMove1dPct != null) {
    parts.push(`US Dollar 1-day move (avg across majors): ${inputs.dollarMove1dPct}%`);
  }
  if (inputs.crudeMovePct != null) {
    parts.push(`Crude oil (USO) today: ${inputs.crudeMovePct}%`);
  }
  if (inputs.yieldCurveInverted != null) {
    parts.push(
      `Yield curve: ${inputs.yieldCurveInverted ? "inverted" : "normal"} ` +
        `(10Y-2Y spread ${inputs.spread2s10s})`
    );
  }
  for (const commodity of COMMODITIES) {
    const s = inputs.surprises[commodity];
    if (s) {
      parts.push(
        `${commodity} latest WASDE surprise (${s.metric}, ${s.release_date}): ` +
          `${s.surprise_pct}% vs prior`
      );
    }
  }
  if (parts.length === 0) throw new SynthesisError("No inputs available for synthesis");

  const text = await complete({
    system,
    messages: [{ role: "user", content: parts.join("\n") }],
    maxTokens: 400,
  });

  const byCommodity = {};
  for (const line of text.split("\n")) {
    const match = line.match(/^\s*(CORN|WHEAT|SOYBEANS)\s*:\s*(.+)$/i);
    if (match) byCommodity[match[1].toUpperCase()] = match[2].trim();
  }
  return byCommodity;
}

async function isStale() {
  const [rows] = await pool.query(
    "SELECT updated_at FROM cross_asset_synthesis WHERE id = 1"
  );
  const updatedAt = rows[0]?.updated_at;
  if (!updatedAt) return true;
  return Date.now() - new Date(updatedAt).getTime() > REFRESH_STALE_MS;
}

async function refresh() {
  const inputs = await gatherInputs();
  const commentary = await analyzeWithClaude(inputs);
  const payload = {
    date: new Date().toISOString().slice(0, 10),
    inputs: {
      dollar_move_1d_pct: inputs.dollarMove1dPct,
      crude_move_pct: inputs.crudeMovePct,
      yield_curve_inverted: inputs.yieldCurveInverted,
      spread_2s10s: inputs.spread2s10s,
    },
    commentary,
  };
  await pool.query(
    `INSERT INTO cross_asset_synthesis (id, payload, updated_at)
     VALUES (1, ?, NOW())
     ON DUPLICATE KEY UPDATE payload = VALUES(payload), updated_at = NOW()`,
    [JSON.stringify(payload)]
  );
  return payload;
}

export async function snapshot() {
  if (await isStale()) {
    try {
      return await refresh();
    } catch (err) {
      console.error("cross-asset synthesis refresh failed:", err);
    }
  }
  const [rows] = await pool.query(
    "SELECT payload FROM cross_asset_synthesis WHERE id = 1"
  );
  if (rows.length === 0) throw new SynthesisError("No synthesis available yet");
  return rows[0].payload;
}
