import { Router } from "express";

import { asyncHandler } from "../asyncHandler.js";
import { requireAuth } from "../requireAuth.js";
import * as communityInsights from "../communityInsights.js";
import * as croplooLearn from "../croplooLearn.js";
import * as newsletter from "../newsletter.js";
import * as publicProfiles from "../publicProfiles.js";

export const router = Router();

// ── Community Insights Feed ─────────────────────────────────────────

router.get("/community-insights", requireAuth, asyncHandler(async (req, res) => {
  const commodity = typeof req.query.commodity === "string" ? req.query.commodity : undefined;
  res.json(await communityInsights.list({ commodity }));
}));

router.post("/community-insights", requireAuth, asyncHandler(async (req, res) => {
  const { commodity, body } = req.body ?? {};
  res.json(await communityInsights.create(req.user.id, { commodity, body }));
}));

// ── Croploo Learn ─────────────────────────────────────────────────────

router.get("/learn", asyncHandler(async (req, res) => {
  res.json(await croplooLearn.list());
}));

router.get("/learn/:slug", asyncHandler(async (req, res) => {
  res.json(await croplooLearn.get(req.params.slug));
}));

// ── Croploo Signals Newsletter ────────────────────────────────────────

router.get("/newsletter/latest", asyncHandler(async (req, res) => {
  res.json(await newsletter.latestIssue());
}));

// No auth required — a visitor with no Croploo account can subscribe.
router.post("/newsletter/subscribe", asyncHandler(async (req, res) => {
  await newsletter.subscribe(req.body?.email);
  res.json({ status: "subscribed" });
}));

router.post("/newsletter/unsubscribe", asyncHandler(async (req, res) => {
  await newsletter.unsubscribe(req.body?.email);
  res.json({ status: "unsubscribed" });
}));

// Triggered by a daily cron hitting this with X-Cron-Secret, same
// pattern as the daily-brief send-now endpoint — sends at most once a
// week since sendWeeklyIssue() no-ops if this week's issue already sent.
router.post("/newsletter/send", asyncHandler(async (req, res) => {
  res.json(await newsletter.sendWeeklyIssue());
}));

// ── Public Profiles ──────────────────────────────────────────────────

router.get("/profile/me", requireAuth, asyncHandler(async (req, res) => {
  res.json(await publicProfiles.getMine(req.user.id));
}));

router.put("/profile/me", requireAuth, asyncHandler(async (req, res) => {
  const { username, is_public, tracked_commodities } = req.body ?? {};
  res.json(
    await publicProfiles.upsert(req.user.id, {
      username,
      isPublic: is_public,
      trackedCommodities: tracked_commodities,
    })
  );
}));

// Public — no auth. This is the endpoint a future croploo.app/u/<username>
// web page would call; see publicProfiles.js's doc comment.
router.get("/profile/:username", asyncHandler(async (req, res) => {
  try {
    res.json(await publicProfiles.getPublic(req.params.username));
  } catch (err) {
    if (err instanceof publicProfiles.PublicProfileError) {
      return res.status(404).json({ detail: err.message });
    }
    throw err;
  }
}));
