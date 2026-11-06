// ui.openView wire-contract tests for @swiftcode/sdk.
//
// Covers the new `context.ui` API (backed by the Swift host's
// `SDKIPCDispatcher` "ui.openView" route): the context sends exactly
// `ui.openView` with a `{viewId}` payload, rejects blank view IDs
// client-side with INVALID_ARGUMENT, and surfaces host denials as typed
// errors. Uses the same scripted-fake-host pattern as cloudmodel.test.mjs.
//
// Run: `npm run build && npm test` (npm test = `node --test "tests/*.test.mjs"`).
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { pathToFileURL, fileURLToPath } from "node:url";
import path from "node:path";

const distUrl = pathToFileURL(
  path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "dist", "index.js"),
).href;
const { createContext, SDKError } = await import(distUrl);

const EXTENSION = { id: "test.ext", name: "Test Extension", version: "1.0.0" };

function createFakeHost(handlers = {}) {
  const requests = [];
  let closed = false;
  let requestCounter = 0;
  const listeners = new Set();
  const host = {
    get closed() {
      return closed;
    },
    get requests() {
      return requests;
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
    close() {
      closed = true;
    },
  };
  return host;
}

function lastRequest(host) {
  const req = host.requests[host.requests.length - 1];
  assert.ok(req !== undefined, "expected the context to have sent a request");
  return req;
}

describe("ui.openView wire contract", () => {
  it("sends exactly ui.openView with {viewId} and resolves on the host's null payload", async () => {
    const host = createFakeHost({ "ui.openView": () => null });
    const { context } = createContext(host, EXTENSION);
    await context.ui.openView("sandbox.view");
    const req = lastRequest(host);
    assert.equal(req.method, "ui.openView");
    assert.deepEqual(req.payload, { viewId: "sandbox.view" });
  });

  it("rejects a blank viewId client-side with INVALID_ARGUMENT", async () => {
    const host = createFakeHost({ "ui.openView": () => null });
    const { context } = createContext(host, EXTENSION);
    await assert.rejects(() => context.ui.openView(""), (error) => {
      assert.ok(error instanceof SDKError);
      assert.equal(error.code, "INVALID_ARGUMENT");
      return true;
    });
    assert.equal(host.requests.length, 0, "no IPC request should have been sent");
  });

  it("surfaces the host's unknown-view denial as a typed error", async () => {
    const host = createFakeHost({
      "ui.openView": () => {
        throw new SDKError("UNKNOWN_CAPABILITY", 'Unknown view "nope.view".');
      },
    });
    const { context } = createContext(host, EXTENSION);
    await assert.rejects(() => context.ui.openView("nope.view"), (error) => {
      assert.ok(error instanceof SDKError);
      assert.equal(error.code, "UNKNOWN_CAPABILITY");
      return true;
    });
  });
});
