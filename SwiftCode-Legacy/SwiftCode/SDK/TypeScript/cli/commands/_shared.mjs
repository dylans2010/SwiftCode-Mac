/**
 * _shared.mjs — shared helpers for the swiftcode CLI command modules.
 *
 * Mirrors the host-side Swift formats byte-for-byte where it matters:
 *   - extensionsRoot(): SWIFTCODE_EXTENSIONS_DIR (test hook) or
 *     ~/Library/Application Support/SwiftCode/Extensions
 *     (SDKExtensionRegistry.extensionsRoot).
 *   - Layout: <root>/<id>/<version>/
 *   - .sdk-install.json: exact field names of SDKInstalledExtension minus
 *     manifest (id, name, version, packageDigest, installPath, installedAt,
 *     updatedAt, enabled), compact JSON with sorted keys, ISO-8601 dates
 *     without fractional seconds (Swift JSONEncoder .iso8601 does not emit
 *     or parse fractional seconds), atomic write + 0600 permissions.
 *   - computeDigestOf(dir): byte-for-byte mirror of
 *     SDKExtensionRegistry.computeDigest(of:): sorted relative paths (UTF-8
 *     byte order); per entry: relative path + NUL + kind byte ('d'/'f'/'l')
 *     + NUL + content bytes (streamed file bytes / symlink destination
 *     string / nothing for dirs); .sdk-install.json excluded by last path
 *     component; the tree root itself excluded.
 *   - extractZip(): native ZIP reader (stored + deflate only) with path
 *     traversal rejection and unsafe-symlink rejection (spec §17).
 */

import { chmod, mkdir, readdir, readFile, rename, rm, symlink, writeFile } from "node:fs/promises";
import { createReadStream } from "node:fs";
import { promises as fsPromises } from "node:fs";
import { createHash } from "node:crypto";
import { inflateRawSync } from "node:zlib";
import os from "node:os";
import path from "node:path";

// ---------------------------------------------------------------------------
// Paths
// ---------------------------------------------------------------------------

export const METADATA_FILE = ".sdk-install.json";
export const MANIFEST_FILE = "swiftcode.json";

/** Controlled extensions directory. Honors SWIFTCODE_EXTENSIONS_DIR (tests). */
export function extensionsRoot() {
  const override = process.env.SWIFTCODE_EXTENSIONS_DIR;
  if (override && override.trim() !== "") return path.resolve(override);
  return path.join(os.homedir(), "Library", "Application Support", "SwiftCode", "Extensions");
}

export function versionDir(id, version) {
  return path.join(extensionsRoot(), id, version);
}

// ---------------------------------------------------------------------------
// Errors / arg parsing / dates
//
// Command modules throw UsageError (from ../errors.mjs) for malformed
// invocations (dispatcher → exit 2) and plain Error for operational
// failures (dispatcher → exit 1). This shared module only throws plain
// Error; commands translate to UsageError where appropriate.
// ---------------------------------------------------------------------------

/**
 * Parse argv tokens (command name already removed) into
 * { positional: string[], flags: Record<string, true|string> }.
 * Supports --flag, --flag value, --flag=value. Single-dash tokens are
 * rejected to keep the surface explicit.
 *
 * `spec` declares which flags are boolean (never consume a following
 * value) and which take a string value:
 *   parseArgs(argv, { booleans: ["update", "json"], strings: ["version"] })
 * Undeclared --flags are still parsed (as boolean) so the caller can
 * reject them with "unknown flag".
 */
export function parseArgs(argv, spec = {}) {
  const booleans = new Set(spec.booleans ?? []);
  const strings = new Set(spec.strings ?? []);
  const positional = [];
  const flags = {};
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (token.startsWith("--")) {
      const eq = token.indexOf("=");
      const name = token.slice(2, eq === -1 ? undefined : eq);
      if (eq !== -1) {
        if (booleans.has(name)) throw new Error(`flag --${name} takes no value`);
        flags[name] = token.slice(eq + 1);
        continue;
      }
      if (strings.has(name)) {
        const next = argv[i + 1];
        if (next === undefined || next.startsWith("-")) {
          throw new Error(`flag --${name} requires a value`);
        }
        flags[name] = next;
        i += 1;
        continue;
      }
      flags[name] = true; // boolean-declared or undeclared (caller rejects unknowns)
    } else if (token.startsWith("-") && token.length > 1) {
      throw new Error(`unexpected flag "${token}" (use --long-form flags)`);
    } else {
      positional.push(token);
    }
  }
  return { positional, flags };
}

/** ISO-8601 with seconds precision, matching Swift JSONEncoder .iso8601. */
export function isoDate(date = new Date()) {
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

export function backupTimestamp(date = new Date()) {
  return date.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
  // e.g. 20261012T201914Z
}

/**
 * Normalize the dispatcher's parsed-args object (or, for direct harnesses,
 * a raw argv array) into { positionals, flags }.
 */
export function normalizeArgs(args, spec = {}) {
  if (Array.isArray(args)) return parseArgs(args, spec);
  const { _ = [], ...rest } = args ?? {};
  return { positionals: [..._], flags: { ...rest } };
}

// ---------------------------------------------------------------------------
// .sdk-install.json records
// ---------------------------------------------------------------------------

const RECORD_FIELDS = ["id", "name", "version", "packageDigest", "installPath", "installedAt", "updatedAt", "enabled"];

function sortedKeysRecord(record) {
  const out = {};
  for (const key of RECORD_FIELDS) out[key] = record[key];
  return out;
}

function validateRecordShape(record, filePath) {
  if (typeof record !== "object" || record === null || Array.isArray(record)) {
    throw new Error(`install record at ${filePath} is not a JSON object`);
  }
  for (const key of ["id", "name", "version", "packageDigest", "installPath", "installedAt", "updatedAt"]) {
    if (typeof record[key] !== "string" || record[key] === "") {
      throw new Error(`install record at ${filePath} has a missing/invalid "${key}"`);
    }
  }
  if (typeof record.enabled !== "boolean") {
    throw new Error(`install record at ${filePath} has a missing/invalid "enabled" flag`);
  }
  if (!/^[0-9a-f]{64}$/.test(record.packageDigest)) {
    throw new Error(`install record at ${filePath} has a malformed packageDigest`);
  }
  return record;
}

/** Read and shape-validate .sdk-install.json; returns null when absent. */
export async function readRecord(dir) {
  const filePath = path.join(dir, METADATA_FILE);
  let data;
  try {
    data = await readFile(filePath, "utf8");
  } catch (error) {
    if (error && error.code === "ENOENT") return null;
    throw error;
  }
  let parsed;
  try {
    parsed = JSON.parse(data);
  } catch {
    throw new Error(`install record at ${filePath} is not valid JSON`);
  }
  return validateRecordShape(parsed, filePath);
}

/**
 * Atomic, 0600 write of the install record with sorted keys (mirrors
 * SDKExtensionRegistry.recordInstall). updatedAt is caller-owned:
 * enable/disable leave it untouched.
 */
export async function writeRecord(dir, record) {
  const filePath = path.join(dir, METADATA_FILE);
  const data = JSON.stringify(sortedKeysRecord(record));
  const tmpPath = path.join(dir, `.${process.pid}.${Date.now()}.tmp`);
  await writeFile(tmpPath, data, "utf8");
  await chmod(tmpPath, 0o600);
  await rename(tmpPath, filePath);
  await chmod(filePath, 0o600);
}

// ---------------------------------------------------------------------------
// Canonical digest (mirror of SDKExtensionRegistry.computeDigest(of:))
// ---------------------------------------------------------------------------

const EXCLUDED_BASENAMES = new Set([METADATA_FILE]);
const KIND_DIR = 0x64; // 'd'
const KIND_FILE = 0x66; // 'f'
const KIND_LINK = 0x6c; // 'l'
const NUL = Buffer.from([0]);

/** Byte-order comparison on UTF-8 bytes (closest to Swift String.sorted for paths). */
function byteCompare(a, b) {
  return Buffer.compare(Buffer.from(a, "utf8"), Buffer.from(b, "utf8"));
}

/** Collect relative paths ("/"-joined) of every entry under root, unsorted. */
async function collectRelativePaths(root, excludeBasenames = EXCLUDED_BASENAMES) {
  const out = [];
  async function walk(currentRel) {
    const abs = path.join(root, currentRel);
    const entries = await readdir(abs, { withFileTypes: true });
    for (const entry of entries) {
      const rel = currentRel === "" ? entry.name : `${currentRel}/${entry.name}`;
      if (excludeBasenames.has(entry.name)) continue; // host metadata, not content
      out.push(rel);
      // Do not descend into symlinked directories (mirrors FileManager enumerator).
      if (entry.isDirectory() && !entry.isSymbolicLink()) {
        await walk(rel);
      }
    }
  }
  await walk("");
  return out;
}

/**
 * Canonical SHA-256 hex digest of a directory tree.
 * Byte layout per entry (sorted relative-path order):
 *   relativePath (UTF-8) + NUL + kindByte ('d'|'f'|'l') + NUL + content
 * where content = streamed file bytes | symlink destination string | nothing.
 *
 * options.excludeBasenames: extra basenames to skip (in addition to the
 * host-metadata set). Used by the packager/verifier to exclude the embedded
 * digest record (swiftcode-digest.json) from the content digest it records.
 */
export async function computeDigestOf(dir, options = {}) {
  let stat;
  try {
    stat = await fsPromises.stat(dir);
  } catch {
    throw new Error(`cannot compute digest: directory missing: ${dir}`);
  }
  if (!stat.isDirectory()) throw new Error(`cannot compute digest: not a directory: ${dir}`);

  const extra = options.excludeBasenames ?? [];
  const exclude =
    extra.length === 0 ? EXCLUDED_BASENAMES : new Set([...EXCLUDED_BASENAMES, ...extra]);

  const root = path.resolve(dir);
  const relatives = (await collectRelativePaths(root, exclude)).sort(byteCompare);
  const hash = createHash("sha256");

  for (const rel of relatives) {
    const abs = path.join(root, rel);
    const lst = await fsPromises.lstat(abs);
    let kind;
    if (lst.isSymbolicLink()) kind = KIND_LINK;
    else if (lst.isFile()) kind = KIND_FILE;
    else kind = KIND_DIR;

    hash.update(Buffer.from(rel, "utf8"));
    hash.update(NUL);
    hash.update(Buffer.from([kind]));
    hash.update(NUL);

    if (kind === KIND_FILE) {
      await new Promise((resolve, reject) => {
        const stream = createReadStream(abs, { highWaterMark: 10 * 1024 * 1024 });
        stream.on("data", (chunk) => hash.update(chunk));
        stream.on("end", resolve);
        stream.on("error", reject);
      });
    } else if (kind === KIND_LINK) {
      const target = await fsPromises.readlink(abs);
      hash.update(Buffer.from(target, "utf8"));
    }
  }
  return hash.digest("hex");
}

// ---------------------------------------------------------------------------
// Native ZIP extraction (stored + deflate), with traversal/unsafe-link guards
// ---------------------------------------------------------------------------

const ZIP_SIG_LOCAL = 0x04034b50;
const ZIP_SIG_CENTRAL = 0x02014b50;
const ZIP_SIG_EOCD = 0x06054b50;
const MAX_ZIP_BYTES = 256 * 1024 * 1024;

function readU16LE(buf, off) {
  return buf.readUInt16LE(off);
}
function readU32LE(buf, off) {
  return buf.readUInt32LE(off);
}

/** Reject entry names that could escape the extraction root. Returns normalized name. */
function sanitizeEntryName(raw) {
  if (typeof raw !== "string" || raw.length === 0) throw new Error("zip entry with empty name");
  if (raw.includes("\0")) throw new Error("zip entry name contains NUL");
  const name = raw.replace(/\\/g, "/");
  if (name.startsWith("/") || /^[A-Za-z]:/.test(name)) {
    throw new Error(`zip entry is absolute: ${raw}`);
  }
  const segments = name.split("/");
  for (const seg of segments) {
    if (seg === "..") throw new Error(`zip entry escapes its directory: ${raw}`);
  }
  // Drop empty segments (e.g. "a//b", "./x") — same as a lexical clean.
  const clean = segments.filter((s) => s !== "" && s !== ".").join("/");
  if (clean === "") throw new Error(`zip entry has no usable name: ${raw}`);
  return clean;
}

function parseCentralDirectory(buf) {
  // Locate EOCD in the last 64 KiB + 22 bytes.
  const tailSize = Math.min(buf.length, 65557);
  let eocd = -1;
  for (let i = buf.length - 22; i >= buf.length - tailSize; i -= 1) {
    if (readU32LE(buf, i) === ZIP_SIG_EOCD) {
      eocd = i;
      break;
    }
  }
  if (eocd === -1) throw new Error("not a zip archive (end-of-central-directory not found)");

  const diskNumber = readU16LE(buf, eocd + 4);
  const cdDisk = readU16LE(buf, eocd + 6);
  const cdCountDisk = readU16LE(buf, eocd + 8);
  const cdCount = readU16LE(buf, eocd + 10);
  const cdSize = readU32LE(buf, eocd + 12);
  const cdOffset = readU32LE(buf, eocd + 16);
  if (diskNumber !== 0 || cdDisk !== 0 || cdCountDisk !== cdCount) {
    throw new Error("multi-disk zip archives are not supported");
  }
  if (cdCount === 0xffff || cdSize === 0xffffffff || cdOffset === 0xffffffff) {
    throw new Error("zip64 archives are not supported");
  }

  const entries = [];
  let off = cdOffset;
  for (let i = 0; i < cdCount; i += 1) {
    if (readU32LE(buf, off) !== ZIP_SIG_CENTRAL) {
      throw new Error(`corrupt zip central directory at entry ${i}`);
    }
    const flags = readU16LE(buf, off + 8);
    const method = readU16LE(buf, off + 10);
    const nameLen = readU16LE(buf, off + 28);
    const extraLen = readU16LE(buf, off + 30);
    const commentLen = readU16LE(buf, off + 32);
    const externalAttrs = readU32LE(buf, off + 38);
    const localOffset = readU32LE(buf, off + 42);
    const compSize = readU32LE(buf, off + 20);
    if (flags & 0x1) throw new Error("encrypted zip entries are not supported");
    if (method !== 0 && method !== 8) {
      throw new Error(`unsupported zip compression method ${method} (only stored/deflate)`);
    }
    if (localOffset === 0xffffffff || compSize === 0xffffffff) {
      throw new Error("zip64 archives are not supported");
    }
    const name = buf.toString("utf8", off + 46, off + 46 + nameLen);
    const unixMode = externalAttrs >>> 16;
    entries.push({ name, method, compSize, localOffset, unixMode, encrypted: false });
    off += 46 + nameLen + extraLen + commentLen;
  }
  return entries;
}

function readEntryData(buf, entry) {
  const off = entry.localOffset;
  if (readU32LE(buf, off) !== ZIP_SIG_LOCAL) {
    throw new Error(`corrupt zip local header for entry ${entry.name}`);
  }
  const flags = readU16LE(buf, off + 6);
  if (flags & 0x1) throw new Error("encrypted zip entries are not supported");
  const method = readU16LE(buf, off + 8);
  if (method !== 0 && method !== 8) {
    throw new Error(`unsupported zip compression method ${method} (only stored/deflate)`);
  }
  const nameLen = readU16LE(buf, off + 26);
  const extraLen = readU16LE(buf, off + 28);
  const dataStart = off + 30 + nameLen + extraLen;
  const dataEnd = dataStart + entry.compSize;
  if (dataEnd > buf.length) throw new Error(`zip entry data out of bounds: ${entry.name}`);
  const raw = buf.subarray(dataStart, dataEnd);
  return method === 0 ? Buffer.from(raw) : inflateRawSync(raw);
}

/**
 * Extract a .swiftcode-extension (zip) into destDir.
 * Rejects absolute entries, ".." segments, encrypted/zip64 archives,
 * methods other than stored/deflate, duplicate entries, and symlinks whose
 * resolved target escapes destDir (spec §17: reject unsafe symlinks).
 * Returns the extracted entry list for testing.
 */
export async function extractZip(zipPath, destDir) {
  let stat;
  try {
    stat = await fsPromises.stat(zipPath);
  } catch {
    throw new Error(`package file not found: ${zipPath}`);
  }
  if (stat.size > MAX_ZIP_BYTES) throw new Error("package exceeds the 256 MiB size limit");
  const buf = await readFile(zipPath);
  const entries = parseCentralDirectory(buf);

  await mkdir(destDir, { recursive: true });
  const extracted = [];

  // Pass 1: validate every name up front so a bad entry fails before any write.
  const sanitized = entries.map((entry) => ({ entry, name: sanitizeEntryName(entry.name) }));
  const seen = new Set();
  for (const { name } of sanitized) {
    const key = name.toLowerCase();
    if (seen.has(key)) throw new Error(`duplicate zip entry: ${name}`);
    seen.add(key);
  }

  // Pass 2: create directories.
  for (const { name } of sanitized) {
    if (name.endsWith("/")) {
      await mkdir(path.join(destDir, name), { recursive: true });
      extracted.push({ name: name.slice(0, -1), kind: "dir" });
    }
  }
  // Pass 3: files and symlinks.
  for (const { entry, name } of sanitized) {
    if (name.endsWith("/")) continue;
    const abs = path.join(destDir, name);
    const data = readEntryData(buf, entry);
    const unixMode = entry.unixMode;
    const isSymlink = (unixMode & 0o170000) === 0o120000;
    await mkdir(path.dirname(abs), { recursive: true });
    if (isSymlink) {
      const target = data.toString("utf8");
      if (target === "") throw new Error(`zip symlink has an empty target: ${name}`);
      // Unsafe-symlink rejection: the resolved target must stay inside destDir.
      const resolved = path.resolve(path.dirname(abs), target);
      const rootResolved = path.resolve(destDir);
      if (resolved !== rootResolved && !resolved.startsWith(rootResolved + path.sep)) {
        throw new Error(`zip symlink escapes the package: ${name} -> ${target}`);
      }
      await symlink(target, abs);
      extracted.push({ name, kind: "symlink", target });
    } else {
      await writeFile(abs, data);
      extracted.push({ name, kind: "file", bytes: data.length });
    }
  }
  return extracted;
}

// ---------------------------------------------------------------------------
// Filesystem moves
// ---------------------------------------------------------------------------

/** Move a directory tree into place (rename; falls back to copy on EXDEV). */
export async function moveDir(src, dest) {
  try {
    await rename(src, dest);
  } catch (error) {
    if (!error || error.code !== "EXDEV") throw error;
    await copyDir(src, dest);
    await rm(src, { recursive: true, force: true });
  }
}

async function copyDir(src, dest) {
  await mkdir(dest, { recursive: true });
  const entries = await readdir(src, { withFileTypes: true });
  for (const entry of entries) {
    const s = path.join(src, entry.name);
    const d = path.join(dest, entry.name);
    if (entry.isSymbolicLink()) {
      await symlink(await fsPromises.readlink(s), d);
    } else if (entry.isDirectory()) {
      await copyDir(s, d);
    } else {
      await fsPromises.copyFile(s, d);
    }
  }
}

/** Best-effort removal of a temp dir (never throws). */
export async function removeQuietly(p) {
  try {
    await rm(p, { recursive: true, force: true });
  } catch {
    /* ignored */
  }
}
