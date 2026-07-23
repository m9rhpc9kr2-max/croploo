import { Router } from "express";

import { asyncHandler } from "../asyncHandler.js";
import * as config from "../config.js";
import { ELEVATORS } from "../elevators.js";
import * as usdaBasis from "../usdaBasis.js";

export const router = Router();

const STATE_NAMES = {
  IL: "Illinois",
  IA: "Iowa",
  MN: "Minnesota",
  IN: "Indiana",
  OH: "Ohio",
  KS: "Kansas",
};

/**
 * Free, embeddable `<iframe>` widget elevators can drop on their own
 * site to show a live basis number — free advertising for Croploo every
 * time someone asks "where does this data come from". No auth, no
 * X-Frame-Options set anywhere in this app, so it embeds cleanly.
 */
router.get("/widget/basis", asyncHandler(async (req, res) => {
  const state = String(req.query.state || "IL").toUpperCase();
  const symbol = String(req.query.commodity || "ZC").toUpperCase();

  if (!usdaBasis.SYMBOL_NAMES[symbol]) {
    return res.status(404).send("Unknown commodity");
  }
  if (!ELEVATORS.some((e) => e.state === state)) {
    return res.status(404).send("Unknown state");
  }

  await usdaBasis.ensureFresh([state], [symbol]);
  const snap = await usdaBasis.latest(state, symbol);
  const avg = await usdaBasis.avg5yr(state, symbol);

  res.send(renderWidget({ state, symbol, snap, avg }));
}));

function renderWidget({ state, symbol, snap, avg }) {
  const commodity = usdaBasis.SYMBOL_NAMES[symbol];
  const stateName = STATE_NAMES[state] ?? state;

  if (!snap) {
    return widgetShell(`
      <div class="empty">No basis data yet for ${commodity} in ${stateName}.</div>
    `);
  }

  const deviation = avg ? snap.basis - avg : 0;
  const color = Math.abs(deviation) < 8 ? "#8a8a8a" : deviation > 0 ? "#3ddc84" : "#ff5c5c";
  const sign = snap.basis >= 0 ? "+" : "";
  const asOf = new Date(snap.snapshot_date).toDateString();

  return widgetShell(`
    <div class="label">${stateName} ${commodity} Basis</div>
    <div class="value" style="color:${color}">${sign}${snap.basis.toFixed(1)}¢<span class="unit">/bu</span></div>
    <div class="sub">vs 5yr avg: ${avg ? `${avg.toFixed(1)}¢` : "—"}</div>
    <div class="asof">USDA AMS AgTransport · as of ${asOf}</div>
  `);
}

function widgetShell(innerHtml) {
  return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<meta http-equiv="refresh" content="300" />
<title>Croploo Basis Widget</title>
<style>
  * { box-sizing: border-box; }
  html, body {
    margin: 0; padding: 0; background: #0a0a0a; color: #fff;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  }
  .card {
    padding: 16px 20px; border: 1px solid #262626; border-radius: 6px;
  }
  .label { font-size: 11px; letter-spacing: 1px; color: #8a8a8a; text-transform: uppercase; }
  .value { font-size: 30px; font-weight: 700; margin-top: 6px; font-variant-numeric: tabular-nums; }
  .unit { font-size: 15px; font-weight: 500; color: #8a8a8a; margin-left: 2px; }
  .sub { font-size: 12px; color: #8a8a8a; margin-top: 4px; }
  .asof { font-size: 10px; color: #555; margin-top: 10px; }
  .empty { font-size: 13px; color: #8a8a8a; padding: 8px 0; }
  .footer { margin-top: 10px; padding-top: 10px; border-top: 1px solid #1c1c1c; }
  .footer a { font-size: 11px; color: #666; text-decoration: none; }
  .footer a:hover { color: #999; }
</style>
</head>
<body>
  <div class="card">
    ${innerHtml}
    <div class="footer"><a href="${config.APP_URL}" target="_blank" rel="noopener">Powered by Croploo →</a></div>
  </div>
</body>
</html>`;
}
