/**
 * Gemini client for CullyAI chat — automatic fallback when Claude is
 * rate-limited or otherwise unavailable (see routes/cullyai.js). Mirrors
 * anthropicClient.js's `agenticComplete({system, messages, tools,
 * executeTool, onEvent, maxIterations, maxTokens})` signature and its
 * `onEvent({type:'text'|'block', ...})` contract so the route can swap
 * providers without changing how it consumes the stream.
 */
import * as config from "./config.js";

const GEMINI_BASE_URL = "https://generativelanguage.googleapis.com/v1beta";

export class GeminiError extends Error {}

function apiKey() {
  if (!config.GEMINI_API_KEY) {
    throw new GeminiError("GEMINI_API_KEY is not configured");
  }
  return config.GEMINI_API_KEY;
}

const TOOL_TIMEOUT_MS = 20000;

/** Guards a single tool executor call — see the identical helper in
 * anthropicClient.js for why this exists (a stuck DB query must not hang
 * the whole agentic loop forever). */
function withTimeout(promise, ms, label) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

/** Anthropic `input_schema` is JSON Schema with lowercase `type` values
 * ("object", "string", ...); Gemini's function-declaration `parameters`
 * use the same shape but `type` is an uppercase enum name. Everything else
 * (properties/required/items/enum) carries over unchanged. */
function convertSchema(schema) {
  if (schema == null || typeof schema !== "object") return schema;
  const out = { ...schema };
  if (typeof out.type === "string") out.type = out.type.toUpperCase();
  if (out.properties) {
    out.properties = Object.fromEntries(
      Object.entries(out.properties).map(([key, value]) => [key, convertSchema(value)])
    );
  }
  if (out.items) out.items = convertSchema(out.items);
  return out;
}

function toGeminiTools(tools) {
  if (!tools?.length) return undefined;
  return [
    {
      function_declarations: tools.map((t) => ({
        name: t.name,
        description: t.description,
        parameters: convertSchema(t.input_schema),
      })),
    },
  ];
}

/** Same flat `{role: 'user'|'assistant', content: string}` shape the route
 * hands to anthropicClient.agenticComplete() — converted to Gemini's
 * `{role: 'user'|'model', parts: [{text}]}` turns. */
function toGeminiContents(messages) {
  return messages.map((m) => ({
    role: m.role === "assistant" ? "model" : "user",
    parts: [{ text: String(m.content ?? "") }],
  }));
}

async function callGemini(body) {
  const resp = await fetch(
    `${GEMINI_BASE_URL}/models/${config.GEMINI_MODEL}:generateContent?key=${apiKey()}`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(60000),
    }
  );
  if (!resp.ok) {
    const detail = await resp.text().catch(() => "");
    throw new GeminiError(`Gemini API HTTP ${resp.status}: ${detail}`);
  }
  return resp.json();
}

/** Same tool-use loop as anthropicClient.agenticComplete(): call the model,
 * execute any requested tools, feed results back, repeat until it stops
 * asking for tools or `maxIterations` is hit. `render_chart` is a display
 * directive (forwarded to the frontend immediately), not a data query. */
export async function agenticComplete({
  system,
  messages,
  tools,
  executeTool,
  onEvent,
  maxIterations = 4,
  maxTokens = 1024,
}) {
  const contents = toGeminiContents(messages);
  const geminiTools = toGeminiTools(tools);

  for (let iteration = 0; iteration < maxIterations; iteration++) {
    const json = await callGemini({
      system_instruction: { parts: [{ text: system }] },
      contents,
      tools: geminiTools,
      generationConfig: { maxOutputTokens: maxTokens },
    });

    const candidate = json.candidates?.[0];
    const parts = candidate?.content?.parts ?? [];

    for (const part of parts) {
      if (part.text) onEvent({ type: "text", delta: part.text });
    }

    const functionCalls = parts.filter((p) => p.functionCall);
    if (functionCalls.length === 0) {
      return;
    }

    contents.push({ role: "model", parts });

    const responseParts = [];
    for (const part of functionCalls) {
      const { name, args } = part.functionCall;

      if (name === "render_chart") {
        onEvent({ type: "block", block: { type: "chart", spec: args } });
        responseParts.push({
          functionResponse: { name, response: { name, content: "Chart rendered to the user." } },
        });
        continue;
      }

      let result;
      try {
        result = await withTimeout(executeTool(name, args), TOOL_TIMEOUT_MS, `Tool ${name}`);
      } catch (err) {
        result = { error: err.message ?? "Tool execution failed" };
      }
      responseParts.push({ functionResponse: { name, response: { name, content: result } } });
    }

    contents.push({ role: "user", parts: responseParts });
  }

  onEvent({
    type: "text",
    delta: "\n\n(Reached the tool-use step limit for this turn — try rephrasing more narrowly.)",
  });
}
