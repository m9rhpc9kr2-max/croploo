/**
 * Macro economic indicators panel — the highest-signal FRED series for
 * commodity/basis trading: inflation, growth, employment, and Fed
 * policy, each shown with its latest reading vs the prior one. CullyAI
 * comments on whichever indicator has the most recent release.
 */
import * as fred from "./fredClient.js";
import { complete } from "./anthropicClient.js";

export class EconomicIndicatorsError extends Error {}

const INDICATORS = [
  { seriesId: "CPIAUCSL", label: "CPI Inflation", unit: "index" },
  { seriesId: "GDP", label: "GDP", unit: "$B" },
  { seriesId: "UNRATE", label: "Unemployment", unit: "%" },
  { seriesId: "FEDFUNDS", label: "Fed Funds Rate", unit: "%" },
  { seriesId: "MANEMP", label: "Manufacturing Employment", unit: "K" },
  { seriesId: "RSXFS", label: "Retail Sales", unit: "$M" },
  { seriesId: "HOUST", label: "Housing Starts", unit: "K" },
  { seriesId: "UMCSENT", label: "Consumer Sentiment", unit: "index" },
];

async function indicatorSnapshot({ seriesId, label, unit }) {
  const rows = await fred.history(seriesId, 3);
  if (rows.length === 0) return null;
  const [latest, prior] = rows;
  const change = prior ? latest.value - prior.value : 0;
  const changePct = prior && prior.value !== 0 ? (change / prior.value) * 100 : 0;
  return {
    series_id: seriesId,
    label,
    unit,
    latest_date: latest.obs_date.toISOString().slice(0, 10),
    latest_value: Number(latest.value.toFixed(2)),
    prior_value: prior ? Number(prior.value.toFixed(2)) : null,
    change: Number(change.toFixed(2)),
    change_pct: Number(changePct.toFixed(2)),
  };
}

async function analyzeWithClaude(indicator) {
  const system =
    "You are CullyAI explaining a fresh US macro data release and its likely read-through " +
    "for the Fed, the dollar, and grain export competitiveness. Respond with 1-3 plain " +
    "sentences, no markdown, no JSON. Never give financial advice — describe the data and " +
    "the typical historical relationship only.";
  const text = await complete({
    system,
    messages: [
      {
        role: "user",
        content:
          `${indicator.label} released ${indicator.latest_date}: ${indicator.latest_value} ` +
          `${indicator.unit} (prior: ${indicator.prior_value} ${indicator.unit}, change ` +
          `${indicator.change_pct}%).`,
      },
    ],
    maxTokens: 300,
  });
  return text.trim();
}

export async function snapshot() {
  const results = await Promise.all(INDICATORS.map(indicatorSnapshot));
  const indicators = results.filter((r) => r !== null);
  if (indicators.length === 0) {
    throw new EconomicIndicatorsError("Not enough FRED data cached yet");
  }

  const mostRecent = [...indicators].sort((a, b) =>
    b.latest_date.localeCompare(a.latest_date)
  )[0];

  let note = "";
  try {
    note = await analyzeWithClaude(mostRecent);
  } catch (err) {
    console.error("economic indicators Claude analysis failed:", err);
  }

  return { indicators, most_recent_series_id: mostRecent.series_id, note };
}
