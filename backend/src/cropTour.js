/**
 * Pro Farmer Crop Tour vs USDA yield comparison.
 *
 * Pro Farmer's national yield estimates are published once a year at the
 * end of the August tour (press release, no API) — the published numbers
 * are stored here as a versioned dataset. USDA's official national
 * yields come live from NASS Quick Stats (final estimate, or the latest
 * in-season forecast during tour season). Claude compares the two the
 * moment both numbers exist for a year, cached per (commodity, year) in
 * crop_tour_analyses.
 */
import { pool } from "./db.js";
import { complete } from "./anthropicClient.js";
import * as nassData from "./nassData.js";

// National estimates published at the end of each August tour
// (bu/acre, Pro Farmer press releases).
const PRO_FARMER_ESTIMATES = {
  CORN: {
    2021: 177.0,
    2022: 168.1,
    2023: 172.0,
    2024: 181.1,
    2025: 182.7,
  },
  SOYBEANS: {
    2021: 51.2,
    2022: 51.7,
    2023: 49.7,
    2024: 54.9,
    2025: 53.0,
  },
};

const COMMODITIES = Object.keys(PRO_FARMER_ESTIMATES);

async function analyzeWithClaude(commodity, rows) {
  const system =
    "You are CullyAI comparing Pro Farmer Crop Tour yield estimates against USDA's " +
    "official numbers for grain traders. Respond with STRICT JSON only matching " +
    'exactly this shape: {"headline": string, "summary": string, "trackRecord": string}. ' +
    "headline is one sentence on the latest divergence (or agreement). summary is 2-3 " +
    "sentences on what the gap between tour and USDA numbers has historically meant " +
    "for price action into the September/October reports. trackRecord is one sentence " +
    "on how the tour's estimates have compared to USDA finals in the years given. " +
    "Never give financial advice — describe historical context and the data only.";

  const text = await complete({
    system,
    messages: [
      {
        role: "user",
        content:
          `Commodity: ${commodity}\n` +
          "Per year: Pro Farmer tour estimate vs USDA NASS yield (final where " +
          "available, otherwise latest in-season forecast), bu/acre:\n" +
          JSON.stringify(rows),
      },
    ],
    maxTokens: 1024,
  });
  const jsonText = text.slice(text.indexOf("{"), text.lastIndexOf("}") + 1);
  const parsed = JSON.parse(jsonText);
  return {
    headline: parsed.headline ?? "",
    summary: parsed.summary ?? "",
    trackRecord: parsed.trackRecord ?? "",
  };
}

async function buildCommodity(commodity) {
  const usdaYears = await nassData.nationalYieldByYear(commodity);
  const usdaByYear = new Map(usdaYears.map((p) => [p.year, p]));
  const proFarmer = PRO_FARMER_ESTIMATES[commodity];

  const rows = [];
  for (const [yearStr, tourEstimate] of Object.entries(proFarmer)) {
    const year = Number(yearStr);
    const usda = usdaByYear.get(year);
    if (!usda) continue;
    rows.push({
      year,
      pro_farmer: tourEstimate,
      usda: usda.value,
      usda_is_final: usda.isFinal,
      diff: Number((tourEstimate - usda.value).toFixed(1)),
    });
  }
  rows.sort((a, b) => b.year - a.year);
  return rows;
}

export async function ensureComparison(commodity) {
  const rows = await buildCommodity(commodity);
  if (rows.length === 0) return { commodity, rows, analysis: null };

  const latestYear = rows[0].year;
  const [existing] = await pool.query(
    "SELECT * FROM crop_tour_analyses WHERE commodity = ? AND tour_year = ?",
    [commodity, latestYear]
  );
  if (existing[0]?.ai_json) {
    return { commodity, rows, analysis: existing[0].ai_json };
  }

  let analysis = null;
  try {
    analysis = await analyzeWithClaude(commodity, rows);
    await pool.query(
      `INSERT INTO crop_tour_analyses (commodity, tour_year, raw_data, ai_json)
       VALUES (?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE raw_data = VALUES(raw_data), ai_json = VALUES(ai_json)`,
      [commodity, latestYear, JSON.stringify(rows), JSON.stringify(analysis)]
    );
  } catch (err) {
    console.error(`crop tour analysis failed for ${commodity}:`, err);
  }
  return { commodity, rows, analysis };
}

export async function ensureAll() {
  const results = await Promise.all(
    COMMODITIES.map(async (commodity) => {
      try {
        return await ensureComparison(commodity);
      } catch (err) {
        console.error(`crop tour failed for ${commodity}:`, err);
        return null;
      }
    })
  );
  return results.filter((r) => r !== null);
}

export function serialize(result) {
  return {
    commodity: result.commodity,
    headline: result.analysis?.headline ?? "",
    summary: result.analysis?.summary ?? "",
    track_record: result.analysis?.trackRecord ?? "",
    years: result.rows,
  };
}
