import { ZipArchive } from "archiver";
import { UsageError } from "../errors.mjs";
import { validateExtension, formatValidationReport } from "./validate.mjs";
import { compileTypeScript } from "./build.mjs";
import {
  DIGEST_FILE_NAME,
  PackageError,
  PackageErrorCode,
  makeDigestRecord,
  serializeDigestRecord,
} from "./_package-format.mjs";
import { computeDigestOf, removeQuietly } from "./_shared.mjs";
import { createHash } from "node:crypto";
import { createWriteStream } from "node:fs";
import { lstat, mkdir, mkdtemp, readdir, readFile, realpath, rm, stat, copyFile, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";

export const definition = {
  name: "package",
  description: "Build and package an extension/app into a deterministic .swiftcode-extension archive",
  usage: `swiftcode package [dir] [--out <dir>] [--json]

Packages the extension or app in [dir] (default: current directory) into
a deterministic .swiftcode-extension archive (spec §17; format details in
sdk/docs/Package-Format.md):

  1. validates swiftcode.json + package checks (same as 'swiftcode validate');
     any failure aborts with exit 1 and no package is produced
  2. requires node_modules/ (run "npm install" in the extension dir first)
  3. builds dist/ with the TypeScript compiler when it is missing
  4. stages swiftcode.json, dist/**, schemas/**, README.md, package.json —
     never node_modules/, .env files, *.tsbuildinfo, or .git droppings
  5. computes the canonical content digest (SHA-256 over the canonicalized
     staged contents) and embeds it as swiftcode-digest.json, so
     'swiftcode install' rejects tampered packages with a typed
     DIGEST_MISMATCH error
  6. the archive is deterministic: entries sorted by name, fixed mtime
     (2000-01-01T00:00:00Z), fixed mode, fixed compression — packaging
     the same tree twice yields byte-identical output
  7. writes <id-slug>-<version>.swiftcode-extension to --out
     (default: <dir>/dist-package/), then prints the path and its
     sha256 digest — only after the archive closes successfully

Options:
  --out <dir>   output directory (created if needed)
  --json        machine-readable output (the dispatcher wraps the result)`,
};

const FIXED_DATE = new Date("2000-01-01T00:00:00Z");
const FIXED_MODE = 0o644;

const INCLUDE_ROOTS = [
  ["swiftcode.json", false],
  ["dist", true],
  ["schemas", true],
  ["README.md", false],
  ["package.json", false],
];

const PRUNE_SEGMENTS = new Set(["node_modules", ".git"]);
const SKIP_BASENAMES = new Set([".DS_Store", ".gitignore", ".gitattributes"]);
const ENV_BASENAME_RE = /^\.env(\.|$)/;
const TSBUILDINFO_RE = /\.tsbuildinfo$/;

function isJson(args) {
  return args.json === true || args.json === "true";
}

function shouldSkip(basename) {
  return (
    SKIP_BASENAMES.has(basename) || ENV_BASENAME_RE.test(basename) || TSBUILDINFO_RE.test(basename)
  );
}

function isWithinRoot(root, target) {
  const resolved = path.resolve(target);
  return resolved === root || resolved.startsWith(root + path.sep);
}

async function collectFiles(root) {
  const files = [];

  async function addFile(abs, rel) {
    const lst = await lstat(abs);
    if (lst.isSymbolicLink()) {
      const resolved = await realpath(abs);
      if (!isWithinRoot(root, resolved)) {
        throw new Error(`refusing to package: symlink escapes the package root: ${rel}`);
      }
      const st = await stat(resolved);
      if (st.isDirectory()) return;
      files.push({ rel, abs: resolved, viaSymlink: true });
      return;
    }
    if (!lst.isFile()) return;
    files.push({ rel, abs, viaSymlink: false });
  }

  async function walk(abs, rel) {
    const entries = await readdir(abs, { withFileTypes: true });
    for (const entry of entries) {
      if (PRUNE_SEGMENTS.has(entry.name)) continue;
      if (shouldSkip(entry.name)) continue;
      const entryAbs = path.join(abs, entry.name);
      const entryRel = `${rel}/${entry.name}`;
      const lst = await lstat(entryAbs);
      if (lst.isSymbolicLink()) {
        await addFile(entryAbs, entryRel);
      } else if (lst.isDirectory()) {
        await walk(entryAbs, entryRel);
      } else if (lst.isFile()) {
        files.push({ rel: entryRel, abs: entryAbs, viaSymlink: false });
      }
    }
  }

  for (const [name, recursive] of INCLUDE_ROOTS) {
    const abs = path.join(root, name);
    let lst;
    try {
      lst = await lstat(abs);
    } catch {
      continue;
    }
    if (lst.isSymbolicLink()) {
      await addFile(abs, name);
    } else if (lst.isDirectory() && recursive) {
      await walk(abs, name);
    } else if (lst.isFile() && !recursive) {
      files.push({ rel: name, abs, viaSymlink: false });
    }
  }

  files.sort((a, b) => (a.rel < b.rel ? -1 : a.rel > b.rel ? 1 : 0));

  for (const f of files) {
    if (f.rel.startsWith("/") || f.rel.includes("\\") || f.rel.split("/").includes("..")) {
      throw new Error(`refusing to package: unsafe entry name: ${f.rel}`);
    }
    if (f.rel === "node_modules" || f.rel.startsWith("node_modules/")) {
      throw new Error(`refusing to package: node_modules content would be shipped: ${f.rel}`);
    }
    const base = f.rel.split("/").pop();
    if (ENV_BASENAME_RE.test(base)) {
      throw new Error(`refusing to package: secret-bearing file would be shipped: ${f.rel}`);
    }
    if (f.rel === DIGEST_FILE_NAME) {
      throw new Error(`refusing to package: source tree already contains ${DIGEST_FILE_NAME}`);
    }
  }
  return files;
}

async function stageFiles(files, staging) {
  for (const f of files) {
    const dest = path.join(staging, f.rel);
    await mkdir(path.dirname(dest), { recursive: true });
    if (f.viaSymlink) {
      await writeFile(dest, await readFile(f.abs));
    } else {
      await copyFile(f.abs, dest);
    }
  }
}

async function collectStagedEntries(staging) {
  const entries = [];
  async function walk(abs, rel) {
    const dirents = await readdir(abs, { withFileTypes: true });
    for (const dirent of dirents) {
      const entryAbs = path.join(abs, dirent.name);
      const entryRel = rel === "" ? dirent.name : `${rel}/${dirent.name}`;
      const lst = await lstat(entryAbs);
      if (lst.isDirectory() && !lst.isSymbolicLink()) {
        await walk(entryAbs, entryRel);
      } else if (lst.isFile() || lst.isSymbolicLink()) {
        entries.push({ rel: entryRel, abs: entryAbs, stats: lst });
      }
    }
  }
  await walk(staging, "");
  entries.sort((a, b) => (a.rel < b.rel ? -1 : a.rel > b.rel ? 1 : 0));
  return entries;
}

async function createArchive(entries, outPath) {
  await mkdir(path.dirname(outPath), { recursive: true });
  const archive = new ZipArchive({ zlib: { level: 9 } });
  const outStream = createWriteStream(outPath);

  const done = new Promise((resolve, reject) => {
    outStream.on("close", resolve);
    outStream.on("error", reject);
    archive.on("error", reject);
    archive.on("warning", reject);
  });

  archive.pipe(outStream);
  for (const e of entries) {
    archive.file(e.abs, { name: e.rel, date: FIXED_DATE, mode: FIXED_MODE, stats: e.stats });
  }
  await archive.finalize();
  await done;

  const { size } = await stat(outPath);
  return { bytes: size };
}

export async function run(args, ctx) {
  if (args._.length > 1) throw new UsageError("too many arguments");
  const json = isJson(args);

  const dirArg = args._[0] ?? ".";
  const root = path.resolve(dirArg);
  let st;
  try {
    st = await stat(root);
  } catch {
    throw new Error(`not a directory: ${root}`);
  }
  if (!st.isDirectory()) throw new Error(`not a directory: ${root}`);

  let outDir;
  if (args.out !== undefined) {
    if (typeof args.out !== "string" || args.out.trim() === "") {
      throw new UsageError("--out requires a directory path");
    }
    outDir = path.resolve(args.out);
  } else {
    outDir = path.join(root, "dist-package");
  }

  const pre = await validateExtension(root, { checkEntrypointExists: false });
  if (!pre.valid) {
    const manifestPath = path.join(root, "swiftcode.json");
    ctx.error(formatValidationReport(manifestPath, pre.problems, pre.warnings));
    return { code: 1, data: { valid: false, problems: pre.problems, warnings: pre.warnings } };
  }
  const manifest = pre.manifest;

  let hasNodeModules = false;
  try {
    hasNodeModules = (await stat(path.join(root, "node_modules"))).isDirectory();
  } catch {
    hasNodeModules = false;
  }
  if (!hasNodeModules) {
    throw new Error(`node_modules not found in ${root} — run "npm install" there first`);
  }

  let distIsDir = false;
  try {
    distIsDir = (await stat(path.join(root, "dist"))).isDirectory();
  } catch {
    distIsDir = false;
  }
  if (!distIsDir) {
    let hasTsconfig = false;
    try {
      hasTsconfig = (await stat(path.join(root, "tsconfig.json"))).isFile();
    } catch {
      hasTsconfig = false;
    }
    if (!hasTsconfig) {
      throw new Error(`no dist/ output and no tsconfig.json in ${root} — cannot compile the extension`);
    }
    if (!json) ctx.log("dist/ not found — compiling…");
    let result;
    try {
      result = await compileTypeScript(root, { capture: json });
    } catch (error) {
      if (error instanceof PackageError) throw error;
      throw new PackageError(
        PackageErrorCode.BUILD_FAILED,
        `could not launch the TypeScript compiler: ${error.message ?? String(error)}`
      );
    }
    if (result.code !== 0) {
      const output = json && result.output.trim() !== "" ? `\n${result.output.trim().slice(0, 4000)}` : "";
      throw new PackageError(
        PackageErrorCode.BUILD_FAILED,
        `TypeScript compilation failed (${result.compiler} exited with code ${result.code})${output}`
      );
    }
    if (!json) ctx.log("compilation succeeded");
  }

  const entrypoint = manifest.runtime.entrypoint;
  const entryAbs = path.join(root, entrypoint);
  try {
    const es = await stat(entryAbs);
    if (!es.isFile()) throw new Error(`entrypoint is not a file: ${entrypoint}`);
  } catch (error) {
    if (error instanceof Error && error.message.startsWith("entrypoint is not a file")) throw error;
    throw new PackageError(
      PackageErrorCode.ENTRYPOINT_MISSING,
      `entrypoint file not found after build: ${entrypoint} — the build did not produce it`
    );
  }

  const files = await collectFiles(root);
  if (files.length === 0) {
    throw new Error(`nothing to package in ${root}`);
  }
  const slug = String(manifest.id).split(".").pop();
  const outPath = path.join(outDir, `${slug}-${manifest.version}.swiftcode-extension`);

  const staging = await mkdtemp(path.join(os.tmpdir(), "swiftcode-package-"));
  try {
    await stageFiles(files, staging);

    const contentDigest = await computeDigestOf(staging, {
      excludeBasenames: [DIGEST_FILE_NAME],
    });
    const record = makeDigestRecord({
      id: manifest.id,
      version: manifest.version,
      kind: manifest.type,
      contentDigest,
    });
    await writeFile(path.join(staging, DIGEST_FILE_NAME), serializeDigestRecord(record), "utf8");

    const entries = await collectStagedEntries(staging);
    try {
      const { bytes } = await createArchive(entries, outPath);
      const digest = createHash("sha256").update(await readFile(outPath)).digest("hex");

      ctx.log(`packaged ${outPath}`);
      ctx.log(`sha256 ${digest}`);
      ctx.log(`content digest ${contentDigest}`);
      ctx.log(`${entries.length} files, ${bytes} bytes`);
      return {
        code: 0,
        data: { path: outPath, sha256: digest, contentDigest, files: entries.length, bytes },
      };
    } catch (error) {
      await rm(outPath, { force: true });
      throw new Error(`packaging failed: ${error.message ?? String(error)}`);
    }
  } finally {
    await removeQuietly(staging);
  }
}
