import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const pkg = JSON.parse(readFileSync(path.join(root, "package.json"), "utf8"));
const entry = path.join(root, "dist", "index.js");

function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

describe("standalone project", () => {
  it("entry point runs and prints a hello containing the package name", () => {
    const res = spawnSync(process.execPath, [entry], { encoding: "utf8" });
    assert.equal(res.status, 0, `dist/index.js exited ${res.status}: ${res.stderr}`);
    assert.match(res.stdout, new RegExp(escapeRegExp(pkg.name)));
  });

  it("greeting() reflects the package name and version", async () => {
    const mod = await import(entry);
    const expected = `Hello from ${pkg.name} v${pkg.version}!`;
    assert.equal(mod.greeting(), expected);
  });
});
