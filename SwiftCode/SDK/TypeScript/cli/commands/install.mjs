/**
 * install.mjs — install a packaged SwiftCode extension (spec §13.1, §17).
 *
 * Usage:
 *   swiftcode install <file.swiftcode-extension> [--update] [--json]
 *
 * Flow (nothing is reported as installed until it is fully verified):
 *   1. Verify the .swiftcode-extension suffix.
 *   2. Extract to a private temp dir (zip; stored/deflate only; traversal
 *      and unsafe-symlink entries rejected).
 *   3. Validate the staged tree with the canonical `validateExtension`
 *      (commands/validate.mjs): manifest structure, entrypoint existence,
 *      symlink containment — BEFORE touching the controlled directory.
 *   4. Compute the canonical package digest (mirrors
 *      SDKExtensionRegistry.computeDigest(of:)).
 *   5. Target <root>/<id>/<version>/: if it exists and --update was not
 *      given, fail ("already installed (use --update)").
 *   6. With --update: back up the existing dir to <dir>.bak-<timestamp>,
 *      move the new tree into place, re-validate the INSTALLED tree
 *      (validateExtension + digest recompute); on any failure, remove the
 *      failed install, restore the backup (rollback), and fail.
 *   7. Write .sdk-install.json with the exact Swift record field names
 *      (id, name, version, packageDigest, installPath, installedAt,
 *      updatedAt, enabled=true), atomically, mode 0600.
 *   8. Only then report the extension identity, requested capabilities,
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
  description: "Install a packaged SwiftCode extension (.swiftcode-extension) into the controlled extensions directory.",
  usage: "swiftcode install <file.swiftcode-extension> [--update] [--json]",
};

const PACKAGE_SUFFIX = ".swiftcode-extension";

function failValidation(label, result) {
  const details = result.problems.map((p) => `  - ${p.path}: ${p.message}`).join("\n");
  throw new Error(`${label}:\n${details}`);
}

async function revalidateInstalledTree(dir, expectedDigest) {
  // Re-validate the INSTALLED tree (not the staging dir) and recompute its
  // digest there. Any failure means the install is bad.
  const result = await validateExtension(dir);
  if (!result.valid) failValidation("re-validation of the installed tree failed", result);
  const digest = await computeDigestOf(dir);
  if (digest !== expectedDigest) {
    throw new Error("re-validation failed: installed tree digest does not match the staged package");
  }
}

export async function run(args, ctx = {}) {
  const log =
    typeof ctx.log === "function" ? ctx.log : (m) => process.stdout.write(`${m}\n`);

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
    await extractZip(resolvedPackage, staging);

    // 3. Canonical validation of the STAGED tree before touching the root.
    const staged = await validateExtension(staging);
    if (!staged.valid) failValidation("package validation failed", staged);
    const manifest = staged.manifest;

    // 4. Canonical digest of the staged tree.
    const digest = await computeDigestOf(staging);

    // 5. Controlled-directory target.
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
      throw new Error(`${manifest.id}@${manifest.version} is already installed (use --update)`);
    }

    if (targetExists && update) {
      // 6a. Back up the existing version dir before replacing it.
      const existing = await readRecord(target);
      if (existing) installedAt = existing.installedAt;
      backupPath = `${target}.bak-${backupTimestamp()}`;
      await rename(target, backupPath);
    }

    // 6b. Move the staged tree into the controlled directory, then
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
      throw new Error(`update failed and was rolled back: ${error.message}`);
    }

    // 7. Record the install (atomic, 0600, exact Swift field names).
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

    // 8. Only now may we say it.
    const capabilities = (manifest.capabilities ?? []).map((c) => ({ id: c.id, reason: c.reason }));
    const data = {
      status: targetExists && update ? "updated" : "installed",
      id: manifest.id,
      name: manifest.name,
      version: manifest.version,
      packageDigest: digest,
      installPath: target,
      enabled: true,
      capabilities,
    };
    if (json) return { code: 0, data };
    log(`Extension: ${manifest.name} (${manifest.id})`);
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
