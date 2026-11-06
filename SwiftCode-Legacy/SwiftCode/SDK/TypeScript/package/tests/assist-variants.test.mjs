// Assist SDK variant tests for @swiftcode/sdk (task B2).
//
// Covers the two typed surfaces:
//   - `assistSDK` (headless): sessions, streaming responses, tool access —
//     every call routes through the dedicated entitled `assist.invoke` IPC
//     route. NO view-opening path may exist here.
//   - `assistSDK.UI`: exposes ONLY embedding of the host's Assist main
//     view via `ui.openView({ viewId: ASSIST_VIEW_ID })` — no headless
//     session/streaming APIs may exist here.
//
// Denial contract (Docs/Intro-to-SDK.md §13): when the host answers with
// the typed `ASSIST_DENIED` denial, the TS wrapper throws
// `SDKAssistAccessError` carrying the VERBATIM user message. The TS layer
// cannot know entitlement state itself and must NOT fabricate it: any
// other host rejection propagates as the original SDKError untouched, and
// no call throws an access error without the host's typed denial.
//
// Run: `npm run build && npm test` (npm test = `node --test "tests/*.test.mjs"`).
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { pathToFileURL, fileURLToPath } from "node:url";
import path from "node:path";

const distUrl = pathToFileURL(
  path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "dist", "index.js"),
).href;
const {
  createContext,
  createAssistAPI,
  createAssistUIAPI,
  ASSIST_VIEW_ID,
  SDKAssistAccessError,
  SDKError,
} = await import(distUrl);

// The §13 user error, verbatim — do not reword. Duplicated here (not
// imported) so the test independently pins the exact user-facing text.
const VERBATIM_DENIAL =
  "This app is not allowed to use Assist because access has not yet been verified. Please check with the app developer for further information.";

const EXTENSION = { id: "test.ext", name: "Test Extension", version: "1.0.0" };

function createFakeHost(handlers = {}) {
  const requests = [];
  let closed = false;
  let requestCounter = 0;
  const listeners = new Set();
  const host = {
    get closed() { return closed; },
    get requests() { return requests; },
    request(method, payload = {}, requestId) {
      const rid = requestId ?? `fake-req-${requestCounter++}`;
      requests.push({ method, payload, requestId: rid });
      return new Promise((resolve, reject) => {
        const handler = handlers[method];
        if (handler === undefined) {
          reject(new SDKError("IPC_MALFORMED", `Unknown method ${method}`, rid));
          return;
        }
        Promise.resolve().then(() => handler(payload, rid, host)).then(resolve, reject);
      });
    },
    onEvent(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    emit(name, payload, requestId) {
      for (const listener of listeners) listener({ name, payload, requestId });
    },
    close() { closed = true; },
  };
  return host;
}

function lastRequest(host) {
  const req = host.requests[host.requests.length - 1];
  assert.ok(req !== undefined, "expected a request to have been sent");
  return req;
}

/** Host that denies every Assist route with the typed ASSIST_DENIED denial. */
function createDenyingHost() {
  const deny = () => {
    throw new SDKError("ASSIST_DENIED", VERBATIM_DENIAL, "corr-denied");
  };
  return createFakeHost({ "assist.invoke": deny, "ui.openView": deny });
}

async function assertAssistAccessError(promise) {
  await assert.rejects(promise, (error) => {
    assert.ok(
      error instanceof SDKAssistAccessError,
      `expected SDKAssistAccessError, got ${error?.constructor?.name}: ${error?.message}`,
    );
    assert.equal(error.message, VERBATIM_DENIAL, "denial message must be the verbatim §13 text");
    assert.equal(error.code, "ASSIST_DENIED");
    return true;
  });
}

describe("assist variants: viewId", () => {
  it('ASSIST_VIEW_ID is the deterministic "assist.main" (no Assist view registered in SDKViewOpenerBuiltIns.swift)', () => {
    assert.equal(ASSIST_VIEW_ID, "assist.main");
  });
});

describe("assist variants: module shape isolation", () => {
  it("headless assistSDK exposes sessions/streaming/tools and NO view-opening path", () => {
    const host = createFakeHost();
    const assist = createAssistAPI(host);
    assert.deepEqual(Object.keys(assist).sort(), [
      "closeSession",
      "createSession",
      "invokeTool",
      "listSessions",
      "sendMessage",
      "streamMessage",
    ]);
    assert.equal(assist.openView, undefined);
    assert.equal(assist.openAssistView, undefined);
  });

  it("assistSDK.UI exposes ONLY the host Assist view embedding — no headless APIs", () => {
    const host = createFakeHost();
    const assistUI = createAssistUIAPI(host);
    assert.deepEqual(Object.keys(assistUI).sort(), ["openAssistView"]);
    assert.equal(assistUI.createSession, undefined);
    assert.equal(assistUI.sendMessage, undefined);
    assert.equal(assistUI.streamMessage, undefined);
    assert.equal(assistUI.closeSession, undefined);
    assert.equal(assistUI.invokeTool, undefined);
  });

  it("createContext attaches both variants with the same isolated shapes", () => {
    const host = createFakeHost();
    const { context } = createContext(host, EXTENSION);
    assert.deepEqual(Object.keys(context.assist).sort(), [
      "closeSession",
      "createSession",
      "invokeTool",
      "listSessions",
      "sendMessage",
      "streamMessage",
    ]);
    assert.equal(context.assist.openAssistView, undefined);
    assert.deepEqual(Object.keys(context.assistUI).sort(), ["openAssistView"]);
    assert.equal(context.assistUI.createSession, undefined);
    // The general ui surface is untouched by the Assist variants.
    assert.equal(typeof context.ui.openView, "function");
  });
});

describe("assist variants: wire contract", () => {
  it("createSession routes through assist.invoke with op session.create", async () => {
    const host = createFakeHost({
      "assist.invoke": (payload) => {
        assert.equal(payload.op, "session.create");
        assert.equal(payload.systemPrompt, "sys");
        return { sessionId: "s-1", createdAt: "2026-10-12T00:00:00Z" };
      },
    });
    const assist = createAssistAPI(host);
    const session = await assist.createSession({ systemPrompt: "sys" });
    assert.deepEqual(session, { sessionId: "s-1", createdAt: "2026-10-12T00:00:00Z" });
    const req = lastRequest(host);
    assert.equal(req.method, "assist.invoke");
    assert.equal(req.payload.op, "session.create");
  });

  it("sendMessage / invokeTool / closeSession use their assist.invoke ops", async () => {
    const ops = [];
    const host = createFakeHost({
      "assist.invoke": (payload) => {
        ops.push(payload.op);
        if (payload.op === "message.send") return { reply: "hello" };
        if (payload.op === "tool.invoke") return { tool: payload.tool, result: { ok: true } };
        return null;
      },
    });
    const assist = createAssistAPI(host);
    assert.equal(await assist.sendMessage("s-1", "hi"), "hello");
    assert.deepEqual(await assist.invokeTool("s-1", { tool: "t", arguments: { a: 1 } }), {
      tool: "t",
      result: { ok: true },
    });
    await assist.closeSession("s-1");
    assert.deepEqual(ops, ["message.send", "tool.invoke", "session.close"]);
    for (const req of host.requests) assert.equal(req.method, "assist.invoke");
  });

  it("listSessions routes through assist.invoke with op session.list", async () => {
    const host = createFakeHost({
      "assist.invoke": (payload) => {
        assert.equal(payload.op, "session.list");
        assert.deepEqual(payload, { op: "session.list" });
        return {
          sessions: [
            { sessionId: "s-1", createdAt: "2026-10-12T00:00:00Z" },
            { sessionId: "s-2", createdAt: "2026-10-12T00:01:00Z" },
          ],
        };
      },
    });
    const assist = createAssistAPI(host);
    const sessions = await assist.listSessions();
    assert.deepEqual(sessions, [
      { sessionId: "s-1", createdAt: "2026-10-12T00:00:00Z" },
      { sessionId: "s-2", createdAt: "2026-10-12T00:01:00Z" },
    ]);
    const req = lastRequest(host);
    assert.equal(req.method, "assist.invoke");
    assert.equal(req.payload.op, "session.list");
  });

  it("streamMessage yields assist.stream chunks correlated by requestId, ending on done:true", async () => {
    const host = createFakeHost({
      "assist.invoke": (payload, requestId, h) => {
        assert.equal(payload.op, "message.stream");
        // Chunks may arrive while the request is still in flight.
        h.emit("assist.stream", { delta: "Hel", done: false }, requestId);
        h.emit("assist.stream", { delta: "lo", done: true }, requestId);
        // An unrelated event must be ignored.
        h.emit("assist.stream", { delta: "NOISE", done: true }, "other-request");
        return { accepted: true };
      },
    });
    const assist = createAssistAPI(host);
    const chunks = [];
    for await (const chunk of assist.streamMessage("s-1", "hi")) chunks.push(chunk);
    assert.deepEqual(chunks, [
      { delta: "Hel", done: false },
      { delta: "lo", done: true },
    ]);
    const req = lastRequest(host);
    assert.equal(req.method, "assist.invoke");
    assert.equal(req.payload.op, "message.stream");
  });

  it("openAssistView calls ui.openView with exactly viewId assist.main", async () => {
    const host = createFakeHost({
      "ui.openView": (payload) => {
        assert.deepEqual(payload, { viewId: "assist.main" });
        return null;
      },
    });
    await createAssistUIAPI(host).openAssistView();
    const req = lastRequest(host);
    assert.equal(req.method, "ui.openView");
    assert.deepEqual(req.payload, { viewId: "assist.main" });
  });
});

describe("assist variants: denial mapping (verbatim §13 message)", () => {
  it("headless: every public function throws SDKAssistAccessError with the verbatim message on ASSIST_DENIED", async () => {
    const host = createDenyingHost();
    const assist = createAssistAPI(host);
    await assertAssistAccessError(assist.createSession());
    await assertAssistAccessError(assist.listSessions());
    await assertAssistAccessError(assist.sendMessage("s-1", "hi"));
    await assertAssistAccessError(
      (async () => {
        for await (const _ of assist.streamMessage("s-1", "hi")) { /* unreachable */ }
      })(),
    );
    await assertAssistAccessError(assist.invokeTool("s-1", { tool: "t", arguments: {} }));
    await assertAssistAccessError(assist.closeSession("s-1"));
  });

  it("UI variant: openAssistView throws SDKAssistAccessError with the verbatim message on ASSIST_DENIED", async () => {
    const host = createDenyingHost();
    await assertAssistAccessError(createAssistUIAPI(host).openAssistView());
  });

  it("denial preserves the host correlationId for log lookup", async () => {
    const host = createDenyingHost();
    try {
      await createAssistAPI(host).createSession();
      assert.fail("expected rejection");
    } catch (error) {
      assert.ok(error instanceof SDKAssistAccessError);
      assert.equal(error.correlationId, "corr-denied");
    }
  });
});

describe("assist variants: no fabricated entitlement state", () => {
  it("success paths resolve with real host data — no access error without a host denial", async () => {
    const host = createFakeHost({
      "assist.invoke": (payload) => {
        if (payload.op === "session.create") return { sessionId: "s-9", createdAt: "t" };
        if (payload.op === "message.send") return { reply: "real reply" };
        return null;
      },
      "ui.openView": () => null,
    });
    const assist = createAssistAPI(host);
    assert.equal((await assist.createSession()).sessionId, "s-9");
    assert.equal(await assist.sendMessage("s-9", "hi"), "real reply");
    await createAssistUIAPI(host).openAssistView();
  });

  it("non-Assist host rejections propagate untouched — never converted to an access error", async () => {
    const host = createFakeHost({
      "assist.invoke": () => {
        throw new SDKError("PERMISSION_DENIED", "Some unrelated broker check failed.", "corr-other");
      },
    });
    const assist = createAssistAPI(host);
    await assert.rejects(assist.createSession(), (error) => {
      assert.ok(error instanceof SDKError, `expected SDKError, got ${error?.constructor?.name}`);
      assert.ok(!(error instanceof SDKAssistAccessError), "must NOT be converted to SDKAssistAccessError");
      assert.equal(error.code, "PERMISSION_DENIED");
      assert.equal(error.message, "Some unrelated broker check failed.");
      return true;
    });
  });

  it("client-side validation errors stay SDKError (INVALID_ARGUMENT), not access errors", async () => {
    const host = createFakeHost();
    const assist = createAssistAPI(host);
    await assert.rejects(assist.sendMessage("", "hi"), (error) => {
      assert.ok(error instanceof SDKError && !(error instanceof SDKAssistAccessError));
      assert.equal(error.code, "INVALID_ARGUMENT");
      return true;
    });
    assert.equal(host.requests.length, 0, "invalid input must never reach the host");
  });
});
