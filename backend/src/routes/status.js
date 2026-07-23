import { Router } from "express";

import { asyncHandler } from "../asyncHandler.js";
import * as statusCheck from "../statusCheck.js";

export const router = Router();

router.get("/status", asyncHandler(async (req, res) => {
  res.json(await statusCheck.checkAll());
}));

const STATE_LABEL = {
  operational: "Operational",
  stale: "Delayed",
  no_data: "No Data Yet",
  not_configured: "Not Configured",
};

const STATE_COLOR = {
  operational: "#3ddc84",
  stale: "#f5a623",
  no_data: "#8a8a8a",
  not_configured: "#8a8a8a",
};

function row(source) {
  const color = STATE_COLOR[source.state] ?? "#8a8a8a";
  const label = STATE_LABEL[source.state] ?? source.state;
  const lastUpdated = source.last_updated
    ? new Date(source.last_updated).toUTCString()
    : "—";
  return `
  <div class="row">
    <div class="dot" style="background:${color}"></div>
    <div class="row-main">
      <div class="row-title">${source.label}</div>
      <div class="row-detail">${source.detail}</div>
    </div>
    <div class="row-side">
      <div class="row-state" style="color:${color}">${label}</div>
      <div class="row-time">Last updated: ${lastUpdated}</div>
    </div>
  </div>`;
}

/** Public status page — no auth, so anyone can check whether a stale
 * number in the app is Croploo's fault or an upstream outage. */
export async function statusPage(req, res) {
  const sources = await statusCheck.checkAll();
  const allUp = sources.every((s) => s.state === "operational" || s.state === "not_configured");

  res.send(`<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<meta http-equiv="refresh" content="60" />
<title>Croploo Status</title>
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;600;700&display=swap" rel="stylesheet" />
<style>
  * { box-sizing: border-box; }
  body {
    margin: 0;
    min-height: 100vh;
    background: #000;
    color: #fff;
    font-family: 'Poppins', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
    display: flex;
    justify-content: center;
    padding: 56px 20px;
  }
  .wrap { width: 100%; max-width: 640px; }
  .logo { display: flex; align-items: center; gap: 10px; margin-bottom: 8px; }
  .logo-mark { width: 28px; height: 28px; }
  .logo-word { font-weight: 600; font-size: 15px; letter-spacing: 1.5px; }
  h1 { font-weight: 700; font-size: 22px; margin: 20px 0 6px; }
  .summary { font-size: 13px; color: #8a8a8a; margin-bottom: 32px; }
  .row {
    display: flex; align-items: center; gap: 14px;
    padding: 16px 0; border-top: 1px solid #1c1c1c;
  }
  .dot { width: 9px; height: 9px; border-radius: 50%; flex-shrink: 0; }
  .row-main { flex: 1; min-width: 0; }
  .row-title { font-weight: 600; font-size: 14px; }
  .row-detail { font-size: 12px; color: #8a8a8a; margin-top: 2px; }
  .row-side { text-align: right; flex-shrink: 0; }
  .row-state { font-weight: 600; font-size: 13px; }
  .row-time { font-size: 11px; color: #8a8a8a; margin-top: 2px; }
  .footer { margin-top: 32px; font-size: 11px; color: #555; }
</style>
</head>
<body>
  <div class="wrap">
    <div class="logo">
      <img class="logo-mark" src="/assets/img/croploo_logo.png" alt="Croploo" />
      <div class="logo-word">CROPLOO</div>
    </div>
    <h1>${allUp ? "All Systems Operational" : "Some Sources Delayed"}</h1>
    <div class="summary">Live status of every real data source Croploo depends on. Auto-refreshes every 60s.</div>
    ${sources.map(row).join("")}
    <div class="footer">Croploo checks each source's own cached data freshness against its normal refresh cadence — it does not spend API quota to render this page.</div>
  </div>
</body>
</html>`);
}
