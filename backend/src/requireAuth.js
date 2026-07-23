import { pool } from "./db.js";
import { decodeToken } from "./security.js";

export async function requireAuth(req, res, next) {
  const header = req.headers.authorization;
  if (!header?.toLowerCase().startsWith("bearer ")) {
    return res.status(401).json({ detail: "Not authenticated" });
  }
  let userId;
  try {
    userId = decodeToken(header.slice(7));
  } catch {
    return res.status(401).json({ detail: "Invalid token" });
  }

  const [rows] = await pool.query("SELECT * FROM users WHERE id = ?", [userId]);
  if (!rows[0]) {
    return res.status(401).json({ detail: "User not found" });
  }
  let user = rows[0];

  // Lazy trial expiry — same "check on read, no cron needed" pattern as
  // marketData.ensureFresh()/usdaBasis.ensureFresh(). A real Stripe
  // subscription always clears trial_ends_at (see billing.js
  // applyCompletedSession), so this can never downgrade a paying user.
  if (user.trial_ends_at && new Date(user.trial_ends_at) < new Date()) {
    await pool.query(
      "UPDATE users SET subscription_tier = 'free', trial_ends_at = NULL WHERE id = ?",
      [user.id]
    );
    user = { ...user, subscription_tier: "free", trial_ends_at: null };
  }

  req.user = user;
  next();
}
