// Security (Keychain) wire-contract tests for @swiftcode/sdk.
// Tests the exact IPC method + payload for every Security API call, the
// client-side validation (IDs, https-only URLs, no credentials in URLs, no
// client-supplied Authorization header), and that malformed host responses
// are rejected with IPC_MALFORMED instead of trusted.
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { pathToFileURL, fileURLToPath } from "node:url";
import path from "node:path";

const distUrl = pathToFileURL(
  path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "dist", "index.js"),
).href;
const {
  createContext,
  createSecurityAPI,
  securityAddValue,
  securityHasValue,
  securityListValueIDs,
  securityDeleteValue,
  securityUseValue,
  SDKError,
} = await import(distUrl);

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
        Promise.resolve().then(() => handler(payload, rid)).then(resolve, reject);
      });
    },
    onEvent(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
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

async function assertRejectsSDKError(promise, code) {
  await assert.rejects(promise, (error) => {
    assert.ok(error instanceof SDKError, `expected SDKError, got ${error}`);
    assert.equal(error.code, code, `expected code ${code}, got ${error.code}`);
    return true;
  });
}

describe("security wire contract", () => {
  it("addValue sends security.addValue with ids+options, resolves metadata only", async () => {
    const host = createFakeHost({
      "security.addValue": () => ({ valueID: "github-token", created: true }),
    });
    const api = createSecurityAPI(host);
    const result = await api.addValue("api-keys", "github-token", {
      label: "GitHub token",
      prompt: "Enter the token.",
    });
    assert.deepEqual(result, { valueID: "github-token", created: true });
    const req = lastRequest(host);
    assert.equal(req.method, "security.addValue");
    assert.deepEqual(req.payload, {
      securityID: "api-keys",
      valueID: "github-token",
      label: "GitHub token",
      prompt: "Enter the token.",
    });
    // Metadata only: the response must not smuggle the secret back.
    assert.ok(!("secret" in result) && !("value" in result));
  });

  it("addValue omits optional label/prompt from the payload", async () => {
    const host = createFakeHost({ "security.addValue": () => ({ valueID: "t", created: false }) });
    const api = createSecurityAPI(host);
    await api.addValue("api-keys", "t");
    assert.deepEqual(lastRequest(host).payload, { securityID: "api-keys", valueID: "t" });
  });

  it("hasValue sends security.hasValue and resolves the boolean", async () => {
    const host = createFakeHost({ "security.hasValue": () => ({ hasValue: true }) });
    const api = createSecurityAPI(host);
    assert.equal(await api.hasValue("api-keys", "github-token"), true);
    const req = lastRequest(host);
    assert.equal(req.method, "security.hasValue");
    assert.deepEqual(req.payload, { securityID: "api-keys", valueID: "github-token" });
  });

  it("listValueIDs sends security.listValueIDs and validates entries", async () => {
    const host = createFakeHost({
      "security.listValueIDs": () => ({
        values: [
          { valueID: "github-token", label: "GitHub token", createdAt: "2026-10-12T14:00:00Z" },
        ],
      }),
    });
    const api = createSecurityAPI(host);
    assert.deepEqual(await api.listValueIDs("api-keys"), [
      { valueID: "github-token", label: "GitHub token", createdAt: "2026-10-12T14:00:00Z" },
    ]);
    assert.equal(lastRequest(host).method, "security.listValueIDs");
  });

  it("deleteValue sends security.deleteValue", async () => {
    const host = createFakeHost({ "security.deleteValue": () => null });
    const api = createSecurityAPI(host);
    await api.deleteValue("api-keys", "github-token");
    const req = lastRequest(host);
    assert.equal(req.method, "security.deleteValue");
    assert.deepEqual(req.payload, { securityID: "api-keys", valueID: "github-token" });
  });

  it("useValue sends security.useValue with the operation and resolves {status, body}", async () => {
    const host = createFakeHost({
      "security.useValue": () => ({ status: 200, body: "{\"login\":\"dylans2010\"}" }),
    });
    const api = createSecurityAPI(host);
    const response = await api.useValue("api-keys", "github-token", {
      kind: "httpAuthorization",
      request: {
        method: "GET",
        url: "https://api.github.com/user",
        headers: { Accept: "application/vnd.github+json" },
      },
    });
    assert.deepEqual(response, { status: 200, body: "{\"login\":\"dylans2010\"}" });
    const req = lastRequest(host);
    assert.equal(req.method, "security.useValue");
    assert.deepEqual(req.payload, {
      securityID: "api-keys",
      valueID: "github-token",
      operation: {
        kind: "httpAuthorization",
        request: {
          method: "GET",
          url: "https://api.github.com/user",
          headers: { Accept: "application/vnd.github+json" },
        },
      },
    });
  });

  it("useValue rejects non-HTTPS URLs client-side", async () => {
    const host = createFakeHost({ "security.useValue": () => ({ status: 200, body: "" }) });
    const api = createSecurityAPI(host);
    await assertRejectsSDKError(
      api.useValue("api-keys", "t", { kind: "httpAuthorization", request: { method: "GET", url: "http://example.com/" } }),
      "INVALID_ARGUMENT",
    );
    assert.equal(host.requests.length, 0, "nothing must reach the host for a rejected URL");
  });

  it("useValue rejects URLs with embedded credentials", async () => {
    const host = createFakeHost({ "security.useValue": () => ({ status: 200, body: "" }) });
    const api = createSecurityAPI(host);
    await assertRejectsSDKError(
      api.useValue("api-keys", "t", {
        kind: "httpAuthorization",
        request: { method: "GET", url: "https://user:pass@example.com/" },
      }),
      "INVALID_ARGUMENT",
    );
    assert.equal(host.requests.length, 0);
  });

  it("useValue rejects a client-supplied Authorization header", async () => {
    const host = createFakeHost({ "security.useValue": () => ({ status: 200, body: "" }) });
    const api = createSecurityAPI(host);
    await assertRejectsSDKError(
      api.useValue("api-keys", "t", {
        kind: "httpAuthorization",
        request: { method: "GET", url: "https://example.com/", headers: { authorization: "Bearer x" } },
      }),
      "INVALID_ARGUMENT",
    );
    assert.equal(host.requests.length, 0);
  });

  it("useValue rejects unsupported operation kinds", async () => {
    const host = createFakeHost({ "security.useValue": () => ({ status: 200, body: "" }) });
    const api = createSecurityAPI(host);
    await assertRejectsSDKError(
      api.useValue("api-keys", "t", { kind: "rawSecret", request: { method: "GET", url: "https://example.com/" } }),
      "INVALID_ARGUMENT",
    );
    assert.equal(host.requests.length, 0);
  });

  it("rejects blank/whitespace IDs with INVALID_ARGUMENT", async () => {
    const host = createFakeHost({ "security.hasValue": () => ({ hasValue: false }) });
    const api = createSecurityAPI(host);
    await assertRejectsSDKError(api.hasValue("", "t"), "INVALID_ARGUMENT");
    await assertRejectsSDKError(api.hasValue("api-keys", "has space"), "INVALID_ARGUMENT");
    assert.equal(host.requests.length, 0);
  });

  it("rejects malformed host responses with IPC_MALFORMED", async () => {
    const host = createFakeHost({
      "security.addValue": () => ({ nope: true }),
      "security.hasValue": () => ({ hasValue: "yes" }),
      "security.listValueIDs": () => ({ values: [{ valueID: "t" }] }),
      "security.useValue": () => ({ status: "200", body: "" }),
    });
    const api = createSecurityAPI(host);
    await assertRejectsSDKError(api.addValue("a", "b"), "IPC_MALFORMED");
    await assertRejectsSDKError(api.hasValue("a", "b"), "IPC_MALFORMED");
    await assertRejectsSDKError(api.listValueIDs("a"), "IPC_MALFORMED");
    await assertRejectsSDKError(
      api.useValue("a", "b", { kind: "httpAuthorization", request: { method: "GET", url: "https://example.com/" } }),
      "IPC_MALFORMED",
    );
  });

  it("host denials surface as typed SDKError rejections", async () => {
    const host = createFakeHost({
      "security.addValue": () => { throw new SDKError("PERMISSION_DENIED", "use.Security not granted", "r1"); },
    });
    const api = createSecurityAPI(host);
    await assertRejectsSDKError(api.addValue("a", "b"), "PERMISSION_DENIED");
  });
});

describe("standalone security helpers", () => {
  it("delegate to the connection installed by createSecurityAPI", async () => {
    const host = createFakeHost({
      "security.addValue": () => ({ valueID: "t", created: true }),
      "security.hasValue": () => ({ hasValue: true }),
      "security.listValueIDs": () => ({ values: [] }),
      "security.deleteValue": () => null,
      "security.useValue": () => ({ status: 204, body: "" }),
    });
    createSecurityAPI(host);
    assert.deepEqual(await securityAddValue("api-keys", "t"), { valueID: "t", created: true });
    assert.equal(await securityHasValue("api-keys", "t"), true);
    assert.deepEqual(await securityListValueIDs("api-keys"), []);
    await securityDeleteValue("api-keys", "t");
    assert.deepEqual(
      await securityUseValue("api-keys", "t", {
        kind: "httpAuthorization",
        request: { method: "POST", url: "https://example.com/hook", body: "{}" },
      }),
      { status: 204, body: "" },
    );
    assert.deepEqual(
      host.requests.map((r) => r.method),
      ["security.addValue", "security.hasValue", "security.listValueIDs", "security.deleteValue", "security.useValue"],
    );
  });

  it("context.security routes over the same connection", async () => {
    const host = createFakeHost({
      "security.hasValue": () => ({ hasValue: false }),
    });
    const { context } = createContext(host, EXTENSION);
    assert.equal(await context.security.hasValue("api-keys", "t"), false);
    assert.equal(lastRequest(host).method, "security.hasValue");
    // createContext installs the connection, so the standalone helpers
    // resolve against it too.
    assert.equal(await securityHasValue("api-keys", "t"), false);
  });
});
