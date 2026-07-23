import { Router } from "express";

import { asyncHandler } from "../asyncHandler.js";
import { pool } from "../db.js";
import { requireAuth } from "../requireAuth.js";
import { decodeToken } from "../security.js";
import * as decisionLog from "../decisionLog.js";
import { FONT_FACES, FONT_UI, FONT_DATA } from "../webFonts.js";

export const router = Router();

/**
 * Like requireAuth, but also accepts the token as ?token=... — needed
 * because the compliance export link is opened in the system browser
 * (via url_launcher), which can't attach an Authorization header.
 */
async function requireAuthViaHeaderOrQuery(req, res, next) {
  const header = req.headers.authorization;
  const queryToken = typeof req.query.token === "string" ? req.query.token : null;
  const token = header?.toLowerCase().startsWith("bearer ")
    ? header.slice(7)
    : queryToken;
  if (!token) return res.status(401).json({ detail: "Not authenticated" });

  let userId;
  try {
    userId = decodeToken(token);
  } catch {
    return res.status(401).json({ detail: "Invalid token" });
  }
  const [rows] = await pool.query("SELECT * FROM users WHERE id = ?", [userId]);
  if (!rows[0]) return res.status(401).json({ detail: "User not found" });
  req.user = rows[0];
  next();
}

router.get("/decision-log", requireAuth, asyncHandler(async (req, res) => {
  res.json(await decisionLog.list(req.user.id));
}));

router.post("/decision-log", requireAuth, asyncHandler(async (req, res) => {
  const { commodity, user_note, cullyai_context } = req.body ?? {};
  const entry = await decisionLog.create(req.user.id, {
    commodity,
    userNote: user_note,
    cullyaiContext: cullyai_context,
  });
  res.json(entry);
}));

function escapeHtml(s) {
  return String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function changePct(from, to) {
  if (from == null || to == null || from === 0) return null;
  return (((to - from) / from) * 100).toFixed(1);
}

/**
 * Compliance Export — a printable HTML report of the user's decision
 * log (browser "Print to PDF" produces the actual PDF; there's no PDF
 * library in this backend, so this is the honest equivalent rather
 * than a fake binary). Suitable for a compliance department's records:
 * "On <date> CullyAI's context was X. The user logged Y."
 */
function changeCell(value, pct) {
  if (value == null) return `<td class="mono">—</td>`;
  const color = pct == null ? "" : pct >= 0 ? "positive" : "negative";
  const pctText = pct != null ? ` (${pct >= 0 ? "+" : ""}${pct}%)` : "";
  return `<td class="mono ${color}">${value}${pctText}</td>`;
}

router.get("/decision-log/compliance-export", requireAuthViaHeaderOrQuery, asyncHandler(async (req, res) => {
  const entries = await decisionLog.list(req.user.id);
  const rows = entries
    .map((e) => {
      const r7 = changePct(e.price_at_log, e.price_7d);
      const r30 = changePct(e.price_at_log, e.price_30d);
      return `<tr>
        <td class="mono">${new Date(e.created_at).toISOString().slice(0, 10)}</td>
        <td>${escapeHtml(e.commodity)}</td>
        <td>${escapeHtml(e.cullyai_context) || "—"}</td>
        <td>${escapeHtml(e.user_note)}</td>
        <td class="mono">${e.price_at_log ?? "—"}</td>
        ${changeCell(e.price_7d, r7)}
        ${changeCell(e.price_30d, r30)}
      </tr>`;
    })
    .join("\n");

  res.send(`<!DOCTYPE html>
<html><head><meta charset="utf-8" />
<title>Croploo Decision Log — Compliance Export</title>
<style>
  ${FONT_FACES}
  * { box-sizing: border-box; }
  body { margin: 0; font-family: ${FONT_UI}; color: #0A0A0A; background: #fff; }
  .masthead { background: #0A0A0A; padding: 26px 40px; display: flex; align-items: center; gap: 12px; }
  .masthead img { width: 30px; height: 30px; }
  .masthead .title { color: #B5B5B5; font-size: 11px; font-weight: 500; letter-spacing: 1.2px; }
  .body { padding: 32px 40px; }
  h1 { font-size: 18px; font-weight: 600; margin: 0 0 6px; }
  p.meta { color: #6B6B6B; font-size: 12px; margin-bottom: 24px; }
  table { width: 100%; border-collapse: collapse; font-size: 12px; }
  th { text-align: left; font-weight: 500; color: #6B6B6B; font-size: 10.5px; letter-spacing: 0.5px;
    text-transform: uppercase; padding: 8px 10px; border-bottom: 1px solid #E4E4E4; }
  td { padding: 10px; border-bottom: 1px solid #E4E4E4; vertical-align: top; }
  td.mono, th.mono { font-family: ${FONT_DATA}; }
  td.positive { color: #16A34A; }
  td.negative { color: #DC2626; }
  @media print { .masthead { background: #0A0A0A !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; } }
</style>
</head><body>
  <div class="masthead">
    <img src="/assets/img/croploo_logo.png" alt="Croploo" />
    <div class="title">DECISION LOG — COMPLIANCE EXPORT</div>
  </div>
  <div class="body">
    <h1>Croploo Decision Log</h1>
    <p class="meta">User: ${escapeHtml(req.user.email)} · Generated: ${new Date().toISOString()} ·
      ${entries.length} entries. Use your browser's Print → Save as PDF for a PDF copy.</p>
    <table>
      <thead><tr>
        <th>Date</th><th>Commodity</th><th>CullyAI Context</th><th>User Decision</th>
        <th class="mono">Price at Log</th><th class="mono">+7D</th><th class="mono">+30D</th>
      </tr></thead>
      <tbody>${rows || '<tr><td colspan="7">No entries yet.</td></tr>'}</tbody>
    </table>
  </div>
</body></html>`);
}));
