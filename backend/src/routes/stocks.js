import { Router } from "express";

import { asyncHandler } from "../asyncHandler.js";
import * as stocks from "../stocks.js";

export const router = Router();

router.get("/stocks/search", asyncHandler(async (req, res) => {
  res.json(await stocks.search(String(req.query.q ?? "")));
}));

router.get("/stocks/quote/:symbol", asyncHandler(async (req, res) => {
  res.json(await stocks.quote(req.params.symbol.toUpperCase()));
}));
