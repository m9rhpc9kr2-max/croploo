import crypto from "node:crypto";

import jwt from "jsonwebtoken";

import * as config from "./config.js";

const ITERATIONS = 200_000;
const KEYLEN = 32;
const DIGEST = "sha256";

export function hashPassword(password) {
  const salt = crypto.randomBytes(16);
  const digest = crypto.pbkdf2Sync(password, salt, ITERATIONS, KEYLEN, DIGEST);
  return `pbkdf2$${ITERATIONS}$${salt.toString("hex")}$${digest.toString("hex")}`;
}

export function verifyPassword(password, stored) {
  const parts = stored.split("$");
  if (parts.length !== 4) return false;
  const [, iterations, saltHex, digestHex] = parts;
  const digest = crypto.pbkdf2Sync(
    password,
    Buffer.from(saltHex, "hex"),
    Number(iterations),
    KEYLEN,
    DIGEST
  );
  const expected = Buffer.from(digestHex, "hex");
  return digest.length === expected.length && crypto.timingSafeEqual(digest, expected);
}

export function createToken(userId) {
  return jwt.sign({ sub: String(userId) }, config.JWT_SECRET, {
    algorithm: "HS256",
    expiresIn: config.JWT_EXPIRES_IN,
  });
}

export function decodeToken(token) {
  const payload = jwt.verify(token, config.JWT_SECRET, { algorithms: ["HS256"] });
  return Number(payload.sub);
}

/** 8-digit numeric code, zero-padded (e.g. "00423981"). */
export function generateVerificationCode() {
  return crypto.randomInt(0, 100_000_000).toString().padStart(8, "0");
}
