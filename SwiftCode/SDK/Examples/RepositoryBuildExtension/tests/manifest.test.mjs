// Manifest contract tests — run with `node --test tests/` AFTER `npm run build`.
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const manifestPath = path.join(root, "swiftcode.json");
const schemaPath = path.join(root, "schemas", "swiftcode-extension-v1.schema.json");

const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
const schema = JSON.parse(await readFile(schemaPath, "utf8"));
const knownCapabilityIds = new Set(schema.properties.capabilities.items.properties.id.enum);

describe("manifest", () => {
  it("declares expected demonstration capabilities", () => {
    const ids = manifest.capabilities.map((c) => c.id);
    assert.deepEqual(ids, [
      "source-control.read",
      "build.execute",
      "project.read",
      "workspace.read",
      "credentials.use",
      "network.request",
    ]);
  });

  it("does not request Assist", () => {
    assert.equal(manifest.assist.requested, false);
  });

  it("contributes demonstration commands", () => {
    const ids = manifest.contributes.commands.map((c) => c.id);
    assert.deepEqual(ids, [
      "inspect-repository",
      "run-build",
      "inspect-project",
      "terminal-command",
      "cloud-model",
      "security-vault",
      "open-docs",
    ]);
  });

  it("every capability id is a real, grantable registry id from the shipped schema", () => {
    for (const cap of manifest.capabilities) {
      assert.ok(knownCapabilityIds.has(cap.id), `unknown capability id: ${cap.id}`);
      assert.notEqual(cap.id, "assist.invoke");
    }
  });

  it("entrypoint resolves to a file that exists (after npm run build)", () => {
    assert.equal(manifest.runtime.entrypoint, "dist/index.js");
    assert.ok(
      existsSync(path.join(root, manifest.runtime.entrypoint)),
      `entrypoint missing: ${manifest.runtime.entrypoint} — run npm run build first`
    );
  });

  it("id, name, version are consistent between manifest and package.json", async () => {
    const pkg = JSON.parse(await readFile(path.join(root, "package.json"), "utf8"));
    assert.equal(manifest.version, pkg.version);
    assert.ok(/^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z][A-Za-z0-9-]*)+$/.test(manifest.id));
  });
});
