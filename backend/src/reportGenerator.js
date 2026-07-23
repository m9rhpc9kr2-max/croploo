/**
 * Weekly market report PDF — real data only, pulled from tables already
 * populated elsewhere in the app (futures_prices, basis_snapshots,
 * wasde_surprises, cot_reports). No new data source, just a PDF rendering
 * of numbers that already exist. Uses pdfkit (added as a new dependency —
 * this backend had no PDF library before).
 *
 * Styled to match the app's own design language: Poppins for headings/body,
 * JetBrains Mono for every number (see lib/core/theme/typography.dart —
 * "data ALWAYS monospace" is an explicit rule there too), green/red for
 * positive/negative, sharp rectangles (no rounded corners).
 */
import path from "node:path";
import { fileURLToPath } from "node:url";
import PDFDocument from "pdfkit";
import { pool } from "./db.js";
import * as cotData from "./cotData.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const FONT_DIR = path.join(__dirname, "assets", "fonts");
const LOGO_PATH = path.join(__dirname, "assets", "img", "croploo_white.png");

const INK = "#0A0A0A";
const MUTED = "#6B6B6B";
const FAINT = "#A6A6A6";
const LINE = "#E4E4E4";
const POSITIVE = "#16A34A";
const NEGATIVE = "#DC2626";
const PAGE_MARGIN = 48;

function registerFonts(doc) {
  doc.registerFont("Heading", path.join(FONT_DIR, "Poppins-Bold.ttf"));
  doc.registerFont("Sub", path.join(FONT_DIR, "Poppins-SemiBold.ttf"));
  doc.registerFont("Body", path.join(FONT_DIR, "Poppins-Medium.ttf"));
  doc.registerFont("BodyRegular", path.join(FONT_DIR, "Poppins-Regular.ttf"));
  doc.registerFont("Mono", path.join(FONT_DIR, "JetBrainsMono-SemiBold.ttf"));
  doc.registerFont("MonoRegular", path.join(FONT_DIR, "JetBrainsMono-Regular.ttf"));
}

async function latestFutures() {
  const [rows] = await pool.query("SELECT * FROM futures_prices ORDER BY symbol");
  return rows;
}

async function latestBasisBySymbol() {
  const [rows] = await pool.query(
    `SELECT symbol, AVG(basis) AS avg_basis, MAX(snapshot_date) AS as_of, COUNT(*) AS state_count
     FROM basis_snapshots
     WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM basis_snapshots b2 WHERE b2.symbol = basis_snapshots.symbol)
     GROUP BY symbol`
  );
  return rows;
}

async function latestWasdeSurprises() {
  const out = [];
  for (const commodity of ["CORN", "WHEAT", "SOYBEANS"]) {
    const [rows] = await pool.query(
      `SELECT * FROM wasde_surprises WHERE commodity = ? ORDER BY release_date DESC LIMIT 1`,
      [commodity]
    );
    if (rows[0]) out.push(rows[0]);
  }
  return out;
}

function asDateString(value) {
  return value instanceof Date ? value.toISOString().slice(0, 10) : String(value);
}

function pageWidth(doc) {
  return doc.page.width - PAGE_MARGIN * 2;
}

/** Black masthead band with the Croploo logo mark and report date/title. */
function drawMasthead(doc) {
  const bandHeight = 132;
  const logoSize = 56;
  const titleX = PAGE_MARGIN + logoSize + 18;
  doc.rect(0, 0, doc.page.width, bandHeight).fill(INK);
  doc.rect(0, bandHeight - 3, doc.page.width, 3).fill("#FFFFFF");
  doc.image(LOGO_PATH, PAGE_MARGIN, 38, { width: logoSize, height: logoSize });

  doc
    .font("Heading")
    .fontSize(16)
    .fillColor("#FFFFFF")
    .text("CROPLOO", titleX, 48, {
      characterSpacing: 2.4,
      lineBreak: false,
    });

  doc
    .font("Body")
    .fontSize(8)
    .fillColor("#A6A6A6")
    .text("MARKET INTELLIGENCE", titleX, 71, {
      characterSpacing: 1.4,
      lineBreak: false,
    });

  doc
    .font("Body")
    .fontSize(10)
    .fillColor("#FFFFFF")
    .text("WEEKLY MARKET REPORT", PAGE_MARGIN, 104, {
      characterSpacing: 1.3,
      lineBreak: false,
    });

  doc
    .font("MonoRegular")
    .fontSize(9)
    .fillColor("#A6A6A6")
    .text(new Date().toISOString().slice(0, 10), PAGE_MARGIN, 104, {
      width: pageWidth(doc),
      align: "right",
    });

  doc.y = bandHeight + 34;
}

/** Section header: small uppercase tag + title, thin rule underneath. */
function drawSectionHeader(doc, tag, title) {
  if (doc.y > doc.page.height - 140) doc.addPage();
  doc.moveDown(0.6);
  doc
    .font("Body")
    .fontSize(9)
    .fillColor(MUTED)
    .text(tag.toUpperCase(), PAGE_MARGIN, doc.y, { characterSpacing: 1 });
  doc.moveDown(0.15);
  doc.font("Sub").fontSize(15).fillColor(INK).text(title, PAGE_MARGIN, doc.y);
  doc.moveDown(0.4);
  const ruleY = doc.y;
  doc.moveTo(PAGE_MARGIN, ruleY).lineTo(PAGE_MARGIN + pageWidth(doc), ruleY).lineWidth(1).strokeColor(LINE).stroke();
  doc.moveDown(0.6);
}

/** One data row: label left, monospace value right, optional color for the value. */
function drawRow(doc, label, value, { color = INK, sub } = {}) {
  const y = doc.y;
  const width = pageWidth(doc);
  doc.font("BodyRegular").fontSize(10.5).fillColor(INK).text(label, PAGE_MARGIN, y, {
    width: width * 0.55,
  });
  doc.font("Mono").fontSize(10.5).fillColor(color).text(value, PAGE_MARGIN + width * 0.55, y, {
    width: width * 0.45,
    align: "right",
  });
  if (sub) {
    doc.moveDown(0.05);
    doc
      .font("MonoRegular")
      .fontSize(8.5)
      .fillColor(FAINT)
      .text(sub, PAGE_MARGIN + width * 0.55, doc.y, { width: width * 0.45, align: "right" });
  }
  doc.moveDown(0.55);
}

function drawEmpty(doc, text) {
  doc.font("BodyRegular").fontSize(10).fillColor(FAINT).text(text, PAGE_MARGIN);
  doc.moveDown(0.6);
}

/**
 * Builds a weekly market report PDF and pipes it to `res` (must have
 * `Content-Type: application/pdf` already set by the caller).
 */
export async function renderWeeklyReport(res) {
  const [futures, basis, wasde, cot] = await Promise.all([
    latestFutures(),
    latestBasisBySymbol(),
    latestWasdeSurprises(),
    cotData.ensureLatest().catch(() => null),
  ]);
  renderReportFromData(res, { futures, basis, wasde, cot });
}

/**
 * Pure rendering step, split out from renderWeeklyReport() so the layout
 * can be exercised with fixture data (see scratchpad test scripts) without
 * a live database connection.
 */
export function renderReportFromData(res, { futures, basis, wasde, cot }) {
  const doc = new PDFDocument({ size: "LETTER", margin: PAGE_MARGIN });
  registerFonts(doc);
  doc.pipe(res);

  drawMasthead(doc);

  drawSectionHeader(doc, "Futures", "Futures Prices");
  if (futures.length === 0) {
    drawEmpty(doc, "No futures data cached yet.");
  }
  for (const f of futures) {
    const up = f.change >= 0;
    drawRow(doc, `${f.symbol}  ${f.name}`, `$${f.price.toFixed(2)}`, {
      color: up ? POSITIVE : NEGATIVE,
      sub: `${up ? "+" : ""}${f.change.toFixed(2)}  (${f.change_pct.toFixed(2)}%)`,
    });
  }

  drawSectionHeader(doc, "Basis", "Basis Snapshot — state average");
  if (basis.length === 0) {
    drawEmpty(doc, "No basis data cached yet.");
  }
  for (const b of basis) {
    drawRow(doc, `${b.symbol}`, `${b.avg_basis.toFixed(2)}¢`, {
      color: b.avg_basis >= 0 ? POSITIVE : NEGATIVE,
      sub: `avg across ${b.state_count} states · as of ${asDateString(b.as_of)}`,
    });
  }

  drawSectionHeader(doc, "USDA", "Latest WASDE Surprises");
  if (wasde.length === 0) {
    drawEmpty(doc, "No WASDE surprise records yet.");
  }
  for (const w of wasde) {
    drawRow(doc, `${w.commodity}  ${w.metric}`, `${w.surprise_pct >= 0 ? "+" : ""}${w.surprise_pct.toFixed(1)}%`, {
      color: w.surprise_pct >= 0 ? POSITIVE : NEGATIVE,
      sub:
        `released ${asDateString(w.release_date)}` +
        (w.price_1w != null ? ` · 1w reaction ${w.price_1w.toFixed(2)}` : ""),
    });
  }

  drawSectionHeader(doc, "CFTC", "COT Positioning — Managed Money");
  if (!cot) {
    drawEmpty(doc, "COT data unavailable.");
  } else {
    for (const snap of cot.snapshots) {
      drawRow(doc, `${snap.commodity}`, `net ${snap.managedMoney.net}`, {
        color: snap.managedMoney.net >= 0 ? POSITIVE : NEGATIVE,
        sub: `${snap.netPercentile3y}th pct (3y) · ${snap.contrarianSignal.replaceAll("_", " ")}`,
      });
    }
  }

  doc.moveDown(1);
  doc
    .moveTo(PAGE_MARGIN, doc.y)
    .lineTo(PAGE_MARGIN + pageWidth(doc), doc.y)
    .lineWidth(1)
    .strokeColor(LINE)
    .stroke();
  doc.moveDown(0.5);
  doc
    .font("BodyRegular")
    .fontSize(8)
    .fillColor(FAINT)
    .text(
      "All figures are real cached values from Croploo's live data sources (Alpha Vantage, USDA AMS/NASS, CFTC). " +
        "No figures on this report are AI-generated or estimated.",
      PAGE_MARGIN,
      doc.y,
      { width: pageWidth(doc) }
    );

  doc.end();
}
