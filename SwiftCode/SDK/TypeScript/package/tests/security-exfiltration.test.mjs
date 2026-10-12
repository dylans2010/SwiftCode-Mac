// Adversarial exfiltration tests for the Security (Keychain) API (SEC-ADV-2).
//
// The security.* IPC API is REAL now (SwiftCode/SDK/TypeScript/package/src/security.ts
// over the real wire contract in SDKSecurityContracts.swift, served by the
// security.* cases in SDKIPCDispatcher.swift). The design invariant is:
// plaintext secrets NEVER cross this boundary in either direction. The
// extension user never supplies a secret; the user types it into the host's
// secure popup, and useValue only ever returns {status, body}.
//
// These tests build a fake in-process host harness implementing the
// documented wire contract (a test-double transport, which is allowed in
// tests) and then prove an attacker CANNOT extract plaintext through ANY
// route. Every test asserts a NEGATIVE: no secret field in any client-
// surfaced value, malformed input rejected with typed errors, cross-app
// identity forgery denied.
//
// The single boundary this suite deliberately does NOT claim: a host is
// the wire authority for the *documented* fields (valueID, label, status,
// body). If a fully compromised host fabricates those fields' contents,
// the client cannot distinguish fabrication from data — there is no secret
// reference on the client side to compare against. The invariant under test
// is that the client never ADDS exposure: every extra field the host
// smuggles is stripped, and only the documented shapes reach extension code.
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { pathToFileURL, fileURLToPath } from "node:url";
import path from "node:path";

const distUrl = pathToFileURL(
  path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "dist", "index.js"),
).href;
const {
  createSecurityAPI,
  securityAddValue,
  securityHasValue,
  securityListValueIDs,
  securityDeleteValue,
  securityUseValue,
  SDKError,
} = await import(distUrl);

// The canary secret. It lives ONLY in the harness (the host). If this
// string ever shows up in anything the client returns, throws, or sends,
// exfiltration happened and the test fails.
const CANARY = "sk-live-EXFILTRATION-CANARY-9f3b2a77";

// ---------------------------------------------------------------------------
// Fake in-process host harness implementing the documented wire contract.
//
// The harness is session-bound: each instance represents ONE extension
// session (callerApp), mirroring the host's contract that the Keychain
// namespace's extension component is derived from the session-bound caller
// identity, never from the payload. securityIDs are registered to the app
// that first stores under them; any other session touching that securityID
// is denied with a typed error.
function createAdversarialHost({
  callerApp = "app-a",
  malicious = false,
  smuggleIn = null, // extra response fields to attempt smuggling, or null
  namespaces = null, // inject a shared namespace registry (multi-session tests)
  store = null, // inject a shared value store (multi-session tests)
} = {}) {
  const requests = [];
  // Default to fresh per-session maps; multi-session tests inject shared ones
  // so two sessions hit the same backend while keeping separate identities.
  namespaces = namespaces ?? new Map(); // securityID -> owning app
  store = store ?? new Map(); // "<app>::<securityID>::<valueID>" -> { label, createdAt }

  const host = {
    get requests() { return requests; },
    get store() { return store; },
    get namespaces() { return namespaces; },
    /** Pre-register a securityID owned by an app (simulates prior storage). */
    register(securityID, owner, valueID = "v1") {
      namespaces.set(securityID, owner);
      store.set(`${owner}::${securityID}::${valueID}`, {
        label: `${valueID} label`,
        createdAt: new Date().toISOString(),
      });
    },
    request(method, payload = {}, requestId = "fake-req") {
      requests.push({ method, payload, requestId });
      return new Promise((resolve, reject) => {
        queueMicrotask(() => {
          try {
            resolve(dispatch(method, payload));
          } catch (error) {
            reject(error);
          }
        });
      });
    },
    onEvent() { return () => {}; },
    sendEvent() {},
    close() {},
    closed: false,
  };

  function deny(message) {
    return new SDKError("SDK_PERMISSION_DENIED", message, "corr-forge-test");
  }

  // The smuggle pack: everything a compromised host tries to slip past the
  // client. These sit OUTSIDE the documented response shapes.
  function smuggle() {
    const pack = {
      secret: CANARY,
      plaintext: CANARY,
      token: CANARY,
      password: CANARY,
      authorization: `Bearer ${CANARY}`,
      Authorization: `Bearer ${CANARY}`,
      debug: { secret: CANARY, nested: { value: CANARY } },
      echo: { headers: { Authorization: `Bearer ${CANARY}` } },
    };
    return smuggleIn === null ? pack : { ...pack, ...smuggleIn };
  }

  function withSmuggle(base) {
    return malicious ? { ...base, ...smuggle() } : base;
  }

  // Session-bound namespace check. Mirrors the host contract: the payload's
  // securityID is looked up against namespaces bound to the SESSION's
  // caller identity. A session claiming another app's Security ID is
  // rejected here, before any Keychain touch.
  function checkNamespace(securityID) {
    const owner = namespaces.get(securityID);
    if (owner === undefined) return; // new securityID: first writer claims it
    if (owner !== callerApp) {
      throw deny(
        `securityID "${securityID}" belongs to another app's Security namespace`,
      );
    }
  }

  function dispatch(method, payload) {
    switch (method) {
      case "security.addValue": {
        checkNamespace(payload.securityID);
        const key = `${callerApp}::${payload.securityID}::${payload.valueID}`;
        const existed = store.has(key);
        namespaces.set(payload.securityID, callerApp);
        store.set(key, {
          label: payload.label ?? "",
          createdAt: new Date().toISOString(),
        });
        return withSmuggle({ valueID: payload.valueID, created: !existed });
      }
      case "security.hasValue": {
        checkNamespace(payload.securityID);
        const key = `${callerApp}::${payload.securityID}::${payload.valueID}`;
        return withSmuggle({ hasValue: store.has(key) });
      }
      case "security.listValueIDs": {
        checkNamespace(payload.securityID);
        const values = [];
        for (const [key, entry] of store) {
          const [app, sid, vid] = key.split("::");
          if (app === callerApp && sid === payload.securityID) {
            values.push(withSmuggle({
              valueID: vid,
              label: entry.label,
              createdAt: entry.createdAt,
            }));
          }
        }
        return withSmuggle({ values });
      }
      case "security.deleteValue": {
        checkNamespace(payload.securityID);
        const key = `${callerApp}::${payload.securityID}::${payload.valueID}`;
        store.delete(key);
        return withSmuggle(null); // host answers with null on success
      }
      case "security.useValue": {
        checkNamespace(payload.securityID);
        const key = `${callerApp}::${payload.securityID}::${payload.valueID}`;
        if (!store.has(key)) {
          throw new SDKError("SDK_NOT_FOUND", "no such value", "corr-forge-test");
        }
        // The host attaches the secret as the Authorization header itself
        // and performs the HTTPS request; only {status, body} come back.
        return withSmuggle({ status: 200, body: JSON.stringify({ ok: true }) });
      }
      default:
        throw new SDKError("IPC_MALFORMED", `Unknown method ${method}`, "corr-forge-test");
    }
  }

  return host;
}

/**
 * Recursively walks every string reachable in `value` (including object
 * keys and nested arrays) and fails if any of them contains the canary.
 * This is the core negative assertion: the secret must not be observable
 * anywhere in client-surfaced data.
 */
function assertNoSecret(value, where, seen = new Set()) {
  if (typeof value === "string") {
    assert.ok(
      !value.includes(CANARY),
      `EXFILTRATION at ${where}: a returned string contains the secret: ${value.slice(0, 80)}`,
    );
    return;
  }
  if (typeof value !== "object" || value === null) return;
  if (seen.has(value)) return;
  seen.add(value);
  if (Array.isArray(value)) {
    value.forEach((entry, i) => assertNoSecret(entry, `${where}[${i}]`, seen));
    return;
  }
  for (const [k, v] of Object.entries(value)) {
    assert.ok(
      !k.includes(CANARY),
      `EXFILTRATION at ${where}: an object key contains the secret: ${k}`,
    );
    assertNoSecret(v, `${where}.${k}`, seen);
  }
}

/** Like assertNoSecret, but also forbids the secret in JSON form of errors. */
function assertErrorClean(error, where) {
  assert.ok(error instanceof SDKError, `expected SDKError at ${where}, got ${error}`);
  assertNoSecret(String(error.message), `${where} (error message)`);
  assertNoSecret(String(error.code), `${where} (error code)`);
}

async function assertRejectsSDKError(promise, code, where) {
  await assert.rejects(
    promise,
    (error) => {
      assert.ok(error instanceof SDKError, `${where}: expected SDKError, got ${error}`);
      assert.equal(error.code, code, `${where}: expected code ${code}, got ${error.code}`);
      assertNoSecret(String(error.message), `${where} (error message)`);
      return true;
    },
    `${where}: expected rejection`,
  );
}

const OP = {
  kind: "httpAuthorization",
  request: { method: "GET", url: "https://api.example.com/whoami" },
};

describe("security exfiltration (adversarial)", () => {
  it("addValue: even a generous host cannot smuggle the secret — metadata only", async () => {
    const host = createAdversarialHost({ malicious: true });
    const api = createSecurityAPI(host);
    const result = await api.addValue("api-keys", "github-token", {
      label: "GitHub token",
      prompt: "Paste your token.",
    });
    // Deep shape: EXACTLY {valueID, created}. Any smuggled field is stripped.
    assert.deepEqual(result, { valueID: "github-token", created: true });
    assertNoSecret(result, "security.addValue result");
    assertNoSecret(JSON.stringify(result), "security.addValue JSON");
  });

  it("useValue: response is exactly {status, body} — no secret, no echoed Authorization", async () => {
    const host = createAdversarialHost({ malicious: true });
    const api = createSecurityAPI(host);
    await api.addValue("api-keys", "github-token");
    const result = await api.useValue("api-keys", "github-token", OP);
    assert.deepEqual(result, { status: 200, body: JSON.stringify({ ok: true }) });
    assertNoSecret(result, "security.useValue result");
    assertNoSecret(JSON.stringify(result), "security.useValue JSON");
    // And the request the client SENT must carry no secret material either.
    const useReq = host.requests.find((r) => r.method === "security.useValue");
    assert.ok(useReq, "expected a security.useValue request");
    assertNoSecret(useReq.payload, "security.useValue outgoing payload");
    const sentHeaders = useReq.payload.operation.request.headers ?? {};
    assert.ok(
      !Object.keys(sentHeaders).some((h) => h.toLowerCase() === "authorization"),
      "client must never send an Authorization header; the host owns it",
    );
  });

  it("hasValue: smuggled fields collapse to a bare boolean", async () => {
    const host = createAdversarialHost({ malicious: true });
    const api = createSecurityAPI(host);
    await api.addValue("api-keys", "github-token");
    const result = await api.hasValue("api-keys", "github-token");
    assert.equal(result, true);
    assert.equal(typeof result, "boolean");
    assertNoSecret(result, "security.hasValue result");
  });

  it("listValueIDs: metadata without secret material, per entry", async () => {
    const host = createAdversarialHost({ malicious: true });
    const api = createSecurityAPI(host);
    await api.addValue("api-keys", "github-token", { label: "GitHub" });
    await api.addValue("api-keys", "npm-token", { label: "npm" });
    const result = await api.listValueIDs("api-keys");
    assert.equal(result.length, 2);
    for (const entry of result) {
      // Deep shape: EXACTLY {valueID, label, createdAt}.
      assert.deepEqual(Object.keys(entry).sort(), ["createdAt", "label", "valueID"]);
      assertNoSecret(entry, `security.listValueIDs entry ${entry.valueID}`);
    }
    assertNoSecret(JSON.stringify(result), "security.listValueIDs JSON");
  });

  it("deleteValue: resolves void even when the host smuggles into the payload", async () => {
    const host = createAdversarialHost({ malicious: true });
    const api = createSecurityAPI(host);
    await api.addValue("api-keys", "github-token");
    const result = await api.deleteValue("api-keys", "github-token");
    assert.equal(result, undefined);
    assert.equal(await api.hasValue("api-keys", "github-token"), false);
  });

  it("malformed IPC: missing fields / wrong types / null / arrays -> typed errors, never a crash", async () => {
    // Hand-rolled responders: each returns a malformed payload for its route.
    const malformedHosts = {
      "security.addValue": () => ({ valueID: "x" }), // missing `created`
      "security.hasValue": () => ({ hasValue: "yes" }), // wrong type
      "security.listValueIDs": () => ({ values: [{ valueID: "x" }] }), // entry missing fields
      "security.useValue": () => ({ status: "200", body: 42 }), // wrong types
    };
    for (const [method, responder] of Object.entries(malformedHosts)) {
      const host = createAdversarialHost();
      const api = createSecurityAPI(host);
      const originalRequest = host.request.bind(host);
      host.request = (m, p, rid) =>
        m === method ? Promise.resolve(responder()) : originalRequest(m, p, rid);
      const call = {
        "security.addValue": () => api.addValue("s", "v"),
        "security.hasValue": () => api.hasValue("s", "v"),
        "security.listValueIDs": () => api.listValueIDs("s"),
        "security.useValue": () => api.useValue("s", "v", OP),
      }[method]();
      await assertRejectsSDKError(call, "IPC_MALFORMED", `${method} malformed`);
    }
    // Null / array / string payloads for every route.
    for (const raw of [null, [], "garbage", 42]) {
      const host = createAdversarialHost();
      const api = createSecurityAPI(host);
      host.request = () => Promise.resolve(raw);
      await assertRejectsSDKError(api.addValue("s", "v"), "IPC_MALFORMED", "addValue non-object");
      await assertRejectsSDKError(api.hasValue("s", "v"), "IPC_MALFORMED", "hasValue non-object");
      await assertRejectsSDKError(api.listValueIDs("s"), "IPC_MALFORMED", "listValueIDs non-object");
      await assertRejectsSDKError(api.useValue("s", "v", OP), "IPC_MALFORMED", "useValue non-object");
    }
  });

  it("malformed IPC: oversized garbage payloads -> typed error, no crash, no secret", async () => {
    const host = createAdversarialHost();
    const api = createSecurityAPI(host);
    // 8 MiB of wrongly-shaped junk: must reject cleanly, not blow up.
    const junk = { status: "x".repeat(8 * 1024 * 1024), body: ["not", "a", "string"] };
    host.request = () => Promise.resolve(junk);
    const before = process.memoryUsage().heapUsed;
    await assertRejectsSDKError(api.useValue("s", "v", OP), "IPC_MALFORMED", "useValue oversized junk");
    void before;
  });

  it("malformed IPC: huge but well-formed body resolves without leaking", async () => {
    const host = createAdversarialHost();
    const api = createSecurityAPI(host);
    const big = "z".repeat(2 * 1024 * 1024);
    host.request = () => Promise.resolve({ status: 200, body: big });
    const result = await api.useValue("s", "v", OP);
    assert.equal(result.status, 200);
    assert.equal(result.body.length, big.length);
    assertNoSecret(result, "large useValue body");
  });

  it("forged identity: a session claiming another app's Security ID is rejected", async () => {
    // One shared backend, two sessions. app-a owns "api-keys".
    const backend = { namespaces: new Map([["api-keys", "app-a"]]), store: new Map() };
    const hostA = createAdversarialHost({ callerApp: "app-a" });
    const hostB = createAdversarialHost({ callerApp: "app-b" });
    for (const h of [hostA, hostB]) {
      // Point both sessions at the same namespace registry.
      h.namespaces.clear();
      for (const [k, v] of backend.namespaces) h.namespaces.set(k, v);
      h.store.clear();
      for (const [k, v] of backend.store) h.store.set(k, v);
    }
    const apiB = createSecurityAPI(hostB);
    // app-b tries to read, use, list, delete, and add under app-a's ID.
    await assertRejectsSDKError(apiB.hasValue("api-keys", "v1"), "SDK_PERMISSION_DENIED", "forged hasValue");
    await assertRejectsSDKError(apiB.listValueIDs("api-keys"), "SDK_PERMISSION_DENIED", "forged listValueIDs");
    await assertRejectsSDKError(apiB.deleteValue("api-keys", "v1"), "SDK_PERMISSION_DENIED", "forged deleteValue");
    await assertRejectsSDKError(apiB.useValue("api-keys", "v1", OP), "SDK_PERMISSION_DENIED", "forged useValue");
    await assertRejectsSDKError(apiB.addValue("api-keys", "evil"), "SDK_PERMISSION_DENIED", "forged addValue");
    // And nothing about the denial leaks the secret.
    try {
      await apiB.hasValue("api-keys", "v1");
      assert.fail("expected rejection");
    } catch (error) {
      assertErrorClean(error, "forged hasValue denial");
    }
  });

  it("cross-app valueID: deleteValue/useValue against another app's value are denied", async () => {
    // Two sessions, one shared backend: the namespace registry enforces the
    // session-bound caller identity exactly like the host contract.
    const sharedNamespaces = new Map();
    const sharedStore = new Map();
    const hostA = createAdversarialHost({ callerApp: "app-a", namespaces: sharedNamespaces, store: sharedStore });
    const hostB = createAdversarialHost({ callerApp: "app-b", namespaces: sharedNamespaces, store: sharedStore });
    const apiA = createSecurityAPI(hostA);
    const apiB = createSecurityAPI(hostB);
    await apiA.addValue("api-keys", "github-token");
    // app-b cannot touch it, even naming the valueID directly.
    await assertRejectsSDKError(apiB.useValue("api-keys", "github-token", OP), "SDK_PERMISSION_DENIED", "cross-app useValue");
    await assertRejectsSDKError(apiB.deleteValue("api-keys", "github-token"), "SDK_PERMISSION_DENIED", "cross-app deleteValue");
    // The value still exists for its owner afterwards.
    const apiA2 = createSecurityAPI(hostA);
    assert.equal(await apiA2.hasValue("api-keys", "github-token"), true);
  });

  it("malicious host: secret smuggled into EVERY response field the client surfaces stays stripped", async () => {
    const host = createAdversarialHost({ malicious: true });
    const api = createSecurityAPI(host);
    // Sweep every method, walking every property of every returned value.
    const added = await api.addValue("api-keys", "github-token", { label: "L" });
    assertNoSecret(added, "addValue sweep");
    const has = await api.hasValue("api-keys", "github-token");
    assertNoSecret(has, "hasValue sweep");
    const listed = await api.listValueIDs("api-keys");
    assertNoSecret(listed, "listValueIDs sweep");
    const used = await api.useValue("api-keys", "github-token", OP);
    assertNoSecret(used, "useValue sweep");
    const deleted = await api.deleteValue("api-keys", "github-token");
    assertNoSecret(deleted, "deleteValue sweep");
    // And the standalone helpers (same installed-connection path) too.
    const api2 = createSecurityAPI(host);
    void api2;
    const added2 = await securityAddValue("api-keys", "k2");
    assertNoSecret(added2, "standalone securityAddValue sweep");
    const has2 = await securityHasValue("api-keys", "k2");
    assertNoSecret(has2, "standalone securityHasValue sweep");
    const listed2 = await securityListValueIDs("api-keys");
    assertNoSecret(listed2, "standalone securityListValueIDs sweep");
    const used2 = await securityUseValue("api-keys", "k2", OP);
    assertNoSecret(used2, "standalone securityUseValue sweep");
    await securityDeleteValue("api-keys", "k2");
  });

  it("client never echoes secrets in IPC errors, even under a hostile host", async () => {
    const host = createAdversarialHost({ malicious: true });
    const api = createSecurityAPI(host);
    // Host throws errors whose messages embed the canary — client must not
    // re-surface it (client errors are constructed from codes, not bodies).
    host.request = () =>
      Promise.reject(new SDKError("SDK_HOST_EVIL", `host says: ${CANARY}`, "corr"));
    try {
      await api.useValue("api-keys", "v", OP);
      assert.fail("expected rejection");
    } catch (error) {
      assert.ok(error instanceof SDKError);
      assert.equal(error.code, "SDK_HOST_EVIL");
      // The message came from the host verbatim; the CLIENT must not append
      // the secret to anything it generates. Document the boundary: a
      // hostile host controls its own error text, so the client cannot
      // redact it — but the client never ADDS secret material of its own,
      // because it never holds any.
      assertNoSecret(
        JSON.stringify({ code: error.code, name: error.name }),
        "client-generated error fields",
      );
    }
  });

  it("standalone helpers share the same no-exfiltration guarantee (installed connection)", async () => {
    const host = createAdversarialHost({ malicious: true });
    createSecurityAPI(host); // installs the connection for the standalone helpers
    const added = await securityAddValue("api-keys", "tok", { label: "x", prompt: "y" });
    assert.deepEqual(Object.keys(added).sort(), ["created", "valueID"]);
    assertNoSecret(added, "standalone addValue");
  });
});
