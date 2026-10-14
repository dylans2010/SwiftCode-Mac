// Snippet library tests for @swiftcode/sdk.
//
// (a) Every snippet's `code` TYPECHECKS against the real built package:
//     each code string is written to a temp .ts file that imports the real
//     package types via a symlinked `node_modules/@swiftcode/sdk`, and
//     `tsc --noEmit` runs over all of them under the same strict settings
//     as the package build. A snippet that calls an invented method fails
//     here — this is the "actually works" proof.
// (b) `searchSnippets` finds "virtualization" -> the sandbox snippet.
// (c) Every snippet's `capabilityId` is a real registry wire ID
//     (SwiftCode/SDK/Contracts/Capability/SDKCapability.swift).
// (d) `snippets.json` is in sync with the compiled `src/snippets.ts` and
//     carries the full executable `code` for every snippet.
//
// Run: `npm run build && npm test` (npm test = `node --test "tests/*.test.mjs"`).
import { describe, it, before, after } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, rmSync, symlinkSync, writeFileSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { pathToFileURL, fileURLToPath } from "node:url";
import path from "node:path";

const packageDir = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const distUrl = pathToFileURL(path.join(packageDir, "dist", "snippets.js")).href;
const { SNIPPETS, searchSnippets, getSnippet } = await import(distUrl);

/** Exact wire IDs from SDKCapabilityID (SwiftCode/SDK/Contracts/Capability/SDKCapability.swift). */
const REGISTRY_IDS = new Set([
  "project.read",
  "workspace.read",
  "workspace.write",
  "source-control.read",
  "source-control.write",
  "build.execute",
  "task.execute",
  "network.request",
  "ui.contribute",
  "credentials.use",
  "use.Security",
  "use.Security.keychain",
  "use.Security.audit",
  "use.Security.crypto",
  "use.Security.securePrompt",
  "use.Security.redaction",
  "use.Security.policy",
  "assist.invoke",
  "db.ExploreView",
  "ci.VisualWF",
  "sandbox.view",
  "virtualization.view",
  "deployConsole.view",
  "use.SwiftCodeModel",
  "terminal.sandbox",
  "simulator.view",
  "preview.live",
  "uibuilder.open",
  "symbols.browse",
  "docs.search",
  "dictionary.open",
  "deviceconnect.open",
]);

describe("snippet library shape", () => {
  it("has one snippet per capability with a real TS API, with unique ids and wire IDs", () => {
    assert.ok(SNIPPETS.length >= 26, `expected >= 26 snippets, got ${SNIPPETS.length}`);
    const ids = new Set();
    for (const snippet of SNIPPETS) {
      assert.match(snippet.id, /^[a-z][a-z0-9-]*$/, `bad snippet id ${snippet.id}`);
      assert.ok(!ids.has(snippet.id), `duplicate snippet id ${snippet.id}`);
      ids.add(snippet.id);
      assert.ok(snippet.title.trim().length > 0, `${snippet.id}: blank title`);
      assert.ok(snippet.description.trim().length > 0, `${snippet.id}: blank description`);
      assert.ok(
        REGISTRY_IDS.has(snippet.capabilityId),
        `${snippet.id}: capabilityId ${snippet.capabilityId} is not a registry wire ID`,
      );
      assert.ok(snippet.tags.length > 0, `${snippet.id}: no tags`);
      assert.ok(snippet.code.includes("@swiftcode/sdk"), `${snippet.id}: code does not import the real SDK`);
      assert.ok(
        snippet.code.includes("runExample"),
        `${snippet.id}: code must export an async runExample(context) entry point`,
      );
    }
  });

  it("covers the prioritized capabilities with the exact wire IDs", () => {
    const byCapability = new Map(SNIPPETS.map((s) => [s.capabilityId, s.id]));
    assert.equal(byCapability.get("sandbox.view"), "open-terminal");
    assert.equal(byCapability.get("virtualization.view"), "open-virtualization-console");
    assert.equal(byCapability.get("deployConsole.view"), "open-deployments-console");
    assert.equal(byCapability.get("db.ExploreView"), "open-database-explorer");
    assert.equal(byCapability.get("use.SwiftCodeModel"), "ask-cloud-model");
    assert.equal(byCapability.get("terminal.sandbox"), "run-sandboxed-command");
    assert.equal(byCapability.get("ci.VisualWF"), "open-ci-workflows");
    assert.ok(byCapability.has("source-control.read"), "missing source-control.read snippet");
    assert.ok(byCapability.has("build.execute"), "missing build.execute snippet");
  });
});

describe("searchSnippets / getSnippet", () => {
  it('finds "virtualization" -> the sandbox snippet', () => {
    const results = searchSnippets("virtualization");
    assert.ok(
      results.some((s) => s.id === "open-virtualization-console"),
      `expected open-virtualization-console in results, got ${results.map((s) => s.id).join(",")}`,
    );
  });

  it("is case-insensitive across title, description, tags, capabilityId, and code", () => {
    const upper = searchSnippets("VIRTUALIZATION").map((s) => s.id).sort();
    const lower = searchSnippets("virtualization").map((s) => s.id).sort();
    assert.deepEqual(upper, lower);
    assert.ok(searchSnippets("Sandbox.View").some((s) => s.id === "open-terminal"));
    assert.ok(searchSnippets("Virtualization.View").some((s) => s.id === "open-virtualization-console"));
    assert.ok(searchSnippets("DeployConsole.View").some((s) => s.id === "open-deployments-console"));
    assert.ok(searchSnippets("xcodebuild").some((s) => s.id === "run-project-build"));
  });

  it("returns all snippets for a blank query and none for gibberish", () => {
    assert.equal(searchSnippets("   ").length, SNIPPETS.length);
    assert.equal(searchSnippets("zzz-no-such-snippet-zzz").length, 0);
  });

  it("getSnippet returns the snippet by id and undefined for unknown ids", () => {
    assert.equal(getSnippet("open-virtualization-console")?.capabilityId, "virtualization.view");
    assert.equal(getSnippet("open-terminal")?.capabilityId, "sandbox.view");
    assert.equal(getSnippet("open-deployments-console")?.capabilityId, "deployConsole.view");
    assert.equal(getSnippet("does-not-exist"), undefined);
  });
});

describe("snippets.json manifest", () => {
  it("is in sync with the compiled snippets.ts (including executable code)", () => {
    const manifestPath = path.join(packageDir, "snippets.json");
    const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
    const expected = SNIPPETS.map((s) => ({
      id: s.id,
      title: s.title,
      description: s.description,
      capabilityId: s.capabilityId,
      tags: [...s.tags],
      code: s.code,
    }));
    assert.deepEqual(manifest, expected, "snippets.json is out of sync — run `npm run build:snippets`");
    for (const entry of manifest) {
      assert.deepEqual(
        Object.keys(entry).sort(),
        ["capabilityId", "code", "description", "id", "tags", "title"],
        `${entry.id}: manifest must carry all fields including executable code`,
      );
      assert.ok(typeof entry.code === "string" && entry.code.includes("runExample"), `${entry.id}: missing executable code`);
    }
  });
});

describe("snippet code typechecks against the real package", () => {
  let workDir;
  let snippetFiles = [];

  before(() => {
    // Temp workspace: each snippet's code becomes its own .ts file, and
    // `node_modules/@swiftcode/sdk` symlinks to this package so
    // `import ... from "@swiftcode/sdk"` resolves to the REAL built types.
    workDir = mkdtempSync(path.join(tmpdir(), "swiftcode-snippets-"));
    const nmDir = path.join(workDir, "node_modules", "@swiftcode", "sdk");
    mkdirSync(path.dirname(nmDir), { recursive: true });
    symlinkSync(packageDir, nmDir, "dir");
    for (const snippet of SNIPPETS) {
      const file = path.join(workDir, `${snippet.id}.ts`);
      writeFileSync(file, snippet.code, "utf8");
      snippetFiles.push({ id: snippet.id, file });
    }
  });

  after(() => {
    if (workDir !== undefined) rmSync(workDir, { recursive: true, force: true });
  });

  it("tsc --noEmit passes for every snippet file (per-snippet results below)", () => {
    const tscBin = path.join(packageDir, "node_modules", ".bin", "tsc");
    const args = [
      "--ignoreConfig",
      "--noEmit",
      "--strict",
      "--exactOptionalPropertyTypes",
      "--noUncheckedIndexedAccess",
      "--module",
      "nodenext",
      "--moduleResolution",
      "nodenext",
      "--target",
      "es2022",
      "--skipLibCheck",
      "--types",
      "node",
      ...snippetFiles.map((s) => s.file),
    ];
    let output = "";
    let exitCode = 0;
    try {
      output = execFileSync(tscBin, args, { cwd: packageDir, encoding: "utf8", stdio: "pipe" });
    } catch (error) {
      exitCode = error.status ?? 1;
      output = (error.stdout ?? "") + (error.stderr ?? "");
    }
    // Attribute errors per snippet file: `path/to/<id>.ts(line,col): error TS…`.
    const errorsById = new Map(snippetFiles.map((s) => [s.id, []]));
    for (const line of String(output).split("\n")) {
      for (const { id, file } of snippetFiles) {
        if (line.startsWith(file)) {
          errorsById.get(id).push(line.trim());
        }
      }
    }
    const failures = [];
    for (const { id } of snippetFiles) {
      const errors = errorsById.get(id);
      console.log(`tsc ${id}: ${errors.length === 0 ? "OK" : "FAIL"}`);
      if (errors.length > 0) failures.push(`${id}:\n  ${errors.join("\n  ")}`);
    }
    assert.equal(exitCode, 0, `tsc failed overall:\n${output}`);
    assert.deepEqual(failures, [], "snippet typecheck failures");
  });
});
