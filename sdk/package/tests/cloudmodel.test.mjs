import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { pathToFileURL, fileURLToPath } from "node:url";
import path from "node:path";

const distUrl = pathToFileURL(
  path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "dist", "index.js"),
).href;
const { createContext, SDKError, SDKCloudModelAccessError, CLOUD_MODEL_ACCESS_DENIED_MESSAGE } = await import(distUrl);

const EXTENSION = { id: "test.ext", name: "Test Extension", version: "1.0.0" };

const VERBATIM_CLOUD_DENIAL =
  "This app is not allowed to use the SwiftCode Cloud Model because access has not yet been verified. Please check with the app developer for further information.";

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

describe("cloudModel.complete entitlement denial (specs/ide/sdk-platform.md, task B4)", () => {
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
