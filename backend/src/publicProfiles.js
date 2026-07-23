/**
 * Public Profiles — backend data model + API only. There is no public
 * web frontend in this repo (Croploo is a Flutter desktop/mobile app),
 * so "croploo.app/u/<username>" doesn't exist yet; a future web project
 * would call GET /public-profile/:username to render it. See the
 * implementation summary for what's still needed to make this live.
 */
import { pool } from "./db.js";

export class PublicProfileError extends Error {}

export async function getMine(userId) {
  const [rows] = await pool.query("SELECT * FROM public_profiles WHERE user_id = ?", [userId]);
  return rows[0] ? serialize(rows[0]) : null;
}

export async function upsert(userId, { username, isPublic, trackedCommodities }) {
  if (!username || !/^[a-z0-9_]{3,32}$/i.test(username)) {
    throw new PublicProfileError("username must be 3-32 alphanumeric/underscore characters");
  }
  await pool.query(
    `INSERT INTO public_profiles (user_id, username, is_public, tracked_commodities, updated_at)
     VALUES (?, ?, ?, ?, NOW())
     ON DUPLICATE KEY UPDATE
       username = VALUES(username), is_public = VALUES(is_public),
       tracked_commodities = VALUES(tracked_commodities), updated_at = NOW()`,
    [userId, username, !!isPublic, JSON.stringify(trackedCommodities ?? [])]
  );
  return getMine(userId);
}

/** Public lookup — only returns data if the profile is marked public. */
export async function getPublic(username) {
  const [rows] = await pool.query(
    "SELECT * FROM public_profiles WHERE username = ? AND is_public = TRUE",
    [username]
  );
  if (rows.length === 0) throw new PublicProfileError("Profile not found or not public");

  const profile = rows[0];
  const [insights] = await pool.query(
    `SELECT ci.commodity, ci.body, ci.created_at FROM community_insights ci
     WHERE ci.user_id = ? ORDER BY ci.created_at DESC LIMIT 10`,
    [profile.user_id]
  );

  return {
    username: profile.username,
    tracked_commodities: profile.tracked_commodities,
    recent_insights: insights.map((i) => ({
      commodity: i.commodity,
      body: i.body,
      created_at: i.created_at.toISOString(),
    })),
  };
}

function serialize(row) {
  return {
    username: row.username,
    is_public: !!row.is_public,
    tracked_commodities: row.tracked_commodities,
  };
}
