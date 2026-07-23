/**
 * News Terminal — headlines from public RSS feeds (Reuters, USDA, AgWeb,
 * DTN Progressive Farmer, WSJ Markets, FT), tagged GRAIN/ENERGY/MACRO/
 * OTHER by CullyAI so the feed can be filtered by relevance. No API key
 * needed; feeds are plain RSS/XML fetched over HTTP.
 */
import { pool } from "./db.js";
import { complete } from "./anthropicClient.js";

export class NewsTerminalError extends Error {}

const REFRESH_STALE_MS = 15 * 60 * 1000;
const TAG_BATCH_SIZE = 25;

const FEEDS = [
  { source: "Reuters", url: "https://feeds.reuters.com/reuters/businessNews" },
  { source: "USDA", url: "https://www.usda.gov/rss/home.xml" },
  { source: "AgWeb", url: "https://www.agweb.com/rss.xml" },
  { source: "DTN Progressive Farmer", url: "https://www.dtnpf.com/agriculture/web/ag/rss" },
  { source: "WSJ Markets", url: "https://feeds.a.dj.com/rss/RSSMarketsMain.xml" },
  { source: "Financial Times", url: "https://www.ft.com/rss/home/us" },
];

function decodeEntities(text) {
  return text
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'")
    .trim();
}

function extractTag(itemXml, tag) {
  const match = itemXml.match(new RegExp(`<${tag}[^>]*>([\\s\\S]*?)</${tag}>`, "i"));
  return match ? decodeEntities(match[1]) : "";
}

/** Minimal regex-based RSS 2.0 <item> parser — no external XML dependency. */
function parseRss(xml, source) {
  const items = xml.match(/<item[\s\S]*?<\/item>/gi) ?? [];
  return items
    .map((itemXml) => {
      const title = extractTag(itemXml, "title");
      let link = extractTag(itemXml, "link");
      if (!link) {
        // Some feeds use <link href="..."/> (Atom-style) inside <item>.
        const hrefMatch = itemXml.match(/<link[^>]*href="([^"]+)"/i);
        link = hrefMatch ? hrefMatch[1] : "";
      }
      const pubDate = extractTag(itemXml, "pubDate") || extractTag(itemXml, "dc:date");
      const parsedDate = pubDate ? new Date(pubDate) : new Date();
      return {
        source,
        title,
        link: link.slice(0, 512),
        publishedAt: Number.isNaN(parsedDate.getTime()) ? new Date() : parsedDate,
      };
    })
    .filter((item) => item.title && item.link);
}

async function fetchFeed(feed) {
  const resp = await fetch(feed.url, {
    headers: { "user-agent": "Mozilla/5.0 (croploo-backend)" },
    signal: AbortSignal.timeout(10000),
  });
  if (!resp.ok) throw new NewsTerminalError(`HTTP ${resp.status} for ${feed.source}`);
  const xml = await resp.text();
  return parseRss(xml, feed.source);
}

async function isStale() {
  const [rows] = await pool.query(
    "SELECT MAX(created_at) AS latest FROM news_headlines"
  );
  const latest = rows[0]?.latest;
  if (!latest) return true;
  return Date.now() - new Date(latest).getTime() > REFRESH_STALE_MS;
}

async function refreshFeeds() {
  const results = await Promise.allSettled(FEEDS.map(fetchFeed));
  for (const [i, result] of results.entries()) {
    if (result.status === "rejected") {
      console.error(`news feed refresh failed for ${FEEDS[i].source}:`, result.reason);
      continue;
    }
    for (const item of result.value) {
      await pool.query(
        `INSERT IGNORE INTO news_headlines (source, title, link, published_at)
         VALUES (?, ?, ?, ?)`,
        [item.source, item.title.slice(0, 512), item.link, item.publishedAt]
      );
    }
  }
}

async function tagUntagged() {
  const [rows] = await pool.query(
    `SELECT id, title FROM news_headlines WHERE tag IS NULL
     ORDER BY published_at DESC LIMIT ?`,
    [TAG_BATCH_SIZE]
  );
  if (rows.length === 0) return;

  const system =
    "You are CullyAI classifying news headlines for a grain-trading terminal. For each " +
    "numbered headline, reply with exactly one line in the form 'N: TAG' where TAG is one " +
    "of GRAIN, ENERGY, MACRO, or OTHER. GRAIN = agriculture/crops/USDA/grain trade. " +
    "ENERGY = oil/gas/crude/refining. MACRO = Fed/inflation/GDP/dollar/broad markets. " +
    "OTHER = anything else. No other text, no markdown.";
  const numbered = rows.map((r, i) => `${i + 1}: ${r.title}`).join("\n");

  let text;
  try {
    text = await complete({
      system,
      messages: [{ role: "user", content: numbered }],
      maxTokens: 800,
    });
  } catch (err) {
    console.error("news headline tagging failed:", err);
    return;
  }

  const validTags = new Set(["GRAIN", "ENERGY", "MACRO", "OTHER"]);
  for (const line of text.split("\n")) {
    const match = line.match(/^\s*(\d+)\s*:\s*(\w+)/);
    if (!match) continue;
    const idx = Number(match[1]) - 1;
    const tag = match[2].toUpperCase();
    if (!validTags.has(tag) || !rows[idx]) continue;
    await pool.query("UPDATE news_headlines SET tag = ? WHERE id = ?", [tag, rows[idx].id]);
  }
}

export async function ensureFresh() {
  if (await isStale()) {
    await refreshFeeds();
  }
  await tagUntagged();
}

export async function snapshot({ limit = 60, tag = null } = {}) {
  await ensureFresh();
  const params = [];
  let where = "";
  if (tag) {
    where = "WHERE tag = ?";
    params.push(tag.toUpperCase());
  }
  params.push(limit);
  const [rows] = await pool.query(
    `SELECT source, title, link, published_at, tag FROM news_headlines
     ${where} ORDER BY published_at DESC LIMIT ?`,
    params
  );
  return rows.map((r) => ({
    source: r.source,
    title: r.title,
    link: r.link,
    published_at: r.published_at.toISOString(),
    tag: r.tag,
  }));
}
