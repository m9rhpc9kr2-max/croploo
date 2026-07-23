import path from "node:path";
import { fileURLToPath } from "node:url";
import cors from "cors";
import express from "express";

import { asyncHandler } from "./asyncHandler.js";
import * as config from "./config.js";
import { router as authRouter } from "./routes/auth.js";
import {
  cancelPage,
  router as billingRouter,
  successPage,
  webhookHandler,
} from "./routes/billing.js";
import { router as marketRouter } from "./routes/market.js";
import { router as basisRouter } from "./routes/basis.js";
import { router as cullyaiRouter } from "./routes/cullyai.js";
import { router as alertsRouter } from "./routes/alerts.js";
import { router as freightRouter } from "./routes/freight.js";
import { router as usdaRouter } from "./routes/usda.js";
import { router as dailyBriefRouter } from "./routes/dailyBrief.js";
import { router as intelRouter } from "./routes/intel.js";
import { router as macroRouter } from "./routes/macro.js";
import { router as analyticsRouter } from "./routes/analytics.js";
import { router as stocksRouter } from "./routes/stocks.js";
import { router as decisionLogRouter } from "./routes/decisionLog.js";
import { router as customDashboardsRouter } from "./routes/customDashboards.js";
import { router as growthRouter } from "./routes/growth.js";
import { router as watchlistRouter } from "./routes/watchlist.js";
import { router as customAlertRulesRouter } from "./routes/customAlertRules.js";
import { router as priceTargetsRouter } from "./routes/priceTargets.js";
import { router as portfolioRouter } from "./routes/portfolio.js";
import { router as statusRouter, statusPage } from "./routes/status.js";
import { router as widgetRouter } from "./routes/widget.js";
import { router as teamsRouter, handleSeatPayment } from "./routes/teams.js";
import { router as apiKeysRouter } from "./routes/apiKeys.js";
import { router as publicApiRouter } from "./routes/publicApi.js";
import { initializeDatabase } from "./db.js";

const app = express();
app.use(cors());

// Serves src/assets/{fonts,img} — the same Poppins/JetBrains Mono/logo
// assets used by the PDF report generator, so every server-rendered HTML
// page (status, billing, compliance export) can reference the real brand
// fonts via @font-face instead of hoping the visitor's OS has them.
const __dirname = path.dirname(fileURLToPath(import.meta.url));
app.use("/assets", express.static(path.join(__dirname, "assets")));

// Stripe signature verification needs the exact raw body, so this route
// must be registered before the global express.json() parser.
app.post("/v1/billing/webhook", express.raw({ type: "application/json" }), webhookHandler);

app.use(express.json());

app.get("/health", (req, res) => res.json({ status: "ok" }));
app.get("/billing/success", asyncHandler(successPage));
app.get("/billing/cancel", cancelPage);
app.get("/status", asyncHandler(statusPage));
app.use(widgetRouter);

const v1 = express.Router();
v1.use("/auth", authRouter);
v1.use("/billing", billingRouter);
v1.use("/cullyai", cullyaiRouter);
v1.use(marketRouter);
v1.use(basisRouter);
v1.use(alertsRouter);
v1.use(freightRouter);
v1.use(usdaRouter);
v1.use(dailyBriefRouter);
v1.use(intelRouter);
v1.use(macroRouter);
v1.use(analyticsRouter);
v1.use(stocksRouter);
v1.use(decisionLogRouter);
v1.use(customDashboardsRouter);
v1.use(growthRouter);
v1.use(watchlistRouter);
v1.use(customAlertRulesRouter);
v1.use(priceTargetsRouter);
v1.use(portfolioRouter);
v1.use(statusRouter);
v1.use(teamsRouter);
v1.use("/api-keys", apiKeysRouter);
v1.use("/public", publicApiRouter);
app.use("/v1", v1);

app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ detail: "Internal server error" });
});

const server = app.listen(config.PORT, () => {
  console.log(`Croploo API (Node) listening on http://localhost:${config.PORT}`);
});

// Initialize database after server starts
initializeDatabase().catch(err => {
  console.error("Database initialization failed:", err);
});

export default server;
