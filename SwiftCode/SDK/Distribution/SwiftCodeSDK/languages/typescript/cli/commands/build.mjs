/**
 * build.mjs — `swiftcode build [dir] [--json] [--project <path>] [--scheme <name>]`
 *
 * Compiler-like build for an extension project, with live compiler output:
 *
 *   - TypeScript projects (tsconfig.json): runs the TypeScript compiler.
 *     The compiler is resolved as <dir>/node_modules/.bin/tsc, then a
 *     PATH `tsc`, then `npx --no-install tsc` (never a silent download).
 *     When none is available the command fails honestly and names every
 *     location it checked — it never pretends to have compiled.
 *   - Swift projects (*.xcodeproj / *.xcworkspace / Package.swift / *.swift
 *     sources): runs `xcodebuild`. When xcodebuild is absent (this Linux
 *     environment, CI without Xcode, ...) the command reports that
 *     honestly instead of faking a build: Swift builds require macOS with
 *     Xcode. The xcodebuild invocation itself is real and is exercised on
 *     Dylan's Mac.
 *
 * In human mode the compiler's stdout/stderr stream live (stdio inherit).
 * In --json mode the output is captured and returned in `data.output` so
 * stdout stays parseable.
 */

import { UsageError } from "../errors.mjs";
import { spawn } from "node:child_process";
import { lstat, readdir, stat } from "node:fs/promises";
import path from "node:path";
import { PackageError, PackageErrorCode } from "./_package-format.mjs";

export const definition = {
  name: "build",
  description: "Compile an extension project (tsc for TypeScript, xcodebuild for Swift) with live output",
  usage: `swiftcode build [dir] [--json] [--project <path>] [--scheme <name>]

Compiles the extension project in [dir] (default: current directory):

  - TypeScript (tsconfig.json present): runs 'tsc -p tsconfig.json' with
    live output. The compiler is resolved as <dir>/node_modules/.bin/tsc,
    then a PATH 'tsc', then 'npx --no-install tsc'.
  - Swift (*.xcodeproj, *.xcworkspace, Package.swift, or *.swift sources):
    runs 'xcodebuild' (Release). --project selects the project file when
    several exist; --scheme selects the scheme (default: first scheme from
    'xcodebuild -list -json'). When xcodebuild is not on this machine the
    command fails honestly instead of faking a build.

Exit 0 when the compiler exits 0; exit 1 with the real compiler failure
otherwise. Nothing is reported as built until the compiler confirms it.

Options:
  --json            machine-readable output (compiler output captured in data.output)
  --project <path>  xcodebuild project/workspace (Swift only)
  --scheme <name>   xcodebuild scheme (Swift only)`,
};

function isJson(args) {
  return args.json === true || args.json === "true";
}

/**
 * Run a child process. Resolves { code, output, spawnError } — never
 * rejects on a bad exit code. When capture is false, the child's stdio is
 * inherited so output streams live.
 */
export function runCompiler(cmd, argv, cwd, capture) {
  return new Promise((resolve) => {
    let child;
    try {
      child = spawn(cmd, argv, {
        cwd,
        stdio: capture ? ["ignore", "pipe", "pipe"] : "inherit",
      });
    } catch (error) {
      resolve({ code: -1, output: "", spawnError: error });
      return;
    }
    let output = "";
    if (capture) {
      child.stdout.on("data", (d) => {
        output += d.toString();
      });
      child.stderr.on("data", (d) => {
        output += d.toString();
      });
    }
    child.on("error", (error) => resolve({ code: -1, output, spawnError: error }));
    child.on("close", (code) => resolve({ code: code ?? -1, output }));
  });
}

async function exists(p) {
  try {
    await stat(p);
    return true;
  } catch {
    return false;
  }
}

/** Resolve the TypeScript compiler for dir: [displayName, cmd, argv]. */
export async function findTypeScriptCompiler(dir) {
  const localTsc = path.join(dir, "node_modules", ".bin", "tsc");
  if (await exists(localTsc)) {
    return { display: localTsc, cmd: localTsc, argv: ["-p", "tsconfig.json"] };
  }
  return null; // PATH tsc / npx are probed by spawn (ENOENT → next candidate)
}

/**
 * Compile TypeScript sources in dir.
 * Returns { compiler, code, output }. Throws PackageError(COMPILER_NOT_FOUND)
 * when no compiler exists; the caller decides how to report a bad exit code.
 */
export async function compileTypeScript(dir, { capture = false } = {}) {
  const candidates = [];
  const local = await findTypeScriptCompiler(dir);
  if (local) candidates.push(local);
  candidates.push({ display: "tsc (PATH)", cmd: "tsc", argv: ["-p", "tsconfig.json"] });
  candidates.push({
    display: "npx --no-install tsc",
    cmd: "npx",
    argv: ["--no-install", "tsc", "-p", "tsconfig.json"],
  });

  let lastSpawnError = null;
  for (const candidate of candidates) {
    const result = await runCompiler(candidate.cmd, candidate.argv, dir, capture);
    if (result.spawnError) {
      lastSpawnError = result.spawnError;
      continue; // compiler not present at this candidate — try the next
    }
    return { compiler: candidate.display, code: result.code, output: result.output };
  }
  throw new PackageError(
    PackageErrorCode.COMPILER_NOT_FOUND,
    `no TypeScript compiler found for ${dir} (checked ${dir}/node_modules/.bin/tsc, ` +
      `a PATH 'tsc', and 'npx --no-install tsc'${
        lastSpawnError ? `: ${lastSpawnError.message ?? String(lastSpawnError)}` : ""
      }) — run "npm install" in the project or install typescript; nothing was compiled`
  );
}

const PRUNE_DIRS = new Set(["node_modules", ".git", "dist", ".build"]);

/** True when dir looks like a Swift project (xcodeproj/workspace/Package.swift/*.swift). */
export async function looksLikeSwiftProject(dir) {
  let top;
  try {
    top = await readdir(dir, { withFileTypes: true });
  } catch {
    return false;
  }
  for (const entry of top) {
    const name = entry.name;
    if (
      name.endsWith(".xcodeproj") ||
      name.endsWith(".xcworkspace") ||
      name === "Package.swift"
    ) {
      return true;
    }
  }
  // Bounded recursive search for *.swift sources (pruned).
  const stack = [dir];
  while (stack.length > 0) {
    const current = stack.pop();
    let entries;
    try {
      entries = await readdir(current, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const entry of entries) {
      if (entry.name.endsWith(".swift") && entry.isFile()) return true;
      if (entry.isDirectory() && !entry.isSymbolicLink() && !PRUNE_DIRS.has(entry.name)) {
        stack.push(path.join(current, entry.name));
      }
    }
  }
  return false;
}

async function xcodebuildAvailable() {
  const result = await runCompiler("xcodebuild", ["-version"], process.cwd(), true);
  return !result.spawnError && result.code === 0;
}

async function resolveXcodeProject(dir, projectArg) {
  if (projectArg !== undefined) {
    const p = path.resolve(dir, projectArg);
    if (!(await exists(p))) throw new Error(`xcodebuild project not found: ${p}`);
    return p;
  }
  const top = await readdir(dir, { withFileTypes: true });
  const projects = top
    .filter((e) => e.name.endsWith(".xcodeproj") || e.name.endsWith(".xcworkspace"))
    .map((e) => path.join(dir, e.name));
  if (projects.length === 0) throw new Error(`no .xcodeproj or .xcworkspace in ${dir} (pass --project)`);
  if (projects.length > 1) {
    throw new Error(
      `multiple Xcode projects in ${dir} (${projects.map((p) => path.basename(p)).join(", ")}) — pass --project to choose`
    );
  }
  return projects[0];
}

async function resolveScheme(projectPath) {
  const result = await runCompiler("xcodebuild", ["-list", "-json", "-project", projectPath], path.dirname(projectPath), true);
  if (result.spawnError || result.code !== 0) return null;
  try {
    const parsed = JSON.parse(result.output);
    const schemes = parsed?.project?.schemes;
    if (Array.isArray(schemes) && schemes.length > 0) return schemes[0];
  } catch {
    /* fall through */
  }
  return null;
}

async function buildSwift(dir, { capture, projectArg, schemeArg }) {
  if (!(await xcodebuildAvailable())) {
    throw new PackageError(
      PackageErrorCode.XCODEBUILD_UNAVAILABLE,
      `xcodebuild is not available on this machine (looked for xcodebuild on PATH) — ` +
        `Swift builds require macOS with Xcode; nothing was compiled`
    );
  }
  const projectPath = await resolveXcodeProject(dir, projectArg);
  const scheme = schemeArg ?? (await resolveScheme(projectPath));
  const argv = projectPath.endsWith(".xcworkspace")
    ? ["-workspace", projectPath]
    : ["-project", projectPath];
  if (scheme) argv.push("-scheme", scheme);
  argv.push("-configuration", "Release", "build");
  const display = `xcodebuild ${argv.join(" ")}`;
  const result = await runCompiler("xcodebuild", argv, dir, capture);
  if (result.spawnError) {
    throw new PackageError(
      PackageErrorCode.BUILD_FAILED,
      `could not launch xcodebuild: ${result.spawnError.message ?? String(result.spawnError)}`
    );
  }
  return { compiler: display, code: result.code, output: result.output };
}

function checkBuildResult(compiler, result, json) {
  if (result.code !== 0) {
    const output = json && result.output.trim() !== "" ? `\n${result.output.trim().slice(0, 4000)}` : "";
    throw new PackageError(
      PackageErrorCode.BUILD_FAILED,
      `compilation failed (${compiler} exited with code ${result.code})${output}`
    );
  }
}

export async function run(args, ctx) {
  if (args._.length > 1) throw new UsageError("too many arguments");
  const json = isJson(args);
  for (const key of ["project", "scheme"]) {
    if (args[key] !== undefined && (typeof args[key] !== "string" || args[key].trim() === "")) {
      throw new UsageError(`--${key} requires a value`);
    }
  }
  for (const key of Object.keys(args)) {
    if (key !== "_" && key !== "json" && key !== "project" && key !== "scheme") {
      throw new UsageError(`unknown flag --${key}`);
    }
  }

  const dirArg = args._[0] ?? ".";
  const dir = path.resolve(dirArg);
  let st;
  try {
    st = await stat(dir);
  } catch {
    throw new Error(`not a directory: ${dir}`);
  }
  if (!st.isDirectory()) throw new Error(`not a directory: ${dir}`);

  let result;
  let kind;
  if (await looksLikeSwiftProject(dir)) {
    kind = "swift";
    if (!json) ctx.log("Swift project detected — building with xcodebuild…");
    result = await buildSwift(dir, {
      capture: json,
      projectArg: args.project,
      schemeArg: args.scheme,
    });
  } else {
    kind = "typescript";
    let hasTsconfig = false;
    try {
      hasTsconfig = (await stat(path.join(dir, "tsconfig.json"))).isFile();
    } catch {
      hasTsconfig = false;
    }
    if (!hasTsconfig) {
      throw new Error(
        `no tsconfig.json and no Swift sources in ${dir} — nothing to compile`
      );
    }
    if (!json) ctx.log("compiling with tsc…");
    result = await compileTypeScript(dir, { capture: json });
  }

  checkBuildResult(result.compiler, result, json);

  if (!json) ctx.log("compilation succeeded");
  const data = { dir, kind, compiler: result.compiler };
  if (json) data.output = result.output;
  return { code: 0, data };
}
