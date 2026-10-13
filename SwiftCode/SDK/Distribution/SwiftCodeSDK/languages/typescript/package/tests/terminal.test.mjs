// Terminal sandbox contract tests for @swiftcode/sdk (Docs/Intro-to-SDK.md §19.1, §19.2).
//
// Loads the real compiled dist/index.js and builds the real context via
// createContext over a scripted fake HostConnection. The tests assert the
// EXACT wire method and payload `context.terminalSandbox.run()` produces,
// the client-side validation of the host's sandboxed-command rule (bare
// allow-listed name or absolute path — never shell), typed error
// propagation, and malformed-result detection.
//
// The client-side checks are an early, friendly failure only: the Swift
// host (`SDKSandboxedTerminal`) re-validates everything. No request is ever
// sent for an invalid call.
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
 * requests are recorded for exact wire assertions.
 */
function createFakeHost(handlers = {}) {
  const requests = [];
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

const RESULT = {
  stdout: "On branch main\n",
  stderr: "",
  exitCode: 0,
  stdoutTruncated: false,
  stderrTruncated: false,
  stdoutTotalBytes: 14,
  stderrTotalBytes: 0,
  byteLimit: 262144,
};

/** Asserts a call throws SDKError/INVALID_ARGUMENT and sends nothing. */
async function assertClientRejected(promise, host, label) {
  await assert.rejects(promise, (error) => {
    assert.ok(error instanceof SDKError, `${label}: expected SDKError, got ${error}`);
    assert.equal(error.code, "INVALID_ARGUMENT", `${label}: wrong code ${error.code}`);
    return true;
  });
  assert.equal(host.requests.length, 0, `${label}: no request must be sent`);
}

describe("terminalSandbox wire contract", () => {
  it('run({command: "git", args: ["status"]}) sends terminalSandbox.run with the exact payload', async () => {
    const host = createFakeHost({ "terminalSandbox.run": () => RESULT });
    const { context } = createContext(host, EXTENSION);
    const result = await context.terminalSandbox.run({ command: "git", args: ["status"] });
    assert.deepEqual(result, RESULT);
    const req = lastRequest(host);
    assert.equal(req.method, "terminalSandbox.run");
    assert.deepEqual(req.payload, { command: "git", args: ["status"] });
  });

  it("omitted args default to [] and optional fields pass through verbatim", async () => {
    const host = createFakeHost({ "terminalSandbox.run": () => RESULT });
    const { context } = createContext(host, EXTENSION);
    await context.terminalSandbox.run({
      command: "/usr/bin/git",
      workingDirectory: "subdir",
      timeout: 10,
    });
    assert.deepEqual(lastRequest(host).payload, {
      command: "/usr/bin/git",
      args: [],
      workingDirectory: "subdir",
      timeout: 10,
    });
  });

  it("a host PERMISSION_DENIED rejection propagates as a typed SDKError", async () => {
    const host = createFakeHost({
      "terminalSandbox.run": () => {
        throw new SDKError("PERMISSION_DENIED", "Grant required.", "fake-req-0");
      },
    });
    const { context } = createContext(host, EXTENSION);
    await assert.rejects(
      context.terminalSandbox.run({ command: "git" }),
      (error) => error instanceof SDKError && error.code === "PERMISSION_DENIED",
    );
  });

  it("a host result missing stdout/stderr/exitCode is IPC_MALFORMED", async () => {
    const host = createFakeHost({ "terminalSandbox.run": () => ({ stdout: "x" }) });
    const { context } = createContext(host, EXTENSION);
    await assert.rejects(
      context.terminalSandbox.run({ command: "git" }),
      (error) => error instanceof SDKError && error.code === "IPC_MALFORMED",
    );
  });
});

describe("terminalSandbox client-side validation (no request sent)", () => {
  it("rejects an empty command", async () => {
    const host = createFakeHost({ "terminalSandbox.run": () => RESULT });
    const { context } = createContext(host, EXTENSION);
    await assertClientRejected(context.terminalSandbox.run({ command: "" }), host, "empty command");
  });

  it("rejects a non-string command", async () => {
    const host = createFakeHost({ "terminalSandbox.run": () => RESULT });
    const { context } = createContext(host, EXTENSION);
    await assertClientRejected(
      context.terminalSandbox.run({ command: 42 }),
      host,
      "non-string command",
    );
  });

  it("rejects shell snippets: semicolons, pipes, $(), backticks, &&", async () => {
    const host = createFakeHost({ "terminalSandbox.run": () => RESULT });
    const { context } = createContext(host, EXTENSION);
    for (const snippet of [
      "git; rm -rf /",
      "ls | grep x",
      "echo $(whoami)",
      "echo `whoami`",
      "git && git status",
      "git status > /tmp/out",
    ]) {
      await assertClientRejected(
        context.terminalSandbox.run({ command: snippet }),
        host,
        `shell snippet ${JSON.stringify(snippet)}`,
      );
    }
  });

  it("rejects commands with whitespace and relative paths", async () => {
    const host = createFakeHost({ "terminalSandbox.run": () => RESULT });
    const { context } = createContext(host, EXTENSION);
    for (const bad of ["git status", " bin/git", "bin/git", "../bin/git", "~/bin/git"]) {
      await assertClientRejected(
        context.terminalSandbox.run({ command: bad }),
        host,
        `bad command ${JSON.stringify(bad)}`,
      );
    }
  });

  it("accepts bare names with dots/dashes/underscores and absolute paths", async () => {
    const host = createFakeHost({ "terminalSandbox.run": () => RESULT });
    const { context } = createContext(host, EXTENSION);
    for (const good of ["git", "python3", "xcode-build_2.0", "/usr/bin/git", "/opt/homebrew/bin/node"]) {
      await context.terminalSandbox.run({ command: good });
    }
    assert.equal(host.requests.length, 5);
  });

  it("rejects non-array args and non-string/NUL/oversized args", async () => {
    const host = createFakeHost({ "terminalSandbox.run": () => RESULT });
    const { context } = createContext(host, EXTENSION);
    await assertClientRejected(
      context.terminalSandbox.run({ command: "git", args: "status" }),
      host,
      "non-array args",
    );
    await assertClientRejected(
      context.terminalSandbox.run({ command: "git", args: [42] }),
      host,
      "non-string arg",
    );
    await assertClientRejected(
      context.terminalSandbox.run({ command: "git", args: ["a\0b"] }),
      host,
      "NUL arg",
    );
    await assertClientRejected(
      context.terminalSandbox.run({ command: "git", args: ["x".repeat(8193)] }),
      host,
      "oversized arg",
    );
    await assertClientRejected(
      context.terminalSandbox.run({ command: "git", args: new Array(257).fill("x") }),
      host,
      "too many args",
    );
  });

  it("rejects an empty workingDirectory", async () => {
    const host = createFakeHost({ "terminalSandbox.run": () => RESULT });
    const { context } = createContext(host, EXTENSION);
    await assertClientRejected(
      context.terminalSandbox.run({ command: "git", workingDirectory: "" }),
      host,
      "empty workingDirectory",
    );
  });

  it("rejects non-positive/non-finite/non-number timeouts", async () => {
    const host = createFakeHost({ "terminalSandbox.run": () => RESULT });
    const { context } = createContext(host, EXTENSION);
    for (const bad of [0, -5, Number.NaN, Number.POSITIVE_INFINITY, "10"]) {
      await assertClientRejected(
        context.terminalSandbox.run({ command: "git", timeout: bad }),
        host,
        `bad timeout ${String(bad)}`,
      );
    }
  });
});
