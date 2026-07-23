import { Router } from "express";
import crypto from "crypto";

import { asyncHandler } from "../asyncHandler.js";
import * as config from "../config.js";
import { pool } from "../db.js";
import { requireAuth } from "../requireAuth.js";
import { getOrCreatePriceId, stripe } from "../stripeClient.js";

export const router = Router();

// Generate a secure random token for team invitations
function generateInviteToken() {
  return crypto.randomBytes(32).toString("hex");
}

// Create a new team (admin only)
router.post(
  "/create",
  requireAuth,
  asyncHandler(async (req, res) => {
    const { name, tier } = req.body ?? {};
    const user = req.user;

    if (!name || !tier) {
      return res.status(400).json({ detail: "name and tier are required" });
    }

    if (!["team", "institutional"].includes(tier)) {
      return res.status(400).json({ detail: "Invalid team tier" });
    }

    if (user.team_id) {
      return res.status(400).json({ detail: "User already belongs to a team" });
    }

    const plan = config.PLANS[tier];
    const seatCount = plan.seats;

    const [result] = await pool.query(
      `INSERT INTO teams (name, owner_id, plan_tier, seat_count) VALUES (?, ?, ?, ?)`,
      [name, user.id, tier, seatCount]
    );

    const teamId = result.insertId;

    // Update user to be team admin
    await pool.query(
      `UPDATE users SET team_id = ?, team_role = 'admin', subscription_tier = ? WHERE id = ?`,
      [teamId, tier, user.id]
    );

    res.json({
      id: teamId,
      name,
      owner_id: user.id,
      plan_tier: tier,
      seat_count: seatCount,
    });
  })
);

// Get team details (members only)
router.get(
  "/my-team",
  requireAuth,
  asyncHandler(async (req, res) => {
    const user = req.user;

    if (!user.team_id) {
      return res.status(404).json({ detail: "User is not on a team" });
    }

    const [teams] = await pool.query(
      `SELECT id, name, owner_id, plan_tier, seat_count, stripe_customer_id, stripe_subscription_id 
       FROM teams WHERE id = ?`,
      [user.team_id]
    );

    if (teams.length === 0) {
      return res.status(404).json({ detail: "Team not found" });
    }

    const team = teams[0];

    // Get all team members
    const [members] = await pool.query(
      `SELECT id, email, username, name, team_role, created_at 
       FROM users WHERE team_id = ? ORDER BY created_at ASC`,
      [user.team_id]
    );

    // Count active members
    const [countResult] = await pool.query(
      `SELECT COUNT(*) as count FROM users WHERE team_id = ?`,
      [user.team_id]
    );
    const memberCount = countResult[0].count;

    // Get pending invitations
    const [invitations] = await pool.query(
      `SELECT id, email, invite_token, expires_at, created_at 
       FROM team_invitations WHERE team_id = ? AND accepted_at IS NULL ORDER BY created_at DESC`,
      [user.team_id]
    );

    res.json({
      ...team,
      members,
      member_count: memberCount,
      invitations,
    });
  })
);

// Invite a team member (admin only)
router.post(
  "/invite",
  requireAuth,
  asyncHandler(async (req, res) => {
    const { email } = req.body ?? {};
    const user = req.user;

    if (!email) {
      return res.status(400).json({ detail: "email is required" });
    }

    if (!user.team_id || user.team_role !== "admin") {
      return res.status(403).json({ detail: "Only team admins can invite members" });
    }

    // Check seat availability
    const [team] = await pool.query(
      `SELECT seat_count FROM teams WHERE id = ?`,
      [user.team_id]
    );

    if (team.length === 0) {
      return res.status(404).json({ detail: "Team not found" });
    }

    const [countResult] = await pool.query(
      `SELECT COUNT(*) as count FROM users WHERE team_id = ?`,
      [user.team_id]
    );
    const activeMembers = countResult[0].count;

    if (activeMembers >= team[0].seat_count) {
      return res.status(400).json({ detail: "No seats available. Please purchase additional seats." });
    }

    // Check if user already exists or is already invited
    const [existingUsers] = await pool.query(
      `SELECT id FROM users WHERE email = ?`,
      [email]
    );

    if (existingUsers.length > 0) {
      const existingUser = existingUsers[0];
      if (existingUser.team_id === user.team_id) {
        return res.status(400).json({ detail: "User is already a team member" });
      }
      return res.status(400).json({ detail: "User already has a Croploo account" });
    }

    const [existingInvites] = await pool.query(
      `SELECT id, expires_at FROM team_invitations WHERE team_id = ? AND email = ? AND accepted_at IS NULL`,
      [user.team_id, email]
    );

    if (existingInvites.length > 0) {
      const invite = existingInvites[0];
      if (new Date(invite.expires_at) > new Date()) {
        return res.status(400).json({ detail: "User already has a pending invitation" });
      }
      // Delete expired invitation
      await pool.query(`DELETE FROM team_invitations WHERE id = ?`, [invite.id]);
    }

    const token = generateInviteToken();
    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000); // 7 days

    await pool.query(
      `INSERT INTO team_invitations (team_id, email, invite_token, expires_at) VALUES (?, ?, ?, ?)`,
      [user.team_id, email, token, expiresAt]
    );

    // TODO: Send email with invitation link
    // For now, return the token so the frontend can display it
    const inviteLink = `${config.APP_URL}/join-team?token=${token}`;

    res.json({
      token,
      invite_link: inviteLink,
      expires_at: expiresAt.toISOString(),
    });
  })
);

// Accept a team invitation (no auth required - used during signup)
router.post(
  "/accept-invite",
  asyncHandler(async (req, res) => {
    const { token } = req.body ?? {};

    if (!token) {
      return res.status(400).json({ detail: "token is required" });
    }

    const [invitations] = await pool.query(
      `SELECT id, team_id, email, expires_at FROM team_invitations WHERE invite_token = ? AND accepted_at IS NULL`,
      [token]
    );

    if (invitations.length === 0) {
      return res.status(404).json({ detail: "Invalid or expired invitation" });
    }

    const invitation = invitations[0];

    if (new Date(invitation.expires_at) < new Date()) {
      return res.status(400).json({ detail: "Invitation has expired" });
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

    res.json({
      team_id: invitation.team_id,
      email: invitation.email,
      plan_tier: team[0].plan_tier,
    });
  })
);

// Remove a team member (admin only)
router.delete(
  "/members/:userId",
  requireAuth,
  asyncHandler(async (req, res) => {
    const { userId } = req.params;
    const user = req.user;

    if (!user.team_id || user.team_role !== "admin") {
      return res.status(403).json({ detail: "Only team admins can remove members" });
    }

    const targetUserId = Number(userId);

    // Cannot remove yourself
    if (targetUserId === user.id) {
      return res.status(400).json({ detail: "Cannot remove yourself from the team" });
    }

    // Cannot remove the team owner
    const [targetUser] = await pool.query(
      `SELECT id, team_id FROM users WHERE id = ?`,
      [targetUserId]
    );

    if (targetUser.length === 0) {
      return res.status(404).json({ detail: "User not found" });
    }

    if (targetUser[0].team_id !== user.team_id) {
      return res.status(400).json({ detail: "User is not a member of this team" });
    }

    const [team] = await pool.query(
      `SELECT owner_id FROM teams WHERE id = ?`,
      [user.team_id]
    );

    if (team[0].owner_id === targetUserId) {
      return res.status(400).json({ detail: "Cannot remove the team owner" });
    }

    // Remove user from team
    await pool.query(
      `UPDATE users SET team_id = NULL, team_role = NULL, subscription_tier = 'free' WHERE id = ?`,
      [targetUserId]
    );

    res.json({ success: true });
  })
);

// Cancel a pending invitation (admin only)
router.delete(
  "/invitations/:inviteId",
  requireAuth,
  asyncHandler(async (req, res) => {
    const { inviteId } = req.params;
    const user = req.user;

    if (!user.team_id || user.team_role !== "admin") {
      return res.status(403).json({ detail: "Only team admins can cancel invitations" });
    }

    const [invitation] = await pool.query(
      `SELECT id, team_id FROM team_invitations WHERE id = ?`,
      [Number(inviteId)]
    );

    if (invitation.length === 0) {
      return res.status(404).json({ detail: "Invitation not found" });
    }

    if (invitation[0].team_id !== user.team_id) {
      return res.status(403).json({ detail: "Invitation does not belong to your team" });
    }

    await pool.query(`DELETE FROM team_invitations WHERE id = ?`, [Number(inviteId)]);

    res.json({ success: true });
  })
);

// Purchase additional seats (admin only)
router.post(
  "/purchase-seats",
  requireAuth,
  asyncHandler(async (req, res) => {
    const { quantity } = req.body ?? {};
    const user = req.user;

    if (!quantity || quantity < 1) {
      return res.status(400).json({ detail: "quantity must be at least 1" });
    }

    if (!user.team_id || user.team_role !== "admin") {
      return res.status(403).json({ detail: "Only team admins can purchase seats" });
    }

    if (!stripe) {
      return res.status(503).json({ detail: "Stripe is not configured" });
    }

    const [team] = await pool.query(
      `SELECT id, stripe_customer_id FROM teams WHERE id = ?`,
      [user.team_id]
    );

    if (team.length === 0) {
      return res.status(404).json({ detail: "Team not found" });
    }

    const amountCents = quantity * config.ADDITIONAL_SEAT_PRICE_CENTS;

    // Create a one-time payment intent for additional seats
    const paymentIntent = await stripe.paymentIntents.create({
      amount: amountCents,
      currency: "usd",
      customer: team[0].stripe_customer_id || undefined,
      metadata: {
        team_id: String(user.team_id),
        additional_seats: String(quantity),
      },
    });

    res.json({
      client_secret: paymentIntent.client_secret,
      amount_cents: amountCents,
      quantity,
    });
  })
);

// Webhook handler for additional seat purchases
export async function handleSeatPayment(paymentIntent) {
  const teamId = paymentIntent.metadata?.team_id;
  const additionalSeats = Number(paymentIntent.metadata?.additional_seats);

  if (!teamId || !additionalSeats) return;

  if (paymentIntent.status === "succeeded") {
    await pool.query(
      `UPDATE teams SET seat_count = seat_count + ? WHERE id = ?`,
      [additionalSeats, teamId]
    );
  }
}
