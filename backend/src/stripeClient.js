import Stripe from "stripe";

import * as config from "./config.js";

export const stripe = config.STRIPE_SECRET_KEY
  ? new Stripe(config.STRIPE_SECRET_KEY)
  : null;

const priceIdCache = {};

/**
 * Finds this plan's live Stripe Price by `metadata.tier`, creating the
 * Product + recurring monthly Price if they don't exist yet. Idempotent
 * across restarts — safe to call on every checkout request.
 * 
 * For grandfathered users (registered before price increase), uses the
 * legacy price from LEGACY_PLAN_PRICES instead of the current price.
 */
export async function getOrCreatePriceId(tier, isGrandfathered = false) {
  const cacheKey = isGrandfathered ? `${tier}_legacy` : tier;
  if (priceIdCache[cacheKey]) return priceIdCache[cacheKey];
  if (!stripe) throw new Error("STRIPE_SECRET_KEY is not configured");

  const plan = config.PLANS[tier];
  if (!plan) throw new Error(`Unknown plan tier: ${tier}`);

  // Grandfathered users get the legacy (pre-increase) price *only* if
  // it's actually lower than the current price — current prices were
  // since cut below several legacy prices, and grandfathering must never
  // charge a user more than they'd pay as a brand-new signup.
  const legacyCents = config.LEGACY_PLAN_PRICES[tier];
  const amountCents = isGrandfathered && legacyCents && legacyCents < plan.amountCents
    ? legacyCents
    : plan.amountCents;

  const products = await stripe.products.list({ active: true, limit: 100 });
  let product = products.data.find((p) => p.metadata?.tier === tier);

  if (!product) {
    product = await stripe.products.create({
      name: plan.name,
      metadata: { tier },
    });
  }

  const prices = await stripe.prices.list({ product: product.id, active: true, limit: 10 });
  let price = prices.data.find(
    (p) => p.unit_amount === amountCents && p.recurring?.interval === "month"
  );

  if (!price) {
    price = await stripe.prices.create({
      product: product.id,
      unit_amount: amountCents,
      currency: "usd",
      recurring: { interval: "month" },
      metadata: { tier, grandfathered: String(isGrandfathered) },
    });
  }

  priceIdCache[cacheKey] = price.id;
  return price.id;
}

let foundingMemberCouponId;

/**
 * The 50%-off-for-life coupon applied at checkout for founding members
 * (see the FOUNDING_MEMBER_SLOTS claim in routes/auth.js). Looked up by a
 * fixed `id` so it's idempotent across restarts, same pattern as
 * getOrCreatePriceId's product/price lookup.
 */
export async function getOrCreateFoundingMemberCouponId() {
  if (foundingMemberCouponId) return foundingMemberCouponId;
  if (!stripe) throw new Error("STRIPE_SECRET_KEY is not configured");

  const couponId = "founding-member-50-off-forever";
  try {
    await stripe.coupons.retrieve(couponId);
  } catch (error) {
    if (error?.code !== "resource_missing") throw error;
    await stripe.coupons.create({
      id: couponId,
      percent_off: 50,
      duration: "forever",
      name: "Founding Member — 50% off for life",
    });
  }

  foundingMemberCouponId = couponId;
  return foundingMemberCouponId;
}
