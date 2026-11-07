import * as dns from "node:dns/promises";
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
}

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
      if (isPlainObject(schema.properties)) {
        return jsonSchemaToZod({ ...schema, type: "object" });
      }
      out = z.unknown();
  }
  return schema.description ? out.describe(schema.description) : out;
}

export function toolInputSchema(parameters) {
  if (!isPlainObject(parameters)) return z.looseObject({});
  const isObjectSchema = parameters.type === "object"
    || isPlainObject(parameters.properties);
  if (!isObjectSchema) return z.looseObject({});
  return jsonSchemaToZod(parameters);
}

function sanitizeModelToolName(name) {
  if (name === "task") return "swiftcode_task";
  return name.replace(/[^a-zA-Z0-9_-]/g, "_");
}

export function isPrivateIp(ip) {
  if (!ip) return false;
  const lower0 = String(ip).toLowerCase();
  if (lower0.startsWith("::ffff:")) {
    const mapped = lower0.slice("::ffff:".length);
    if (net.isIP(mapped) === 4) return isPrivateIp(mapped);
    const hexMatch = mapped.match(/^([0-9a-f]{1,4}):([0-9a-f]{1,4})$/);
    if (hexMatch) {
      const hi = parseInt(hexMatch[1], 16);
      const lo = parseInt(hexMatch[2], 16);
      const dotted = `${hi >> 8}.${hi & 0xff}.${lo >> 8}.${lo & 0xff}`;
      return isPrivateIp(dotted);
    }
  }
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

export async function assertPublicUrl(rawUrl) {
  let url;
  try {
    url = new URL(rawUrl);
  } catch {
    throw new Error(`fetch_url: not a valid URL: ${rawUrl}`);
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new Error(`fetch_url: only http/https are allowed, got ${url.protocol}`);
  }
  const host = url.hostname.replace(/^\[|\]$/g, "");
  if (host === "localhost" || host.endsWith(".localhost")) {
    throw new Error("fetch_url: localhost targets are blocked");
  }
  if (net.isIP(host)) {
    if (isPrivateIp(host)) throw new Error(`fetch_url: private IP targets are blocked (${host})`);
    return url;
  }
  const resolvedAll = await dns.lookup(host, { all: true }).catch(() => null);
  if (resolvedAll) {
    for (const entry of resolvedAll) {
      if (isPrivateIp(entry.address)) {
        throw new Error(`fetch_url: ${host} resolves to a private IP and is blocked`);
      }
    }
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

function redact(text, secrets) {
  let out = String(text);
  for (const secret of secrets) {
    if (secret && secret.length >= 8) out = out.split(secret).join("[redacted]");
  }
  return out;
}

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
    } catch {  }
    while (emitting || emitQueue.length > 0) {
      await new Promise((r) => setTimeout(r, 5));
    }
    process.exit(code);
  };

  const abortRun = async (reason) => {
    cancelled = true;
    try {
      runAbort?.abort(new Error(reason));
    } catch {  }
    try {
      if (runResult) await runResult.cancel();
    } catch {  }
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
      const maxCostDollars = typeof config.maxCost === "number" && config.maxCost > 0
        ? config.maxCost : DEFAULT_MAX_COST;
      const toolTimeoutMs = Number.isInteger(config.toolTimeoutMs)
        && config.toolTimeoutMs >= 1000 ? config.toolTimeoutMs : DEFAULT_TOOL_TIMEOUT_MS;
      const perRequestTimeoutMs = Number.isInteger(config.perRequestTimeoutMs)
        && config.perRequestTimeoutMs >= 1000
        ? config.perRequestTimeoutMs : DEFAULT_REQUEST_TIMEOUT_MS;
      const allowFinalResponse = config.allowFinalResponse === undefined
        ? true : config.allowFinalResponse;

      const requestTools = Array.isArray(run.tools) ? run.tools : [];
      const swiftcodeByModelName = new Map();
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

      const requestedByKey = new Map();
      const requestedById = new Map();
      const emitToolEvent = (fields) => out({
        type: "tool_event",
        event: {
          provider: PROVIDER,
          sessionId,
          ...fields,
        },
      });
      const ensureRequested = (modelName, displayName, source, args, preferredId) => {
        if (typeof preferredId === "string" && preferredId.length > 0
            && requestedById.has(preferredId)) {
          return requestedById.get(preferredId);
        }
        const key = `${modelName}\n${stableStringify(args)}`;
        const existing = requestedByKey.get(key);
        if (existing && !(typeof preferredId === "string" && preferredId.length > 0)) return existing.id;
        const id = (typeof preferredId === "string" && preferredId.length > 0)
          ? preferredId
          : `tc_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`;
        if (typeof preferredId === "string" && preferredId.length > 0) {
          requestedById.set(preferredId, id);
        }
        if (!requestedByKey.has(key)) requestedByKey.set(key, { id, modelName });
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
      const isCancelledError = (error) => {
        const message = error?.message || String(error || "");
        return cancelled || /cancelled by Swift/i.test(message);
      };

      const makeBridgedExecute = (modelName, displayName) => {
        return async (params, context) => {
          const args = params && typeof params === "object" ? params : {};
          const id = ensureRequested(modelName, displayName, "swiftcode", args, context?.callId);
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
            }, toolTimeoutMs + 30_000);
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
              state: isCancelledError(error) ? "cancelled" : "failed",
              arguments: args,
              error: isCancelledError(error) ? "Cancelled" : redact(error.message || String(error), secrets),
              completedAt: new Date().toISOString(),
            });
            throw error;
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
            modelName = `openrouter_${modelName}`;
            displayName = modelName;
            if (swiftcodeNames.has(modelName)) {
              await fail(
                `Tool name collision: a SwiftCode tool is already named "${modelName}", ` +
                  `so the OpenRouter host tool cannot be renamed to it in combined mode. ` +
                  `Rename the SwiftCode tool; no silent merge is performed.`,
              );
              return;
            }
          }
          const originalExecute = host.execute;
          sdkTools.push(tool({
            name: modelName,
            description: host.description,
            inputSchema: host.inputSchema,
            timeoutMs: toolTimeoutMs,
            execute: async (params, context) => {
              const args = params && typeof params === "object" ? params : {};
              const id = ensureRequested(modelName, displayName, "openrouter", args, context?.callId);
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
                  state: isCancelledError(error) ? "cancelled" : "failed",
                  arguments: args,
                  error: isCancelledError(error) ? "Cancelled" : redact(error.message || String(error), secrets),
                  completedAt: new Date().toISOString(),
                });
                throw error;
              }
            },
          }));
        }
      }

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
          if (typeof call.id === "string" && call.id.length > 0
              && requestedById.has(call.id)) continue;
          const displayName = swiftcodeByModelName.get(call.name) || call.name;
          const source = swiftcodeByModelName.has(call.name) ? "swiftcode" : "openrouter";
          if (typeof call.id === "string" && call.id.length > 0) {
            requestedById.set(call.id, call.id);
          }
          const key = `${call.name}\n${stableStringify(args)}`;
          if (!requestedByKey.has(key)) {
            requestedByKey.set(key, { id: call.id, modelName: call.name });
          }
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
      const toolStream = (async () => {
        for await (const _event of result.getToolStream()) {  }
      })();
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
        if (!runPromise) void finish(0);
      });
      return;
    }
    diag(`ignoring unknown stdin message type: ${msg.type}`);
  });

  rl.on("close", () => {
    if (runFinished || exitCode !== null) return;
    if (runPromise) {
      void abortRun("Swift closed stdin").then(() => finish(0));
    } else {
      void finish(0);
    }
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`openrouter-bridge fatal: ${error?.message ?? error}\n`);
    process.exit(1);
  });
}
