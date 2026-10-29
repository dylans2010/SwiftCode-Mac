// opencode-bridge.mjs — SwiftCode Assist <-> OpenCode SDK bridge.
//
// Runs under Node. It is NOT part of the Xcode target: Workstream D's
// SDKRuntimeManager installs this file (plus a node_modules tree holding
// @opencode-ai/sdk) into Application Support, e.g.
//   <Application Support>/SwiftCode/SDKHosts/opencode/opencode-bridge.mjs
//   <Application Support>/SwiftCode/SDKHosts/opencode/node_modules/@opencode-ai/sdk
// Node resolves '@opencode-ai/sdk' by walking up from this file, so the
// bridge must live inside that installed directory, not beside the .swift
// sources. Swift launches it with argv:
//
//   node opencode-bridge.mjs --server-url <url> [--managed]
//
// --managed means SwiftCode owns the server: the bridge starts it with
// createOpencode() and closes it on exit. Without --managed the bridge
// only connects to a server the user already runs and NEVER closes it.
//
// NDJSON protocol (shared across SDK hosts). Swift -> bridge, one JSON
// object per stdin line:
//   {"type":"run","requestId","provider":"opencode","model":"opencode:provider/model",
//    "systemPrompt","userText","history":[{"role","text"}],
//    "tools":[{"name","description","parameters"}],
//    "toolSource":"swiftcode|opencode|combined",
//    "config":{"directory","sessionId","agentName"}}
//   {"type":"tool_result","id","result"} | {"type":"tool_result","id","error":...}
//   {"type":"cancel","requestId"}
// Bridge -> Swift, one JSON object per stdout line:
//   {"type":"ready","provider":"opencode","sdkVersion"}
//   {"type":"text","delta"}
//   {"type":"tool_event","event":{provider,sessionId,toolCallId,toolName,source,
//     state,arguments,result,error,startedAt,completedAt}}
//   {"type":"tool_call","id","name","arguments"}  (SwiftCode-native tool;
//     the bridge waits for the matching tool_result line before prompting
//     again — a model-generated JSON request is NEVER a completed run)
//   {"type":"done","finalText"}
//   {"type":"error","message"}
//
// Readiness contract: "ready" is printed ONLY after the SDK import
// resolves AND global.health() on the target server succeeds. A bridge
// that prints ready has a live server behind it; anything else is an
// error line followed by a nonzero exit. Diagnostics go to stderr only
// (never stdout, which is the NDJSON channel), and never include the
// system prompt, tool arguments, or any secret.
//
// SDK surface used (verified against @opencode-ai/sdk@1.19.5, v2 client,
// dist/v2/gen/sdk.gen.d.ts):
//   createOpencode({hostname, port, signal, timeout}) -> {client, server}
//     server: {url, close()}
//   createOpencodeClient({baseUrl, directory}) -> client
//   client.global.health() -> {healthy, version}
//   client.config.providers() -> configured providers/models
//   client.tool.ids() -> all tool ids (used to disable server tools)
//   client.session.create({directory, agent, model:{id, providerID}})
//   client.session.promptAsync({sessionID, directory, model:{providerID, modelID},
//     agent, system, tools:{[name]: boolean}, parts:[{type:"text", text}]})
//   client.session.abort({sessionID, directory})
//   client.session.messages({sessionID, directory}) (best-effort detail
//     fetch for completed tool parts: input/output live there, not in
//     the minimal ToolPart carried by events)
//   client.event.subscribe({directory}) -> {stream: AsyncGenerator}
//     event shapes consumed: message.part.delta (text), message.part.updated
//     (tool parts), session.idle (turn end), session.error (fatal),
//     permission.asked / permission.v2.asked (default-deny, see below)
//   client.permission.reply({requestID, reply:"reject"})
//     (verified in the same .d.ts; the older permission.respond
//     {sessionID, permissionID, response} exists as a fallback only)
//
// System prompt mechanism: promptAsync's `system` field. SwiftCode's
// real system prompt is sent verbatim on EVERY prompt (initial and each
// tool-result follow-up), so a multi-turn run cannot drift back to the
// server's default instructions. History is folded into the prompt text
// as a clearly delimited transcript because promptAsync has no history
// parameter; it is not re-sent as system content.
//
// Permission policy: provider-managed tools NEVER auto-approve. On a
// permission.asked event the bridge replies "reject" through the SDK and
// emits a tool_event with state "failed" and an explicit
// permission-denied error. If the reply call itself fails, the tool is
// still reported failed; the run is not allowed to proceed past a
// permission gate silently.
//
// Tool sources:
//   swiftcode — session names the tools-denied `swiftcode` agent AND all
//     server tool ids are disabled via the prompt tools map, so the
//     server cannot execute anything itself. The model is instructed to
//     answer in SwiftCode's JSON tool-request format; the bridge parses
//     that JSON after each turn and emits tool_call lines for Swift to
//     execute through the native registry.
//   opencode — built-in tools run normally on the server; their parts
//     become tool_event lines with source "opencode".
//   combined — SwiftCode JSON tools plus non-colliding built-ins. A
//     built-in whose name collides with a SwiftCode tool is disabled
//     via the prompt tools map, so the SwiftCode tool deterministically
//     wins; routing is by the event's source field, never by name.
//   openrouter — NOT supported as a tool source for OpenCode; the bridge
//     errors actionably instead of silently falling back.

import * as readline from "node:readline";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const PROVIDER = "opencode";
const MAX_TOOL_ROUNDS = 25;
const SDK_PACKAGE = "@opencode-ai/sdk";
const SDK_VERSION = "1.19.5";

function out(obj) {
  process.stdout.write(JSON.stringify(obj) + "\n");
}

function err(message) {
  // Diagnostics only: never the system prompt, arguments, or secrets.
  process.stderr.write(`[opencode-bridge] ${message}\n`);
}

function fatal(message) {
  out({ type: "error", message });
  process.exitCode = 1;
  // Give stdout a chance to flush before exiting.
  setTimeout(() => process.exit(1), 50);
}

/** Parse argv: --server-url <url> [--managed]. */
function parseArgv() {
  const args = process.argv.slice(2);
  let serverURL = "http://127.0.0.1:4096";
  let managed = false;
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--server-url" && args[i + 1]) serverURL = args[++i];
    else if (args[i] === "--managed") managed = true;
  }
  return { serverURL, managed };
}

/** Strictly parse "opencode:provider/model". Never guesses. */
function parseModelID(storedID) {
  if (typeof storedID !== "string" || !storedID.startsWith("opencode:")) {
    throw new Error(
      `Invalid OpenCode model id "${storedID}": expected "opencode:<provider>/<model>" ` +
        `(for example "opencode:anthropic/claude-sonnet-4-5"). ` +
        `Select an OpenCode model in Assist Settings; a bare "provider/model" id belongs to OpenRouter.`,
    );
  }
  const rest = storedID.slice("opencode:".length);
  const slash = rest.indexOf("/");
  if (slash < 0) {
    throw new Error(
      `Invalid OpenCode model id "${storedID}": missing "/" between provider and model. ` +
        `Expected "opencode:<provider>/<model>".`,
    );
  }
  const providerID = rest.slice(0, slash);
  const modelID = rest.slice(slash + 1);
  if (!providerID || !modelID || /\s/.test(providerID) || /\s/.test(modelID)) {
    throw new Error(
      `Invalid OpenCode model id "${storedID}": provider and model must both be non-empty with no whitespace.`,
    );
  }
  return { providerID, modelID };
}

function isLoopback(urlString) {
  try {
    const u = new URL(urlString);
    return u.hostname === "localhost" || u.hostname === "127.0.0.1" || u.hostname === "::1";
  } catch {
    return false;
  }
}

/** Best-effort: confirm provider/model exist in the server catalog. */
async function validateAgainstCatalog(client, providerID, modelID) {
  let providers;
  try {
    const res = await client.config.providers();
    providers = res?.data ?? res;
  } catch (e) {
    err(`catalog check skipped (config.providers failed: ${e?.message ?? e})`);
    return;
  }
  const list = Array.isArray(providers) ? providers : (providers?.providers ?? []);
  const provider = list.find(
    (p) => p?.id === providerID || p?.providerID === providerID || p?.name === providerID,
  );
  if (!provider) {
    throw new Error(
      `OpenCode provider "${providerID}" is not configured on this server. ` +
        `Configure it in OpenCode (opencode.json / provider auth) or select a different model.`,
    );
  }
  const models = provider.models ?? provider.Models ?? [];
  if (Array.isArray(models) && models.length > 0) {
    const found = models.some((m) => {
      if (typeof m === "string") return m === modelID;
      return m?.id === modelID || m?.modelID === modelID || m?.name === modelID;
    });
    if (!found) {
      throw new Error(
        `OpenCode model "${modelID}" was not found for provider "${providerID}" on this server. ` +
          `Select a model from the server's catalog in Assist Settings; SwiftCode never substitutes another model.`,
      );
    }
  }
  // If the catalog carries no model list, do not hard-fail: the server
  // itself will reject an unknown model at prompt time, which surfaces
  // as a run error rather than a guessed substitution.
}

function toolStateFromSDK(state) {
  switch (state) {
    case "pending":
      return "pending";
    case "running":
      return "running";
    case "completed":
      return "completed";
    case "error":
      return "failed";
    default:
      return "pending";
  }
}

/** Walk a session.messages payload for the part with the given id. */
function findPart(payload, partID) {
  const stack = [payload];
  while (stack.length > 0) {
    const node = stack.pop();
    if (Array.isArray(node)) {
      for (const item of node) stack.push(item);
    } else if (node && typeof node === "object") {
      if (node.id === partID && node.type === "tool") return node;
      if (Array.isArray(node.parts)) for (const p of node.parts) stack.push(p);
      for (const value of Object.values(node)) {
        if (value && typeof value === "object") stack.push(value);
      }
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// stdin line queue: run handling consumes tool_result/cancel lines itself,
// so lines are read through a single queue with waiters, never two readers.
// ---------------------------------------------------------------------------

class LineQueue {
  constructor() {
    this.queued = [];
    this.waiters = [];
    this.closed = false;
  }
  push(line) {
    if (this.waiters.length > 0) this.waiters.shift()(line);
    else this.queued.push(line);
  }
  close() {
    this.closed = true;
    for (const w of this.waiters.splice(0)) w(null);
  }
  next() {
    if (this.queued.length > 0) return Promise.resolve(this.queued.shift());
    if (this.closed) return Promise.resolve(null);
    return new Promise((resolve) => this.waiters.push(resolve));
  }
}

async function main() {
  const { serverURL, managed } = parseArgv();

  // Dynamic import so a missing SDK becomes a JSON error line + exit 1,
  // not a bare Node stack trace on stderr with no protocol output.
  let sdk;
  let sdkVersion = SDK_VERSION;
  try {
    sdk = await import("@opencode-ai/sdk/v2");
    // The SDK's exports map does not expose "./package.json", so resolve
    // the v2 entry file and walk up to the package root instead.
    const entryPath = fileURLToPath(import.meta.resolve("@opencode-ai/sdk/v2"));
    let dir = path.dirname(entryPath);
    for (let depth = 0; depth < 8; depth++) {
      const candidate = path.join(dir, "package.json");
      try {
        const pkg = JSON.parse(fs.readFileSync(candidate, "utf8"));
        if (pkg?.name === SDK_PACKAGE && typeof pkg.version === "string") {
          sdkVersion = pkg.version;
          break;
        }
      } catch {
        // Not this directory; keep walking up.
      }
      const parent = path.dirname(dir);
      if (parent === dir) break;
      dir = parent;
    }
  } catch (e) {
    fatal(
      `OpenCode SDK "${SDK_PACKAGE}@${SDK_VERSION}" could not be loaded: ${e?.message ?? e}. ` +
        `Reinstall the Assist SDK runtime from Assist Settings (the runtime manager installs it under ` +
        `Application Support/SwiftCode/SDKHosts/opencode) and try again.`,
    );
    return;
  }

  const abortController = new AbortController();
  let client = null;
  let managedServer = null;
  let shuttingDown = false;

  async function shutdown(exitCode) {
    if (shuttingDown) return;
    shuttingDown = true;
    if (managedServer) {
      try {
        managedServer.close();
      } catch (e) {
        err(`managed server close failed: ${e?.message ?? e}`);
      }
      managedServer = null;
    }
    process.exit(exitCode);
  }
  process.on("SIGTERM", () => void shutdown(0));
  process.on("SIGINT", () => void shutdown(0));

  // --- Connect / start, then health-check BEFORE printing ready. ---
  try {
    if (managed) {
      if (!isLoopback(serverURL)) {
        throw new Error(
          `Refusing to start a managed OpenCode server for non-loopback URL "${serverURL}". ` +
            `Managed servers are loopback-only; connect to your own server instead.`,
        );
      }
      const url = new URL(serverURL);
      const started = await sdk.createOpencode({
        hostname: url.hostname,
        port: url.port ? Number(url.port) : 4096,
        signal: abortController.signal,
      });
      client = started.client;
      managedServer = started.server;
      err(`managed server started at ${started.server.url}`);
    } else {
      client = sdk.createOpencodeClient({ baseUrl: serverURL });
    }
    const health = await client.global.health();
    const healthData = health?.data ?? health;
    if (!healthData || healthData.healthy !== true) {
      throw new Error(
        `OpenCode server at ${serverURL} did not report healthy ` +
          `(response: ${JSON.stringify(healthData) ?? "empty"}). ` +
          `Start it with "opencode serve" (or enable the managed server in Assist Settings) and try again`,
      );
    }
    // Deliberately NOT reporting the server's version in "ready": the
    // runtime manager's handshake requires ready.sdkVersion to equal
    // the pinned SDK package version (1.19.5). The server version is
    // diagnostics only.
    if (healthData.version) err(`server version ${healthData.version}`);
  } catch (e) {
    if (managedServer) {
      try {
        managedServer.close();
      } catch {}
    }
    fatal(
      `Cannot reach a healthy OpenCode server at ${serverURL}: ${e?.message ?? e}. ` +
        `If no server is running, start one with "opencode serve" and ensure it listens on ${serverURL}, ` +
        `or enable the managed server in Assist Settings. SwiftCode never starts a server you do not own unless managed mode is on.`,
    );
    return;
  }

  out({ type: "ready", provider: PROVIDER, sdkVersion });

  const lines = new LineQueue();
  const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
  rl.on("line", (line) => lines.push(line));
  rl.on("close", () => lines.close());

  // --- Run loop: one run request at a time; tool_result/cancel lines are
  // consumed by the active run, never by a second reader. ---
  for (;;) {
    const raw = await lines.next();
    if (raw === null) break; // stdin EOF
    let msg;
    try {
      msg = JSON.parse(raw);
    } catch {
      err("ignoring non-JSON stdin line");
      continue;
    }
    if (msg?.type === "run") {
      const ok = await handleRun(client, lines, msg, managedServer !== null);
      if (!ok) {
        // Run-level failure is fatal to this bridge process: Swift
        // relaunches a fresh bridge per run, and a nonzero exit is the
        // signal that the error line above was not a soft warning.
        await shutdown(1);
        return;
      }
    } else if (msg?.type === "cancel") {
      // No active run; nothing to cancel.
      continue;
    } else {
      err(`ignoring unknown stdin message type "${msg?.type}"`);
    }
  }

  await shutdown(0);
}

/**
 * Execute one run. Returns true to keep the bridge alive for another run,
 * false when a fatal error already printed an error line and the process
 * must exit nonzero (fatal() handles the exit; this only stops looping).
 */
async function handleRun(client, lines, req, _isManaged) {
  const requestId = req.requestId ?? "run";
  try {
    if (req.provider && req.provider !== "opencode") {
      throw new Error(`This bridge serves provider "opencode", not "${req.provider}".`);
    }
    if (req.toolSource === "openrouter") {
      throw new Error(
        `Tool source "openrouter" is not supported for OpenCode sessions: OpenRouter tools belong to the ` +
          `OpenRouter Agent SDK runtime, not to an OpenCode server. Choose "swiftcode", "opencode", or ` +
          `"combined" as the OpenCode tool source in Assist Settings.`,
      );
    }
    if (!["swiftcode", "opencode", "combined"].includes(req.toolSource)) {
      throw new Error(
        `Unknown OpenCode tool source "${req.toolSource}": expected "swiftcode", "opencode", or "combined".`,
      );
    }
    const { providerID, modelID } = parseModelID(req.model);
    await validateAgainstCatalog(client, providerID, modelID);

    const directory = req.config?.directory;
    if (!directory || typeof directory !== "string") {
      throw new Error(
        `OpenCode run requires config.directory (the workspace root) so the server session is scoped to the project.`,
      );
    }
    const agentName = req.config?.agentName || "swiftcode";
    const swiftcodeTools = Array.isArray(req.tools) ? req.tools : [];

    // Server tool gating for this run.
    // swiftcode: deny-all agent + every server tool id disabled.
    // opencode: no gating; the server's tools run normally.
    // combined: colliding built-ins disabled so the SwiftCode tool wins.
    let toolsMap;
    if (req.toolSource === "swiftcode") {
      toolsMap = {};
      try {
        const res = await client.tool.ids({ directory });
        const ids = res?.data ?? res;
        const list = Array.isArray(ids) ? ids : (ids?.ids ?? []);
        for (const id of list) if (typeof id === "string") toolsMap[id] = false;
      } catch (e) {
        err(`tool.ids lookup failed, relying on deny-all agent alone: ${e?.message ?? e}`);
      }
    } else if (req.toolSource === "combined") {
      toolsMap = {};
      const swiftNames = new Set(swiftcodeTools.map((t) => t.name));
      try {
        const res = await client.tool.ids({ directory });
        const ids = res?.data ?? res;
        const list = Array.isArray(ids) ? ids : (ids?.ids ?? []);
        for (const id of list) {
          if (typeof id === "string" && swiftNames.has(id)) toolsMap[id] = false;
        }
      } catch (e) {
        err(`tool.ids lookup failed, collision disabling skipped: ${e?.message ?? e}`);
      }
    }

    // Create or resume the session. A supplied sessionId resumes the
    // server-side conversation; otherwise a fresh session is created.
    let sessionID = req.config?.sessionId;
    if (!sessionID) {
      const created = await client.session.create({
        directory,
        ...(req.toolSource === "opencode" ? {} : { agent: agentName }),
        model: { id: modelID, providerID },
      });
      sessionID = created?.data?.id ?? created?.id;
      if (!sessionID) throw new Error("OpenCode session.create returned no session id.");
    }

    // Event consumer: runs concurrently with promptAsync and feeds the
    // per-turn queue below. It never prints directly except permission
    // denials (which need an immediate SDK reply).
    const eventQueue = [];
    let eventWaiter = null;
    let eventDone = false;
    let eventError = null;
    const pushEvent = (event) => {
      if (eventWaiter) {
        const w = eventWaiter;
        eventWaiter = null;
        w(event);
      } else {
        eventQueue.push(event);
      }
    };
    const nextEvent = () =>
      new Promise((resolve) => {
        if (eventQueue.length > 0) resolve(eventQueue.shift());
        else if (eventDone) resolve(null);
        else eventWaiter = resolve;
      });

    let eventTaskError = null;
    let eventStream = null;
    const eventTask = (async () => {
      try {
        const sub = await client.event.subscribe({ directory });
        eventStream = sub.stream;
        for await (const event of sub.stream) {
          const props = event?.properties ?? {};
          if (props.sessionID && props.sessionID !== sessionID) continue;
          // Permission gates: default deny, via the verified reply API.
          if (event?.type === "permission.asked" || event?.type === "permission.v2.asked") {
            const requestID = props.id ?? props.requestID;
            const toolInfo = props.tool;
            try {
              if (requestID) await client.permission.reply({ requestID, reply: "reject" });
              else throw new Error("permission event carried no request id");
            } catch (replyError) {
              // Fallback to the older respond shape; if that fails too,
              // the denial is still reported — the run must not proceed
              // past the gate silently.
              try {
                await client.permission.respond({
                  sessionID,
                  permissionID: requestID,
                  response: "reject",
                });
              } catch {
                err(`permission reply failed: ${replyError?.message ?? replyError}`);
              }
            }
            pushEvent({
              type: "tool_event",
              event: {
                provider: PROVIDER,
                sessionId: sessionID,
                toolCallId: toolInfo?.callID ?? requestID ?? "",
                toolName: props.permission ?? "unknown",
                source: "opencode",
                state: "failed",
                arguments: "",
                result: "",
                error:
                  `Permission denied by SwiftCode policy: the OpenCode server asked for "${props.permission ?? "unknown"}" ` +
                  `and SwiftCode denied it. Provider-managed tools are never auto-approved.`,
                startedAt: "",
                completedAt: "",
              },
            });
            continue;
          }
          pushEvent(event);
        }
      } catch (e) {
        eventTaskError = e;
      } finally {
        eventDone = true;
        if (eventWaiter) {
          const w = eventWaiter;
          eventWaiter = null;
          w(null);
        }
      }
    })();

    // Prompt loop: one promptAsync per turn; swiftcode/combined turns
    // that yield a JSON tool request pause for Swift's tool_result.
    let promptText = buildPromptText(req);
    let toolRounds = 0;
    let finalText = "";
    for (;;) {
      const systemForTurn = swiftcodeSystemPrompt(req, swiftcodeTools);
      await client.session.promptAsync({
        sessionID,
        directory,
        model: { providerID, modelID },
        ...(req.toolSource === "opencode" ? {} : { agent: agentName }),
        ...(toolsMap ? { tools: toolsMap } : {}),
        system: systemForTurn,
        parts: [{ type: "text", text: promptText }],
      });

      // Drain events until this turn goes idle (or errors / aborts).
      let turnText = "";
      let turnError = null;
      const toolParts = new Map();
      for (;;) {
        const event = await nextEvent();
        if (event === null) {
          if (eventTaskError) turnError = eventTaskError;
          break;
        }
        if (event.type === "session.idle") {
          const idleProps = event.properties ?? {};
          if (!idleProps.sessionID || idleProps.sessionID === sessionID) break;
          continue;
        }
        if (event.type === "session.error") {
          const e = event.properties?.error;
          turnError = new Error(
            `OpenCode session error: ${e?.name ?? "UnknownError"}: ${e?.data?.message ?? JSON.stringify(e) ?? "unknown"}`,
          );
          break;
        }
        if (event.type === "message.part.delta") {
          const delta = event.properties?.delta;
          if (typeof delta === "string" && delta.length > 0) {
            turnText += delta;
            out({ type: "text", delta });
          }
          continue;
        }
        if (event.type === "message.part.updated") {
          const part = event.properties?.part;
          if (part?.type === "tool") {
            const state = toolStateFromSDK(part.state);
            const prior = toolParts.get(part.id);
            toolParts.set(part.id, part);
            // Fill arguments/result best-effort on terminal states:
            // the event's ToolPart is minimal, the full part (with
            // state.input / state.output) lives in session.messages.
            let args = "";
            let result = "";
            if (state === "completed" || state === "failed") {
              try {
                const msgs = await client.session.messages({ sessionID, directory });
                const full = findPart(msgs?.data ?? msgs, part.id);
                const st = full?.state;
                if (st?.input) args = JSON.stringify(st.input);
                if (st?.output !== undefined) result = typeof st.output === "string" ? st.output : JSON.stringify(st.output);
                else if (st?.result !== undefined) result = typeof st.result === "string" ? st.result : JSON.stringify(st.result);
              } catch (e) {
                err(`tool detail fetch failed for part ${part.id}: ${e?.message ?? e}`);
              }
            }
            out({
              type: "tool_event",
              event: {
                provider: PROVIDER,
                sessionId: sessionID,
                toolCallId: part.callID ?? part.id,
                toolName: part.tool,
                source: "opencode",
                state,
                arguments: args,
                result,
                error: state === "failed" ? `OpenCode tool "${part.tool}" failed (see server logs for detail).` : "",
                startedAt: prior ? "" : "",
                completedAt: "",
              },
            });
          }
          continue;
        }
        // All other event kinds (session.updated, step markers, diffs,
        // message.updated, …) carry no text or tool state SwiftCode
        // renders; they are consumed and ignored, never surfaced raw.
      }
      if (turnError) throw turnError;
      finalText = turnText;

      // SwiftCode-tool turns: parse the model's JSON tool request.
      if (req.toolSource === "swiftcode" || req.toolSource === "combined") {
        const parsed = extractJSONToolRequest(turnText);
        if (parsed && typeof parsed.toolId === "string") {
          if (++toolRounds > MAX_TOOL_ROUNDS) {
            throw new Error(
              `OpenCode run stopped after ${MAX_TOOL_ROUNDS} consecutive SwiftCode tool calls without a final response. ` +
                `The model kept requesting tools; SwiftCode does not loop forever.`,
            );
          }
          const callId = `swiftcode-${requestId}-${toolRounds}`;
          out({
            type: "tool_call",
            id: callId,
            name: parsed.toolId,
            arguments: JSON.stringify(parsed.input ?? {}),
          });
          // Wait for Swift's verdict (or cancellation). A tool_call is
          // a request, not a result: nothing is marked completed here.
          const verdict = await waitForToolResult(lines, callId);
          if (verdict.cancelled) {
            try {
              await client.session.abort({ sessionID, directory });
            } catch {}
            out({ type: "done", finalText: turnText });
            eventDone = true;
            if (eventStream && typeof eventStream.return === "function") {
              try {
                await eventStream.return();
              } catch {}
            }
            await eventTask.catch(() => {});
            return true;
          }
          promptText =
            verdict.error !== undefined
              ? `Tool "${parsed.toolId}" failed with error: ${verdict.error}\nContinue with the result above or answer the user.`
              : `Tool "${parsed.toolId}" returned:\n${verdict.result}\nContinue with the result above or answer the user.`;
          continue; // next promptAsync turn, same session
        }
      }
      // No SwiftCode tool request: this turn's text is the answer.
      // (For opencode-only runs, server tool results were already
      // streamed as tool_event lines during the turn.)
      break;
    }

    // Close this run's event subscription so a later run on the same
    // (resumed) session does not receive duplicate events from two
    // consumers. This does not close the server or the session, which
    // Swift may resume by sessionId.
    eventDone = true;
    if (eventStream && typeof eventStream.return === "function") {
      try {
        await eventStream.return();
      } catch {}
    }
    await eventTask.catch(() => {});
    out({ type: "done", finalText });
    return true;
  } catch (e) {
    out({ type: "error", message: `${e?.message ?? e}` });
    return false;
  }
}

/** Compose the user-visible prompt: history transcript + current text. */
function buildPromptText(req) {
  const parts = [];
  if (Array.isArray(req.history) && req.history.length > 0) {
    const transcript = req.history
      .map((h) => `${h.role === "assistant" ? "Assistant" : "User"}: ${h.text}`)
      .join("\n");
    parts.push(`Previous conversation (do not repeat it, continue from it):\n${transcript}`);
  }
  parts.push(req.userText ?? "");
  return parts.filter((p) => p.length > 0).join("\n\n");
}

/**
 * System prompt sent on every promptAsync turn. SwiftCode's real system
 * prompt always comes first and is never trimmed. For SwiftCode-tool
 * runs, the JSON tool-request contract is appended after it (it is the
 * format AssistAgentSession already parses); it does not replace or
 * override any SwiftCode instruction.
 */
function swiftcodeSystemPrompt(req, swiftcodeTools) {
  const base = req.systemPrompt ?? "";
  if (req.toolSource === "opencode") return base;
  const toolList =
    swiftcodeTools.length > 0
      ? swiftcodeTools
          .map((t) => `- ${t.name}: ${t.description ?? ""}\n  parameters: ${JSON.stringify(t.parameters ?? {})}`)
          .join("\n")
      : "(no SwiftCode tools were supplied for this run)";
  const extra = [
    `Tool protocol (SwiftCode tools only; OpenCode's own tools are ${req.toolSource === "combined" ? "also available through the server, except any whose name collides with a SwiftCode tool below — those are disabled on the server so the SwiftCode tool wins" : "disabled for this run"}):`,
    `Available SwiftCode tools:\n${toolList}`,
    `When you need a SwiftCode tool, respond with ONLY this JSON object and no other text: {"toolId": "<tool name>", "input": {<arguments>}, "explanation": "<why>"}.\n` +
      `SwiftCode validates, permission-checks, and executes the tool, then returns the real result to you. ` +
      `A tool request is not a completed execution until that result arrives. ` +
      `When you have everything you need, respond with ONLY: {"finalResponse": "<your answer>"}.`,
  ].join("\n\n");
  return base ? `${base}\n\n${extra}` : extra;
}

/**
 * Extract a SwiftCode JSON tool request or finalResponse from model
 * text. Accepts a bare JSON object or one embedded in surrounding text
 * (first "{" to last "}"). Returns null when no such object parses.
 */
function extractJSONToolRequest(text) {
  if (!text) return null;
  const trimmed = text.trim();
  const candidates = [trimmed];
  const first = trimmed.indexOf("{");
  const last = trimmed.lastIndexOf("}");
  if (first >= 0 && last > first) candidates.push(trimmed.slice(first, last + 1));
  for (const candidate of candidates) {
    try {
      const parsed = JSON.parse(candidate);
      if (parsed && typeof parsed === "object" && (typeof parsed.toolId === "string" || typeof parsed.finalResponse === "string")) {
        return parsed;
      }
    } catch {
      // Not JSON; try the next candidate.
    }
  }
  return null;
}

/** Await the tool_result (or cancel) line for one tool_call id. */
async function waitForToolResult(lines, callId) {
  for (;;) {
    const raw = await lines.next();
    if (raw === null) return { cancelled: true };
    let msg;
    try {
      msg = JSON.parse(raw);
    } catch {
      continue;
    }
    if (msg?.type === "tool_result" && msg.id === callId) {
      return msg.error !== undefined ? { error: String(msg.error) } : { result: String(msg.result ?? "") };
    }
    if (msg?.type === "cancel") return { cancelled: true };
    // A new run request arriving mid-tool-wait is a protocol error;
    // ignore it rather than interleaving two runs on one session.
    err(`ignoring unexpected stdin message type "${msg?.type}" while awaiting tool result`);
  }
}

await main();
