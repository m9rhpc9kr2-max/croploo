/**
 * Builds USDA report records from real NASS data (nassData.js) and has
 * Claude analyze them. The numbers themselves (production, yield,
 * stocks, progress, condition, and the comparison table) are computed
 * deterministically from real data here — Claude only supplies the
 * narrative interpretation (headline/summary/direction/risk factors),
 * never the figures.
 */
import { pool } from "./db.js";
import * as nassData from "./nassData.js";
import { complete } from "./anthropicClient.js";
import { SOURCES } from "./dataSources.js";
import * as wasdeSurprises from "./wasdeSurprises.js";

const REPORT_TITLES = {
  WASDE: (commodity) => `${titleCase(commodity)} Supply & Demand — Latest USDA NASS Data`,
  CROP_PROGRESS: (commodity) => `${titleCase(commodity)} Crop Progress — Weekly USDA NASS Update`,
};

function titleCase(s) {
  return s.charAt(0) + s.slice(1).toLowerCase();
}

function pctChange(current, previous) {
  if (!previous) return 0;
  return ((current - previous) / Math.abs(previous)) * 100;
}

async function buildWasdeReport(commodity) {
  const data = await nassData.wasdeData(commodity);
  const rows = [];
  const addMetric = (label, points, unit) => {
    if (points.length === 0) return;
    const [cur, prev] = points;
    rows.push({
      metric: label,
      previous: prev ? `${prev.value.toLocaleString()} ${unit}` : "—",
      current: `${cur.value.toLocaleString()} ${unit}`,
      change: prev ? `${pctChange(cur.value, prev.value).toFixed(1)}%` : "—",
      highlight: prev ? Math.abs(pctChange(cur.value, prev.value)) > 5 : false,
    });
  };
  addMetric("Production", data.production, "bu");
  addMetric("Yield", data.yield, "bu/acre");
  addMetric("Stocks", data.stocks, "bu");

  const releaseDate = data.production[0]
    ? `${data.production[0].year}-01-01`
    : new Date().toISOString().slice(0, 10);

  return { rawData: data, comparisonTitle: "Year-over-Year", comparison: rows, releaseDate };
}

async function buildCropProgressReport(commodity) {
  const data = await nassData.cropProgressData(commodity);
  const grouped = new Map();
  for (const p of [...data.progress, ...data.condition]) {
    const list = grouped.get(p.shortDesc) ?? [];
    list.push(p);
    grouped.set(p.shortDesc, list);
  }

  const rows = [];
  let releaseDate = new Date().toISOString().slice(0, 10);
  for (const [label, points] of grouped) {
    points.sort((a, b) => `${b.year}${b.period}`.localeCompare(`${a.year}${a.period}`));
    const [cur, prev] = points;
    if (!cur) continue;
    if (/^\d{4}-\d{2}-\d{2}$/.test(String(cur.period))) releaseDate = cur.period;
    rows.push({
      metric: label,
      previous: prev ? `${prev.value}%` : "—",
      current: `${cur.value}%`,
      change: prev ? `${(cur.value - prev.value).toFixed(1)} pts` : "—",
      highlight: prev ? Math.abs(cur.value - prev.value) > 10 : false,
    });
  }

  return {
    rawData: data,
    comparisonTitle: `Week-over-Week (${data.state})`,
    comparison: rows,
    releaseDate,
  };
}

async function analyzeWithClaude(reportType, commodity, built) {
  const system =
    "You are a USDA agricultural data analyst. Given real USDA NASS statistics, " +
    "respond with STRICT JSON only (no markdown, no prose outside the JSON) matching " +
    'exactly this shape: {"headline": string, "direction": "BULLISH"|"BEARISH"|"NEUTRAL", ' +
    '"summary": string, "keyPoints": string[], "reasoning": string, "basisImpact": string, ' +
    '"confidence": number between 0 and 1, "riskFactors": string[]}. ' +
    "Write from the perspective of grain basis and futures traders. Never give financial " +
    "advice — describe historical context and data-driven implications only.";

  const userContent =
    `Report type: ${reportType}\nCommodity: ${commodity}\n` +
    `Real USDA NASS data (JSON):\n${JSON.stringify(built.rawData)}\n\n` +
    `Comparison table already computed from this data:\n${JSON.stringify(built.comparison)}`;

  const text = await complete({
    system,
    messages: [{ role: "user", content: userContent }],
    maxTokens: 2048,
  });

  const jsonText = text.slice(text.indexOf("{"), text.lastIndexOf("}") + 1);
  const parsed = JSON.parse(jsonText);
  return {
    headline: parsed.headline ?? `${titleCase(commodity)} ${reportType}`,
    direction: parsed.direction ?? "NEUTRAL",
    summary: parsed.summary ?? "",
    keyPoints: parsed.keyPoints ?? [],
    reasoning: parsed.reasoning ?? "",
    basisImpact: parsed.basisImpact ?? "",
    confidence: typeof parsed.confidence === "number" ? parsed.confidence : 0.5,
    riskFactors: parsed.riskFactors ?? [],
  };
}

async function buildReportData(reportType, commodity) {
  return reportType === "WASDE"
    ? buildWasdeReport(commodity)
    : buildCropProgressReport(commodity);
}

export async function ensureReport(reportType, commodity) {
  const built = await buildReportData(reportType, commodity);

  if (reportType === "WASDE") {
    await wasdeSurprises.recordSurprise(commodity, built.releaseDate, built.rawData);
    await wasdeSurprises.backfillReactions();
  }

  const [existing] = await pool.query(
    `SELECT * FROM usda_reports WHERE report_type = ? AND commodity = ? AND release_date = ?`,
    [reportType, commodity, built.releaseDate]
  );
  if (existing[0]?.ai_json) return existing[0];

  const analysis = await analyzeWithClaude(reportType, commodity, built);
  const aiJson = { ...analysis, comparisonTitle: built.comparisonTitle, comparison: built.comparison };
  const title = REPORT_TITLES[reportType](commodity);

  await pool.query(
    `INSERT INTO usda_reports (report_type, commodity, title, release_date, raw_data, ai_processed_at, ai_json)
     VALUES (?, ?, ?, ?, ?, NOW(), ?)
     ON DUPLICATE KEY UPDATE
       raw_data = VALUES(raw_data), ai_processed_at = VALUES(ai_processed_at), ai_json = VALUES(ai_json)`,
    [reportType, commodity, title, built.releaseDate, JSON.stringify(built.rawData), JSON.stringify(aiJson)]
  );

  const [rows] = await pool.query(
    `SELECT * FROM usda_reports WHERE report_type = ? AND commodity = ? AND release_date = ?`,
    [reportType, commodity, built.releaseDate]
  );
  return rows[0];
}

export async function reanalyze(id) {
  const [rows] = await pool.query("SELECT * FROM usda_reports WHERE id = ?", [id]);
  const row = rows[0];
  if (!row) return null;

  const built = await buildReportData(row.report_type, row.commodity);
  const analysis = await analyzeWithClaude(row.report_type, row.commodity, built);
  const aiJson = { ...analysis, comparisonTitle: built.comparisonTitle, comparison: built.comparison };

  await pool.query(`UPDATE usda_reports SET ai_processed_at = NOW(), ai_json = ? WHERE id = ?`, [
    JSON.stringify(aiJson),
    id,
  ]);
  const [updated] = await pool.query("SELECT * FROM usda_reports WHERE id = ?", [id]);
  return updated[0];
}

export function serialize(row) {
  const ai = row.ai_json || {};
  return {
    id: row.id,
    report_type: row.report_type,
    commodity: row.commodity,
    title: row.title,
    release_date: row.release_date.toISOString().slice(0, 10),
    ai_processed_at: row.ai_processed_at ? row.ai_processed_at.toISOString() : null,
    ai_headline: ai.headline ?? "",
    ai_direction: ai.direction ?? "NEUTRAL",
    ai_summary: ai.summary ?? "",
    ai_key_points: ai.keyPoints ?? [],
    commodity_impacts: [
      {
        commodity: row.commodity,
        direction: ai.direction ?? "NEUTRAL",
        reasoning: ai.reasoning ?? "",
        basis_impact: ai.basisImpact ?? "",
      },
    ],
    risk_factors: ai.riskFactors ?? [],
    basis_impact: ai.basisImpact ?? "",
    confidence: ai.confidence ?? 0.5,
    comparison_title: ai.comparisonTitle ?? "",
    comparison: ai.comparison ?? [],
    source: `${SOURCES.NASS.label} + ${SOURCES.ANTHROPIC.label} analysis`,
    as_of: row.ai_processed_at ? row.ai_processed_at.toISOString() : null,
  };
}
