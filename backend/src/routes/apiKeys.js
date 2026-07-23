import express from "express";

import { asyncHandler } from "../asyncHandler.js";
import { requireAuth } from "../requireAuth.js";
import {
  createApiKey,
  listApiKeys,
  deleteApiKey,
  getApiUsage,
} from "../apiAuth.js";

const router = express.Router();

/**
 * POST /v1/api-keys
 * Create a new API key for the authenticated user.
 */
router.post(
  "/",
  requireAuth,
  asyncHandler(async (req, res) => {
    const { name } = req.body ?? {};
    if (!name) {
      return res.status(400).json({ detail: "name is required" });
    }

    const result = await createApiKey(req.user.id, name);

    res.json({
      id: result.id,
      key: result.key,
      prefix: result.prefix,
      name: result.name,
      message: "Save this key now — you won't see it again.",
    });
  })
);

/**
 * GET /v1/api-keys
 * List all API keys for the authenticated user.
 */
router.get(
  "/",
  requireAuth,
  asyncHandler(async (req, res) => {
    const keys = await listApiKeys(req.user.id);
    res.json(keys);
  })
);

/**
 * DELETE /v1/api-keys/:id
 * Delete an API key.
 */
router.delete(
  "/:id",
  requireAuth,
  asyncHandler(async (req, res) => {
    const keyId = Number(req.params.id);
    const deleted = await deleteApiKey(req.user.id, keyId);

    if (!deleted) {
      return res.status(404).json({ detail: "API key not found" });
    }

    res.json({ status: "deleted" });
  })
);

/**
 * GET /v1/api-keys/usage
 * Get current API usage for today.
 */
router.get(
  "/usage",
  requireAuth,
  asyncHandler(async (req, res) => {
    const usage = await getApiUsage(req.user.id);
    res.json(usage);
  })
);

export { router };
