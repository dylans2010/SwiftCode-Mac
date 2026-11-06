// Extension lifecycle tests — run with `node --test tests/` AFTER `npm run build`.
// Loads the real compiled dist/index.js and exercises activate/deactivate
// through a recording test harness (test double at the unit-test boundary,
// per spec §12.5 — the extension code under test is the real compiled code).
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { pathToFileURL, fileURLToPath } from "node:url";
import path from "node:path";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const extensionUrl = pathToFileURL(path.join(root, "dist", "index.js")).href;
const { default: extension } = await import(extensionUrl);

// Minimal harness shaped like the host's SwiftCodeContext surface used here:
// commands.register records and returns a disposable; other surfaces throw
// so any accidental call to an unimplemented surface fails loudly.
function makeContext() {
  const disposed = [];
  const registered = [];
  return {
    disposed,
    registered,
    context: {
      commands: {
        register(command) {
          registered.push(command);
          return {
            dispose() {
              disposed.push(command.id);
            },
          };
        },
      },
      sourceControl: {
        getStatus() {
          throw new Error("getStatus must not run in lifecycle tests");
        },
      },
      build: {
        run() {
          throw new Error("build.run must not run in lifecycle tests");
        },
      },
      log: { info() {} },
    },
  };
}

describe("extension", () => {
  it("default export carries id, activate, deactivate", () => {
    assert.equal(typeof extension.id, "string");
    assert.ok(extension.id.length > 0);
    assert.equal(typeof extension.activate, "function");
    assert.equal(typeof extension.deactivate, "function");
  });

  it("activate registers all seven demonstration commands", async () => {
    const { context, registered } = makeContext();
    await extension.activate(context);
    assert.deepEqual(
      registered.map((c) => c.id),
      [
        "inspect-repository",
        "run-build",
        "inspect-project",
        "terminal-command",
        "cloud-model",
        "security-vault",
        "open-docs",
      ]
    );
    for (const command of registered) {
      assert.equal(typeof command.execute, "function");
    }
    await extension.deactivate(); // leave a clean slate for other tests
  });

  it("deactivate disposes every registration", async () => {
    const { context, disposed } = makeContext();
    await extension.activate(context);
    await extension.deactivate();
    assert.deepEqual(
      disposed.sort(),
      [
        "cloud-model",
        "inspect-project",
        "inspect-repository",
        "open-docs",
        "run-build",
        "security-vault",
        "terminal-command",
      ]
    );
  });

  it("a partial activation failure unwinds registrations and rethrows", async () => {
    const first = makeContext();
    const { context } = first;
    let calls = 0;
    const failing = {
      ...context,
      commands: {
        register(command) {
          calls += 1;
          if (calls === 2) throw new Error("registration failed");
          return context.commands.register(command);
        },
      },
    };
    await assert.rejects(() => extension.activate(failing), /registration failed/);
    assert.deepEqual(first.disposed, ["inspect-repository"]);
  });
});

// Working harness for the command handlers: records every call the handlers
// make against the host API surface, so the tests prove the handlers use the
// real contract (method names, payload shapes, streaming iteration).
function makeLiveContext({
  status,
  buildResult,
  buildEvents,
  projectInfo = null,
  projectError = null,
  cloudResponse = "Summary of the extension architecture.",
  securityValues = [],
  terminalResult = { stdout: "git version 2.43.0\n", stderr: "", exitCode: 0 },
}) {
  const calls = {
    getStatus: 0,
    run: [],
    logged: [],
    warned: [],
    complete: [],
    getCurrent: 0,
    openView: [],
    listValueIDs: [],
    runTerminal: [],
  };
  const registered = [];
  const context = {
    extension: { id: "com.example.test" },
    commands: {
      register(command) {
        registered.push(command);
        return { dispose() {} };
      },
    },
    sourceControl: {
      async getStatus() {
        calls.getStatus += 1;
        return status;
      },
    },
    build: {
      async run(request) {
        calls.run.push(request);
        const events = (async function* () {
          for (const event of buildEvents) yield event;
        })();
        return {
          id: "handle-1",
          output: events,
          async wait() {
            return buildResult;
          },
          async cancel() {},
        };
      },
    },
    project: {
      async getCurrent() {
        calls.getCurrent += 1;
        if (projectError !== null) throw projectError;
        return projectInfo;
      },
    },
    cloudModel: {
      async complete(request) {
        calls.complete.push(request);
        return cloudResponse;
      },
    },
    terminalSandbox: {
      async run(request) {
        calls.runTerminal.push(request);
        return terminalResult;
      },
    },
    ui: {
      async openView(viewId) {
        calls.openView.push(viewId);
      },
    },
    security: {
      async listValueIDs(securityID) {
        calls.listValueIDs.push(securityID);
        return securityValues;
      },
    },
    log: {
      info(message, fields) {
        calls.logged.push([message, fields]);
      },
      warn(message, fields) {
        calls.warned.push([message, fields]);
      },
    },
  };
  return { context, registered, calls };
}

describe("command handlers", () => {
  it("inspect-repository returns the host status unchanged and logs isRepository", async () => {
    const status = {
      isRepository: true,
      branchName: "main",
      ahead: 0,
      behind: 0,
      stagedCount: 1,
      unstagedCount: 0,
      untrackedCount: 0,
      files: [],
    };
    const { context, registered, calls } = makeLiveContext({
      status,
      buildResult: null,
      buildEvents: [],
    });
    await extension.activate(context);
    const command = registered.find((c) => c.id === "inspect-repository");
    const result = await command.execute();
    assert.equal(calls.getStatus, 1);
    assert.equal(result, status); // no fabrication: the host object is returned as-is
    assert.deepEqual(calls.logged, [["Repository status retrieved", { isRepository: true }]]);
    await extension.deactivate();
  });

  it("run-build uses host-resolved default target, streams output, returns wait()", async () => {
    const buildResult = {
      status: "succeeded",
      durationSeconds: 1.2,
      errorCount: 0,
      warningCount: 0,
      diagnostics: [],
      correlationId: "corr-1",
    };
    const buildEvents = [
      { kind: "stdout", text: "Compiling…", timestamp: 1 },
      { kind: "status", text: "Build succeeded", timestamp: 2 },
    ];
    const { context, registered, calls } = makeLiveContext({
      status: null,
      buildResult,
      buildEvents,
    });
    await extension.activate(context);
    const command = registered.find((c) => c.id === "run-build");
    const result = await command.execute();
    // Empty target = host resolves the default scheme of the open project.
    assert.deepEqual(calls.run, [{ target: "" }]);
    assert.deepEqual(
      calls.logged.map(([message]) => message),
      ["Compiling…", "Build succeeded"]
    );
    assert.equal(result, buildResult);
    await extension.deactivate();
  });

  it("inspect-project returns the host project unchanged and logs hasProject", async () => {
    const projectInfo = {
      name: "Example",
      path: "/Users/example/Example",
      bundleIdentifier: "com.example.Example",
    };
    const { context, registered, calls } = makeLiveContext({
      status: null,
      buildResult: null,
      buildEvents: [],
      projectInfo,
    });
    await extension.activate(context);
    const command = registered.find((c) => c.id === "inspect-project");
    const result = await command.execute();
    assert.equal(calls.getCurrent, 1);
    assert.equal(result, projectInfo); // no fabrication: the host object is returned as-is
    assert.deepEqual(calls.logged, [["Project metadata requested", { hasProject: true }]]);
    await extension.deactivate();
  });

  it("inspect-project returns null and warns when the host rejects getCurrent", async () => {
    const { context, registered, calls } = makeLiveContext({
      status: null,
      buildResult: null,
      buildEvents: [],
      projectError: new Error("Unknown method: project.getCurrent"),
    });
    await extension.activate(context);
    const command = registered.find((c) => c.id === "inspect-project");
    const result = await command.execute();
    assert.equal(calls.getCurrent, 1);
    assert.equal(result, null);
    assert.equal(calls.warned.length, 1);
    assert.equal(calls.warned[0][0], "Project metadata request failed or unhandled by host");
    await extension.deactivate();
  });

  it("terminal-command runs git --version through the sandbox and returns the result", async () => {
    const { context, registered, calls } = makeLiveContext({
      status: null,
      buildResult: null,
      buildEvents: [],
    });
    await extension.activate(context);
    const command = registered.find((c) => c.id === "terminal-command");
    const result = await command.execute();
    assert.deepEqual(calls.runTerminal, [{ command: "git", args: ["--version"] }]);
    assert.deepEqual(result, { stdout: "git version 2.43.0\n", stderr: "", exitCode: 0 });
    assert.deepEqual(calls.logged, [
      ["Terminal sandbox command completed", { exitCode: 0, stdout: "git version 2.43.0" }],
    ]);
    await extension.deactivate();
  });

  it("cloud-model completes with the fixed prompt and returns the response", async () => {
    const { context, registered, calls } = makeLiveContext({
      status: null,
      buildResult: null,
      buildEvents: [],
    });
    await extension.activate(context);
    const command = registered.find((c) => c.id === "cloud-model");
    const result = await command.execute();
    assert.deepEqual(calls.complete, [
      {
        prompt: "Summarize the architecture of a SwiftCode extension.",
        systemPrompt: "You are a helpful coding assistant.",
      },
    ]);
    assert.deepEqual(result, { response: "Summary of the extension architecture." });
    assert.deepEqual(calls.logged, [
      ["Cloud model completion received", { responseLength: "Summary of the extension architecture.".length }],
    ]);
    await extension.deactivate();
  });

  it("security-vault lists secret IDs under the extension id and returns them", async () => {
    const { context, registered, calls } = makeLiveContext({
      status: null,
      buildResult: null,
      buildEvents: [],
      securityValues: ["api-key", "oauth-token"],
    });
    await extension.activate(context);
    const command = registered.find((c) => c.id === "security-vault");
    const result = await command.execute();
    assert.deepEqual(calls.listValueIDs, ["com.example.test"]);
    assert.deepEqual(result, { securityID: "com.example.test", values: ["api-key", "oauth-token"] });
    assert.deepEqual(calls.logged, [
      ["Security vault value IDs retrieved", { securityID: "com.example.test", count: 2 }],
    ]);
    await extension.deactivate();
  });

  it("open-docs opens the docs.search view and reports success", async () => {
    const { context, registered, calls } = makeLiveContext({
      status: null,
      buildResult: null,
      buildEvents: [],
    });
    await extension.activate(context);
    const command = registered.find((c) => c.id === "open-docs");
    const result = await command.execute();
    assert.deepEqual(calls.openView, ["docs.search"]);
    assert.deepEqual(result, { success: true });
    // open-docs logs with no fields, so compare messages only (as run-build does).
    assert.deepEqual(
      calls.logged.map(([message]) => message),
      ["Documentation browser opened."]
    );
    await extension.deactivate();
  });
});
