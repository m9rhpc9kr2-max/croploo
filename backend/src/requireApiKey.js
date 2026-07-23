import { validateApiKey, checkRateLimit } from "./apiAuth.js";
import { pool } from "./db.js";

/**
 * Middleware to authenticate requests using API key (X-API-Key header).
 * Sets req.user if authentication succeeds.
 */
export async function requireApiKey(req, res, next) {
  const apiKey = req.headers["x-api-key"];

  if (!apiKey) {
    return res.status(401).json({ detail: "API key required" });
  }

  const userId = await validateApiKey(apiKey);

  if (!userId) {
    return res.status(401).json({ detail: "Invalid or inactive API key" });
  }

  // Get user details including subscription tier
  const [userRows] = await pool.query(
    `SELECT id, email, subscription_tier FROM users WHERE id = ?`,
    [userId]
  );

  if (userRows.length === 0) {
    return res.status(401).json({ detail: "User not found" });
  }

  req.user = userRows[0];
  next();
}

/**
 * Middleware to check rate limits based on user's subscription tier.
 */
export async function requireApiRateLimit(req, res, next) {
  const { id: userId, subscription_tier: tier } = req.user;

  const allowed = await checkRateLimit(userId, tier);

  if (!allowed) {
    return res.status(429).json({
      detail: "API rate limit exceeded",
      tier,
    });
  }

  next();
}
