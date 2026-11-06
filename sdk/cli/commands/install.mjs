/**
 * install.mjs — install a packaged SwiftCode extension or app (spec §13.1, §17).
 *
 * Usage:
 *   swiftcode install <file.swiftcode-extension> [--update] [--json]
 *
 * Extensions and apps share the identical `.swiftcode-extension` format
 * (format details in SwiftCode/SDK/Documentation/Package-Format.md); the
 * manifest `type` field ("extension" | "app") selects the kind, and both
 * install into the same controlled extensions directory.
 *
 * Flow (nothing is reported as installed until it is fully verified):
 *   1. Verify the .swiftcode-extension suffix.
 *   2. Extract to a private temp dir (zip; stored/deflate only; traversal
 *      and unsafe-symlink entries rejected).
 *   3. Verify the embedded integrity record: swiftcode-digest.json must be
 *      present and well-formed, and the canonical digest recomputed over
 *      the extracted tree must equal the embedded contentDigest. Any
 *      post-packaging modification fails here with a typed DIGEST_MISMATCH
 *      — never a generic silent failure.
 *   4. Validate the staged tree with the canonical `validateExtension`
 *      (commands/validate.mjs): manifest structure, entrypoint existence,
 *      symlink containment — BEFORE touching the controlled directory.
 *      Schema violations fail with typed MANIFEST_INVALID.
 *   5. Check the digest record describes the same id/version/kind as the
 *      manifest (DIGEST_IDENTITY_MISMATCH).
 *   6. Compute the canonical package digest (mirrors
 *      SDKExtensionRegistry.computeDigest(of:)).
 *   7. Target <root>/<id>/<version>/: if it exists and --update was not
 *      given, fail ("already installed (use --update)").
 *   8. With --update: back up the existing dir to <dir>.bak-<timestamp>,
 *      move the new tree into place, re-validate the INSTALLED tree
 *      (validateExtension + digest recompute); on any failure, remove the
 *      failed install, restore the backup (rollback), and fail.
 *   9. Write .sdk-install.json with the exact Swift record field names
 *      (id, name, version, packageDigest, installPath, installedAt,
 *      updatedAt, enabled=true), atomically, mode 0600.
 *   10. Only then report the package identity, requested capabilities,
 *      and the "not yet approved" notice.
 *
 * The CLI never grants capabilities (spec §13.2 / §8.3): approval happens
 * in SwiftCode Studio.
 */

import { mkdir, mkdtemp, rename, stat } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { UsageError } from "../errors.mjs";
import { validateExtension } from "./validate.mjs";
import {
  PACKAGE_KINDS,
  PACKAGE_SUFFIX,
  PackageError,
  PackageErrorCode,
  checkDigestIdentity,
  verifyPackageDigest,
} from "./_package-format.mjs";
import {
  backupTimestamp,
  computeDigestOf,
  extractZip,
  extensionsRoot,
  isoDate,
  moveDir,
  normalizeArgs,
  readRecord,
  removeQuietly,
  versionDir,
  writeRecord,
} from "./_shared.mjs";

export const definition = {
  name: "install",
  description: "Install a packaged SwiftCode extension or app (.swiftcode-extension) into the controlled extensions directory.",
  usage: `swiftcode install <file.swiftcode-extension> [--update] [--json]

Installs the extension or app packaged in <file> (see 'swiftcode package';
format details in SwiftCode/SDK/Documentation/Package-Format.md):

  1. extracts to a private temp dir (zip traversal / unsafe symlinks rejected)
  2. verifies the embedded swiftcode-digest.json integrity record — a
     package modified after packaging fails here with a typed
     DIGEST_MISMATCH error (exit 1), never silently
  3. validates the staged tree (manifest schema, entrypoint, symlinks)
     BEFORE touching the controlled directory — schema violations fail
     with a typed MANIFEST_INVALID error
  4. installs to <extensions-root>/<id>/<version>/ (already installed
     without --update → ALREADY_INSTALLED); --update backs up, replaces,
     re-validates, and rolls back on any failure
  5. writes .sdk-install.json (exact host record fields, atomic, 0600)

Extensions and apps use the same format; the manifest "type" field
("extension" | "app") selects the kind.

Typed errors (also in --json data.error.code): DIGEST_RECORD_MISSING,
DIGEST_RECORD_MALFORMED, DIGEST_MISMATCH, DIGEST_IDENTITY_MISMATCH,
MANIFEST_INVALID, ALREADY_INSTALLED.

Options:
  --update   replace an already-installed id@version (with rollback)
  --json     machine-readable output (the dispatcher wraps the result)`,
};

function kindLabel(manifest) {
  return manifest.type === "app" ? "App" : "Extension";
}

function failValidation(label, result) {
  const details = result.problems.map((p) => `  - ${p.path}: ${p.message}`).join("\n");
  throw new PackageError(PackageErrorCode.MANIFEST_INVALID, `${label}:\n${details}`, {
    problems: result.problems,
    warnings: result.warnings,
  });
}

async function revalidateInstalledTree(dir, expectedDigest) {
  // Re-validate the INSTALLED tree (not the staging dir) and recompute its
  // digest there. Any failure means the install is bad.
  const result = await validateExtension(dir);
  if (!result.valid) failValidation("re-validation of the installed tree failed", result);
  const digest = await computeDigestOf(dir);
  if (digest !== expectedDigest) {
    throw new PackageError(
      PackageErrorCode.DIGEST_MISMATCH,
      `re-validation failed: installed tree digest does not match the staged package (expected ${expectedDigest}, computed ${digest})`,
      { expected: expectedDigest, actual: digest }
    );
  }
}

function toTypedFailure(error) {
  if (error instanceof PackageError) {
    return {
      code: 1,
      data: { error: { code: error.code, message: error.message, details: error.details } },
    };
  }
  const code = typeof error?.code === "string" ? error.code : "INSTALL_FAILED";
  return {
    code: 1,
    data: { error: { code, message: error?.message ?? String(error), details: null } },
  };
}

export async function run(args, ctx = {}) {
  const log =
    typeof ctx.log === "function" ? ctx.log : (m) => process.stdout.write(`${m}\n`);
  const err =
    typeof ctx.error === "function" ? ctx.error : (m) => process.stderr.write(`${m}\n`);

  try {
    return await runInstall(args, { log });
  } catch (error) {
    if (error instanceof UsageError) throw error; // dispatcher → exit 2 + usage
    err(error.message ?? String(error));
    return toTypedFailure(error);
  }
}

async function runInstall(args, { log }) {
  const { positionals: rawPos, flags } = normalizeArgs(args);
  const positionals = [...rawPos];

  // The dispatcher's parser greedily consumes the token after a boolean
  // flag as its value, so `install --update <path>` arrives as
  // update="<path>". Reinterpret string-valued booleans so flag order
  // never matters.
  let update = false;
  if (flags.update === true || flags.update === "true") {
    update = true;
  } else if (typeof flags.update === "string") {
    positionals.unshift(flags.update);
    update = true;
  }
  let json = flags.json === true || flags.json === "true";
  if (typeof flags.json === "string" && flags.json !== "true" && flags.json !== "false") {
    positionals.unshift(flags.json);
    json = true;
  }
  for (const key of Object.keys(flags)) {
    if (key !== "update" && key !== "json") throw new UsageError(`unknown flag --${key}`);
  }

  if (positionals.length === 0) throw new UsageError("missing package path");
  if (positionals.length > 1) throw new UsageError(`unexpected argument: ${positionals[1]}`);
  const packagePath = positionals[0];

  if (!packagePath.endsWith(PACKAGE_SUFFIX)) {
    throw new UsageError(`package must have the "${PACKAGE_SUFFIX}" suffix: ${packagePath}`);
  }
  const resolvedPackage = path.resolve(process.cwd(), packagePath);

  const staging = await mkdtemp(path.join(os.tmpdir(), "swiftcode-install-"));
  try {
    // 1-2. Extract to the staging dir (traversal + unsafe links rejected).
    try {
      await extractZip(resolvedPackage, staging);
    } catch (error) {
      if (error && error.code === "ENOENT") {
        throw new PackageError(
          PackageErrorCode.MANIFEST_UNREADABLE,
          `package file not found: ${resolvedPackage}`
        );
      }
      throw new PackageError(
        PackageErrorCode.ARCHIVE_UNREADABLE,
        `cannot extract the package archive: ${error.message ?? String(error)}`
      );
    }
    // 3. Embedded integrity record: recompute the canonical digest over
    //    the extracted tree and compare with the packager's record. This
    //    catches ANY post-packaging modification (flipped byte in dist/,
    //    edited manifest, added/removed file) with DIGEST_MISMATCH.
    const digestRecord = await verifyPackageDigest(staging);

    // 4. Canonical validation of the STAGED tree before touching the root.
    const staged = await validateExtension(staging);
    if (!staged.valid) failValidation("package validation failed", staged);
    const manifest = staged.manifest;

    // 5. The digest record must describe this manifest.
    checkDigestIdentity(digestRecord, manifest);

    // 6. Canonical digest of the staged tree (covers the whole installed
    //    tree, including the embedded digest record itself).
    const digest = await computeDigestOf(staging);

    // 7. Controlled-directory target.
    const target = versionDir(manifest.id, manifest.version);
    let targetExists = false;
    try {
      const s = await stat(target);
      if (!s.isDirectory()) throw new Error(`install target exists but is not a directory: ${target}`);
      targetExists = true;
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }

    let installedAt = isoDate();
    let backupPath = null;

    if (targetExists && !update) {
      throw new PackageError(
        PackageErrorCode.ALREADY_INSTALLED,
        `${manifest.id}@${manifest.version} is already installed (use --update)`
      );
    }

    if (targetExists && update) {
      // 8a. Back up the existing version dir before replacing it.
      const existing = await readRecord(target);
      if (existing) installedAt = existing.installedAt;
      backupPath = `${target}.bak-${backupTimestamp()}`;
      await rename(target, backupPath);
    }

    // 8b. Move the staged tree into the controlled directory, then
    //     re-validate the INSTALLED tree before anything is "installed".
    try {
      await mkdir(path.dirname(target), { recursive: true });
      await moveDir(staging, target);
      // Test hook: simulate a post-move verification failure so the
      // rollback path can be exercised deterministically. Test-only.
      if (process.env.SWIFTCODE_CLI_TEST_FAIL_AFTER_MOVE === "1") {
        throw new Error("simulated post-move verification failure (test hook)");
      }
      await revalidateInstalledTree(target, digest);
    } catch (error) {
      // Roll back: remove the failed install (including a partial copy
      // when the move itself failed), restore the backup.
      await removeQuietly(target);
      if (backupPath) {
        try {
          await rename(backupPath, target);
        } catch (restoreError) {
          throw new Error(
            `update failed (${error.message}); ROLLBACK ALSO FAILED — the previous version is preserved at ${backupPath}: ${restoreError.message}`
          );
        }
      }
      if (error instanceof PackageError) throw error;
      throw new Error(`update failed and was rolled back: ${error.message}`);
    }

    // 9. Record the install (atomic, 0600, exact Swift field names).
    await writeRecord(target, {
      id: manifest.id,
      name: manifest.name,
      version: manifest.version,
      packageDigest: digest,
      installPath: target,
      installedAt,
      updatedAt: isoDate(),
      enabled: true,
    });

    // The old version is verified replaced — drop the backup.
    if (backupPath) await removeQuietly(backupPath);

    // 10. Only now may we say it.
    const label = kindLabel(manifest);
    const capabilities = (manifest.capabilities ?? []).map((c) => ({ id: c.id, reason: c.reason }));
    const data = {
      status: targetExists && update ? "updated" : "installed",
      kind: PACKAGE_KINDS.includes(manifest.type) ? manifest.type : "extension",
      id: manifest.id,
      name: manifest.name,
      version: manifest.version,
      packageDigest: digest,
      contentDigest: digestRecord.contentDigest,
      installPath: target,
      enabled: true,
      capabilities,
    };
    if (json) return { code: 0, data };
    log(`${label}: ${manifest.name} (${manifest.id})`);
    log(`Version:   ${manifest.version}`);
    log(`Digest:    ${digest}`);
    log(`Installed: ${target}`);
    if (capabilities.length > 0) {
      log("Capabilities requested:");
      for (const cap of capabilities) log(`  - ${cap.id} — ${cap.reason}`);
    } else {
      log("Capabilities requested: none");
    }
    log(
      `${targetExists && update ? "Updated" : "Installed"}. Not yet approved — approve capabilities in SwiftCode Studio before first run.`
    );
    return 0;
  } finally {
    await removeQuietly(staging);
  }
}
