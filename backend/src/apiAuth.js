import crypto from "crypto";

import * as config from "./config.js";
import { pool } from "./db.js";

const API_KEY_PREFIX = "knx_";
const API_KEY_LENGTH = 32;

/**
 * Generate a new API key for a user.
 * Format: knx_<32-char-random>
 * Returns the full key (only shown once to the user).
 */
export function generateApiKey() {
  const randomBytes = crypto.randomBytes(API_KEY_LENGTH);
  const key = randomBytes.toString("hex");
  return `${API_KEY_PREFIX}${key}`;
}

/**
 * Hash an API key for storage (SHA-256).
 * We never store the actual key, only the hash.
 */
export function hashApiKey(key) {
  return crypto.createHash("sha256").update(key).digest("hex");
}

/**
 * Extract the prefix (first 8 chars after knx_) for display/identification.
 */
export function extractApiKeyPrefix(key) {
  if (!key || !key.startsWith(API_KEY_PREFIX)) return "";
  return key.substring(API_KEY_PREFIX.length, API_KEY_PREFIX.length + 8);
}

/**
 * Create a new API key for a user.
 */
export async function createApiKey(userId, name) {
  const fullKey = generateApiKey();
  const keyHash = hashApiKey(fullKey);
  const keyPrefix = extractApiKeyPrefix(fullKey);

  const [result] = await pool.query(
    `INSERT INTO api_keys (user_id, key_hash, key_prefix, name) VALUES (?, ?, ?, ?)`,
    [userId, keyHash, keyPrefix, name]
  );

  return {
    id: result.insertId,
    key: fullKey,
    prefix: keyPrefix,
    name,
  };
}

/**
 * List all API keys for a user (without the full keys, only prefixes).
 */
export async function listApiKeys(userId) {
  const [rows] = await pool.query(
    `SELECT id, key_prefix, name, is_active, last_used_at, created_at 
     FROM api_keys WHERE user_id = ? ORDER BY created_at DESC`,
    [userId]
  );
  return rows;
}

/**
 * Delete an API key.
 */
export async function deleteApiKey(userId, keyId) {
  const [result] = await pool.query(
    `DELETE FROM api_keys WHERE id = ? AND user_id = ?`,
    [keyId, userId]
  );
  return result.affectedRows > 0;
}

/**
 * Validate an API key and return the associated user ID.
 * Returns null if the key is invalid or inactive.
 */
export async function validateApiKey(key) {
  if (!key || !key.startsWith(API_KEY_PREFIX)) {
    return null;
  }

  const keyHash = hashApiKey(key);

  const [rows] = await pool.query(
    `SELECT id, user_id, is_active FROM api_keys WHERE key_hash = ?`,
    [keyHash]
  );

  if (rows.length === 0) {
    return null;
  }

  const apiKey = rows[0];

  if (!apiKey.is_active) {
    return null;
  }

  // Update last_used_at
  await pool.query(
    `UPDATE api_keys SET last_used_at = NOW() WHERE id = ?`,
    [apiKey.id]
  );

  return apiKey.user_id;
}

/**
 * Check and increment API usage for rate limiting.
 * Returns true if the limit has not been exceeded, false otherwise.
 */
export async function checkRateLimit(userId, tier) {
  const dailyLimit = config.API_RATE_LIMITS[tier] || 0;

  if (dailyLimit === 0) {
    return false; // No API access for this tier
  }

  // Get the user's most recently used API key
  const [keyRows] = await pool.query(
    `SELECT id FROM api_keys WHERE user_id = ? AND is_active = TRUE ORDER BY last_used_at DESC LIMIT 1`,
    [userId]
  );

  if (keyRows.length === 0) {
    return false;
  }

  const keyId = keyRows[0].id;
  const today = new Date().toISOString().split("T")[0];

  // Get or create usage record for today
  const [usageRows] = await pool.query(
    `SELECT call_count FROM api_usage WHERE key_id = ? AND call_date = ?`,
    [keyId, today]
  );

  let currentCount = 0;
  if (usageRows.length > 0) {
    currentCount = usageRows[0].call_count;
  }

  if (currentCount >= dailyLimit) {
    return false;
  }

  // Increment the count
  if (usageRows.length === 0) {
    await pool.query(
      `INSERT INTO api_usage (key_id, call_date, call_count) VALUES (?, ?, 1)`,
      [keyId, today]
    );
  } else {
    await pool.query(
      `UPDATE api_usage SET call_count = call_count + 1 WHERE key_id = ? AND call_date = ?`,
      [keyId, today]
    );
  }

  return true;
}

/**
 * Get remaining API calls for today.
 */
export async function getApiUsage(userId) {
  const [keyRows] = await pool.query(
    `SELECT id FROM api_keys WHERE user_id = ? AND is_active = TRUE ORDER BY last_used_at DESC LIMIT 1`,
    [userId]
  );

  if (keyRows.length === 0) {
    return { used: 0, limit: 0, remaining: 0 };
  }

  const keyId = keyRows[0].id;
  const today = new Date().toISOString().split("T")[0];

  const [usageRows] = await pool.query(
    `SELECT call_count FROM api_usage WHERE key_id = ? AND call_date = ?`,
    [keyId, today]
  );

  const used = usageRows.length > 0 ? usageRows[0].call_count : 0;

  // Get user's tier to determine limit
  const [userRows] = await pool.query(
    `SELECT subscription_tier FROM users WHERE id = ?`,
    [userId]
  );

  if (userRows.length === 0) {
    return { used, limit: 0, remaining: 0 };
  }

  const tier = userRows[0].subscription_tier;
  const limit = config.API_RATE_LIMITS[tier] || 0;

  return {
    used,
    limit,
    remaining: Math.max(0, limit - used),
  };
}
