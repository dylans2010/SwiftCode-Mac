/**
 * package.mjs — `swiftcode package [dir] [--out <dir>] [--json]`
 *
 * Builds (if needed) and packages an extension or app into a deterministic
 * `.swiftcode-extension` zip archive (spec §17; format documented in
 * SwiftCode/SDK/Documentation/Package-Format.md):
 *
 *   1. Validate the manifest + package checks first (validate.mjs).
 *      Any failure → exit 1, no package is produced.
 *   2. Require node_modules (else tell the user to run `npm install` first).
 *   3. Ensure dist/ is built; if missing, compile with the shared
 *      TypeScript build (build.mjs — local .bin/tsc, PATH tsc, then
 *      `npx --no-install tsc`; never a silent download).
 *   4. Collect the shippable set: swiftcode.json, dist/**, schemas/**,
 *      README.md, package.json — excluding node_modules/, .env*,
 *      *.tsbuildinfo, and version-control droppings (.git/, .gitignore…).
 *   5. Stage the shippable set into a private temp dir (contained
 *      symlinks are materialized as regular files, exactly as archived).
 *   6. Compute the canonical content digest over the staged tree
 *      (SHA-256 over the canonicalized contents, same byte layout the
 *      host registry uses) and embed it as `swiftcode-digest.json` in
 *      the archive, so `install` can detect any post-packaging tampering
 *      with a typed DIGEST_MISMATCH error.
 *   7. Write a DETERMINISTIC zip: entries sorted by name, fixed mtime
 *      (2000-01-01T00:00:00Z), fixed file mode (0644), fixed deflate
 *      level. Zip entries embed mtimes/modes, so without fixing them
 *      every build would hash differently; fixing them makes the
 *      archive byte-reproducible and the sha256 digest stable.
 *   8. sha256 the finished file and print path + digest ONLY after the
 *      archive has closed successfully — never before.
 *
 * No secrets are ever printed; only paths, counts, and digests.
 */

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
SwiftCode/SDK/Documentation/Package-Format.md):

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

// Fixed mtime for every zip entry. Zip entries embed modification times
// (and modes); fixing them — along with sorted entry order and a fixed
// compression level — is what makes the archive byte-reproducible, so the
// reported sha256 digest is stable across runs and machines.
const FIXED_DATE = new Date("2000-01-01T00:00:00Z");
const FIXED_MODE = 0o644;

// Shippable roots: [relative path, recursive?]
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

/**
 * Collect the shippable file set: [{ rel, abs, viaSymlink }].
 * rel uses forward slashes. Throws on unsafe symlinks (defense in depth —
 * validate already rejects them before we get here).
 */
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
      if (st.isDirectory()) return; // never ship symlinked directories
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
      continue; // optional root (schemas/, README.md may be absent)
    }
    if (lst.isSymbolicLink()) {
      await addFile(abs, name);
    } else if (lst.isDirectory() && recursive) {
      await walk(abs, name);
    } else if (lst.isFile() && !recursive) {
      files.push({ rel: name, abs, viaSymlink: false });
    }
  }

  // Deterministic order: byte-wise by archive name.
  files.sort((a, b) => (a.rel < b.rel ? -1 : a.rel > b.rel ? 1 : 0));

  // Final safety assertions — these can never trigger given the walk above,
  // but a packager must fail closed rather than ship something unexpected.
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

/**
 * Copy the shippable set into a private staging dir, materializing
 * contained symlinks as regular files — exactly what the archive will
 * contain, so the content digest computed over the staging dir matches
 * what `install` recomputes over the extracted tree.
 */
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

/** Walk the staging dir; return [{ rel, abs, stats }] sorted byte-wise. */
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

/** Create the deterministic zip. Resolves with { bytes } once closed. */
async function createArchive(entries, outPath) {
  await mkdir(path.dirname(outPath), { recursive: true });
  // archiver v8: instantiate the format class directly (no factory function).
  const archive = new ZipArchive({ zlib: { level: 9 } });
  const outStream = createWriteStream(outPath);

  const done = new Promise((resolve, reject) => {
    outStream.on("close", resolve);
    outStream.on("error", reject);
    archive.on("error", reject);
    // archiver "warning" = entry skipped (e.g. stat race) — fail loudly
    // instead of shipping a silently incomplete package.
    archive.on("warning", reject);
  });

  archive.pipe(outStream);
  for (const e of entries) {
    // `stats` is passed on every file() call so archiver skips its
    // concurrent stat queue and keeps entries in the sorted call order
    // (stat completion order would otherwise race and break determinism).
    // The explicit numeric mode wins over stats.mode (archiver core
    // _normalizeEntryData), so modes stay fixed at 0644.
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

  // (a) Validate first — fail before producing anything.
  // checkEntrypointExists is false here: dist/ may not be built yet; the
  // entrypoint is verified again after the build step below.
  const pre = await validateExtension(root, { checkEntrypointExists: false });
  if (!pre.valid) {
    const manifestPath = path.join(root, "swiftcode.json");
    ctx.error(formatValidationReport(manifestPath, pre.problems, pre.warnings));
    return { code: 1, data: { valid: false, problems: pre.problems, warnings: pre.warnings } };
  }
  const manifest = pre.manifest;

  // (b) Dependencies must be installed before we can build.
  let hasNodeModules = false;
  try {
    hasNodeModules = (await stat(path.join(root, "node_modules"))).isDirectory();
  } catch {
    hasNodeModules = false;
  }
  if (!hasNodeModules) {
    throw new Error(`node_modules not found in ${root} — run "npm install" there first`);
  }

  // (c) Ensure dist/ is built.
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

  // The entrypoint must exist now that dist/ is ensured.
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

  // (d) Collect the shippable set, stage it, digest it, archive it.
  const files = await collectFiles(root);
  if (files.length === 0) {
    throw new Error(`nothing to package in ${root}`);
  }
  const slug = String(manifest.id).split(".").pop();
  const outPath = path.join(outDir, `${slug}-${manifest.version}.swiftcode-extension`);

  const staging = await mkdtemp(path.join(os.tmpdir(), "swiftcode-package-"));
  try {
    await stageFiles(files, staging);

    // Canonical content digest over the staged tree, excluding the digest
    // record itself (it is written next). `install` recomputes this exact
    // value over the extracted tree — any tampered byte breaks the match.
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
      // Digest ONLY after the archive closed successfully.
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
      // Never leave a partial archive behind looking like a finished package.
      await rm(outPath, { force: true });
      throw new Error(`packaging failed: ${error.message ?? String(error)}`);
    }
  } finally {
    await removeQuietly(staging);
  }
}
