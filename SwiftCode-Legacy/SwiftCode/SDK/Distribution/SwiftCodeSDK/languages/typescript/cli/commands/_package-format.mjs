import { readFile } from "node:fs/promises";
import path from "node:path";
import { computeDigestOf } from "./_shared.mjs";

export const PACKAGE_SUFFIX = ".swiftcode-extension";
export const DIGEST_FILE_NAME = "swiftcode-digest.json";
export const MANIFEST_FILE_NAME = "swiftcode.json";
export const FORMAT_VERSION = 1;

export const PACKAGE_KINDS = ["extension", "app"];

export const PackageErrorCode = {
  DIGEST_RECORD_MISSING: "DIGEST_RECORD_MISSING",
  DIGEST_RECORD_MALFORMED: "DIGEST_RECORD_MALFORMED",
  DIGEST_MISMATCH: "DIGEST_MISMATCH",
  DIGEST_IDENTITY_MISMATCH: "DIGEST_IDENTITY_MISMATCH",
  MANIFEST_INVALID: "MANIFEST_INVALID",
  MANIFEST_UNREADABLE: "MANIFEST_UNREADABLE",
  ARCHIVE_UNREADABLE: "ARCHIVE_UNREADABLE",
  ARCHIVE_UNSAFE_ENTRY: "ARCHIVE_UNSAFE_ENTRY",
  ENTRYPOINT_MISSING: "ENTRYPOINT_MISSING",
  ALREADY_INSTALLED: "ALREADY_INSTALLED",
  BUILD_FAILED: "BUILD_FAILED",
  COMPILER_NOT_FOUND: "COMPILER_NOT_FOUND",
  XCODEBUILD_UNAVAILABLE: "XCODEBUILD_UNAVAILABLE",
};

export class PackageError extends Error {
  constructor(code, message, details = null) {
    super(`[${code}] ${message}`);
    this.name = "PackageError";
    this.code = code;
    this.details = details;
  }
}

export function makeDigestRecord({ id, version, kind, contentDigest }) {
  return {
    contentDigest,
    formatVersion: FORMAT_VERSION,
    id,
    kind,
    version,
  };
}

export function serializeDigestRecord(record) {
  return JSON.stringify(makeDigestRecord(record));
}

function isHex64(value) {
  return typeof value === "string" && /^[0-9a-f]{64}$/.test(value);
}

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
