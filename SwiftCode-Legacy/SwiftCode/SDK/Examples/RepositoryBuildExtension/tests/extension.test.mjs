// Extension lifecycle tests — run with `node --test tests/` AFTER `npm run build`.
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
        getStatus() { throw new Error("getStatus must not run in lifecycle tests"); },
        getDiff() { throw new Error("getDiff must not run in lifecycle tests"); },
      },
      build: {
        run() { throw new Error("build.run must not run in lifecycle tests"); },
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

  it("activate registers all demonstration commands", async () => {
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
    await extension.deactivate();
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
});
