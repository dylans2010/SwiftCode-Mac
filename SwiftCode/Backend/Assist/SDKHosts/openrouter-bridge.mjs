// openrouter-bridge.mjs — SwiftCode Assist <-> OpenRouter Agent SDK bridge.
//
// Runs under Node. It is NOT part of the Xcode target: the shared runtime
// manager installs this file (plus a node_modules tree holding
// @openrouter/agent and its dependencies) into Application Support, e.g.
//   <Application Support>/SwiftCode/SDKRuntime/openrouter/bridge/openrouter-bridge.mjs
//   <Application Support>/SwiftCode/SDKRuntime/openrouter/node_modules/@openrouter/agent
//   <Application Support>/SwiftCode/SDKRuntime/openrouter/node_modules/zod
//   <Application Support>/SwiftCode/SDKRuntime/openrouter/node_modules/@openrouter/sdk
// (the repo copy at SwiftCode/Backend/Assist/SDKHosts/openrouter-bridge.mjs
// is the source the manager copies from). Node resolves
// '@openrouter/agent' by walking up from the bridge file and via the
// NODE_PATH the manager sets, so the bridge must live inside that
// installed directory, not beside the .swift sources. Swift launches it
// with argv:
//
//   node openrouter-bridge.mjs
//
// with the API key ONLY in an environment variable —
// SWIFTCODE_OPENROUTER_API_KEY, or OPENROUTER_API_KEY as injected by
// SDKRuntimeManager for the openRouter provider — or, when the launcher
// passes no key environment (Workstream A's SDKBridgeLaunching seam),
// in the run request's non-logged `apiKey` field. Never argv, never
// logged, never echoed back in any stdout/stderr line; error text is
// scrubbed of the key.
// One run per process: Swift sends one `run` line, answers `tool_call`
// lines with `tool_result` lines, and the process exits after `done`
// or `error`.
//
// NDJSON protocol (shared across SDK hosts). Swift -> bridge, one JSON
// object per stdin line:
//   {"type":"run","requestId","provider":"openrouter","model",
//    "systemPrompt","userText","history":[{"role","text"}],
//    "tools":[{"name","description","parameters"}],
//    "toolSource":"swiftcode|openrouter|combined",
//    "config":{"maxSteps","maxCost","toolTimeoutMs","perRequestTimeoutMs",
//              "allowFinalResponse"}}
//   {"type":"tool_result","id","result"} | {"type":"tool_result","id","error":...}
//   {"type":"cancel","requestId"}
// Bridge -> Swift, one JSON object per stdout line:
//   {"type":"ready","provider":"openrouter","sdkVersion"}
//   {"type":"text","delta"}
//   {"type":"tool_event","event":{provider,sessionId,toolCallId,toolName,source,
//     state,arguments,result,error,startedAt,completedAt}}
//   {"type":"tool_call","id","name","arguments"}  (SwiftCode-native tool;
//     the bridge waits for the matching tool_result line before the run
//     continues — a model-generated tool request is NEVER a completed
//     execution, and a Swift error is thrown back into the SDK as a tool
//     error, never reported as success)
//   {"type":"done","finalText"}
//   {"type":"error","message"}
//
// Readiness contract — read this before treating "ready" as "connected":
// "ready" is printed ONLY after the @openrouter/agent imports resolve,
// which proves the SDK is installed and loadable. It does NOT prove the
// API key is valid. @openrouter/agent 0.11.0 exposes no cost-free key
// check: client construction does not contact the API, and the only
// key verification is a real model call. The bridge therefore never
// prints a fake "connected" state. The first run's 401 is mapped to an
// actionable "invalid API key" error line (see mapRunError). Settings'
// connection test remains OpenRouterAssistProvider's /models check; the
// bridge's job is execution, not authentication probing.
//
// SDK surface used (verified against the installed @openrouter/agent
// 0.11.0, esm/*.d.ts — not from memory):
//   import { callModel, tool, stepCountIs, maxCost } from '@openrouter/agent'
//   import { OpenRouter } from '@openrouter/agent/openrouter'
//     new OpenRouter({ apiKey })  (extends @openrouter/sdk OpenRouterCore)
//   callModel(client, { model, input, instructions, tools, stopWhen,
//     allowFinalResponse, signal, toolTimeoutMs }, { timeoutMs })
//     -> ModelResult with getText(), getTextStream(), getToolStream(),
//        getToolCallsStream(), cancel()
//   callModel input: string | Item[]; history items are EasyInputMessage
//     { role, content }. `instructions` is a ResponsesRequest field
//     carried by BaseCallModelInput, and the SDK re-sends the full
//     accumulated input array AND the original `instructions` on every
//     turn (documented in async-params.d.ts allowFinalResponse notes and
//     README "The pending tool calls ... then the full conversation and
//     the original `instructions` are sent"), so SwiftCode's system
//     prompt persists across tool rounds — it is not a first-turn-only
//     prefix.
//   tool({ name, description, inputSchema, execute, timeoutMs })
//     inputSchema is a Zod v4 object (zod/v4/core $ZodObject); execute
//     receives (params, context) where context.callId is the call id.
//   stopWhen: [stepCountIs(n), maxCost(dollars)] (OR semantics).
//   Cancellation: the `signal` option (AbortController) aborts the
//     in-flight request/stream and stops the loop at the next turn
//     boundary; ModelResult.cancel() does the same from the outside.
//     A supplied `signal` composes with per-request `timeoutMs` (the
//     RequestOptions third argument); passing a raw signal through
//     RequestOptions would silently disable the SDK's timeout wiring,
//     so the bridge always uses the `signal` option, never RequestOptions.
//   Tool timeout: tool-level `timeoutMs` (and run-level `toolTimeoutMs`)
//     bounds the round's WAIT, not the tool body; on expiry the model
//     receives { error, code: 'tool_timeout' } and ctx.signal aborts.
//
// System prompt mechanism: `instructions` = SwiftCode's real system
// prompt, verbatim, on the callModel request. History + userText become
// the `input` item array. Nothing else is injected as system content.
//
// Tool sources:
//   swiftcode — every request tool becomes tool() whose execute posts a
//     tool_call line and awaits Swift's tool_result. Swift executes via
//     the native registry (validation/permissions in the Swift layer);
//     the bridge enforces a per-call timeout and surfaces Swift errors
//     as tool errors to the model.
//   openrouter — tools execute in this JS host. The host catalog is
//     exactly two real tools (see buildHostTools): fetch_url (safe HTTP
//     GET with private-network blocking, timeout, and size cap) and
//     current_datetime. Host tools NEVER touch the filesystem or shell.
//   combined — swiftcode tools (bridged) + host tools together. On a
//     name collision the swiftcode tool wins and the host tool is
//     renamed with prefix `openrouter_`; routing is by the event's
//     `source` field, never by display name alone.
//   opencode — NOT supported as a tool source for OpenRouter. The bridge
//     errors actionably instead of silently falling back to another
//     source.
//
// Tool-name sanitisation: OpenAI function names allow [a-zA-Z0-9_-].
// Swift tool names outside that set are sanitised to the model-facing
// name (other characters -> '_'); the tool_call line and Swift routing
// always use the ORIGINAL name via the modelName -> originalName map.
// The SDK-reserved name 'task' is renamed to 'swiftcode_task' for the
// same reason. Two different originals sanitising to one model name is
// an actionable error, never a silent merge.
//
// Tool-event identity: getToolCallsStream() yields ParsedToolCall
// { id, name, arguments } as calls are parsed; execute() receives the
// same call (context.callId). Both paths register in one map keyed by
// name + stable argument JSON, so exactly one `requested` event is
// emitted per call and `running`/`completed`/`failed` reuse its id.
// Zod schemas use looseObject (unknown keys preserved) precisely so
// parsed arguments and execute params stay identical for that key.

import * as dns from "node:dns";
import * as net from "node:net";
import { createRequire } from "node:module";
import * as readline from "node:readline";
import { pathToFileURL } from "node:url";
import { callModel, maxCost, stepCountIs, tool } from "@openrouter/agent";
import { OpenRouter } from "@openrouter/agent/openrouter";
import { z } from "zod";

const PROVIDER = "openrouter";
const ENV_KEY = "SWIFTCODE_OPENROUTER_API_KEY";
const READY_TYPE = "ready";
const DEFAULT_MAX_STEPS = 25;
const DEFAULT_MAX_COST = 2.0;
const DEFAULT_TOOL_TIMEOUT_MS = 120_000;
const DEFAULT_REQUEST_TIMEOUT_MS = 90_000;
const HOST_FETCH_TIMEOUT_MS = 15_000;
const HOST_FETCH_MAX_BYTES = 200_000;
const HOST_FETCH_MAX_REDIRECTS = 3;

const require = createRequire(import.meta.url);
let SDK_VERSION = "unknown";
try {
  SDK_VERSION = require("@openrouter/agent/package.json").version;
} catch {
  // Imports above already resolved; version is informational only.
}

// ---------------------------------------------------------------------------
// Small utilities (exported for the smoke test; no side effects on import).
// ---------------------------------------------------------------------------

export function stableStringify(value) {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(",")}]`;
  const keys = Object.keys(value).sort();
  return `{${keys
    .map((k) => `${JSON.stringify(k)}:${stableStringify(value[k])}`)
    .join(",")}}`;
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

// Convert a JSON Schema object (the shape Swift sends for a tool's
// `parameters`) into a Zod v4 object schema. Supported: string, number,
// integer, boolean, array, object (nested), string enums, required vs
// optional, descriptions. Anything else degrades to z.unknown() for that
// node rather than failing the whole tool — the model still sees the
// tool, and Swift-side validation remains the authority on arguments.
// Top-level and nested objects use looseObject so unknown keys survive
// Zod parsing: parsed tool-call arguments and execute() params must be
// identical for tool-event correlation (see header).
export function jsonSchemaToZod(schema) {
  if (!isPlainObject(schema)) return z.unknown();
  if (Array.isArray(schema.enum) && schema.enum.length > 0) {
    const values = schema.enum.filter((v) => typeof v === "string");
    if (values.length > 0 && values.length === schema.enum.length) {
      const out = z.enum(values);
      return schema.description ? out.describe(schema.description) : out;
    }
  }
  let out;
  switch (schema.type) {
    case "string":
      out = z.string();
      break;
    case "number":
      out = z.number();
      break;
    case "integer":
      out = z.number().int();
      break;
    case "boolean":
      out = z.boolean();
      break;
    case "null":
      out = z.null();
      break;
    case "array":
      out = z.array(
        schema.items ? jsonSchemaToZod(schema.items) : z.unknown(),
      );
      break;
    case "object": {
      const props = isPlainObject(schema.properties) ? schema.properties : {};
      const required = new Set(
        Array.isArray(schema.required) ? schema.required : [],
      );
      const shape = {};
      for (const [name, prop] of Object.entries(props)) {
        const converted = jsonSchemaToZod(prop);
        shape[name] = required.has(name) ? converted : converted.optional();
      }
      out = z.looseObject(shape);
      break;
    }
    default:
      // No `type`, but properties present: treat as an object.
      if (isPlainObject(schema.properties)) {
        return jsonSchemaToZod({ ...schema, type: "object" });
      }
      out = z.unknown();
  }
  return schema.description ? out.describe(schema.description) : out;
}

export function toolInputSchema(parameters) {
  if (!isPlainObject(parameters)) return z.looseObject({});
  // parameters is itself the object schema for the tool's arguments.
  const converted = jsonSchemaToZod(parameters);
  // jsonSchemaToZod returns a looseObject for object schemas; anything
  // else (e.g. a bare non-object schema) cannot be a tool input schema.
  if (converted && converted._zod && converted._zod.def
      && converted._zod.def.type === "object") {
    return converted;
  }
  return z.looseObject({});
}

function sanitizeModelToolName(name) {
  if (name === "task") return "swiftcode_task";
  return name.replace(/[^a-zA-Z0-9_-]/g, "_");
}

// ---------------------------------------------------------------------------
// Host-side tools (toolSource "openrouter"). Exactly two, both real.
// Neither touches the filesystem, the shell, or any credential.
// ---------------------------------------------------------------------------

function isPrivateIp(ip) {
  if (!ip) return false;
  if (net.isIP(ip) === 4) {
    const [a, b] = ip.split(".").map(Number);
    if (a === 10) return true;
    if (a === 127) return true;
    if (a === 172 && b >= 16 && b <= 31) return true;
    if (a === 192 && b === 168) return true;
    if (a === 169 && b === 254) return true;
    return false;
  }
  if (net.isIP(ip) === 6) {
    const lower = ip.toLowerCase();
    return lower === "::1" || lower.startsWith("fc") || lower.startsWith("fd")
      || lower.startsWith("fe8") || lower.startsWith("fe9")
      || lower.startsWith("fea") || lower.startsWith("feb");
  }
  return false;
}

async function assertPublicUrl(rawUrl) {
  let url;
  try {
    url = new URL(rawUrl);
  } catch {
    throw new Error(`fetch_url: not a valid URL: ${rawUrl}`);
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new Error(`fetch_url: only http/https are allowed, got ${url.protocol}`);
  }
  const host = url.hostname;
  if (host === "localhost" || host.endsWith(".localhost")) {
    throw new Error("fetch_url: localhost targets are blocked");
  }
  if (net.isIP(host)) {
    if (isPrivateIp(host)) throw new Error(`fetch_url: private IP targets are blocked (${host})`);
    return url;
  }
  const resolved = await dns.lookup(host).catch(() => null);
  if (resolved && isPrivateIp(resolved.address)) {
    throw new Error(`fetch_url: ${host} resolves to a private IP and is blocked`);
  }
  return url;
}

async function fetchUrlImpl({ url: rawUrl }) {
  let current = await assertPublicUrl(rawUrl);
  let response = null;
  for (let hop = 0; hop <= HOST_FETCH_MAX_REDIRECTS; hop++) {
    response = await fetch(current.toString(), {
      method: "GET",
      redirect: "manual",
      signal: AbortSignal.timeout(HOST_FETCH_TIMEOUT_MS),
      // Deliberately minimal: no Authorization, no cookies, no env-derived
      // headers. Nothing credential-like is ever forwarded to the target.
      headers: {
        Accept: "text/html,application/json,application/xml,text/*;q=0.8",
        "User-Agent": "SwiftCode-OpenRouter-Host/1.0",
      },
    });
    if (response.status >= 300 && response.status < 400) {
      const location = response.headers.get("location");
      if (!location) break;
      if (hop === HOST_FETCH_MAX_REDIRECTS) {
        throw new Error("fetch_url: too many redirects");
      }
      current = await assertPublicUrl(new URL(location, current).toString());
      continue;
    }
    break;
  }
  const contentType = response.headers.get("content-type") || "";
  const isText = contentType.startsWith("text/")
    || contentType.includes("json") || contentType.includes("xml");
  if (!isText) {
    // Consume (and discard) the body so the connection is released, but
    // never return binary content to the model.
    await response.arrayBuffer().catch(() => null);
    return {
      status: response.status,
      contentType,
      text: "",
      note: "Non-text content is not returned by fetch_url.",
    };
  }
  const reader = response.body.getReader();
  const chunks = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > HOST_FETCH_MAX_BYTES) {
      await reader.cancel().catch(() => null);
      throw new Error(
        `fetch_url: response exceeds the ${HOST_FETCH_MAX_BYTES} byte cap`,
      );
    }
    chunks.push(value);
  }
  const text = Buffer.concat(chunks).toString("utf-8");
  return { status: response.status, contentType, text };
}

// Returns plain tool configs (NOT tool() objects): the run handler wraps
// each config exactly once with tool(), adding the event-emitting
// execute wrapper and the per-call timeout. Wrapping twice would feed a
// Tool object back into the tool() factory, which expects a config.
export function buildHostTools() {
  return [
    {
      modelName: "fetch_url",
      source: "openrouter",
      name: "fetch_url",
      description:
        "Fetch a public http/https URL with GET and return its status, content type, and text (up to 200KB). Private-network and localhost targets are blocked, no credentials are forwarded, and binary content is not returned.",
      inputSchema: z.looseObject({ url: z.string() }),
      execute: fetchUrlImpl,
    },
    {
      modelName: "current_datetime",
      source: "openrouter",
      name: "current_datetime",
      description: "Return the current date and time in UTC (ISO string and Unix seconds).",
      inputSchema: z.looseObject({}),
      execute: async () => {
        const now = new Date();
        return { iso: now.toISOString(), unix: Math.floor(now.getTime() / 1000) };
      },
    },
  ];
}

// ---------------------------------------------------------------------------
// Bridge runtime (only runs when executed directly, not on import).
// ---------------------------------------------------------------------------

function redact(text, secrets) {
  let out = String(text);
  for (const secret of secrets) {
    if (secret && secret.length >= 8) out = out.split(secret).join("[redacted]");
  }
  return out;
}

// SDK failures are not always plain Errors: the @openrouter/sdk error
// classes carry statusCode (not status) and a nested error.message, and
// a dummy/invalid key fails as "User not found." — which is a 401 even
// though the text never says so. Extract message + status defensively.
function errorMessage(error) {
  if (error instanceof Error) return error.message || String(error);
  if (error && typeof error === "object") {
    if (typeof error.message === "string" && error.message) return error.message;
    if (error.error && typeof error.error.message === "string") return error.error.message;
    if (error.data$ && error.data$.error && typeof error.data$.error.message === "string") {
      return error.data$.error.message;
    }
  }
  return String(error);
}

function errorStatus(error) {
  if (!error || typeof error !== "object") return null;
  for (const key of ["statusCode", "status", "code"]) {
    if (typeof error[key] === "number") return error[key];
    if (error.error && typeof error.error[key] === "number") return error.error[key];
  }
  return null;
}

function mapRunError(error) {
  const raw = errorMessage(error);
  const status = errorStatus(error);
  if (status === 401 || /401|unauthorized|invalid api key|user not found/i.test(raw)) {
    return "OpenRouter rejected the API key (401). Check the key in Assist Settings (API Keys) and test the connection again.";
  }
  if (status === 402 || /402|insufficient.*credit/i.test(raw)) {
    return "OpenRouter reports insufficient credits (402) for this account.";
  }
  if (status === 429 || /429|rate limit/i.test(raw)) {
    return "OpenRouter rate-limited the request (429). Wait and retry.";
  }
  return raw;
}

async function main() {
  let apiKey = "";
  const secrets = [];
  const emitQueue = [];
  let emitting = false;
  const out = (obj) => {
    // Promise-based write so process.exit below never truncates stdout.
    const line = `${JSON.stringify(obj)}\n`;
    return new Promise((resolve) => {
      emitQueue.push([line, resolve]);
      if (!emitting) drainQueue();
    });
  };
  function drainQueue() {
    emitting = true;
    const next = emitQueue.shift();
    if (!next) {
      emitting = false;
      return;
    }
    const [line, resolve] = next;
    process.stdout.write(line, () => {
      resolve();
      drainQueue();
    });
  }
  const diag = (message) => {
    process.stderr.write(`${redact(message, secrets)}\n`);
  };

  await out({ type: READY_TYPE, provider: PROVIDER, sdkVersion: SDK_VERSION });

  const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });

  let runPromise = null;
  let runAbort = null;
  let runResult = null;
  let cancelled = false;
  let runFinished = false;
  const pendingToolResults = new Map();
  let exitCode = null;

  const finish = async (code) => {
    if (exitCode !== null) return;
    exitCode = code;
    try {
      rl.close();
    } catch { /* already closed */ }
    // Drain the emit queue before exiting so the final line is not lost.
    while (emitting || emitQueue.length > 0) {
      await new Promise((r) => setTimeout(r, 5));
    }
    process.exit(code);
  };

  const abortRun = async (reason) => {
    cancelled = true;
    try {
      runAbort?.abort(new Error(reason));
    } catch { /* controller already aborted */ }
    try {
      if (runResult) await runResult.cancel();
    } catch { /* cancel is best-effort; the abort signal is authoritative */ }
    for (const [id, pending] of pendingToolResults) {
      pending.reject(new Error(reason));
      pendingToolResults.delete(id);
    }
  };

  process.on("SIGTERM", () => {
    void abortRun("cancelled by Swift").then(() => finish(0));
  });
  process.on("SIGINT", () => {
    void abortRun("cancelled by Swift").then(() => finish(0));
  });

  const handleRun = async (run) => {
    const sessionId = run.requestId || "openrouter-run";
    const fail = async (message) => {
      await out({ type: "error", message: redact(message, secrets) });
      await finish(1);
    };

    try {
      if (run.provider !== PROVIDER) {
        await fail(`This bridge serves provider "${PROVIDER}", not "${run.provider}".`);
        return;
      }
      if (run.toolSource === "opencode") {
        await fail(
          "Tool source \"opencode\" is not supported by the OpenRouter SDK provider. "
          + "Use \"swiftcode\", \"openrouter\", or \"combined\".",
        );
        return;
      }
      if (!["swiftcode", "openrouter", "combined"].includes(run.toolSource)) {
        await fail(`Unsupported toolSource "${run.toolSource}". Use "swiftcode", "openrouter", or "combined".`);
        return;
      }
      const model = typeof run.model === "string" ? run.model.trim() : "";
      if (!model || /\s/.test(model)) {
        await fail(
          "The selected model id is empty or malformed. Select an OpenRouter model "
          + "(provider/model, e.g. openai/gpt-4o) in Assist Settings; no substitute model was chosen.",
        );
        return;
      }
      if (typeof run.systemPrompt !== "string" || run.systemPrompt.trim() === "") {
        await fail("No system prompt was supplied. SwiftCode's real system prompt is required; a generic prompt is never substituted.");
        return;
      }
      if (typeof run.userText !== "string" || run.userText.trim() === "") {
        await fail("No user text was supplied for this run.");
        return;
      }
      apiKey = process.env[ENV_KEY] || process.env.OPENROUTER_API_KEY
        || (typeof run.apiKey === "string" ? run.apiKey : "");
      if (apiKey) secrets.push(apiKey);
      if (!apiKey) {
        await fail(
          "No OpenRouter API key is available to this bridge. Add one in Assist Settings "
          + "(API Keys) — the key is passed via the SWIFTCODE_OPENROUTER_API_KEY environment "
          + "variable, never on the command line.",
        );
        return;
      }

      const config = run.config && typeof run.config === "object" ? run.config : {};
      const maxSteps = Number.isInteger(config.maxSteps) && config.maxSteps >= 1
        && config.maxSteps <= 200 ? config.maxSteps : DEFAULT_MAX_STEPS;
      // NOTE: named maxCostDollars deliberately — a local called `maxCost`
      // would shadow the imported maxCost() stop-condition factory.
      const maxCostDollars = typeof config.maxCost === "number" && config.maxCost > 0
        ? config.maxCost : DEFAULT_MAX_COST;
      const toolTimeoutMs = Number.isInteger(config.toolTimeoutMs)
        && config.toolTimeoutMs >= 1000 ? config.toolTimeoutMs : DEFAULT_TOOL_TIMEOUT_MS;
      const perRequestTimeoutMs = Number.isInteger(config.perRequestTimeoutMs)
        && config.perRequestTimeoutMs >= 1000
        ? config.perRequestTimeoutMs : DEFAULT_REQUEST_TIMEOUT_MS;
      const allowFinalResponse = config.allowFinalResponse === undefined
        ? true : config.allowFinalResponse;

      // --- Build the tool list -------------------------------------------------
      const requestTools = Array.isArray(run.tools) ? run.tools : [];
      const swiftcodeByModelName = new Map(); // modelName -> original name
      const swiftcodeTools = [];
      if (run.toolSource === "swiftcode" || run.toolSource === "combined") {
        for (const t of requestTools) {
          if (!t || typeof t.name !== "string" || t.name.trim() === "") {
            await fail("A tool in the run request has no name; refusing to build an ambiguous tool list.");
            return;
          }
          const modelName = sanitizeModelToolName(t.name);
          if (swiftcodeByModelName.has(modelName)) {
            await fail(
              `Two SwiftCode tools sanitise to the same model-facing name "${modelName}" `
              + `("${swiftcodeByModelName.get(modelName)}" and "${t.name}"). Rename one; no silent merge is performed.`,
            );
            return;
          }
          swiftcodeByModelName.set(modelName, t.name);
          swiftcodeTools.push({ originalName: t.name, modelName, tool: t });
        }
      }
      const swiftcodeNames = new Set(swiftcodeTools.map((t) => t.modelName));

      const requestedByKey = new Map(); // name + args JSON -> { id, modelName }
      const emitToolEvent = (fields) => out({
        type: "tool_event",
        event: {
          provider: PROVIDER,
          sessionId,
          ...fields,
        },
      });
      const ensureRequested = (modelName, displayName, source, args) => {
        const key = `${modelName}\n${stableStringify(args)}`;
        const existing = requestedByKey.get(key);
        if (existing) return existing.id;
        const id = `tc_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`;
        requestedByKey.set(key, { id, modelName });
        void emitToolEvent({
          toolCallId: id,
          toolName: displayName,
          source,
          state: "requested",
          arguments: args,
          startedAt: new Date().toISOString(),
        });
        return id;
      };

      const makeBridgedExecute = (modelName, displayName) => {
        return async (params, context) => {
          const args = params && typeof params === "object" ? params : {};
          const id = ensureRequested(modelName, displayName, "swiftcode", args);
          // If the stream consumer already registered this call, the id
          // above is the stream's id; otherwise it is the execute
          // context's call id (or a generated one) — either way exactly
          // one `requested` event exists for this call.
          await emitToolEvent({
            toolCallId: id,
            toolName: displayName,
            source: "swiftcode",
            state: "running",
            arguments: args,
            startedAt: new Date().toISOString(),
          });
          await out({ type: "tool_call", id, name: displayName, arguments: args });
          const result = await new Promise((resolve, reject) => {
            const timer = setTimeout(() => {
              pendingToolResults.delete(id);
              reject(new Error(
                `Timed out after ${toolTimeoutMs}ms waiting for Swift to answer tool call "${displayName}".`,
              ));
            }, toolTimeoutMs + 30_000); // backstop only; the SDK's own
            // timeoutMs (below) is what reports tool_timeout to the model.
            const onAbort = () => {
              clearTimeout(timer);
              pendingToolResults.delete(id);
              reject(new Error("cancelled by Swift"));
            };
            if (context && context.signal) {
              if (context.signal.aborted) {
                onAbort();
                return;
              }
              context.signal.addEventListener("abort", onAbort, { once: true });
            }
            pendingToolResults.set(id, {
              resolve: (value) => {
                clearTimeout(timer);
                resolve(value);
              },
              reject: (error) => {
                clearTimeout(timer);
                reject(error);
              },
            });
          }).catch(async (error) => {
            await emitToolEvent({
              toolCallId: id,
              toolName: displayName,
              source: "swiftcode",
              state: "failed",
              arguments: args,
              error: redact(error.message || String(error), secrets),
              completedAt: new Date().toISOString(),
            });
            throw error; // SDK surfaces this as a tool error to the model.
          });
          await emitToolEvent({
            toolCallId: id,
            toolName: displayName,
            source: "swiftcode",
            state: "completed",
            arguments: args,
            result,
            completedAt: new Date().toISOString(),
          });
          return result;
        };
      };

      const sdkTools = [];
      for (const entry of swiftcodeTools) {
        sdkTools.push(tool({
          name: entry.modelName,
          description: entry.tool.description || `SwiftCode-native tool ${entry.originalName}.`,
          inputSchema: toolInputSchema(entry.tool.parameters),
          timeoutMs: toolTimeoutMs,
          execute: makeBridgedExecute(entry.modelName, entry.originalName),
        }));
      }
      if (run.toolSource === "openrouter" || run.toolSource === "combined") {
        for (const host of buildHostTools()) {
          let modelName = host.modelName;
          let displayName = host.modelName;
          if (run.toolSource === "combined" && swiftcodeNames.has(modelName)) {
            // SwiftCode wins; the host tool is renamed, never dropped
            // silently and never allowed to shadow the native tool.
            modelName = `openrouter_${modelName}`;
            displayName = modelName;
          }
          const originalExecute = host.execute;
          sdkTools.push(tool({
            name: modelName,
            description: host.description,
            inputSchema: host.inputSchema,
            timeoutMs: toolTimeoutMs,
            execute: async (params, context) => {
              const args = params && typeof params === "object" ? params : {};
              const id = ensureRequested(modelName, displayName, "openrouter", args);
              await emitToolEvent({
                toolCallId: id,
                toolName: displayName,
                source: "openrouter",
                state: "running",
                arguments: args,
                startedAt: new Date().toISOString(),
              });
              try {
                const result = await originalExecute(params, context);
                await emitToolEvent({
                  toolCallId: id,
                  toolName: displayName,
                  source: "openrouter",
                  state: "completed",
                  arguments: args,
                  result,
                  completedAt: new Date().toISOString(),
                });
                return result;
              } catch (error) {
                await emitToolEvent({
                  toolCallId: id,
                  toolName: displayName,
                  source: "openrouter",
                  state: "failed",
                  arguments: args,
                  error: redact(error.message || String(error), secrets),
                  completedAt: new Date().toISOString(),
                });
                throw error;
              }
            },
          }));
        }
      }

      // --- Build callModel input ----------------------------------------------
      // instructions = SwiftCode's real system prompt (verbatim, and
      // re-sent by the SDK on every turn — see header). History + the new
      // user turn become the input item array.
      const roleMap = {
        user: "user",
        assistant: "assistant",
        system: "system",
        developer: "developer",
      };
      const input = [];
      const history = Array.isArray(run.history) ? run.history : [];
      for (const item of history) {
        if (!item || typeof item.text !== "string") continue;
        input.push({
          role: roleMap[item.role] || "user",
          content: item.text,
        });
      }
      input.push({ role: "user", content: run.userText });

      const client = new OpenRouter({ apiKey });
      runAbort = new AbortController();
      const result = callModel(client, {
        model,
        input,
        instructions: run.systemPrompt,
        tools: sdkTools,
        stopWhen: [stepCountIs(maxSteps), maxCost(maxCostDollars)],
        allowFinalResponse,
        signal: runAbort.signal,
        toolTimeoutMs,
      }, { timeoutMs: perRequestTimeoutMs });
      runResult = result;

      const textStream = (async () => {
        for await (const delta of result.getTextStream()) {
          if (delta) await out({ type: "text", delta });
        }
      })();
      const toolCallsStream = (async () => {
        for await (const call of result.getToolCallsStream()) {
          if (!call || typeof call.name !== "string") continue;
          const args = call.arguments && typeof call.arguments === "object"
            ? call.arguments : {};
          const key = `${call.name}\n${stableStringify(args)}`;
          if (requestedByKey.has(key)) continue; // execute() already owns it
          const displayName = swiftcodeByModelName.get(call.name) || call.name;
          const source = swiftcodeByModelName.has(call.name) ? "swiftcode" : "openrouter";
          requestedByKey.set(key, { id: call.id, modelName: call.name });
          await emitToolEvent({
            toolCallId: call.id,
            toolName: displayName,
            source,
            state: "requested",
            arguments: args,
            startedAt: new Date().toISOString(),
          });
        }
      })();
      // Argument deltas for in-flight calls (and preliminary generator
      // results, which this bridge never produces) are consumed and
      // discarded: the parsed calls above are the UI source of truth.
      const toolStream = (async () => {
        for await (const _event of result.getToolStream()) { /* drain */ }
      })();
      // Attach no-op handlers NOW: a stream consumer can reject before
      // getText() settles, and an unobserved rejection crashes Node
      // before the run's catch below can report it. allSettled below
      // still observes the original promises.
      textStream.catch(() => {});
      toolCallsStream.catch(() => {});
      toolStream.catch(() => {});

      let finalText = "";
      try {
        finalText = await result.getText();
        const settled = await Promise.allSettled([textStream, toolCallsStream, toolStream]);
        for (const entry of settled) {
          if (entry.status === "rejected") {
            diag(`stream consumer ended with an error after getText resolved: ${mapRunError(entry.reason)}`);
          }
        }
      } catch (error) {
        if (cancelled) {
          await out({ type: "error", message: "cancelled" });
          await finish(0);
          return;
        }
        await fail(mapRunError(error));
        return;
      }
      await out({ type: "done", finalText });
      runFinished = true;
      await finish(0);
    } catch (error) {
      diag(`run failed: ${error && error.stack ? error.stack : error}`);
      if (cancelled) {
        await out({ type: "error", message: "cancelled" });
        await finish(0);
        return;
      }
      await fail(mapRunError(error));
    }
  };

  rl.on("line", (line) => {
    if (!line.trim()) return;
    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      diag(`ignoring non-JSON stdin line: ${line.slice(0, 120)}`);
      return;
    }
    if (msg.type === "run") {
      if (runPromise) {
        diag("ignoring second run line: one run per bridge process");
        return;
      }
      runPromise = handleRun(msg);
      return;
    }
    if (msg.type === "tool_result") {
      const pending = pendingToolResults.get(msg.id);
      if (!pending) {
        diag(`tool_result for unknown id ${msg.id}; ignoring`);
        return;
      }
      pendingToolResults.delete(msg.id);
      if (msg.error !== undefined && msg.error !== null) {
        pending.reject(new Error(typeof msg.error === "string" ? msg.error : JSON.stringify(msg.error)));
      } else {
        pending.resolve(msg.result === undefined ? null : msg.result);
      }
      return;
    }
    if (msg.type === "cancel") {
      void abortRun("cancelled by Swift").then(() => {
        // If no run is active yet, cancellation just ends the process.
        if (!runPromise) void finish(0);
      });
      return;
    }
    diag(`ignoring unknown stdin message type: ${msg.type}`);
  });

  rl.on("close", () => {
    if (runFinished || exitCode !== null) return;
    if (runPromise) {
      // Swift went away mid-run: abort the SDK run, then exit.
      void abortRun("Swift closed stdin").then(() => finish(0));
    } else {
      void finish(0);
    }
  });
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`openrouter-bridge fatal: ${error && error.stack ? error.stack : error}\n`);
    process.exit(1);
  });
}
