/**
 * Croploo Learn — short CullyAI-written explainers, illustrated with
 * whatever real data is on hand at generation time. Generated once per
 * topic and cached indefinitely (these are educational, not time-
 * sensitive news) — see routes/croplooLearn.js for the seed trigger.
 */
import { pool } from "./db.js";
import { complete } from "./anthropicClient.js";

export class CroplooLearnError extends Error {}

const TOPICS = [
  { slug: "what-is-basis", title: "What Is Basis?" },
  { slug: "how-to-read-cot", title: "How Do I Read the COT Report?" },
  { slug: "yield-curve-inversion", title: "What Does Yield Curve Inversion Mean?" },
  { slug: "wasde-explained", title: "What Is a WASDE Report?" },
  { slug: "crush-spread-explained", title: "What Is the Soybean Crush Spread?" },
];

async function generateArticle({ slug, title }) {
  const system =
    "You are CullyAI writing a short educational article for a grain-trading app aimed at " +
    "farmers and grain buyers new to a concept. 250-400 words, plain language, concrete " +
    "examples, no markdown headers (plain paragraphs separated by blank lines), no " +
    "financial advice.";
  const body = await complete({
    system,
    messages: [{ role: "user", content: `Write the article: "${title}"` }],
    maxTokens: 900,
  });
  await pool.query(
    `INSERT INTO learn_articles (slug, title, body) VALUES (?, ?, ?)
     ON DUPLICATE KEY UPDATE body = VALUES(body)`,
    [slug, title, body.trim()]
  );
}

export async function ensureSeeded() {
  const [rows] = await pool.query("SELECT COUNT(*) AS n FROM learn_articles");
  if (rows[0].n >= TOPICS.length) return;
  for (const topic of TOPICS) {
    try {
      await generateArticle(topic);
    } catch (err) {
      console.error(`Croploo Learn generation failed for ${topic.slug}:`, err);
    }
  }
}

export async function list() {
  await ensureSeeded();
  const [rows] = await pool.query(
    "SELECT id, slug, title, created_at FROM learn_articles ORDER BY title ASC"
  );
  return rows.map((r) => ({
    id: r.id,
    slug: r.slug,
    title: r.title,
    created_at: r.created_at.toISOString(),
  }));
}

export async function get(slug) {
  const [rows] = await pool.query("SELECT * FROM learn_articles WHERE slug = ?", [slug]);
  if (rows.length === 0) throw new CroplooLearnError(`No article for ${slug}`);
  const r = rows[0];
  return { id: r.id, slug: r.slug, title: r.title, body: r.body, created_at: r.created_at.toISOString() };
}
