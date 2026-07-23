/**
 * Thin wrapper around the Claude Messages API — a streaming helper for
 * CullyAI chat and a one-shot helper for USDA report analysis.
 */
import * as config from "./config.js";

const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";

export class AnthropicError extends Error {}

const TOOL_TIMEOUT_MS = 20000;

/** Guards a single tool executor call — a stuck DB query or leaked pool
 * connection would otherwise hang the whole agentic loop (and the SSE
 * response) forever, since only the Anthropic API calls have their own
 * abort timeout. */
function withTimeout(promise, ms, label) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

function headers() {
  if (!config.ANTHROPIC_API_KEY) {
    throw new AnthropicError("ANTHROPIC_API_KEY is not configured");
  }
  return {
    "content-type": "application/json",
    "x-api-key": config.ANTHROPIC_API_KEY,
    "anthropic-version": ANTHROPIC_VERSION,
  };
}

/**
 * Streams a Messages API response, invoking onDelta(text) for every text
 * chunk as it arrives. Resolves once the stream ends.
 */
export async function streamChat({ system, messages, maxTokens = 1024, onDelta }) {
  const resp = await fetch(ANTHROPIC_API_URL, {
    method: "POST",
    headers: headers(),
    body: JSON.stringify({
      model: config.ANTHROPIC_MODEL,
      max_tokens: maxTokens,
      system,
      messages,
      stream: true,
    }),
    signal: AbortSignal.timeout(60000),
  });

  if (!resp.ok || !resp.body) {
    const detail = await resp.text().catch(() => "");
    throw new AnthropicError(`Anthropic API HTTP ${resp.status}: ${detail}`);
  }

  const reader = resp.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });

    const lines = buffer.split("\n");
    buffer = lines.pop() ?? "";

    for (const line of lines) {
      if (!line.startsWith("data: ")) continue;
      const payload = line.slice(6).trim();
      if (!payload || payload === "[DONE]") continue;

      let event;
      try {
        event = JSON.parse(payload);
      } catch {
        continue;
      }

      if (event.type === "content_block_delta" && event.delta?.type === "text_delta") {
        onDelta(event.delta.text);
      }
    }
  }
}

/**
 * Agentic tool-use loop for CullyAI. Additive to this module — `complete()`
 * and `streamChat()` above are untouched so the 20+ other callers of this
 * client (WASDE analysis, daily brief, etc.) are unaffected.
 *
 * Runs non-streaming Messages API calls in a loop: whenever Claude responds
 * with `stop_reason: "tool_use"`, every `tool_use` block is executed via the
 * caller-supplied `executeTool(name, input)` and fed back as `tool_result`
 * blocks, until Claude produces a final answer (`stop_reason !== "tool_use"`)
 * or `maxIterations` is hit. Text blocks are forwarded via
 * `onEvent({type:'text', delta})` as they appear in each turn (a full turn's
 * text at a time, not token-by-token — true token streaming through a
 * tool-use loop requires accumulating partial `input_json_delta` events
 * across the stream, which is real added complexity deferred for now).
 *
 * The special `render_chart` tool is treated as a display directive, not a
 * data query: its `input` *is* the chart spec, forwarded immediately via
 * `onEvent({type:'block', block:{type:'chart', spec: input}})` so the
 * frontend can render it while Claude continues/finishes its explanation.
 */
export async function agenticComplete({
  system,
  messages,
  tools,
  executeTool,
  onEvent,
  maxIterations = 4,
  maxTokens = 1024,
}) {
  const conversation = [...messages];

  for (let iteration = 0; iteration < maxIterations; iteration++) {
    const resp = await fetch(ANTHROPIC_API_URL, {
      method: "POST",
      headers: headers(),
      body: JSON.stringify({
        model: config.ANTHROPIC_MODEL,
        max_tokens: maxTokens,
        system,
        messages: conversation,
        tools,
      }),
      signal: AbortSignal.timeout(60000),
    });

    if (!resp.ok) {
      const detail = await resp.text().catch(() => "");
      throw new AnthropicError(`Anthropic API HTTP ${resp.status}: ${detail}`);
    }

    const json = await resp.json();
    const content = json.content ?? [];

    for (const block of content) {
      if (block.type === "text" && block.text) {
        onEvent({ type: "text", delta: block.text });
      }
    }

    if (json.stop_reason !== "tool_use") {
      return;
    }

    conversation.push({ role: "assistant", content });

    const toolUseBlocks = content.filter((b) => b.type === "tool_use");
    const toolResults = [];
    for (const toolUse of toolUseBlocks) {
      if (toolUse.name === "render_chart") {
        onEvent({ type: "block", block: { type: "chart", spec: toolUse.input } });
        toolResults.push({
          type: "tool_result",
          tool_use_id: toolUse.id,
          content: "Chart rendered to the user.",
        });
        continue;
      }

      let result;
      try {
        result = await withTimeout(
          executeTool(toolUse.name, toolUse.input),
          TOOL_TIMEOUT_MS,
          `Tool ${toolUse.name}`
        );
      } catch (err) {
        result = { error: err.message ?? "Tool execution failed" };
      }
      toolResults.push({
        type: "tool_result",
        tool_use_id: toolUse.id,
        content: JSON.stringify(result),
      });
    }

    conversation.push({ role: "user", content: toolResults });
  }

  onEvent({
    type: "text",
    delta: "\n\n(Reached the tool-use step limit for this turn — try rephrasing more narrowly.)",
  });
}

/** Non-streaming helper for structured, one-shot completions (JSON out). */
export async function complete({ system, messages, maxTokens = 1024 }) {
  const resp = await fetch(ANTHROPIC_API_URL, {
    method: "POST",
    headers: headers(),
    body: JSON.stringify({
      model: config.ANTHROPIC_MODEL,
      max_tokens: maxTokens,
      system,
      messages,
    }),
    signal: AbortSignal.timeout(60000),
  });

  if (!resp.ok) {
    const detail = await resp.text().catch(() => "");
    throw new AnthropicError(`Anthropic API HTTP ${resp.status}: ${detail}`);
  }

  const json = await resp.json();
  return (json.content ?? []).map((b) => b.text ?? "").join("");
}
