/**
 * validate.mjs — `swiftcode validate [dir] [--json]`
 *
 * Fast local structural validation of an extension's swiftcode.json plus the
 * package-level checks from spec §7.2 (entrypoint safety/existence, no
 * path traversal, no symlinks escaping the package root, no .env/node_modules
 * shipped).
 *
 * This mirrors the REAL manifest schema at
 * SwiftCode/SDK/Contracts/Manifest/swiftcode-extension-v1.schema.json
 * (patterns, enums, length bounds, required fields, additionalProperties).
 * Every violation is collected and reported — never just the first.
 *
 * IMPORTANT: this is the fast local check. The Swift host performs the
 * authoritative strict validation at install time (unknown capabilities are
 * rejected with UNKNOWN_CAPABILITY, incompatible SDK ranges with
 * INCOMPATIBLE_SDK_VERSION, etc.). A "valid" result here means the manifest
 * is well-formed, not that the host will accept or trust the package.
 *
 * Reusable entry point for other commands (e.g. `package`, `dev`):
 *   import { validateExtension } from "./validate.mjs";
 *   const { valid, problems, warnings, manifest } =
 *     await validateExtension(dir, { checkEntrypointExists: true });
 */

import { UsageError } from "../errors.mjs";
import { PACKAGE_KINDS } from "./_package-format.mjs";
import { lstat, readdir, readFile, readlink, stat } from "node:fs/promises";
import path from "node:path";

export const definition = {
  name: "validate",
  description: "Validate an extension's swiftcode.json and package contents",
  usage: `swiftcode validate [dir] [--json]

Validates the extension in [dir] (default: current directory):

  - swiftcode.json exists and parses as JSON
  - structural validation mirroring the real manifest schema
    (SwiftCode/SDK/Contracts/Manifest/swiftcode-extension-v1.schema.json):
    required fields, types, length bounds, manifestVersion === 1,
    reverse-DNS id, semver version, runtime.language === "typescript",
    sdk.name === "@swiftcode/sdk", sdk.protocolVersion === 1,
    capability ids from the v1 registry (unique), command ids unique
    and kebab-case, assist.requested boolean
  - package checks (spec §7.2): runtime.entrypoint is relative with no
    ".." segments, the entrypoint file exists under the package root,
    no symlinks escape the package root, no .env files or node_modules
    content would be shipped

Exit 0 and prints "valid" when everything passes; exit 1 lists every
problem found (never just the first one).

This is the fast local check. The Swift host performs the authoritative
strict validation at install time — a "valid" result here does not grant
capabilities or establish package trust.

Options:
  --json    machine-readable output (the dispatcher wraps the result)`,
};

// ---------------------------------------------------------------------------
// Schema mirror (SwiftCode/SDK/Contracts/Manifest/swiftcode-extension-v1.schema.json)
// ---------------------------------------------------------------------------

const ID_PATTERN = /^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z][A-Za-z0-9-]*)+$/;
const SEMVER_PATTERN =
  /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-((0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(\.(0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(\+([0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*))?$/;
const ENTRYPOINT_PATTERN = /^(?![/\\])(?!.*\.\.)[^\x00]+$/;
const VERSION_RANGE_PATTERN = /^[\^~>=<\d\.\-xX\*\|\s,]+$/;
const COMMAND_ID_PATTERN = /^[a-z0-9-]+$/;

const TOP_LEVEL_KEYS = new Set([
  "$schema",
  "assist",
  "capabilities",
  "contributes",
  "description",
  "id",
  "manifestVersion",
  "name",
  "runtime",
  "sdk",
  "type",
  "version",
]);
const REQUIRED_TOP_LEVEL = [
  "manifestVersion",
  "id",
  "name",
  "version",
  "type",
  "runtime",
  "sdk",
  "capabilities",
];

// Capability IDs across the canonical SDK registry (SDKCapability.swift + ScopesIDLists.ts).
const CAPABILITY_IDS = [
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
];
const CAPABILITY_SET = new Set(CAPABILITY_IDS);

// Basenames treated as secret-bearing: warned on, never shipped.
const ENV_BASENAME_RE = /^\.env(\.|$)/;

// ---------------------------------------------------------------------------
// Problem collection
// ---------------------------------------------------------------------------

function makeCollector() {
  const problems = [];
  const warnings = [];
  return {
    problems,
    warnings,
    error(p, message) {
      problems.push({ path: p, message });
    },
    warn(p, message) {
      warnings.push({ path: p, message });
    },
  };
}

function isObject(v) {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function checkUnknownKeys(obj, allowed, c, base) {
  for (const key of Object.keys(obj)) {
    if (!allowed.has(key)) c.error(base ? `${base}.${key}` : key, `unsupported field "${key}" (manifestVersion 1 has no such field)`);
  }
}

function checkRequired(obj, required, c, base) {
  for (const key of required) {
    if (obj[key] === undefined) c.error(base ? `${base}.${key}` : key, `missing required field "${key}"`);
  }
}

function checkString(c, base, value, { minLength = 0, maxLength = Infinity, pattern = null, patternHint = "" } = {}) {
  if (value === undefined) return false; // missing-field error already recorded by checkRequired
  if (typeof value !== "string") {
    c.error(base, `must be a string`);
    return false;
  }
  if (value.length < minLength) {
    c.error(base, `must not be blank`);
    return false;
  }
  if (value.length > maxLength) {
    c.error(base, `exceeds the ${maxLength}-character limit (${value.length} characters)`);
    return false;
  }
  if (pattern && !pattern.test(value)) {
    c.error(base, `has an invalid value ${JSON.stringify(value)}${patternHint ? ` (${patternHint})` : ""}`);
    return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Structural validation (mirrors the JSON schema)
// ---------------------------------------------------------------------------

function validateStructure(manifest, c) {
  checkUnknownKeys(manifest, TOP_LEVEL_KEYS, c, "");
  checkRequired(manifest, REQUIRED_TOP_LEVEL, c, "");

  // manifestVersion
  if (manifest.manifestVersion !== undefined) {
    if (!Number.isInteger(manifest.manifestVersion)) {
      c.error("manifestVersion", "must be an integer");
    } else if (manifest.manifestVersion !== 1) {
      c.error("manifestVersion", `unsupported manifest version ${manifest.manifestVersion} (this tool validates version 1)`);
    }
  }

  // id — reverse-DNS, schema pattern (allows uppercase; NOT lowercase-only)
  checkString(c, "id", manifest.id, {
    maxLength: 128,
    pattern: ID_PATTERN,
    patternHint: 'reverse-DNS, e.g. "com.example.my-extension"',
  });

  checkString(c, "name", manifest.name, { minLength: 1, maxLength: 128 });

  checkString(c, "version", manifest.version, {
    maxLength: 64,
    pattern: SEMVER_PATTERN,
    patternHint: "must be semver 2.0.0",
  });

  if (manifest.type !== undefined && !PACKAGE_KINDS.includes(manifest.type)) {
    c.error("type", `must be one of ${PACKAGE_KINDS.join(", ")}, got ${JSON.stringify(manifest.type)}`);
  }

  if (manifest.description !== undefined) {
    checkString(c, "description", manifest.description, { maxLength: 1000 });
  }

  if (manifest.$schema !== undefined && typeof manifest.$schema !== "string") {
    c.error("$schema", "must be a string");
  }

  validateRuntime(manifest.runtime, c);
  validateSdk(manifest.sdk, c);
  validateCapabilities(manifest.capabilities, c);

  if (manifest.assist !== undefined) validateAssist(manifest.assist, c);
  if (manifest.contributes !== undefined) validateContributes(manifest.contributes, c);
}

function validateRuntime(runtime, c) {
  const base = "runtime";
  if (runtime === undefined) return; // missing-field error already recorded
  if (!isObject(runtime)) {
    c.error(base, "must be an object");
    return;
  }
  checkUnknownKeys(runtime, new Set(["language", "entrypoint", "minimumSwiftCodeVersion"]), c, base);
  checkRequired(runtime, ["language", "entrypoint", "minimumSwiftCodeVersion"], c, base);

  if (runtime.language !== undefined && runtime.language !== "typescript") {
    c.error(`${base}.language`, `unsupported runtime language ${JSON.stringify(runtime.language)} (only "typescript" is supported)`);
  }

  if (runtime.entrypoint !== undefined) {
    const ok = checkString(c, `${base}.entrypoint`, runtime.entrypoint, { maxLength: 256 });
    if (ok) {
      const ep = runtime.entrypoint;
      if (path.isAbsolute(ep) || /^[/\\]/.test(ep)) {
        c.error(`${base}.entrypoint`, `must be a relative path inside the package, got absolute path ${JSON.stringify(ep)}`);
      } else if (ep.includes("..")) {
        c.error(`${base}.entrypoint`, `must not contain ".." segments (path traversal), got ${JSON.stringify(ep)}`);
      } else if (!ENTRYPOINT_PATTERN.test(ep)) {
        c.error(`${base}.entrypoint`, `has an invalid value ${JSON.stringify(ep)} (must be relative, no "..", no NUL)`);
      }
    }
  }

  if (runtime.minimumSwiftCodeVersion !== undefined) {
    checkString(c, `${base}.minimumSwiftCodeVersion`, runtime.minimumSwiftCodeVersion, {
      maxLength: 64,
      pattern: SEMVER_PATTERN,
      patternHint: "must be semver 2.0.0",
    });
  }
}

function validateSdk(sdk, c) {
  const base = "sdk";
  if (sdk === undefined) return;
  if (!isObject(sdk)) {
    c.error(base, "must be an object");
    return;
  }
  checkUnknownKeys(sdk, new Set(["name", "versionRange", "protocolVersion"]), c, base);
  checkRequired(sdk, ["name", "versionRange", "protocolVersion"], c, base);

  if (sdk.name !== undefined && sdk.name !== "@swiftcode/sdk") {
    c.error(`${base}.name`, `must be "@swiftcode/sdk", got ${JSON.stringify(sdk.name)}`);
  }
  if (sdk.versionRange !== undefined) {
    checkString(c, `${base}.versionRange`, sdk.versionRange, {
      minLength: 1,
      maxLength: 64,
      pattern: VERSION_RANGE_PATTERN,
      patternHint: 'npm-style semver range, e.g. "^1.0.0"',
    });
  }
  if (sdk.protocolVersion !== undefined) {
    if (!Number.isInteger(sdk.protocolVersion)) {
      c.error(`${base}.protocolVersion`, "must be an integer");
    } else if (sdk.protocolVersion !== 1) {
      c.error(`${base}.protocolVersion`, `unsupported protocol version ${sdk.protocolVersion} (this tool validates version 1)`);
    }
  }
}

function validateCapabilities(capabilities, c) {
  const base = "capabilities";
  if (capabilities === undefined) return;
  if (!Array.isArray(capabilities)) {
    c.error(base, "must be an array");
    return;
  }
  if (capabilities.length < 1) c.error(base, "must request at least one capability");
  if (capabilities.length > 32) c.error(base, `requests ${capabilities.length} capabilities; the maximum is 32`);
  const seen = new Set();
  capabilities.forEach((cap, i) => {
    const p = `${base}[${i}]`;
    if (!isObject(cap)) {
      c.error(p, "must be an object");
      return;
    }
    checkUnknownKeys(cap, new Set(["id", "reason"]), c, p);
    checkRequired(cap, ["id", "reason"], c, p);
    if (cap.id !== undefined) {
      if (typeof cap.id !== "string" || !CAPABILITY_SET.has(cap.id)) {
        c.error(`${p}.id`, `unknown capability id ${JSON.stringify(cap.id)} (must be one of: ${CAPABILITY_IDS.join(", ")})`);
      } else if (seen.has(cap.id)) {
        c.error(`${p}.id`, `duplicate capability id "${cap.id}"`);
      } else {
        seen.add(cap.id);
      }
    }
    if (cap.reason !== undefined) {
      checkString(c, `${p}.reason`, cap.reason, { minLength: 1, maxLength: 500 });
    }
  });
}

function validateAssist(assist, c) {
  const base = "assist";
  if (!isObject(assist)) {
    c.error(base, "must be an object");
    return;
  }
  checkUnknownKeys(assist, new Set(["requested"]), c, base);
  checkRequired(assist, ["requested"], c, base);
  if (assist.requested !== undefined && typeof assist.requested !== "boolean") {
    c.error(`${base}.requested`, `must be a boolean, got ${JSON.stringify(assist.requested)}`);
  }
}

function validateContributes(contributes, c) {
  const base = "contributes";
  if (!isObject(contributes)) {
    c.error(base, "must be an object");
    return;
  }
  checkUnknownKeys(contributes, new Set(["commands"]), c, base);
  checkRequired(contributes, ["commands"], c, base);
  const commands = contributes.commands;
  if (commands === undefined) return;
  const cp = `${base}.commands`;
  if (!Array.isArray(commands)) {
    c.error(cp, "must be an array");
    return;
  }
  if (commands.length < 1) c.error(cp, "must contain at least one command");
  if (commands.length > 64) c.error(cp, `contributes ${commands.length} commands; the maximum is 64`);
  const seen = new Set();
  commands.forEach((cmd, i) => {
    const p = `${cp}[${i}]`;
    if (!isObject(cmd)) {
      c.error(p, "must be an object");
      return;
    }
    checkUnknownKeys(cmd, new Set(["id", "title"]), c, p);
    checkRequired(cmd, ["id", "title"], c, p);
    if (cmd.id !== undefined) {
      const ok = checkString(c, `${p}.id`, cmd.id, {
        maxLength: 64,
        pattern: COMMAND_ID_PATTERN,
        patternHint: "lowercase alphanumeric plus hyphens",
      });
      if (ok) {
        if (seen.has(cmd.id)) c.error(`${p}.id`, `duplicate command id "${cmd.id}"`);
        else seen.add(cmd.id);
      }
    }
    if (cmd.title !== undefined) {
      checkString(c, `${p}.title`, cmd.title, { minLength: 1, maxLength: 128 });
    }
  });
}

// ---------------------------------------------------------------------------
// Package-level checks (spec §7.2 — filesystem reality)
// ---------------------------------------------------------------------------

function isWithinRoot(root, target) {
  const resolved = path.resolve(target);
  return resolved === root || resolved.startsWith(root + path.sep);
}

/** Walk the whole tree (pruning node_modules/.git); report symlinks escaping
 *  root and .env files. Lexical resolution — works for dangling links too. */
async function walkTree(root, c) {
  const PRUNE = new Set(["node_modules", ".git"]);

  async function walk(abs, rel) {
    let entries;
    try {
      entries = await readdir(abs, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      if (rel === "" && PRUNE.has(entry.name)) continue;
      const entryAbs = path.join(abs, entry.name);
      const entryRel = rel ? `${rel}/${entry.name}` : entry.name;
      let lst;
      try {
        lst = await lstat(entryAbs);
      } catch {
        continue;
      }
      if (lst.isSymbolicLink()) {
        let target = null;
        try {
          target = await readlink(entryAbs);
        } catch {
          /* unreadable below */
        }
        if (target === null) {
          c.error(entryRel, "unreadable symlink");
        } else if (!isWithinRoot(root, path.resolve(path.dirname(entryAbs), target))) {
          c.error(entryRel, `symlink escapes the package root -> ${target} (PATH_TRAVERSAL)`);
        }
        continue; // never descend through symlinks
      }
      if (ENV_BASENAME_RE.test(entry.name)) {
        c.warn(entryRel, "secret-bearing file will NOT be shipped in the package (excluded by the packager)");
      }
      if (lst.isDirectory()) {
        await walk(entryAbs, entryRel);
      }
    }
  }

  await walk(root, "");
}

/**
 * Validate the extension rooted at dir.
 * options.checkEntrypointExists (default true): set false when the caller
 *   will build dist/ right after (the `package` command's pre-build check).
 * Returns { valid, problems, warnings, manifest } — manifest is the parsed
 * object when JSON parsing succeeded, else null.
 */
export async function validateExtension(dir, options = {}) {
  const { checkEntrypointExists = true } = options;
  const c = makeCollector();
  const root = path.resolve(dir);
  const manifestPath = path.join(root, "swiftcode.json");

  let manifest = null;
  let raw;
  try {
    raw = await readFile(manifestPath, "utf8");
  } catch (error) {
    if (error && error.code === "ENOENT") {
      c.error("swiftcode.json", `manifest not found at ${manifestPath}`);
    } else {
      c.error("swiftcode.json", `cannot be read: ${error.message ?? String(error)}`);
    }
    return { valid: false, problems: c.problems, warnings: c.warnings, manifest: null };
  }
  try {
    manifest = JSON.parse(raw);
  } catch (error) {
    c.error("swiftcode.json", `malformed JSON: ${error.message ?? String(error)}`);
    return { valid: false, problems: c.problems, warnings: c.warnings, manifest: null };
  }
  if (!isObject(manifest)) {
    c.error("swiftcode.json", "must contain a single JSON object");
    return { valid: false, problems: c.problems, warnings: c.warnings, manifest: null };
  }

  validateStructure(manifest, c);

  // $schema: a relative pointer must resolve to a file shipped in the package
  // (spec §7.1 — dead schema references are rejected at install time).
  if (typeof manifest.$schema === "string") {
    const ref = manifest.$schema;
    const isUrl = /^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(ref);
    if (!isUrl) {
      const schemaAbs = path.resolve(root, ref);
      if (!isWithinRoot(root, schemaAbs)) {
        c.error("$schema", `schema reference escapes the package root: ${JSON.stringify(ref)}`);
      } else {
        try {
          const s = await stat(schemaAbs);
          if (!s.isFile()) c.error("$schema", `schema reference is not a file: ${JSON.stringify(ref)}`);
        } catch {
          c.error("$schema", `schema file not found in the package: ${JSON.stringify(ref)}`);
        }
      }
    }
  }

  // Entrypoint existence (inside the validated package root).
  const entrypoint = manifest?.runtime && typeof manifest.runtime.entrypoint === "string" ? manifest.runtime.entrypoint : null;
  if (entrypoint && ENTRYPOINT_PATTERN.test(entrypoint) && !path.isAbsolute(entrypoint)) {
    const abs = path.join(root, entrypoint);
    if (checkEntrypointExists) {
      try {
        const s = await stat(abs);
        if (!s.isFile()) {
          c.error("runtime.entrypoint", `entrypoint is not a file: ${entrypoint}`);
        }
      } catch {
        c.error(
          "runtime.entrypoint",
          `entrypoint file not found: ${entrypoint} (build the extension first, e.g. "npm run build")`
        );
      }
    }
    // The entrypoint must never resolve into node_modules (never shipped).
    if (isWithinRoot(path.join(root, "node_modules"), abs)) {
      c.error("runtime.entrypoint", "entrypoint must not live under node_modules/ (never shipped)");
    }
  }

  // Symlink containment + .env warnings across the whole tree.
  await walkTree(root, c);

  return {
    valid: c.problems.length === 0,
    problems: c.problems,
    warnings: c.warnings,
    manifest,
  };
}

/** Human-readable multi-line report of all problems (and warnings). */
export function formatValidationReport(manifestPath, problems, warnings) {
  const lines = [`invalid: ${manifestPath} — ${problems.length} problem${problems.length === 1 ? "" : "s"}:`];
  for (const p of problems) {
    lines.push(`  - ${p.path}: ${p.message}`);
  }
  if (warnings.length > 0) {
    lines.push(`warnings (${warnings.length}):`);
    for (const w of warnings) {
      lines.push(`  - ${w.path}: ${w.message}`);
    }
  }
  return lines.join("\n");
}

export async function run(args, ctx) {
  if (args._.length > 1) throw new UsageError("too many arguments");
  const dirArg = args._[0] ?? ".";
  const root = path.resolve(dirArg);
  let st;
  try {
    st = await stat(root);
  } catch {
    throw new Error(`not a directory: ${root}`);
  }
  if (!st.isDirectory()) throw new Error(`not a directory: ${root}`);

  const { valid, problems, warnings, manifest } = await validateExtension(root);
  const manifestPath = path.join(root, "swiftcode.json");
  const data = {
    valid,
    dir: root,
    problems,
    warnings,
    manifest: manifest ? { id: manifest.id ?? null, name: manifest.name ?? null, version: manifest.version ?? null } : null,
  };

  if (valid) {
    ctx.log("valid");
    if (warnings.length > 0) {
      ctx.error(`warnings (${warnings.length}):`);
      for (const w of warnings) ctx.error(`  - ${w.path}: ${w.message}`);
    }
    return { code: 0, data };
  }
  ctx.error(formatValidationReport(manifestPath, problems, warnings));
  return { code: 1, data };
}
