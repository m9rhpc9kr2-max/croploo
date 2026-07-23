/**
 * Referral rewards: a user's own (already-unique, already-lowercase)
 * username doubles as their referral code — no separate code column or
 * generator needed. When someone who signed up with that code converts
 * to a paid plan for the first time, the referrer gets a real Stripe
 * customer-balance credit for one month of that plan, automatically
 * applied to their next invoice (or held until they subscribe, if
 * they're still on the free tier themselves).
 */
import { pool } from "./db.js";
import * as config from "./config.js";
import { stripe } from "./stripeClient.js";

/** Looks up a referrer by the code entered at signup (their username). */
export async function findReferrer(code) {
  if (!code) return null;
  const [rows] = await pool.query("SELECT id FROM users WHERE username = ?", [
    String(code).trim().toLowerCase(),
  ]);
  return rows[0]?.id ?? null;
}

/** Credits the referrer, if any, the first time `referredUserId` converts
 * to a paid tier. Safe to call on every checkout completion (webhook
 * retries, later upgrades) — the unique key on referred_user_id makes it
 * a no-op after the first successful credit. */
export async function creditReferrerIfEligible(referredUserId, tier) {
  if (!stripe) return;
  const plan = config.PLANS[tier];
  if (!plan) return;

  const [existing] = await pool.query(
    "SELECT id FROM referral_credits WHERE referred_user_id = ?",
    [referredUserId]
  );
  if (existing.length > 0) return;

  const [referredRows] = await pool.query("SELECT * FROM users WHERE id = ?", [referredUserId]);
  const referredUser = referredRows[0];
  if (!referredUser?.referred_by) return;

  const [referrerRows] = await pool.query("SELECT * FROM users WHERE id = ?", [
    referredUser.referred_by,
  ]);
  const referrer = referrerRows[0];
  if (!referrer) return;

  let customerId = referrer.stripe_customer_id;
  if (!customerId) {
    const customer = await stripe.customers.create({
      email: referrer.email,
      name: referrer.name || undefined,
    });
    customerId = customer.id;
    await pool.query("UPDATE users SET stripe_customer_id = ? WHERE id = ?", [
      customerId,
      referrer.id,
    ]);
  }

  const balanceTx = await stripe.customers.createBalanceTransaction(customerId, {
    amount: -plan.amountCents,
    currency: "usd",
    description: `Referral credit: @${referredUser.username} subscribed to ${plan.name}`,
  });

  await pool.query(
    `INSERT INTO referral_credits (referrer_id, referred_user_id, amount_cents, stripe_balance_transaction_id)
     VALUES (?, ?, ?, ?)`,
    [referrer.id, referredUserId, plan.amountCents, balanceTx.id]
  );
}

export async function summaryForUser(userId) {
  const [signups] = await pool.query(
    "SELECT username, subscription_tier, created_at FROM users WHERE referred_by = ?",
    [userId]
  );
  const [credits] = await pool.query(
    "SELECT amount_cents, created_at FROM referral_credits WHERE referrer_id = ? ORDER BY created_at DESC",
    [userId]
  );
  return {
    signups: signups.map((s) => ({
      username: s.username,
      subscription_tier: s.subscription_tier,
      joined_at: s.created_at.toISOString(),
    })),
    credits: credits.map((c) => ({
      amount_cents: c.amount_cents,
      created_at: c.created_at.toISOString(),
    })),
    total_credit_cents: credits.reduce((sum, c) => sum + c.amount_cents, 0),
  };
}
