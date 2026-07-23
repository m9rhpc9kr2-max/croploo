import { Router } from "express";

import { asyncHandler } from "../asyncHandler.js";
import { pool } from "../db.js";
import { requireAuth } from "../requireAuth.js";
import { decodeToken } from "../security.js";
import { agenticComplete as anthropicAgenticComplete } from "../anthropicClient.js";
import { agenticComplete as geminiAgenticComplete } from "../geminiClient.js";
import { AI_TOOLS, AI_TOOL_EXECUTORS } from "../aiTools.js";
import * as memory from "../cullyaiMemory.js";
import * as synthesis from "../crossAssetSynthesis.js";
import * as reportGenerator from "../reportGenerator.js";
import * as config from "../config.js";

export const router = Router();

/**
 * Like requireAuth, but also accepts the token as ?token=... — the weekly
 * report link is opened directly (browser download / url_launcher), which
 * can't attach an Authorization header. Mirrors decisionLog.js's helper.
 */
async function requireAuthViaHeaderOrQuery(req, res, next) {
  const header = req.headers.authorization;
  const queryToken = typeof req.query.token === "string" ? req.query.token : null;
  const token = header?.toLowerCase().startsWith("bearer ") ? header.slice(7) : queryToken;
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

// `null` means unlimited (Pro/Desk). Free/Basic get 3 messages/day.
const DAILY_LIMITS = { free: 3, basic: 3, pro: null, desk: null };
const HOURLY_LIMIT = 60;

// In-memory sliding window — fine at this app's single-instance Cloud Run
// scale; the daily cap (the limit that actually matters commercially) is
// enforced durably via cullyai_usage instead.
const hourlyHits = new Map();

function systemPrompt(user, ctx) {
  const today = new Date().toISOString().slice(0, 10);
  let prompt =
    "You are CullyAI, expert in US grain markets (corn, wheat, soybeans), " +
    "CBOT futures, basis trading, USDA reports, and freight. Be concise, " +
    "data-focused. Never give financial advice. " +
    `Date: ${today}. User plan: ${user.subscription_tier}. ` +
    "You have read-only query tools for real basis history, futures history, " +
    "WASDE surprise history, COT positioning, and seasonal patterns — use them " +
    "whenever a question needs specific numbers or a time series; never invent " +
    "data. Call render_chart to show a chart when a time series or comparison " +
    "is genuinely clearer visually, using only real data you already pulled " +
    "via a query tool. Don't render a chart for simple one-number answers. " +
    "For 'should I sell/hold' or multi-factor questions: pull each relevant " +
    "signal (basis, COT, seasonal, WASDE) with its own tool call, state what " +
    "each one implies on its own, then combine them into one recommendation " +
    "with an explicit confidence level — don't skip straight to a verdict. " +
    "For 'what if' scenario questions, use query_wasde_surprises to find the " +
    "closest real historical surprise of similar magnitude and report its " +
    "actual reaction — if there's no real historical basis for a scenario " +
    "(e.g. an event type you have no data for), say so plainly instead of " +
    "guessing. For comparisons between two time periods, use compare_periods " +
    "rather than eyeballing two separate history calls. For backtest requests, " +
    "use run_backtest and always state the sample size and date range so the " +
    "user can judge confidence. For portfolio stress questions, use " +
    "stress_test_portfolio — it already operates on the user's own real " +
    "positions.";
  if (ctx?.lastCommodities?.length) {
    prompt +=
      ` This user has previously asked about: ${ctx.lastCommodities.join(", ")}. ` +
      "Use that only if relevant to the current question — don't force it in.";
  }
  return prompt;
}

async function withinDailyLimit(user) {
  const limit = DAILY_LIMITS[user.subscription_tier] ?? null;
  if (limit === null) return true;

  const today = new Date().toISOString().slice(0, 10);
  const [rows] = await pool.query(
    "SELECT message_count FROM cullyai_usage WHERE user_id = ? AND date = ?",
    [user.id, today]
  );
  return (rows[0]?.message_count ?? 0) < limit;
}

async function recordUsage(userId) {
  const today = new Date().toISOString().slice(0, 10);
  await pool.query(
    `INSERT INTO cullyai_usage (user_id, message_count, date)
     VALUES (?, 1, ?)
     ON DUPLICATE KEY UPDATE message_count = message_count + 1`,
    [userId, today]
  );
}

function withinHourlyLimit(userId) {
  const now = Date.now();
  const hits = (hourlyHits.get(userId) ?? []).filter((t) => now - t < 3_600_000);
  hourlyHits.set(userId, hits);
  if (hits.length >= HOURLY_LIMIT) return false;
  hits.push(now);
  return true;
}

router.post("/chat", requireAuth, asyncHandler(async (req, res) => {
  const messages = Array.isArray(req.body?.messages) ? req.body.messages : [];
  if (messages.length === 0) {
    return res.status(400).json({ detail: "messages must be a non-empty array" });
  }

  if (!withinHourlyLimit(req.user.id)) {
    return res.status(429).json({ detail: "Hourly rate limit exceeded" });
  }
  if (!(await withinDailyLimit(req.user))) {
    return res.status(429).json({ upgrade: true, detail: "Daily message limit reached" });
  }

  res.setHeader("Content-Type", "text/event-stream");
  res.setHeader("Cache-Control", "no-cache, no-transform");
  res.setHeader("Connection", "keep-alive");
  res.setHeader("X-Accel-Buffering", "no");
  res.flushHeaders();
  // A transient status label, not part of the reply text — the client
  // shows it next to the thinking animation and clears it the moment the
  // first real `delta` arrives (see live_repository.dart / providers.dart).
  // Previously this was sent as a `delta` itself, which permanently baked
  // "Checking live market data…" into the start of every reply.
  res.write(`data: ${JSON.stringify({ status: "Checking live market data…" })}\n\n`);

  const anthropicMessages = messages.map((m) => ({
    role: m.role === "assistant" ? "assistant" : "user",
    content: String(m.content ?? ""),
  }));
  const lastUserText = anthropicMessages[anthropicMessages.length - 1]?.content ?? "";
  let fullReply = "";

  // Overall watchdog: agenticComplete already bounds each Anthropic/Gemini
  // call (60s) and each tool call (20s, see anthropicClient.js /
  // geminiClient.js), but this is a last line of defense so an unforeseen
  // hang always ends the SSE stream with a visible error instead of leaving
  // the client stuck on "Checking live market data…" forever.
  const CHAT_TIMEOUT_MS = 150000;

  function runProvider(agenticComplete, memoryCtx, toolCtx) {
    return Promise.race([
      agenticComplete({
        system: systemPrompt(req.user, memoryCtx),
        messages: anthropicMessages,
        tools: AI_TOOLS,
        executeTool: (name, input) => {
          const executor = AI_TOOL_EXECUTORS[name];
          if (!executor) throw new Error(`Unknown tool: ${name}`);
          return executor(input, toolCtx);
        },
        onEvent: (event) => {
          if (event.type === "text") {
            fullReply += event.delta;
            res.write(`data: ${JSON.stringify({ delta: event.delta })}\n\n`);
          } else if (event.type === "block") {
            res.write(`data: ${JSON.stringify({ block: event.block })}\n\n`);
          }
        },
      }),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error("CullyAI chat timed out")), CHAT_TIMEOUT_MS)
      ),
    ]);
  }

  try {
    const memoryCtx = await memory.context(req.user.id);
    const toolCtx = { userId: req.user.id };
    try {
      await runProvider(anthropicAgenticComplete, memoryCtx, toolCtx);
    } catch (err) {
      // Fall back to Gemini only if Claude hasn't produced any real content
      // yet this turn (e.g. it was rate-limited or errored before/during
      // its first response) — never switch models mid-answer, and only if
      // a Gemini key is actually configured.
      if (fullReply.length > 0 || !config.GEMINI_API_KEY) throw err;
      console.error("CullyAI: Anthropic failed, falling back to Gemini:", err.message);
      await runProvider(geminiAgenticComplete, memoryCtx, toolCtx);
    }
    await recordUsage(req.user.id);
    if (lastUserText && fullReply) {
      await memory.recordTurn(req.user.id, lastUserText, fullReply).catch((err) =>
        console.error("cullyai memory write failed:", err)
      );
    }
    res.write("data: [DONE]\n\n");
  } catch (err) {
    console.error(err);
    res.write(`data: ${JSON.stringify({ error: "CullyAI is temporarily unavailable" })}\n\n`);
  } finally {
    res.end();
  }
}));

// Prior-session recall: recent turns + a "welcome back" nudge if the
// user's last conversation was more than half a day ago.
router.get("/context", requireAuth, asyncHandler(async (req, res) => {
  const [history, welcomeBack] = await Promise.all([
    memory.recentHistory(req.user.id),
    memory.welcomeBack(req.user.id),
  ]);
  res.json({ history, welcome_back: welcomeBack });
}));

// Cross-asset synthesis: dollar/crude/yield-curve/WASDE combined into
// one net-effect read per commodity — see src/crossAssetSynthesis.js.
router.get("/synthesis", requireAuth, asyncHandler(async (req, res) => {
  res.json(await synthesis.snapshot());
}));

// Weekly market report PDF — real cached data only, see reportGenerator.js.
// requireAuthViaHeaderOrQuery so it can be opened as a direct download link.
router.get("/report/weekly", requireAuthViaHeaderOrQuery, asyncHandler(async (req, res) => {
  res.setHeader("Content-Type", "application/pdf");
  res.setHeader("Content-Disposition", "inline; filename=croploo-weekly-report.pdf");
  await reportGenerator.renderWeeklyReport(res);
}));
