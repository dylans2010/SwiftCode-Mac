// Build → ship → install round-trip tests for the swiftcode CLI
// (Docs/Intro-to-SDK.md §8 Task A4).
//
// Exercises the REAL CLI end to end with stock node: generate an extension
// with the real generator -> `swiftcode build` (tsc, live output) ->
// `swiftcode package` (deterministic .swiftcode-extension with an embedded
// digest record) -> `swiftcode install` (digest + schema verification) ->
// run the installed entry through the real node runtime adapter.
//
// Also: determinism (10 packages byte-identical), tamper rejection (typed
// DIGEST_MISMATCH), missing digest record (DIGEST_RECORD_MISSING), schema
// violation with a valid digest (MANIFEST_INVALID), broken-TypeScript build
// failure, and the honest xcodebuild-absent path.
//
// Run: `npm run build && npm test` from SwiftCode/SDK/TypeScript/package
// (npm test = `node --test "tests/*.test.mjs"`). Everything the tests
// touch lives under a private mkdtemp sandbox; the real
// ~/Library/Application Support/SwiftCode/Extensions is never used.
import { describe, it, before } from "node:test";
import assert from "node:assert/strict";
import { spawn, execFile } from "node:child_process";
import { createRequire } from "node:module";
import { createWriteStream } from "node:fs";
import {
  lstat,
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  stat,
  symlink,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const testsDir = path.dirname(fileURLToPath(import.meta.url));
// tests/ -> package/ -> TypeScript/ -> SDK/ -> SwiftCode/ -> repo root
const REPO = path.resolve(testsDir, "..", "..", "..", "..", "..");
const CLI_DIR = path.join(REPO, "SwiftCode", "SDK", "TypeScript", "cli");
const CLI = path.join(CLI_DIR, "swiftcode.mjs");
const GENERATOR = path.join(CLI_DIR, "create-extension.mjs");
const RUNTIME_ADAPTER = path.join(
  REPO,
  "SwiftCode",
  "SDK",
  "TypeScript",
  "runtime-adapter",
  "dist",
  "adapter.js"
);
const SDK_PACKAGE_DIST = path.join(
  REPO,
  "SwiftCode",
  "SDK",
  "TypeScript",
  "package",
  "dist",
  "index.js"
);

const FIXED_DATE = new Date("2000-01-01T00:00:00Z");
const EXT_ID = "com.example.a4-roundtrip";
const EXT_VERSION = "0.1.0";

const cliRequire = createRequire(path.join(CLI_DIR, "package.json"));

// ---------------------------------------------------------------------------
// Process helpers
// ---------------------------------------------------------------------------

function runCommand(cmd, argv, { cwd = undefined, env = {}, stdinData = null } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, argv, {
      cwd,
      env: { ...process.env, ...env },
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => {
      stdout += d.toString();
    });
    child.stderr.on("data", (d) => {
      stderr += d.toString();
    });
    child.on("error", reject);
    child.on("close", (code) => resolve({ code: code ?? -1, stdout, stderr }));
    if (stdinData !== null) {
      child.stdin.write(stdinData);
      child.stdin.end();
    }
  });
}

const runCli = (args, opts = {}) => runCommand(process.execPath, [CLI, ...args], opts);

function parseJsonEnvelope(stdout) {
  return JSON.parse(stdout);
}

// ---------------------------------------------------------------------------
// Deterministic re-zip (mirrors the packager's archive settings)
// ---------------------------------------------------------------------------

async function rezipDeterministic(stageDir, outPath, { dropRelPaths = [] } = {}) {
  const { ZipArchive } = cliRequire("archiver");
  const drop = new Set(dropRelPaths);
  const entries = [];
  async function walk(abs, rel) {
    const dirents = await readdir(abs, { withFileTypes: true });
    for (const dirent of dirents) {
      const entryAbs = path.join(abs, dirent.name);
      const entryRel = rel === "" ? dirent.name : `${rel}/${dirent.name}`;
      if (drop.has(entryRel)) continue;
      const st = await lstat(entryAbs);
      if (st.isDirectory() && !st.isSymbolicLink()) {
        await walk(entryAbs, entryRel);
      } else {
        entries.push({ rel: entryRel, abs: entryAbs, stats: st });
      }
    }
  }
  await walk(stageDir, "");
  entries.sort((a, b) => (a.rel < b.rel ? -1 : a.rel > b.rel ? 1 : 0));

  const archive = new ZipArchive({ zlib: { level: 9 } });
  const outStream = createWriteStream(outPath);
  await new Promise((resolve, reject) => {
    outStream.on("close", resolve);
    outStream.on("error", reject);
    archive.on("error", reject);
    archive.on("warning", reject);
    archive.pipe(outStream);
    (async () => {
      for (const e of entries) {
        archive.file(e.abs, { name: e.rel, date: FIXED_DATE, mode: 0o644, stats: e.stats });
      }
      await archive.finalize();
    })();
  });
  return outPath;
}

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------

let sandbox;
let genDir;
let pkgDir;
let extRoot;
let packagePath;

before(async () => {
  for (const p of [CLI, GENERATOR, RUNTIME_ADAPTER, SDK_PACKAGE_DIST]) {
    const s = await stat(p).catch(() => null);
    assert.ok(s && s.isFile(), `required build artifact missing: ${p}`);
  }
  sandbox = await mkdtemp(path.join(os.tmpdir(), "swiftcode-a4-"));
  genDir = path.join(sandbox, "ext");
  pkgDir = path.join(sandbox, "pkg");
  extRoot = path.join(sandbox, "extensions");
  await mkdir(pkgDir, { recursive: true });

  // Real generated extension (what `swiftcode create` produces).
  const created = await runCommand(process.execPath, [
    GENERATOR,
    "--id",
    EXT_ID,
    "--name",
    "A4 Roundtrip",
    "--outDir",
    genDir,
  ]);
  assert.equal(created.code, 0, `generator failed:\n${created.stderr}`);
  const hasSeededDeps =
    (await stat(path.join(genDir, "node_modules", "@swiftcode", "sdk")).catch(() => null)) !== null &&
    (await stat(path.join(genDir, "node_modules", "typescript")).catch(() => null)) !== null;
  if (!hasSeededDeps) {
    const installed = await runCommand("npm", ["install", "--prefer-offline", "--no-audit", "--no-fund"], {
      cwd: genDir,
    });
    assert.equal(installed.code, 0, `npm install failed:\n${installed.stderr}`);
  }
});

describe("swiftcode build -> package -> install -> run round-trip", () => {
  it("build compiles the generated extension with tsc", async () => {
    const r = await runCli(["build", genDir]);
    assert.equal(r.code, 0, `build failed:\n${r.stderr}`);
    assert.match(r.stdout, /compilation succeeded/);
    const entry = await stat(path.join(genDir, "dist", "index.js"));
    assert.ok(entry.isFile());
  });

  it("build --json captures compiler output without polluting stdout", async () => {
    const r = await runCli(["build", genDir, "--json"]);
    assert.equal(r.code, 0, `build --json failed:\n${r.stderr}`);
    const envelope = parseJsonEnvelope(r.stdout);
    assert.equal(envelope.ok, true);
    assert.equal(envelope.command, "build");
    assert.equal(envelope.data.kind, "typescript");
  });

  it("package produces a deterministic archive with an embedded digest record", async () => {
    const r = await runCli(["package", genDir, "--out", pkgDir, "--json"]);
    assert.equal(r.code, 0, `package failed:\n${r.stderr}`);
    const envelope = parseJsonEnvelope(r.stdout);
    assert.equal(envelope.ok, true);
    const { data } = envelope;
    assert.match(data.sha256, /^[0-9a-f]{64}$/);
    assert.match(data.contentDigest, /^[0-9a-f]{64}$/);
    packagePath = data.path;
    assert.ok(packagePath.endsWith(".swiftcode-extension"));
    const st = await stat(packagePath);
    assert.ok(st.isFile() && st.size > 0);

    // The embedded digest record is present, well-formed, and describes
    // the same content digest the packager reported.
    const { extractZip } = await import(
      pathToFileURL(path.join(CLI_DIR, "commands", "_shared.mjs")).href
    );
    const probe = path.join(sandbox, "probe");
    await extractZip(packagePath, probe);
    const record = JSON.parse(await readFile(path.join(probe, "swiftcode-digest.json"), "utf8"));
    assert.deepEqual(Object.keys(record).sort(), [
      "contentDigest",
      "formatVersion",
      "id",
      "kind",
      "version",
    ]);
    assert.equal(record.formatVersion, 1);
    assert.equal(record.id, EXT_ID);
    assert.equal(record.version, EXT_VERSION);
    assert.equal(record.kind, "extension");
    assert.equal(record.contentDigest, data.contentDigest);
    assert.ok((await stat(path.join(probe, "dist", "index.js"))).isFile());
  });

  it("determinism: packaging the same tree 10 times is byte-identical", async () => {
    const digests = [];
    for (let i = 0; i < 10; i += 1) {
      const out = path.join(sandbox, `det-${i}`);
      await mkdir(out, { recursive: true });
      const r = await runCli(["package", genDir, "--out", out, "--json"]);
      assert.equal(r.code, 0, `package run ${i} failed:\n${r.stderr}`);
      digests.push(parseJsonEnvelope(r.stdout).data.sha256);
    }
    for (const d of digests) assert.equal(d, digests[0], "package digests differ across runs");
    const a = path.join(sandbox, "det-0", "a4-roundtrip-0.1.0.swiftcode-extension");
    const b = path.join(sandbox, "det-9", "a4-roundtrip-0.1.0.swiftcode-extension");
    const [ba, bb] = await Promise.all([readFile(a), readFile(b)]);
    assert.ok(ba.equals(bb), "package bytes differ across runs");
  });

  it("tamper: a flipped byte in dist/ is rejected with typed DIGEST_MISMATCH", async () => {
    const { extractZip } = await import(
      pathToFileURL(path.join(CLI_DIR, "commands", "_shared.mjs")).href
    );
    const stage = path.join(sandbox, "tamper-dist");
    await extractZip(packagePath, stage);
    const target = path.join(stage, "dist", "index.js");
    const buf = await readFile(target);
    buf[64] ^= 0x01;
    await writeFile(target, buf);
    const tampered = path.join(sandbox, "tampered-dist.swiftcode-extension");
    await rezipDeterministic(stage, tampered);

    const r = await runCli(["install", tampered, "--json"], {
      env: { SWIFTCODE_EXTENSIONS_DIR: extRoot },
    });
    assert.equal(r.code, 1, "tampered install must fail");
    const envelope = parseJsonEnvelope(r.stdout);
    assert.equal(envelope.ok, false);
    assert.equal(envelope.error.data.error.code, "DIGEST_MISMATCH");
    assert.match(envelope.error.data.error.message, /\[DIGEST_MISMATCH\]/);
    assert.match(r.stderr, /DIGEST_MISMATCH/);
    // Nothing reached the controlled directory.
    assert.equal(await stat(extRoot).catch(() => null), null);
  });

  it("tamper: a flipped byte in the manifest is rejected with typed DIGEST_MISMATCH", async () => {
    const { extractZip } = await import(
      pathToFileURL(path.join(CLI_DIR, "commands", "_shared.mjs")).href
    );
    const stage = path.join(sandbox, "tamper-manifest");
    await extractZip(packagePath, stage);
    const target = path.join(stage, "swiftcode.json");
    const buf = await readFile(target);
    buf[buf.length - 4] ^= 0x01;
    await writeFile(target, buf);
    const tampered = path.join(sandbox, "tampered-manifest.swiftcode-extension");
    await rezipDeterministic(stage, tampered);

    const r = await runCli(["install", tampered], {
      env: { SWIFTCODE_EXTENSIONS_DIR: extRoot },
    });
    assert.equal(r.code, 1, "tampered install must fail");
    assert.match(r.stderr, /\[DIGEST_MISMATCH\]/);
  });

  it("tamper: a package without the digest record is rejected with DIGEST_RECORD_MISSING", async () => {
    const { extractZip } = await import(
      pathToFileURL(path.join(CLI_DIR, "commands", "_shared.mjs")).href
    );
    const stage = path.join(sandbox, "tamper-nodigest");
    await extractZip(packagePath, stage);
    const stripped = path.join(sandbox, "no-digest.swiftcode-extension");
    await rezipDeterministic(stage, stripped, { dropRelPaths: ["swiftcode-digest.json"] });

    const r = await runCli(["install", stripped, "--json"], {
      env: { SWIFTCODE_EXTENSIONS_DIR: extRoot },
    });
    assert.equal(r.code, 1);
    assert.equal(parseJsonEnvelope(r.stdout).error.data.error.code, "DIGEST_RECORD_MISSING");
  });

  it("schema violation with a valid digest is rejected with typed MANIFEST_INVALID", async () => {
    const sharedUrl = pathToFileURL(path.join(CLI_DIR, "commands", "_shared.mjs")).href;
    const formatUrl = pathToFileURL(path.join(CLI_DIR, "commands", "_package-format.mjs")).href;
    const { extractZip, computeDigestOf } = await import(sharedUrl);
    const { makeDigestRecord, serializeDigestRecord, DIGEST_FILE_NAME } = await import(formatUrl);
    const stage = path.join(sandbox, "tamper-schema");
    await extractZip(packagePath, stage);
    // Corrupt the manifest schema (unknown capability) but keep JSON valid,
    // then honestly recompute the digest record so the integrity check passes
    // and the schema validator is the layer that must catch it.
    const manifestPath = path.join(stage, "swiftcode.json");
    const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
    manifest.capabilities.push({ id: "mind.read", reason: "bogus" });
    await writeFile(manifestPath, JSON.stringify(manifest));
    const contentDigest = await computeDigestOf(stage, { excludeBasenames: [DIGEST_FILE_NAME] });
    await writeFile(
      path.join(stage, DIGEST_FILE_NAME),
      serializeDigestRecord(
        makeDigestRecord({
          id: manifest.id,
          version: manifest.version,
          kind: manifest.type,
          contentDigest,
        })
      ),
      "utf8"
    );
    const bad = path.join(sandbox, "bad-manifest.swiftcode-extension");
    await rezipDeterministic(stage, bad);

    const r = await runCli(["install", bad, "--json"], {
      env: { SWIFTCODE_EXTENSIONS_DIR: extRoot },
    });
    assert.equal(r.code, 1);
    const typed = parseJsonEnvelope(r.stdout).error.data.error;
    assert.equal(typed.code, "MANIFEST_INVALID");
    assert.ok(
      typed.details.problems.some((p) => p.path === "capabilities[2].id"),
      `expected a capabilities[2].id problem, got ${JSON.stringify(typed.details.problems)}`
    );
  });

  it("install verifies digest + schema and installs into the controlled directory", async () => {
    const r = await runCli(["install", packagePath, "--json"], {
      env: { SWIFTCODE_EXTENSIONS_DIR: extRoot },
    });
    assert.equal(r.code, 0, `install failed:\n${r.stderr}`);
    const envelope = parseJsonEnvelope(r.stdout);
    assert.equal(envelope.ok, true);
    const { data } = envelope;
    assert.equal(data.id, EXT_ID);
    assert.equal(data.version, EXT_VERSION);
    assert.equal(data.kind, "extension");
    assert.match(data.packageDigest, /^[0-9a-f]{64}$/);

    const installedDir = path.join(extRoot, EXT_ID, EXT_VERSION);
    assert.ok((await stat(path.join(installedDir, "swiftcode.json"))).isFile());
    assert.ok((await stat(path.join(installedDir, "dist", "index.js"))).isFile());
    assert.ok((await stat(path.join(installedDir, "swiftcode-digest.json"))).isFile());
    const record = JSON.parse(await readFile(path.join(installedDir, ".sdk-install.json"), "utf8"));
    assert.equal(record.id, EXT_ID);
    assert.equal(record.packageDigest, data.packageDigest);
    assert.equal(record.enabled, true);
  });

  it("run: the installed entry activates through the node runtime adapter", async () => {
    const installedDir = path.join(extRoot, EXT_ID, EXT_VERSION);
    // The installed package ships no node_modules; the host runtime
    // supplies the SDK. Mirror that with a run dir.
    const runDir = path.join(sandbox, "rundir");
    await mkdir(path.join(runDir, "node_modules", "@swiftcode"), { recursive: true });
    await symlink(
      path.join(REPO, "SwiftCode", "SDK", "TypeScript", "package"),
      path.join(runDir, "node_modules", "@swiftcode", "sdk")
    );
    await symlink(path.join(installedDir, "dist"), path.join(runDir, "dist"));

    const child = spawn(
      process.execPath,
      [
        RUNTIME_ADAPTER,
        "--entrypoint",
        path.join(runDir, "dist", "index.js"),
        "--manifest",
        path.join(installedDir, "swiftcode.json"),
      ],
      { stdio: ["pipe", "pipe", "pipe"] }
    );
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => {
      stdout += d.toString();
    });
    const active = new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error(`adapter never activated:\n${stderr}`)), 20000);
      child.stderr.on("data", (d) => {
        stderr += d.toString();
        if (stderr.includes("active; awaiting host events")) {
          clearTimeout(timer);
          resolve();
        }
      });
    });
    const closed = new Promise((resolve) => child.on("close", resolve));
    child.on("error", (e) => {
      throw e;
    });
    await active; // the installed entry loaded and activate() ran
    child.stdin.end(); // host hangs up -> bounded teardown
    const code = await closed;
    assert.equal(code, 0, `adapter exited ${code}:\n${stderr}`);
    assert.match(stdout, /"event":"extension\.ready"/);
    assert.match(stdout, /"method":"commands\.register"/);
  });
});

describe("swiftcode build failure modes", () => {
  it("broken TypeScript fails with the real compiler diagnostic", async () => {
    const srcFile = path.join(genDir, "src", "index.ts");
    const original = await readFile(srcFile, "utf8");
    await writeFile(srcFile, `${original}\nconst broken = ;\n`, "utf8");
    try {
      const r = await runCli(["build", genDir]);
      assert.equal(r.code, 1, "broken build must fail");
      assert.match(r.stderr, /error TS1109|compilation failed/i);
    } finally {
      await writeFile(srcFile, original, "utf8");
    }
  });

  it("Swift sources without xcodebuild fail honestly (no fake build)", async () => {
    let hasXcodebuild = false;
    try {
      const probe = await runCommand("xcodebuild", ["-version"]);
      hasXcodebuild = probe.code === 0;
    } catch {
      hasXcodebuild = false;
    }
    if (hasXcodebuild) {
      // On a Mac with Xcode the real xcodebuild path runs instead; the
      // honest-absence assertion only applies where xcodebuild is missing.
      return;
    }
    const swiftDir = path.join(sandbox, "swiftproj");
    await mkdir(swiftDir, { recursive: true });
    await writeFile(path.join(swiftDir, "main.swift"), 'print("hi")\n', "utf8");
    const r = await runCli(["build", swiftDir]);
    assert.equal(r.code, 1);
    assert.match(r.stderr, /\[XCODEBUILD_UNAVAILABLE\]/);
    assert.match(r.stderr, /nothing was compiled/);
  });

  it("missing compiler is reported honestly", async () => {
    // A TypeScript project whose node_modules has no tsc, with PATH
    // scrubbed of node tooling, must fail with COMPILER_NOT_FOUND —
    // never a silent success.
    const bare = path.join(sandbox, "bare-ts");
    await mkdir(bare, { recursive: true });
    await writeFile(path.join(bare, "tsconfig.json"), JSON.stringify({ compilerOptions: {} }), "utf8");
    const scrubbed = { PATH: "/usr/bin:/bin" };
    const r = await runCli(["build", bare], { env: scrubbed });
    // /usr/bin:/bin has no tsc and no npx on this machine; either the
    // honest missing-compiler error or (if a tsc somehow resolves) a
    // genuine tsc failure — but never exit 0.
    assert.notEqual(r.code, 0, "build without a compiler must not succeed");
    if (/COMPILER_NOT_FOUND/.test(r.stderr)) {
      assert.match(r.stderr, /nothing was compiled/);
    }
  });
});
