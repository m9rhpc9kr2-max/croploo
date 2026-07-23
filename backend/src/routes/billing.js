import { Router } from "express";

import { asyncHandler } from "../asyncHandler.js";
import * as config from "../config.js";
import { pool } from "../db.js";
import { requireAuth } from "../requireAuth.js";
import { getOrCreateFoundingMemberCouponId, getOrCreatePriceId, stripe } from "../stripeClient.js";
import * as referrals from "../referrals.js";
import { handleSeatPayment } from "./teams.js";

export const router = Router();

router.post(
  "/checkout",
  requireAuth,
  asyncHandler(async (req, res) => {
    if (!stripe) {
      return res.status(503).json({ detail: "Stripe is not configured" });
    }
    const { tier } = req.body ?? {};
    if (!config.PLANS[tier]) {
      return res.status(400).json({ detail: `Unknown plan: ${tier}` });
    }

    const user = req.user;

    // Check if user is grandfathered (created before price increase)
    const isGrandfathered = user.created_at < config.GRANDFATHER_CUTOFF;
    const priceId = await getOrCreatePriceId(tier, isGrandfathered);

    const discounts = user.founding_member
      ? [{ coupon: await getOrCreateFoundingMemberCouponId() }]
      : undefined;

    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      customer_email: user.email,
      client_reference_id: String(user.id),
      line_items: [{ price: priceId, quantity: 1 }],
      discounts,
      metadata: { tier, userId: String(user.id), grandfathered: String(isGrandfathered) },
      subscription_data: { metadata: { tier, userId: String(user.id), grandfathered: String(isGrandfathered) } },
      success_url: `${config.APP_URL}/billing/success?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${config.APP_URL}/billing/cancel`,
    });

    res.json({ url: session.url });
  })
);

const TRIAL_DAYS = 14;

router.post(
  "/start-trial",
  requireAuth,
  asyncHandler(async (req, res) => {
    const user = req.user;
    if (user.has_used_trial) {
      return res.status(400).json({ detail: "Trial already used" });
    }
    if (user.subscription_tier !== "free") {
      return res.status(400).json({ detail: "Already on a paid plan" });
    }

    const trialEndsAt = new Date(Date.now() + TRIAL_DAYS * 24 * 60 * 60 * 1000);
    await pool.query(
      "UPDATE users SET subscription_tier = 'pro', trial_ends_at = ?, has_used_trial = TRUE WHERE id = ?",
      [trialEndsAt, user.id]
    );
    res.json({ subscription_tier: "pro", trial_ends_at: trialEndsAt.toISOString() });
  })
);

async function applyCompletedSession(session) {
  const userId = session.client_reference_id;
  const tier = session.metadata?.tier;
  const isGrandfathered = session.metadata?.grandfathered === "true";
  if (!userId || !tier) return;

  // Store grandfathered tier for users who registered before price increase
  const grandfatheredTier = isGrandfathered ? tier : null;

  // Clear any trial state — a real paid subscription supersedes it, so
  // requireAuth's lazy trial-expiry check must never downgrade this user.
  await pool.query(
    `UPDATE users
     SET subscription_tier = ?, stripe_customer_id = COALESCE(stripe_customer_id, ?), trial_ends_at = NULL, grandfathered_tier = ?
     WHERE id = ?`,
    [tier, session.customer ?? null, grandfatheredTier, userId]
  );

  await referrals.creditReferrerIfEligible(Number(userId), tier);
}

/**
 * Raw-body route — mounted separately in server.js *before* the global
 * express.json() parser, since Stripe's signature check needs the exact
 * unparsed request body.
 */
export const webhookHandler = asyncHandler(async (req, res) => {
  if (!stripe || !config.STRIPE_WEBHOOK_SECRET) {
    return res.status(503).send("Webhook not configured");
  }

  let event;
  try {
    event = stripe.webhooks.constructEvent(
      req.body,
      req.headers["stripe-signature"],
      config.STRIPE_WEBHOOK_SECRET
    );
  } catch (err) {
    return res.status(400).send(`Webhook signature verification failed: ${err.message}`);
  }

  switch (event.type) {
    case "checkout.session.completed":
      await applyCompletedSession(event.data.object);
      break;
    case "customer.subscription.deleted": {
      const subscription = event.data.object;
      const userId = subscription.metadata?.userId;
      if (userId) {
        await pool.query("UPDATE users SET subscription_tier = 'free' WHERE id = ?", [userId]);
      }
      break;
    }
    case "payment_intent.succeeded": {
      const paymentIntent = event.data.object;
      // Handle additional seat purchases for teams
      if (paymentIntent.metadata?.team_id) {
        await handleSeatPayment(paymentIntent);
      }
      break;
    }
    default:
      break;
  }

  res.json({ received: true });
});

// Simple landing pages Checkout redirects to (this app has no web frontend).
// Styled to match the app: black background, white text, Poppins.
function landingPage({ title, message, icon }) {
  return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Croploo</title>
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;600;700&display=swap" rel="stylesheet" />
<style>
  * { box-sizing: border-box; }
  body {
    margin: 0;
    min-height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    background: #000;
    color: #fff;
    font-family: 'Poppins', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  }
  .card {
    text-align: center;
    padding: 48px 40px;
  }
  .logo {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 10px;
    margin-bottom: 32px;
  }
  .logo-mark {
    width: 32px;
    height: 32px;
  }
  .logo-word {
    font-weight: 600;
    font-size: 18px;
    letter-spacing: 1.5px;
  }
  .icon {
    width: 56px;
    height: 56px;
    border-radius: 50%;
    background: #fff;
    color: #000;
    display: flex;
    align-items: center;
    justify-content: center;
    margin: 0 auto 24px;
  }
  .icon svg { width: 26px; height: 26px; }
  h1 {
    font-weight: 700;
    font-size: 22px;
    margin: 0 0 10px;
  }
  p {
    font-weight: 400;
    font-size: 14px;
    color: #8a8a8a;
    margin: 0;
  }
</style>
</head>
<body>
  <div class="card">
    <div class="logo">
      <img class="logo-mark" src="/assets/img/croploo_logo.png" alt="Croploo" />
      <div class="logo-word">CROPLOO</div>
    </div>
    <div class="icon">${icon}</div>
    <h1>${title}</h1>
    <p>${message}</p>
  </div>
</body>
</html>`;
}

const CHECK_ICON =
  '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M5 13l4 4L19 7" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/></svg>';
const CLOSE_ICON =
  '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M6 6l12 12M18 6L6 18" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/></svg>';

// This app has no publicly reachable URL for Stripe's webhook to call, so
// the webhook above only fires when running `stripe listen` locally. As
// the reliable path, verify the just-completed session directly here (the
// success redirect includes the session ID) and persist the tier then.
export async function successPage(req, res) {
  const sessionId = req.query.session_id;
  if (stripe && sessionId) {
    const session = await stripe.checkout.sessions.retrieve(sessionId);
    if (session.payment_status === "paid") {
      await applyCompletedSession(session);
    }
  }

  res.send(
    landingPage({
      title: "Payment successful",
      message: "You can close this window.",
      icon: CHECK_ICON,
    })
  );
}

export function cancelPage(req, res) {
  res.send(
    landingPage({
      title: "Checkout canceled",
      message: "You can close this window.",
      icon: CLOSE_ICON,
    })
  );
}
