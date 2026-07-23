import { Router } from "express";

import { asyncHandler } from "../asyncHandler.js";
import * as config from "../config.js";
import * as dailyBrief from "../dailyBrief.js";
import * as dailyBriefEmail from "../dailyBriefEmail.js";
import { decodeToken } from "../security.js";

export const router = Router();

function softUserId(req) {
  const header = req.headers.authorization;
  if (!header?.toLowerCase().startsWith("bearer ")) return null;
  try {
    return decodeToken(header.slice(7));
  } catch {
    return null;
  }
}

router.get("/daily-brief", asyncHandler(async (req, res) => {
  const userId = softUserId(req);
  const row = userId ? await dailyBrief.ensureForUser(userId) : await dailyBrief.ensureToday();
  res.json(dailyBrief.serialize(row));
}));

// Meant to be called once a day at 7:30 ET by an external scheduler
// (Cloud Run has no built-in cron) — not user-facing, hence the shared
// secret instead of a user session.
router.post("/daily-brief/send-now", asyncHandler(async (req, res) => {
  if (!config.CRON_SECRET || req.headers["x-cron-secret"] !== config.CRON_SECRET) {
    return res.status(401).json({ detail: "Not authorized" });
  }
  const result = await dailyBriefEmail.sendToAllSubscribers();
  res.json({ ok: true, ...result });
}));
