import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { pathToFileURL, fileURLToPath } from "node:url";
import path from "node:path";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const extensionUrl = pathToFileURL(path.join(root, "dist", "index.js")).href;
const { default: extension } = await import(extensionUrl);

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

  it("activate registers inspect-repository and run-build", async () => {
    const { context, registered } = makeContext();
    await extension.activate(context);
    assert.deepEqual(
      registered.map((c) => c.id),
      ["inspect-repository", "run-build"]
    );
    for (const command of registered) {
      assert.equal(typeof command.execute, "function");
    }
    await extension.deactivate();
  });

  it("deactivate disposes every registration", async () => {
    const { context, disposed } = makeContext();
    await extension.activate(context);
    await extension.deactivate();
    assert.deepEqual(disposed.sort(), ["inspect-repository", "run-build"]);
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

function makeLiveContext({ status, buildResult, buildEvents }) {
  const calls = { getStatus: 0, run: [], logged: [] };
  const registered = [];
  const context = {
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
    log: {
      info(message, fields) {
        calls.logged.push([message, fields]);
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
    assert.equal(result, status);
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
    assert.deepEqual(calls.run, [{ target: "" }]);
    assert.deepEqual(
      calls.logged.map(([message]) => message),
      ["Compiling…", "Build succeeded"]
    );
    assert.equal(result, buildResult);
    await extension.deactivate();
  });
});
