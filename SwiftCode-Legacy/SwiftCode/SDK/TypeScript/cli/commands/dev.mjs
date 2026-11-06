#!/usr/bin/env node
/**
 * dev.mjs — local development loop for a SwiftCode TypeScript extension.
 *
 *   swiftcode dev [dir]
 *
 * Resolves `dir` (default: cwd), requires swiftcode.json + package.json +
 * tsconfig.json there, then runs an initial cycle and watches
 * `src/` (recursive) plus the three config files (single-file watchers).
 *
 * Each cycle, in order, with timestamped phase labels:
 *   1. [compile]  tsc -p tsconfig.json — errors stop the cycle, watcher stays alive.
 *   2. [manifest] + [package] — manifest + package validation (same checks the
 *      `validate` command runs; implemented here because commands/validate.mjs
 *      was not present in this checkout — see cli/agent_notes.md for the
 *      duplication note).
 *   3. [tests]    node --test tests/*.test.mjs when tests/ exists.
 *
 * v1 has NO host attachment (the Swift host driver arrives later), so there
 * are no runtime sessions to duplicate or restart here: dev only rebuilds,
 * revalidates, and retests. Run against the live host from SwiftCode Studio.
 * SIGINT / SIGTERM shut down cleanly (watchers closed, exit 0).
 */

import { existsSync, readFileSync, readdirSync, watch } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";

// ---------------------------------------------------------------------------
// CLI contract (owned by the CLI-core module; implemented here exactly).
// ---------------------------------------------------------------------------

export const definition = {
  name: "dev",
  description:
    "Watch a SwiftCode extension directory, recompiling, revalidating, and " +
    "retesting on every change. No host attachment in v1: dev never activates " +
    "an extension — run against the live host from SwiftCode Studio.",
  usage: "swiftcode dev [dir]",
};

const MANIFEST_FILE = "swiftcode.json";
const PACKAGE_FILE = "package.json";
const TSCONFIG_FILE = "tsconfig.json";
const DEBOUNCE_MS = 300;
const SUPPORTED_MANIFEST_VERSION = 1;
const SUPPORTED_PROTOCOL_VERSION = 1;
const ID_PATTERN = /^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z][A-Za-z0-9-]*)+$/;
const SEMVER_PATTERN =
  /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$/;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function ts() {
  return new Date().toLocaleTimeString("en-GB", { hour12: false });
}

function log(phase, message) {
  process.stdout.write(`[${ts()}] [${phase}] ${message}\n`);
}

function err(phase, message) {
  process.stderr.write(`[${ts()}] [${phase}] error: ${message}\n`);
}

function readJsonFile(filePath) {
  try {
    const text = readFileSync(filePath, "utf8");
    try {
      return { ok: true, value: JSON.parse(text) };
    } catch (jsonError) {
      return { ok: false, error: `invalid JSON: ${jsonError.message}` };
    }
  } catch (fsError) {
    return { ok: false, error: `cannot read: ${fsError.message}` };
  }
}

/** Locate the shipped manifest schema: the project copy first, then the SDK contracts. */
function locateManifestSchema(dir) {
  const projectCopy = path.join(dir, "schemas", "swiftcode-extension-v1.schema.json");
  if (existsSync(projectCopy)) return projectCopy;
  // cli/commands/dev.mjs -> cli/commands -> cli -> TypeScript -> SDK -> Contracts/Manifest
  const thisFile = new URL(import.meta.url);
  const repoCopy = path.resolve(
    path.dirname(thisFile.pathname),
    "..",
    "..",
    "..",
    "Contracts",
    "Manifest",
    "swiftcode-extension-v1.schema.json"
  );
  return existsSync(repoCopy) ? repoCopy : null;
}

function tscBinary(dir) {
  const local = path.join(dir, "node_modules", ".bin", "tsc");
  return existsSync(local) ? local : "tsc";
}

// ---------------------------------------------------------------------------
// Manifest validation (mirrors the `validate` command's checks).
// ---------------------------------------------------------------------------

function validateManifest(dir) {
  const problems = [];
  const warnings = [];

  const manifestPath = path.join(dir, MANIFEST_FILE);
  if (!existsSync(manifestPath)) {
    problems.push(`${MANIFEST_FILE} is missing`);
    return { manifest: null, problems, warnings };
  }
  const parsed = readJsonFile(manifestPath);
  if (!parsed.ok) {
    problems.push(`${MANIFEST_FILE}: ${parsed.error}`);
    return { manifest: null, problems, warnings };
  }
  const m = parsed.value;
  if (typeof m !== "object" || m === null || Array.isArray(m)) {
    problems.push(`${MANIFEST_FILE}: root must be a JSON object`);
    return { manifest: null, problems, warnings };
  }

  for (const field of [
    "manifestVersion",
    "id",
    "name",
    "version",
    "type",
    "runtime",
    "sdk",
    "capabilities",
  ]) {
    if (m[field] === undefined || m[field] === null) {
      problems.push(`missing required field: ${field}`);
    }
  }
  if (problems.length > 0) return { manifest: m, problems, warnings };

  if (m.manifestVersion !== SUPPORTED_MANIFEST_VERSION) {
    problems.push(
      `unsupported manifestVersion ${JSON.stringify(m.manifestVersion)} — expected ${SUPPORTED_MANIFEST_VERSION}`
    );
  }

  if (typeof m.id !== "string" || !ID_PATTERN.test(m.id)) {
    problems.push(`id must be reverse-DNS (e.g. com.example.my-ext), got ${JSON.stringify(m.id)}`);
  }
  if (typeof m.name !== "string" || m.name.trim() === "") {
    problems.push("name must be a non-empty string");
  }
  if (typeof m.version !== "string" || !SEMVER_PATTERN.test(m.version)) {
    problems.push(`version must be semver, got ${JSON.stringify(m.version)}`);
  }
  if (m.type !== "extension") {
    warnings.push(`type is ${JSON.stringify(m.type)} — only "extension" is supported in v1`);
  }

  // runtime
  const runtime = m.runtime;
  if (typeof runtime !== "object" || runtime === null) {
    problems.push("runtime must be an object");
  } else {
    if (runtime.language !== "typescript") {
      problems.push(
        `unsupported runtime language ${JSON.stringify(runtime.language)} — expected "typescript"`
      );
    }
    const entrypoint = runtime.entrypoint;
    if (typeof entrypoint !== "string" || entrypoint.trim() === "") {
      problems.push("runtime.entrypoint must be a non-empty string");
    } else if (entrypoint.includes("..")) {
      problems.push(`runtime.entrypoint must not escape the package root: ${JSON.stringify(entrypoint)}`);
    } else {
      const resolved = path.resolve(dir, entrypoint);
      if (!resolved.startsWith(dir + path.sep)) {
        problems.push(`runtime.entrypoint escapes the package root: ${JSON.stringify(entrypoint)}`);
      } else if (!existsSync(resolved)) {
        problems.push(
          `runtime.entrypoint resolves to a missing file: ${entrypoint} — build first`
        );
      }
    }
  }

  // sdk
  const sdk = m.sdk;
  if (typeof sdk !== "object" || sdk === null) {
    problems.push("sdk must be an object");
  } else {
    if (typeof sdk.versionRange !== "string" || sdk.versionRange.trim() === "") {
      problems.push("sdk.versionRange must be a non-empty string");
    }
    if (sdk.protocolVersion !== SUPPORTED_PROTOCOL_VERSION) {
      problems.push(
        `unsupported sdk.protocolVersion ${JSON.stringify(sdk.protocolVersion)} — expected ${SUPPORTED_PROTOCOL_VERSION}`
      );
    }
  }

  // capabilities
  const caps = m.capabilities;
  if (!Array.isArray(caps) || caps.length === 0) {
    problems.push("capabilities must be a non-empty array");
  } else {
    const schemaPath = locateManifestSchema(dir);
    let knownCapabilityIds = null;
    if (schemaPath) {
      const schemaJson = readJsonFile(schemaPath);
      if (schemaJson.ok) {
        try {
          knownCapabilityIds = new Set(
            schemaJson.value.properties.capabilities.items.properties.id.enum
          );
        } catch {
          knownCapabilityIds = null;
        }
      }
    }
    if (!knownCapabilityIds) {
      warnings.push("shipped manifest schema not found — capability ids not checked against registry");
    }
    for (const cap of caps) {
      if (typeof cap !== "object" || cap === null || typeof cap.id !== "string") {
        problems.push(`capability must be an object with a string id, got ${JSON.stringify(cap)}`);
        continue;
      }
      if (knownCapabilityIds && !knownCapabilityIds.has(cap.id)) {
        problems.push(`unknown capability id: ${JSON.stringify(cap.id)} — not in the SDK registry`);
      }
      if (typeof cap.reason !== "string" || cap.reason.trim() === "") {
        problems.push(`capability ${JSON.stringify(cap.id)} needs a non-empty reason`);
      }
    }
  }

  // contributions
  if (m.contributes?.commands !== undefined) {
    const commands = m.contributes.commands;
    if (!Array.isArray(commands)) {
      problems.push("contributes.commands must be an array");
    } else {
      const seen = new Set();
      for (const cmd of commands) {
        if (typeof cmd !== "object" || cmd === null || typeof cmd.id !== "string" || cmd.id.trim() === "") {
          problems.push(`contribution command must have a non-empty string id, got ${JSON.stringify(cmd)}`);
          continue;
        }
        if (seen.has(cmd.id)) problems.push(`duplicate contribution command id: ${cmd.id}`);
        seen.add(cmd.id);
      }
    }
  }

  // Assist posture: extensions must not request Assist (separate entitlement).
  if (m.assist?.requested === true) {
    problems.push(
      "assist.requested must not be true — Assist is a separately protected entitlement, not a manifest grant"
    );
  }

  return { manifest: m, problems, warnings };
}

function validatePackage(dir, manifest) {
  const problems = [];
  const warnings = [];

  const packagePath = path.join(dir, PACKAGE_FILE);
  if (!existsSync(packagePath)) {
    problems.push(`${PACKAGE_FILE} is missing`);
    return { problems, warnings };
  }
  const parsed = readJsonFile(packagePath);
  if (!parsed.ok) {
    problems.push(`${PACKAGE_FILE}: ${parsed.error}`);
    return { problems, warnings };
  }
  const pkg = parsed.value;
  if (typeof pkg !== "object" || pkg === null || Array.isArray(pkg)) {
    problems.push(`${PACKAGE_FILE}: root must be a JSON object`);
    return { problems, warnings };
  }

  if (typeof pkg.name !== "string" || pkg.name.trim() === "") {
    problems.push(`${PACKAGE_FILE}: name must be a non-empty string`);
  }
  if (manifest && manifest.id) {
    // Accept either the full id slug ("com-example-devfixture") or the last
    // segment ("devfixture") — both appear in the wild and both are fine.
    const idStr = String(manifest.id);
    const candidates = new Set([
      idStr.replace(/\./g, "-").toLowerCase(),
      idStr.split(".").pop().toLowerCase(),
    ]);
    if (!candidates.has(pkg.name)) {
      warnings.push(
        `${PACKAGE_FILE}: name ${JSON.stringify(pkg.name)} does not match manifest id (${JSON.stringify(idStr)})`
      );
    }
  }
  if (typeof pkg.version !== "string" || !SEMVER_PATTERN.test(pkg.version)) {
    problems.push(`${PACKAGE_FILE}: version must be semver, got ${JSON.stringify(pkg.version)}`);
  } else if (manifest && manifest.version && pkg.version !== manifest.version) {
    problems.push(
      `${PACKAGE_FILE}: version ${pkg.version} does not match manifest version ${manifest.version}`
    );
  }
  if (pkg.type !== "module") {
    problems.push(`${PACKAGE_FILE}: type must be "module", got ${JSON.stringify(pkg.type)}`);
  }
  if (!pkg.scripts || typeof pkg.scripts.build !== "string") {
    warnings.push(`${PACKAGE_FILE}: no "build" script — dev uses tsc -p tsconfig.json directly`);
  }
  return { problems, warnings };
}

// ---------------------------------------------------------------------------
// Cycle phases
// ---------------------------------------------------------------------------

function phaseCompile(dir) {
  const binary = tscBinary(dir);
  log("compile", `running ${path.basename(binary)} -p ${TSCONFIG_FILE} …`);
  const result = spawnSync(binary, ["-p", TSCONFIG_FILE], {
    cwd: dir,
    encoding: "utf8",
    timeout: 300_000,
    maxBuffer: 8 * 1024 * 1024,
  });
  const output = `${result.stdout ?? ""}${result.stderr ?? ""}`.trimEnd();
  if (result.error) {
    err("compile", `could not launch the TypeScript compiler: ${result.error.message}`);
    return false;
  }
  if (result.status !== 0) {
    err("compile", "COMPILATION FAILED — skipping manifest validation and tests, still watching");
    if (output) process.stderr.write(`${output}\n`);
    return false;
  }
  if (output) process.stdout.write(`${output}\n`);
  log("compile", "compilation succeeded");
  return true;
}

function phaseValidate(dir) {
  const { manifest, problems, warnings } = validateManifest(dir);
  const pkg = validatePackage(dir, manifest);
  const allProblems = [...problems, ...pkg.problems];
  const allWarnings = [...warnings, ...pkg.warnings];
  for (const w of allWarnings) log("manifest", `warning: ${w}`);
  if (allProblems.length > 0) {
    err("manifest", "MANIFEST/PACKAGE VALIDATION FAILED");
    for (const p of allProblems) err("manifest", `  ${p}`);
    return false;
  }
  log("manifest", "manifest valid");
  log("package", "package.json valid");
  return true;
}

function phaseTests(dir) {
  const testsDir = path.join(dir, "tests");
  if (!existsSync(testsDir)) {
    log("tests", "no tests/ directory — skipping");
    return true;
  }
  let files;
  try {
    files = readdirSync(testsDir)
      .filter((f) => f.endsWith(".test.mjs"))
      .map((f) => path.join("tests", f))
      .sort();
  } catch (readError) {
    err("tests", `cannot read tests/: ${readError.message}`);
    return false;
  }
  if (files.length === 0) {
    log("tests", "no *.test.mjs files in tests/ — skipping");
    return true;
  }
  log("tests", `running node --test on ${files.length} file(s) …`);
  const result = spawnSync(process.execPath, ["--test", ...files], {
    cwd: dir,
    encoding: "utf8",
    timeout: 300_000,
    maxBuffer: 8 * 1024 * 1024,
  });
  const output = `${result.stdout ?? ""}${result.stderr ?? ""}`.trimEnd();
  if (output) process.stdout.write(`${output}\n`);
  let pass = null;
  let fail = null;
  for (const line of output.split("\n")) {
    // node --test summary lines look like "ℹ pass 12" / "# pass 12".
    const m = line.match(/^[ℹ#]\s+(pass|fail)\s+(\d+)/u);
    if (m) {
      if (m[1] === "pass") pass = Number(m[2]);
      else fail = Number(m[2]);
    }
  }
  if (result.status !== 0) {
    err(
      "tests",
      `TESTS FAILED (pass ${pass ?? "?"}, fail ${fail ?? "?"})`
    );
    return false;
  }
  log("tests", `all tests passed (pass ${pass ?? "?"}, fail ${fail ?? "?"})`);
  return true;
}

/**
 * One full cycle: compile → validate → test. Returns true when everything
 * passed. Phases are labeled so compile success is never confused with
 * manifest validity; a failed phase stops later phases but never the watcher.
 */
function runCycle(dir) {
  log("dev", "cycle started");
  if (!phaseCompile(dir)) {
    log("dev", "cycle done — compile failed; fix the errors and save to retry");
    return false;
  }
  if (!phaseValidate(dir)) {
    log("dev", "cycle done — manifest/package invalid; edit config and save to retry");
    return false;
  }
  const testsOk = phaseTests(dir);
  if (!testsOk) {
    log("dev", "cycle done — tests failing");
    return false;
  }
  log("dev", "cycle done — compile OK, manifest valid, tests green");
  return true;
}

// ---------------------------------------------------------------------------
// Help
// ---------------------------------------------------------------------------

function printHelp() {
  const lines = [
    "",
    "  swiftcode dev — local development loop for a SwiftCode TypeScript extension",
    "",
    `  ${definition.usage}`,
    "",
    "  Resolves [dir] (default: current directory), requires swiftcode.json +",
    "  package.json + tsconfig.json there, then runs an initial cycle and watches",
    "  src/ (recursively) plus the three config files. On every change (debounced",
    "  300ms) it runs, in order:",
    "",
    "    1. [compile]  tsc -p tsconfig.json",
    "    2. [manifest] + [package]  manifest & package.json validation",
    "    3. [tests]    node --test tests/*.test.mjs (when tests/ exists)",
    "",
    "  A failed phase stops the rest of that cycle but never the watcher.",
    "  Ctrl-C (SIGINT) or SIGTERM stops the loop cleanly.",
    "",
    "  No host attachment in v1: dev rebuilds, revalidates, and retests on",
    "  change; it never activates an extension. Run against the live host from",
    "  SwiftCode Studio.",
    "",
  ];
  process.stdout.write(`${lines.join("\n")}\n`);
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

export async function run(args, ctx) {
  // The dispatcher passes the parsed-args object ({ _: [positionals], ...flags });
  // a bare array is also accepted (per the command contract).
  const argv = Array.isArray(args) ? args : Array.isArray(args?._) ? args._ : [];
  const flags = Array.isArray(args) ? {} : args ?? {};
  if (argv.includes("--help") || argv.includes("-h") || flags.help === true) {
    printHelp();
    return 0;
  }

  const positional = argv.filter((a) => typeof a === "string" && !a.startsWith("-"));
  const dir = path.resolve(positional[0] ?? ctx?.cwd ?? process.cwd());

  // Required project files — missing any one is a hard failure, named explicitly.
  const missing = [MANIFEST_FILE, PACKAGE_FILE, TSCONFIG_FILE].filter(
    (f) => !existsSync(path.join(dir, f))
  );
  if (missing.length > 0) {
    for (const f of missing) err("dev", `missing required file: ${path.join(dir, f)}`);
    process.stderr.write(
      `dev: ${dir} is not a SwiftCode extension project (${missing.join(", ")} missing)\n`
    );
    return 1;
  }

  log("dev", `watching ${dir}`);
  log("dev", "no host attachment in v1 — dev rebuilds/revalidates/retests only");

  // Initial pass, then watch.
  runCycle(dir);

  let shuttingDown = false;
  let cycleRunning = false;
  let cyclePending = false;
  let debounceTimer = null;
  const watchers = [];

  const closeWatchers = () => {
    for (const w of watchers) {
      try {
        w.close();
      } catch {
        /* already closed */
      }
    }
  };

  const maybeRunCycle = () => {
    if (shuttingDown) return;
    if (cycleRunning) {
      cyclePending = true;
      return;
    }
    cycleRunning = true;
    try {
      runCycle(dir);
    } finally {
      cycleRunning = false;
      if (cyclePending && !shuttingDown) {
        cyclePending = false;
        maybeRunCycle();
      }
    }
  };

  const onChange = (eventType, displayName) => {
    if (shuttingDown) return;
    log("watch", `change detected (${eventType}): ${displayName}`);
    if (debounceTimer) clearTimeout(debounceTimer);
    debounceTimer = setTimeout(maybeRunCycle, DEBOUNCE_MS);
  };

  const watchTarget = (target, label) => {
    const options = label === "src" ? { recursive: true } : {};
    const w = watch(target, options, (eventType, filename) => {
      onChange(eventType, `${label}/${filename ?? ""}`);
    });
    w.on("error", (error) => err("watch", `${label}: watcher error — ${error.message}`));
    watchers.push(w);
    log("watch", `watching ${label}/ (${label === "src" ? "recursive" : "single-file"})`);
  };

  const srcDir = path.join(dir, "src");
  if (existsSync(srcDir)) {
    watchTarget(srcDir, "src");
  } else {
    log("watch", "no src/ directory — watching config files only");
  }
  for (const f of [MANIFEST_FILE, PACKAGE_FILE, TSCONFIG_FILE]) {
    watchTarget(path.join(dir, f), f);
  }

  // Clean shutdown: SIGINT/SIGTERM print "stopping", close watchers, exit 0.
  // The run() promise resolves so the dispatcher can set process.exitCode = 0.
  let resolveDone;
  const done = new Promise((resolve) => {
    resolveDone = resolve;
  });
  const shutdown = (signal) => {
    if (shuttingDown) return;
    shuttingDown = true;
    if (debounceTimer) clearTimeout(debounceTimer);
    log("dev", `stopping (${signal}) — closing watchers`);
    closeWatchers();
    resolveDone(0);
  };
  process.on("SIGINT", () => shutdown("SIGINT"));
  process.on("SIGTERM", () => shutdown("SIGTERM"));

  return done;
}
