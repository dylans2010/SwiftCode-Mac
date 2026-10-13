/**
 * _package-format.mjs — the `.swiftcode-extension` package format, shared by
 * the `package` and `install` commands.
 *
 * Format (documented precisely in
 * SwiftCode/SDK/Documentation/Package-Format.md):
 *   - a ZIP archive (stored or deflate entries only; no encryption, no
 *     zip64, no multi-disk), entries sorted byte-wise by name, fixed mtime
 *     2000-01-01T00:00:00Z, fixed mode 0644 — byte-reproducible.
 *   - required entries: `swiftcode.json` (manifest), `swiftcode-digest.json`
 *     (embedded integrity record), `dist/**` (compiled output, including
 *     `runtime.entrypoint`); optional: `schemas/**`, `README.md`,
 *     `package.json`, other assets. Never `node_modules/`, `.env*`,
 *     `*.tsbuildinfo`, `.git/`, `.DS_Store`.
 *   - `swiftcode-digest.json` carries `contentDigest`: SHA-256 over the
 *     canonicalized package contents (see below), so tampering with any
 *     shipped byte is detectable without trusting the archive itself.
 *
 * Canonicalization (digest input): the exact byte layout of
 * `computeDigestOf` in `_shared.mjs` (which mirrors
 * `SDKExtensionRegistry.computeDigest(of:)` on the host): every entry of
 * the extracted tree, sorted by relative path (UTF-8 byte order),
 * excluding the digest record itself; per entry
 *   relativePath (UTF-8) + NUL + kindByte ('d'/'f'/'l') + NUL + content
 * where content is file bytes, the symlink destination string, or nothing
 * for directories.
 */

import { readFile } from "node:fs/promises";
import path from "node:path";
import { computeDigestOf } from "./_shared.mjs";

export const PACKAGE_SUFFIX = ".swiftcode-extension";
export const DIGEST_FILE_NAME = "swiftcode-digest.json";
export const MANIFEST_FILE_NAME = "swiftcode.json";
export const FORMAT_VERSION = 1;

/** Package kinds carried by the manifest `type` field (v1). */
export const PACKAGE_KINDS = ["extension", "app"];

// ---------------------------------------------------------------------------
// Typed errors
//
// Every package-format failure is a PackageError with a stable machine
// code — never a generic silent failure. The commands surface `code` in
// --json output and prefix the human-readable message with [CODE].
// ---------------------------------------------------------------------------

export const PackageErrorCode = {
  /** swiftcode-digest.json is absent from the package. */
  DIGEST_RECORD_MISSING: "DIGEST_RECORD_MISSING",
  /** swiftcode-digest.json exists but is not valid JSON / has a bad shape. */
  DIGEST_RECORD_MALFORMED: "DIGEST_RECORD_MALFORMED",
  /** Recomputed canonical digest != embedded contentDigest (tampering). */
  DIGEST_MISMATCH: "DIGEST_MISMATCH",
  /** Digest record id/version/kind disagree with swiftcode.json. */
  DIGEST_IDENTITY_MISMATCH: "DIGEST_IDENTITY_MISMATCH",
  /** swiftcode.json fails manifest-schema validation. */
  MANIFEST_INVALID: "MANIFEST_INVALID",
  /** swiftcode.json is missing or unreadable. */
  MANIFEST_UNREADABLE: "MANIFEST_UNREADABLE",
  /** The archive itself is not a readable zip. */
  ARCHIVE_UNREADABLE: "ARCHIVE_UNREADABLE",
  /** A zip entry is unsafe (absolute, "..", duplicate, bad method...). */
  ARCHIVE_UNSAFE_ENTRY: "ARCHIVE_UNSAFE_ENTRY",
  /** The declared runtime.entrypoint file is absent from the package. */
  ENTRYPOINT_MISSING: "ENTRYPOINT_MISSING",
  /** The id@version is already installed and --update was not given. */
  ALREADY_INSTALLED: "ALREADY_INSTALLED",
  /** A build step (tsc/xcodebuild) failed. */
  BUILD_FAILED: "BUILD_FAILED",
  /** No usable compiler found for the project language. */
  COMPILER_NOT_FOUND: "COMPILER_NOT_FOUND",
  /** Swift sources need xcodebuild, which is not on this machine. */
  XCODEBUILD_UNAVAILABLE: "XCODEBUILD_UNAVAILABLE",
};

export class PackageError extends Error {
  /**
   * @param {string} code one of PackageErrorCode
   * @param {string} message human-readable detail (no secrets)
   * @param {unknown} details optional structured detail (problems list, digests)
   */
  constructor(code, message, details = null) {
    super(`[${code}] ${message}`);
    this.name = "PackageError";
    this.code = code;
    this.details = details;
  }
}

// ---------------------------------------------------------------------------
// Digest record
// ---------------------------------------------------------------------------

/**
 * Build the canonical digest-record object for a manifest + content digest.
 * Field order is fixed (sorted keys) and the JSON is compact — the record
 * is deterministic: the same contents always serialize to the same bytes.
 */
export function makeDigestRecord({ id, version, kind, contentDigest }) {
  return {
    contentDigest,
    formatVersion: FORMAT_VERSION,
    id,
    kind,
    version,
  };
}

/** Serialize a digest record deterministically (UTF-8, no trailing newline). */
export function serializeDigestRecord(record) {
  return JSON.stringify(makeDigestRecord(record));
}

function isHex64(value) {
  return typeof value === "string" && /^[0-9a-f]{64}$/.test(value);
}

/**
 * Read and shape-check swiftcode-digest.json from an extracted package dir.
 * Throws PackageError DIGEST_RECORD_MISSING / DIGEST_RECORD_MALFORMED.
 */
export async function readDigestRecord(dir) {
  const filePath = path.join(dir, DIGEST_FILE_NAME);
  let raw;
  try {
    raw = await readFile(filePath, "utf8");
  } catch (error) {
    if (error && error.code === "ENOENT") {
      throw new PackageError(
        PackageErrorCode.DIGEST_RECORD_MISSING,
        `package is missing the embedded integrity record ${DIGEST_FILE_NAME} — it was not produced by 'swiftcode package' v1`
      );
    }
    throw new PackageError(
      PackageErrorCode.DIGEST_RECORD_MALFORMED,
      `cannot read ${DIGEST_FILE_NAME}: ${error.message ?? String(error)}`
    );
  }
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (error) {
    throw new PackageError(
      PackageErrorCode.DIGEST_RECORD_MALFORMED,
      `${DIGEST_FILE_NAME} is not valid JSON: ${error.message ?? String(error)}`
    );
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new PackageError(
      PackageErrorCode.DIGEST_RECORD_MALFORMED,
      `${DIGEST_FILE_NAME} must contain a single JSON object`
    );
  }
  const problems = [];
  if (parsed.formatVersion !== FORMAT_VERSION) {
    problems.push(`formatVersion must be ${FORMAT_VERSION}, got ${JSON.stringify(parsed.formatVersion)}`);
  }
  if (typeof parsed.id !== "string" || parsed.id === "") problems.push(`"id" must be a non-empty string`);
  if (typeof parsed.version !== "string" || parsed.version === "") {
    problems.push(`"version" must be a non-empty string`);
  }
  if (!PACKAGE_KINDS.includes(parsed.kind)) {
    problems.push(`"kind" must be one of ${PACKAGE_KINDS.join(", ")}, got ${JSON.stringify(parsed.kind)}`);
  }
  if (!isHex64(parsed.contentDigest)) {
    problems.push(`"contentDigest" must be a 64-character lowercase hex SHA-256`);
  }
  if (problems.length > 0) {
    throw new PackageError(
      PackageErrorCode.DIGEST_RECORD_MALFORMED,
      `${DIGEST_FILE_NAME} is malformed: ${problems.join("; ")}`,
      { problems }
    );
  }
  return parsed;
}

/**
 * Verify a staged/extracted package tree against its embedded digest record.
 * Recomputes the canonical digest over `dir` (excluding the digest record
 * itself) and compares it to the record's contentDigest.
 *
 * Throws PackageError DIGEST_MISMATCH (with expected/actual digests in
 * details) when any shipped byte differs from what the packager recorded.
 */
export async function verifyPackageDigest(dir) {
  const record = await readDigestRecord(dir);
  const actual = await computeDigestOf(dir, { excludeBasenames: [DIGEST_FILE_NAME] });
  if (actual !== record.contentDigest) {
    throw new PackageError(
      PackageErrorCode.DIGEST_MISMATCH,
      `package contents do not match the embedded digest — the package was modified after packaging (expected ${record.contentDigest}, computed ${actual})`,
      { expected: record.contentDigest, actual }
    );
  }
  return record;
}

/**
 * The digest record must describe the same package the manifest declares.
 * Throws PackageError DIGEST_IDENTITY_MISMATCH.
 */
export function checkDigestIdentity(record, manifest) {
  const mismatches = [];
  if (record.id !== manifest.id) mismatches.push(`id: digest record ${JSON.stringify(record.id)} vs manifest ${JSON.stringify(manifest.id)}`);
  if (record.version !== manifest.version) {
    mismatches.push(`version: digest record ${JSON.stringify(record.version)} vs manifest ${JSON.stringify(manifest.version)}`);
  }
  if (record.kind !== manifest.type) {
    mismatches.push(`kind: digest record ${JSON.stringify(record.kind)} vs manifest type ${JSON.stringify(manifest.type)}`);
  }
  if (mismatches.length > 0) {
    throw new PackageError(
      PackageErrorCode.DIGEST_IDENTITY_MISMATCH,
      `digest record does not describe this manifest: ${mismatches.join("; ")}`,
      { mismatches }
    );
  }
}
