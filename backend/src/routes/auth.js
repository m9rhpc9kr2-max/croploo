import { Router } from "express";

import { asyncHandler } from "../asyncHandler.js";
import * as config from "../config.js";
import { pool } from "../db.js";
import { sendPasswordResetEmail, sendVerificationEmail } from "../mailer.js";
import { requireAuth } from "../requireAuth.js";
import * as referrals from "../referrals.js";
import {
  createToken,
  generateVerificationCode,
  hashPassword,
  verifyPassword,
} from "../security.js";

export const router = Router();

const USERNAME_RE = /^[a-z]{3,20}$/;

const FOUNDING_MEMBER_SLOTS = 50;

/**
 * Claims one of the first FOUNDING_MEMBER_SLOTS signup slots for `userId`,
 * if any remain. Uses SELECT ... FOR UPDATE inside a transaction so
 * concurrent registrations can't both claim the last slot.
 */
async function claimFoundingMemberSlot(userId) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    await conn.query(
      `INSERT INTO promo_counters (name, count) VALUES ('founding_50', 0)
       ON DUPLICATE KEY UPDATE name = name`
    );
    const [[row]] = await conn.query(
      `SELECT count FROM promo_counters WHERE name = 'founding_50' FOR UPDATE`
    );
    if (row.count < FOUNDING_MEMBER_SLOTS) {
      await conn.query(
        `UPDATE promo_counters SET count = count + 1 WHERE name = 'founding_50'`
      );
      await conn.query(`UPDATE users SET founding_member = TRUE WHERE id = ?`, [userId]);
    }
    await conn.commit();
  } catch (error) {
    await conn.rollback();
    throw error;
  } finally {
    conn.release();
  }
}

function serializeUser(row) {
  return {
    id: String(row.id),
    email: row.email,
    username: row.username,
    name: row.name,
    subscription_tier: row.subscription_tier,
    daily_brief_email: !!row.daily_brief_email,
    referral_code: row.username.toUpperCase(),
    trial_ends_at: row.trial_ends_at
      ? new Date(row.trial_ends_at).toISOString()
      : null,
    has_used_trial: !!row.has_used_trial,
    team_id: row.team_id ? String(row.team_id) : null,
    team_role: row.team_role,
    founding_member: !!row.founding_member,
  };
}

async function issueVerificationCode(userId, email) {
  const code = generateVerificationCode();
  const expires = new Date(Date.now() + config.VERIFICATION_CODE_TTL_MINUTES * 60_000);
  await pool.query(
    "UPDATE users SET verification_code = ?, verification_expires = ? WHERE id = ?",
    [code, expires, userId]
  );
  await sendVerificationEmail(email, code);
}

router.post("/register", asyncHandler(async (req, res) => {
  const { email, password, username, name = "", referral_code, invite_token } = req.body ?? {};
  if (!email || !password || !username) {
    return res.status(400).json({ detail: "email, username and password are required" });
  }
  if (!USERNAME_RE.test(username)) {
    return res
      .status(400)
      .json({ detail: "Username must be 3-20 lowercase letters (a-z)" });
  }
  if (password.length < 6) {
    return res.status(400).json({ detail: "Password must be at least 6 characters" });
  }

  const [existing] = await pool.query(
    "SELECT id FROM users WHERE email = ? OR username = ?",
    [email, username]
  );
  if (existing.length > 0) {
    return res.status(409).json({ detail: "Email or username already registered" });
  }

  // Handle team invitation acceptance
  let teamId = null;
  let teamRole = null;
  let subscriptionTier = 'free';

  if (invite_token) {
    const [invitations] = await pool.query(
      `SELECT team_id, email, expires_at FROM team_invitations WHERE invite_token = ? AND accepted_at IS NULL`,
      [invite_token]
    );

    if (invitations.length === 0) {
      return res.status(400).json({ detail: "Invalid or expired invitation" });
    }

    const invitation = invitations[0];

    if (new Date(invitation.expires_at) < new Date()) {
      return res.status(400).json({ detail: "Invitation has expired" });
    }

    if (invitation.email && invitation.email.toLowerCase() !== email.toLowerCase()) {
      return res.status(400).json({ detail: "This invitation is for a different email address" });
    }

    // Check seat availability
    const [team] = await pool.query(
      `SELECT seat_count, plan_tier FROM teams WHERE id = ?`,
      [invitation.team_id]
    );

    if (team.length === 0) {
      return res.status(404).json({ detail: "Team not found" });
    }

    const [countResult] = await pool.query(
      `SELECT COUNT(*) as count FROM users WHERE team_id = ?`,
      [invitation.team_id]
    );
    const activeMembers = countResult[0].count;

    if (activeMembers >= team[0].seat_count) {
      return res.status(400).json({ detail: "No seats available" });
    }

    teamId = invitation.team_id;
    teamRole = 'member';
    subscriptionTier = team[0].plan_tier;
  }

  // A referral code is just the referrer's own username (see
  // referrals.js) — an unknown/empty code silently results in no
  // referrer rather than a signup error, since referrals are a bonus,
  // not a requirement.
  const referredBy = await referrals.findReferrer(referral_code);

  const [result] = await pool.query(
    `INSERT INTO users (email, username, name, password_hash, subscription_tier, is_verified, referred_by, team_id, team_role)
     VALUES (?, ?, ?, ?, ?, FALSE, ?, ?, ?)`,
    [email, username, name, hashPassword(password), subscriptionTier, referredBy, teamId, teamRole]
  );

  // Mark invitation as accepted
  if (teamId) {
    await pool.query(
      `UPDATE team_invitations SET accepted_at = NOW() WHERE invite_token = ?`,
      [invite_token]
    );
  }

  await claimFoundingMemberSlot(result.insertId);
  await issueVerificationCode(result.insertId, email);

  res.json({ status: "verification_sent", email });
}));

router.get("/me", requireAuth, asyncHandler(async (req, res) => {
  res.json(serializeUser(req.user));
}));

router.get("/referrals", requireAuth, asyncHandler(async (req, res) => {
  const summary = await referrals.summaryForUser(req.user.id);
  res.json({ code: req.user.username.toUpperCase(), ...summary });
}));

// Update editable account fields (name, email, username). Password has
// its own dedicated flow below. Email and username are checked for
// uniqueness against every *other* user before anything is written —
// if either is taken, the whole update is rejected (nothing is saved,
// including the other field) rather than partially applied.
router.put("/me", requireAuth, asyncHandler(async (req, res) => {
  const { name, email, username } = req.body ?? {};
  const updates = [];
  const params = [];

  if (name !== undefined) {
    if (typeof name !== "string" || name.trim().length === 0) {
      return res.status(400).json({ detail: "name must be a non-empty string" });
    }
    updates.push("name = ?");
    params.push(name.trim());
  }

  if (email !== undefined) {
    if (typeof email !== "string" || !email.includes("@")) {
      return res.status(400).json({ detail: "email must be a valid email address" });
    }
    const [existing] = await pool.query(
      "SELECT id FROM users WHERE email = ? AND id != ?",
      [email, req.user.id]
    );
    if (existing.length > 0) {
      return res.status(409).json({ detail: "Email already in use" });
    }
    updates.push("email = ?");
    params.push(email.trim());
  }

  if (username !== undefined) {
    if (!USERNAME_RE.test(username)) {
      return res
        .status(400)
        .json({ detail: "Username must be 3-20 lowercase letters (a-z)" });
    }
    const [existing] = await pool.query(
      "SELECT id FROM users WHERE username = ? AND id != ?",
      [username, req.user.id]
    );
    if (existing.length > 0) {
      return res.status(409).json({ detail: "Username already taken" });
    }
    updates.push("username = ?");
    params.push(username);
  }

  if (updates.length === 0) {
    return res.status(400).json({ detail: "Nothing to update" });
  }

  params.push(req.user.id);
  await pool.query(`UPDATE users SET ${updates.join(", ")} WHERE id = ?`, params);

  const [rows] = await pool.query("SELECT * FROM users WHERE id = ?", [req.user.id]);
  res.json(serializeUser(rows[0]));
}));

router.post("/change-password", requireAuth, asyncHandler(async (req, res) => {
  const { current_password, new_password } = req.body ?? {};
  if (!current_password || !new_password) {
    return res.status(400).json({ detail: "current_password and new_password are required" });
  }
  if (new_password.length < 6) {
    return res.status(400).json({ detail: "Password must be at least 6 characters" });
  }
  if (!verifyPassword(current_password, req.user.password_hash)) {
    return res.status(401).json({ detail: "Current password is incorrect" });
  }
  await pool.query("UPDATE users SET password_hash = ? WHERE id = ?", [
    hashPassword(new_password),
    req.user.id,
  ]);
  res.json({ status: "password_changed" });
}));

router.put("/me/preferences", requireAuth, asyncHandler(async (req, res) => {
  const { daily_brief_email } = req.body ?? {};
  if (typeof daily_brief_email !== "boolean") {
    return res.status(400).json({ detail: "daily_brief_email must be a boolean" });
  }
  await pool.query("UPDATE users SET daily_brief_email = ? WHERE id = ?", [
    daily_brief_email,
    req.user.id,
  ]);
  res.json(serializeUser({ ...req.user, daily_brief_email }));
}));

router.post("/verify-email", asyncHandler(async (req, res) => {
  const { email, code } = req.body ?? {};
  if (!email || !code) {
    return res.status(400).json({ detail: "email and code are required" });
  }

  const [rows] = await pool.query("SELECT * FROM users WHERE email = ?", [email]);
  const user = rows[0];
  if (!user) {
    return res.status(404).json({ detail: "No account for this email" });
  }
  if (user.is_verified) {
    return res.status(400).json({ detail: "Account already verified" });
  }
  if (
    !user.verification_code ||
    user.verification_code !== code ||
    !user.verification_expires ||
    new Date(user.verification_expires) < new Date()
  ) {
    return res.status(400).json({ detail: "Invalid or expired code" });
  }

  await pool.query(
    "UPDATE users SET is_verified = TRUE, verification_code = NULL, verification_expires = NULL WHERE id = ?",
    [user.id]
  );

  res.json({
    access_token: createToken(user.id),
    token_type: "bearer",
    user: serializeUser({ ...user, is_verified: true }),
  });
}));

router.post("/resend-code", asyncHandler(async (req, res) => {
  const { email } = req.body ?? {};
  const [rows] = await pool.query("SELECT * FROM users WHERE email = ?", [email]);
  const user = rows[0];
  if (!user || user.is_verified) {
    // Don't reveal whether the account exists.
    return res.json({ status: "ok" });
  }
  await issueVerificationCode(user.id, user.email);
  res.json({ status: "ok" });
}));

router.post("/login", asyncHandler(async (req, res) => {
  // Accepts either the account's email or its username in the same
  // field, so users don't have to remember which one they signed up with.
  const { email, username, password } = req.body ?? {};
  const identifier = email ?? username;
  if (!identifier || !password) {
    return res.status(400).json({ detail: "email/username and password are required" });
  }

  const [rows] = await pool.query("SELECT * FROM users WHERE email = ? OR username = ?", [
    identifier,
    String(identifier).toLowerCase(),
  ]);
  const user = rows[0];
  if (!user || !verifyPassword(password, user.password_hash)) {
    return res.status(401).json({ detail: "Invalid credentials" });
  }
  if (!user.is_verified) {
    return res.status(403).json({ detail: "Email not verified", email: user.email });
  }

  res.json({
    access_token: createToken(user.id),
    token_type: "bearer",
    user: serializeUser(user),
  });
}));

router.post("/forgot-password", asyncHandler(async (req, res) => {
  const { email_or_username } = req.body ?? {};
  const identifier = String(email_or_username ?? "").trim();
  if (!identifier) {
    return res.status(400).json({ detail: "email_or_username is required" });
  }

  const [rows] = await pool.query("SELECT * FROM users WHERE email = ? OR username = ?", [
    identifier,
    identifier.toLowerCase(),
  ]);
  const user = rows[0];
  if (!user) {
    // Don't reveal whether the account exists.
    return res.json({ status: "ok" });
  }

  const code = generateVerificationCode();
  const expires = new Date(Date.now() + config.VERIFICATION_CODE_TTL_MINUTES * 60_000);
  await pool.query("UPDATE users SET reset_code = ?, reset_expires = ? WHERE id = ?", [
    code,
    expires,
    user.id,
  ]);
  await sendPasswordResetEmail(user.email, code);

  res.json({ status: "ok", email: user.email });
}));

router.post("/reset-password", asyncHandler(async (req, res) => {
  const { email, code, new_password } = req.body ?? {};
  if (!email || !code || !new_password) {
    return res.status(400).json({ detail: "email, code and new_password are required" });
  }
  if (new_password.length < 6) {
    return res.status(400).json({ detail: "Password must be at least 6 characters" });
  }

  const [rows] = await pool.query("SELECT * FROM users WHERE email = ?", [email]);
  const user = rows[0];
  if (
    !user ||
    !user.reset_code ||
    user.reset_code !== code ||
    !user.reset_expires ||
    new Date(user.reset_expires) < new Date()
  ) {
    return res.status(400).json({ detail: "Invalid or expired code" });
  }

  await pool.query(
    "UPDATE users SET password_hash = ?, reset_code = NULL, reset_expires = NULL WHERE id = ?",
    [hashPassword(new_password), user.id]
  );

  res.json({
    access_token: createToken(user.id),
    token_type: "bearer",
    user: serializeUser({ ...user, password_hash: undefined }),
  });
}));
