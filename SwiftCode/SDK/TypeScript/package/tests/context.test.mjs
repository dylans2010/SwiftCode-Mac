// Context contract tests for @swiftcode/sdk (Docs/Intro-to-SDK.md §19.1, §19.2).
//
// Loads the real compiled dist/index.js and builds the real context via
// createContext over a scripted fake HostConnection. The fake host records
// every IPC method+payload the context emits and answers from a script —
// the tests assert the EXACT wire method and payload each context method
// produces, denial propagation, build-event streaming, and the
// single-dispatch regression for commands.execute (the double-dispatch fix).
//
// Run: `npm run build && npm test` (npm test = `node --test tests/`).
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { pathToFileURL, fileURLToPath } from "node:url";
import path from "node:path";

const distUrl = pathToFileURL(
  path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "dist", "index.js"),
).href;
const { createContext, SDKError } = await import(distUrl);

const EXTENSION = { id: "test.ext", name: "Test Extension", version: "1.0.0" };

/**
 * Scripted fake host implementing the HostConnection shape. `handlers`
 * maps an IPC method to `(payload, requestId) => responsePayload`; a
 * handler may throw to script an `ok:false`-style rejection. All inbound
 * requests and outbound events are recorded for exact wire assertions.
 */
function createFakeHost(handlers = {}) {
  const requests = [];
  const outboundEvents = [];
  const listeners = new Set();
  let closed = false;
  let requestCounter = 0;
  const host = {
    get closed() {
      return closed;
    },
    get requests() {
      return requests;
    },
    get outboundEvents() {
      return outboundEvents;
    },
    request(method, payload = {}, requestId) {
      const rid = requestId ?? `fake-req-${requestCounter++}`;
      requests.push({ method, payload, requestId: rid });
      return new Promise((resolve, reject) => {
        const handler = handlers[method];
        if (handler === undefined) {
          reject(new SDKError("IPC_MALFORMED", `Unknown method ${method}`, rid));
          return;
        }
        Promise.resolve()
          .then(() => handler(payload, rid))
          .then(resolve, reject);
      });
    },
    onEvent(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    sendEvent(name, payload = {}) {
      outboundEvents.push({ name, payload });
    },
    close() {
      closed = true;
    },
    /** Scripts an inbound host→extension event frame. */
    emitHostEvent(name, payload, requestId = "evt-1") {
      const event = { name, payload, requestId };
      for (const listener of [...listeners]) listener(event);
    },
  };
  return host;
}

function lastRequest(host) {
  const req = host.requests[host.requests.length - 1];
  assert.ok(req !== undefined, "expected the context to have sent a request");
  return req;
}

describe("context wire contract", () => {
  it("sourceControl.getStatus() sends sourceControl.getStatus with {}", async () => {
    const status = {
      isRepository: true,
      branchName: "main",
      ahead: 0,
      behind: 0,
      stagedCount: 1,
      unstagedCount: 0,
      untrackedCount: 0,
      files: [{ path: "a.txt", status: "modified", isStaged: true }],
    };
    const host = createFakeHost({ "sourceControl.getStatus": () => status });
    const { context } = createContext(host, EXTENSION);
    assert.deepEqual(await context.sourceControl.getStatus(), status);
    const req = lastRequest(host);
    assert.equal(req.method, "sourceControl.getStatus");
    assert.deepEqual(req.payload, {});
  });

  it("sourceControl.getDiff({maxBytes: 100}) sends sourceControl.getDiff with {options: {maxBytes: 100}}", async () => {
    const diff = { files: [], truncated: false, totalBytes: 0, byteLimit: 100 };
    const host = createFakeHost({ "sourceControl.getDiff": () => diff });
    const { context } = createContext(host, EXTENSION);
    assert.deepEqual(await context.sourceControl.getDiff({ maxBytes: 100 }), diff);
    const req = lastRequest(host);
    assert.equal(req.method, "sourceControl.getDiff");
    assert.deepEqual(req.payload, { options: { maxBytes: 100 } });
  });

  it("sourceControl.getDiff() with no options sends {}", async () => {
    const host = createFakeHost({
      "sourceControl.getDiff": () => ({ files: [], truncated: false, totalBytes: 0, byteLimit: 262144 }),
    });
    const { context } = createContext(host, EXTENSION);
    await context.sourceControl.getDiff();
    assert.deepEqual(lastRequest(host).payload, {});
  });

  it('build.run({target: "Foo"}) sends build.run with {target: "Foo"}', async () => {
    const host = createFakeHost({ "build.run": () => ({ handleId: "h-1" }) });
    const { context } = createContext(host, EXTENSION);
    const handle = await context.build.run({ target: "Foo" });
    assert.equal(handle.id, "h-1");
    const req = host.requests.find((r) => r.method === "build.run");
    assert.ok(req !== undefined);
    assert.deepEqual(req.payload, { target: "Foo" });
  });

  it("build.cancel() on a handle sends build.cancel with {handleId}", async () => {
    const host = createFakeHost({
      "build.run": () => ({ handleId: "h-9" }),
      "build.cancel": () => ({}),
    });
    const { context } = createContext(host, EXTENSION);
    const handle = await context.build.run({ target: "Foo" });
    await handle.cancel();
    const req = lastRequest(host);
    assert.equal(req.method, "build.cancel");
    assert.deepEqual(req.payload, { handleId: "h-9" });
  });

  it("commands.register sends {id, title} only and dispose() sends commands.unregister", async () => {
    const host = createFakeHost({ "commands.register": () => ({}), "commands.unregister": () => ({}) });
    const { context } = createContext(host, EXTENSION);
    const disposable = context.commands.register({
      id: "my-cmd",
      title: "My Command",
      execute: async () => "done",
    });
    assert.equal(typeof disposable.dispose, "function");
    const registered = lastRequest(host);
    assert.equal(registered.method, "commands.register");
    // The execute function must NEVER cross the wire.
    assert.deepEqual(registered.payload, { id: "my-cmd", title: "My Command" });

    disposable.dispose();
    const unregistered = lastRequest(host);
    assert.equal(unregistered.method, "commands.unregister");
    assert.deepEqual(unregistered.payload, { commandID: "my-cmd" });

    // Idempotent: a second dispose sends nothing more.
    const before = host.requests.length;
    disposable.dispose();
    assert.equal(host.requests.length, before);
  });

  it("host ok:false PERMISSION_DENIED propagates as a thrown SDKError (denial is not faked as success)", async () => {
    const host = createFakeHost({
      "sourceControl.getStatus": () => {
        throw new SDKError("PERMISSION_DENIED", "Capability source-control.read is not granted.", "corr-denied");
      },
    });
    const { context } = createContext(host, EXTENSION);
    await assert.rejects(context.sourceControl.getStatus(), (error) => {
      assert.ok(error instanceof SDKError, `expected SDKError, got ${error?.constructor?.name}`);
      assert.equal(error.code, "PERMISSION_DENIED");
      assert.equal(error.message, "Capability source-control.read is not granted.");
      assert.equal(error.correlationId, "corr-denied");
      return true;
    });
  });

  it("context exposes the entitled Assist variants only (task B2 boundary, replaces the §9 deny-by-default assertion)", () => {
    const host = createFakeHost();
    const { context } = createContext(host, EXTENSION);
    // Part B opens Assist deliberately through two entitled variants.
    assert.equal(typeof context.assist.createSession, "function");
    assert.equal(typeof context.assistUI.openAssistView, "function");
    // Variant isolation: the headless variant has no view-opening path,
    // the UI variant has no headless session APIs.
    assert.equal(context.assist.openAssistView, undefined);
    assert.equal(context.assistUI.createSession, undefined);
  });
});

describe("build handle streaming", () => {
  it("feeds build.output events then build.finished: iterator yields in order, wait() resolves to the terminal result", async () => {
    const host = createFakeHost({ "build.run": () => ({ handleId: "h-1" }) });
    const { context } = createContext(host, EXTENSION);

    // Start the run; events may arrive before the handle exists (stashed, then replayed).
    const handlePromise = context.build.run({ target: "Foo" });
    const runRequestId = host.requests[0].requestId;
    host.emitHostEvent("build.output", { handleId: "h-1", kind: "stdout", text: "line 1", timestamp: 1000 }, runRequestId);
    host.emitHostEvent("build.output", { handleId: "h-1", kind: "stderr", text: "warn x", timestamp: 1001 }, runRequestId);
    host.emitHostEvent(
      "build.output",
      { handleId: "h-1", kind: "status", text: "compiling", timestamp: 1002 },
      runRequestId,
    );
    host.emitHostEvent(
      "build.finished",
      {
        handleId: "h-1",
        status: "succeeded",
        durationSeconds: 1.5,
        errorCount: 0,
        warningCount: 2,
        diagnostics: [],
        correlationId: "corr-build",
      },
      runRequestId,
    );

    const handle = await handlePromise;
    assert.equal(handle.id, "h-1");

    const seen = [];
    for await (const event of handle.output) seen.push(event);
    assert.deepEqual(
      seen.map((e) => [e.kind, e.text]),
      [
        ["stdout", "line 1"],
        ["stderr", "warn x"],
        ["status", "compiling"],
      ],
    );

    // wait() must resolve from the cached build.finished result — the fake
    // host has no "build.wait" handler, so a second request would reject.
    const result = await handle.wait();
    assert.equal(result.status, "succeeded");
    assert.equal(result.correlationId, "corr-build");
    assert.equal(result.warningCount, 2);
    assert.deepEqual(
      host.requests.map((r) => r.method),
      ["build.run"],
      "wait() must not issue build.wait after build.finished was received",
    );
  });
});

describe("commands.execute dispatch regression", () => {
  it("REGRESSION: one host commands.execute event produces exactly one handler invocation", async () => {
    const host = createFakeHost({ "commands.register": () => ({}), "commands.unregister": () => ({}) });
    const { context, getCommandHandler } = createContext(host, EXTENSION);

    let invocations = 0;
    context.commands.register({
      id: "do-thing",
      title: "Do Thing",
      execute: async () => {
        invocations++;
        return "ok";
      },
    });

    // 1. The host delivers a commands.execute event through the connection.
    //    createContext must NOT self-dispatch it: dispatch is owned
    //    exclusively by the runtime adapter via getCommandHandler.
    host.emitHostEvent("commands.execute", { commandID: "do-thing", payload: {} }, "evt-exec-1");
    // Flush the event loop so any rogue synchronous/self dispatch would run.
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(invocations, 0, "createContext self-dispatched commands.execute (double-dispatch bug is back)");

    // 2. The runtime adapter owns dispatch: exactly one invocation.
    const handler = getCommandHandler("do-thing");
    assert.equal(typeof handler, "function", "runtime adapter must resolve the handler via getCommandHandler");
    await handler({});
    assert.equal(invocations, 1, "one host commands.execute event must produce exactly one handler invocation");

    // 3. After unregister, the handler is gone for the adapter too.
    context.subscriptions.disposeAll();
    assert.equal(getCommandHandler("do-thing"), undefined);
  });
});
