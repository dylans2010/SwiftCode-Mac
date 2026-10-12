// Cloud model contract tests for @swiftcode/sdk (Docs/Intro-to-SDK.md §19.1, §19.2).
//
// Loads the real compiled dist/index.js and builds the real context via
// createContext over a scripted fake HostConnection (the same pattern as
// context.test.mjs). The fake host records every IPC method+payload the
// context emits and answers from a script — the tests assert the EXACT
// wire method and payload for context.cloudModel.complete(...), that host
// denials surface as typed errors with the right codes, and that a
// malformed host response is rejected instead of trusted.
//
// Run: `npm run build && npm test` (npm test = `node --test "tests/*.test.mjs"`).
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { pathToFileURL, fileURLToPath } from "node:url";
import path from "node:path";

const distUrl = pathToFileURL(
  path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "dist", "index.js"),
).href;
const { createContext, SDKError, SDKCloudModelAccessError, CLOUD_MODEL_ACCESS_DENIED_MESSAGE } = await import(distUrl);

const EXTENSION = { id: "test.ext", name: "Test Extension", version: "1.0.0" };

// The §13 cloud-model denial, verbatim — do not reword. Duplicated here
// (not imported) so the test independently pins the exact user-facing
// text. PROPOSED WORDING — Dylan finalizes it; when he does, this literal
// and the exported constant must change together.
const VERBATIM_CLOUD_DENIAL =
  "This app is not allowed to use the SwiftCode Cloud Model because access has not yet been verified. Please check with the app developer for further information.";

/**
 * Scripted fake host implementing the HostConnection shape. `handlers`
 * maps an IPC method to `(payload, requestId) => responsePayload`; a
 * handler may throw to script an `ok:false`-style rejection. All inbound
 * requests are recorded for exact wire assertions.
 */
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

describe("cloudModel.complete wire contract", () => {
  it("sends exactly cloudModel.complete with {prompt} for a bare prompt", async () => {
    const host = createFakeHost({ "cloudModel.complete": () => ({ response: "hello" }) });
    const { context } = createContext(host, EXTENSION);
    assert.equal(await context.cloudModel.complete({ prompt: "Summarize this" }), "hello");
    const req = lastRequest(host);
    assert.equal(req.method, "cloudModel.complete");
    assert.deepEqual(req.payload, { prompt: "Summarize this" });
  });

  it("sends the full payload shape with history, systemPrompt, and modelIdentifier", async () => {
    const host = createFakeHost({ "cloudModel.complete": () => ({ response: "ok" }) });
    const { context } = createContext(host, EXTENSION);
    await context.cloudModel.complete({
      prompt: "Continue",
      history: [
        { role: "user", content: "First" },
        { role: "assistant", content: "Reply" },
      ],
      systemPrompt: "Be concise.",
      modelIdentifier: "cloud-model-a",
    });
    const req = lastRequest(host);
    assert.equal(req.method, "cloudModel.complete");
    assert.deepEqual(req.payload, {
      prompt: "Continue",
      history: [
        { role: "user", content: "First" },
        { role: "assistant", content: "Reply" },
      ],
      systemPrompt: "Be concise.",
      modelIdentifier: "cloud-model-a",
    });
  });

  it("surfaces PERMISSION_DENIED as a typed error with its code", async () => {
    const host = createFakeHost({
      "cloudModel.complete": () => {
        throw new SDKError("PERMISSION_DENIED", "The extension does not hold the use.SwiftCodeModel grant.", "fake-req-0");
      },
    });
    const { context } = createContext(host, EXTENSION);
    await assert.rejects(context.cloudModel.complete({ prompt: "x" }), (error) => {
      assert.ok(error instanceof SDKError);
      assert.equal(error.code, "PERMISSION_DENIED");
      return true;
    });
  });

  it("surfaces RESOURCE_LIMIT_EXCEEDED as a typed quota error (never a fabricated response)", async () => {
    const host = createFakeHost({
      "cloudModel.complete": () => {
        throw new SDKError("RESOURCE_LIMIT_EXCEEDED", "The SwiftCode Cloud Model daily request quota is exhausted.", "fake-req-0");
      },
    });
    const { context } = createContext(host, EXTENSION);
    await assert.rejects(context.cloudModel.complete({ prompt: "x" }), (error) => {
      assert.ok(error instanceof SDKError);
      assert.equal(error.code, "RESOURCE_LIMIT_EXCEEDED");
      return true;
    });
    // The rejection carries the typed error only — no text to mistake for a model answer.
  });

  it("rejects an empty prompt client-side without sending anything", async () => {
    const host = createFakeHost({ "cloudModel.complete": () => ({ response: "nope" }) });
    const { context } = createContext(host, EXTENSION);
    await assert.rejects(context.cloudModel.complete({ prompt: "" }), (error) => {
      assert.ok(error instanceof SDKError);
      assert.equal(error.code, "INVALID_ARGUMENT");
      return true;
    });
    assert.equal(host.requests.length, 0);
  });

  it("rejects a non-string prompt client-side without sending anything", async () => {
    const host = createFakeHost({ "cloudModel.complete": () => ({ response: "nope" }) });
    const { context } = createContext(host, EXTENSION);
    await assert.rejects(context.cloudModel.complete({ prompt: 42 }), (error) => {
      assert.ok(error instanceof SDKError);
      assert.equal(error.code, "INVALID_ARGUMENT");
      return true;
    });
    assert.equal(host.requests.length, 0);
  });

  it("rejects a malformed host response with IPC_MALFORMED", async () => {
    const host = createFakeHost({ "cloudModel.complete": () => ({ nope: 1 }) });
    const { context } = createContext(host, EXTENSION);
    await assert.rejects(context.cloudModel.complete({ prompt: "x" }), (error) => {
      assert.ok(error instanceof SDKError);
      assert.equal(error.code, "IPC_MALFORMED");
      return true;
    });
  });
});

describe("cloudModel.complete entitlement denial (Docs/Intro-to-SDK.md §13, task B4)", () => {
  it("maps the host's typed CLOUD_MODEL_DENIED to SDKCloudModelAccessError with the verbatim message", async () => {
    const host = createFakeHost({
      "cloudModel.complete": () => {
        throw new SDKError("CLOUD_MODEL_DENIED", "host-side entitlement denial", "corr-123");
      },
    });
    const { context } = createContext(host, EXTENSION);
    await assert.rejects(context.cloudModel.complete({ prompt: "x" }), (error) => {
      assert.ok(error instanceof SDKCloudModelAccessError);
      assert.equal(error.code, "CLOUD_MODEL_DENIED");
      assert.equal(error.message, VERBATIM_CLOUD_DENIAL);
      assert.equal(error.correlationId, "corr-123");
      return true;
    });
  });

  it("the exported message constant matches the verbatim §13 text", () => {
    assert.equal(CLOUD_MODEL_ACCESS_DENIED_MESSAGE, VERBATIM_CLOUD_DENIAL);
  });

  it("does NOT map unrelated denials — they propagate untouched", async () => {
    for (const code of ["PERMISSION_DENIED", "API_KEY_SCOPE_INSUFFICIENT", "SERVICE_UNAVAILABLE"]) {
      const host = createFakeHost({
        "cloudModel.complete": () => {
          throw new SDKError(code, "some other denial", "corr-x");
        },
      });
      const { context } = createContext(host, EXTENSION);
      await assert.rejects(context.cloudModel.complete({ prompt: "x" }), (error) => {
        assert.ok(error instanceof SDKError);
        assert.ok(!(error instanceof SDKCloudModelAccessError));
        assert.equal(error.code, code);
        return true;
      });
    }
  });

  it("never throws an access error without the host's typed denial", async () => {
    const host = createFakeHost({ "cloudModel.complete": () => ({ response: "ok" }) });
    const { context } = createContext(host, EXTENSION);
    assert.equal(await context.cloudModel.complete({ prompt: "x" }), "ok");
  });
});
