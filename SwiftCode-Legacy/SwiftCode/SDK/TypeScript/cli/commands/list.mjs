/**
 * list.mjs — list installed SwiftCode extensions (spec §3.1).
 *
 * Usage:
 *   swiftcode list [--json]
 *
 * Scans the controlled extensions directory the way
 * SDKExtensionRegistry.scan() does: an entry is recognized only when BOTH
 * swiftcode.json (re-read + re-validated with the canonical
 * `validateExtension`, fail closed) and .sdk-install.json exist and their
 * id/version match the directory layout. Malformed entries are skipped
 * with a stderr warning instead of aborting the scan.
 *
 * Human output is a table: id / version / enabled / digest (12-char short
 * form of the recorded packageDigest). --json returns the full records as
 * a JSON array with the exact Swift field names.
 */

import { readdir } from "node:fs/promises";
import path from "node:path";
import { UsageError } from "../errors.mjs";
import { validateExtension } from "./validate.mjs";
import { extensionsRoot, normalizeArgs, readRecord } from "./_shared.mjs";

export const definition = {
  name: "list",
  description: "List installed SwiftCode extensions (id, version, enabled, digest).",
  usage: "swiftcode list [--json]",
};

async function scanInstalls(root, warn) {
  const found = [];
  let idNames;
  try {
    idNames = await readdir(root);
  } catch (error) {
    if (error && error.code === "ENOENT") return found; // nothing installed yet
    throw error;
  }
  for (const idName of idNames.sort()) {
    const idDir = path.join(root, idName);
    let versionNames;
    try {
      const entries = await readdir(idDir, { withFileTypes: true });
      versionNames = entries
        .filter((e) => e.isDirectory())
        .map((e) => e.name)
        .sort();
    } catch {
      continue;
    }
    for (const versionName of versionNames) {
      const dir = path.join(idDir, versionName);
      const entry = await readInstall(idName, versionName, dir, warn);
      if (entry) found.push(entry);
    }
  }
  return found;
}

async function readInstall(idName, versionName, dir, warn) {
  // 1. Host metadata record; identity must match the layout.
  let record;
  try {
    record = await readRecord(dir);
  } catch (error) {
    warn(`skipping ${idName}/${versionName}: ${error.message}`);
    return null;
  }
  if (!record) {
    warn(`skipping ${idName}/${versionName}: missing .sdk-install.json`);
    return null;
  }
  if (record.id !== idName || record.version !== versionName) {
    warn(`skipping ${idName}/${versionName}: record identity does not match directory layout`);
    return null;
  }

  // 2. Manifest: re-read AND re-validate with the canonical validator.
  //    A tampered swiftcode.json fails closed — the record alone is never
  //    trusted.
  let result;
  try {
    result = await validateExtension(dir);
  } catch (error) {
    warn(`skipping ${idName}/${versionName}: manifest re-validation crashed: ${error.message}`);
    return null;
  }
  if (!result.valid) {
    warn(`skipping ${idName}/${versionName}: manifest re-validation failed`);
    return null;
  }
  const manifest = result.manifest;
  if (!manifest || manifest.id !== idName || manifest.version !== versionName) {
    warn(`skipping ${idName}/${versionName}: manifest identity does not match directory layout`);
    return null;
  }

  return {
    id: record.id,
    name: record.name,
    version: record.version,
    packageDigest: record.packageDigest,
    installPath: record.installPath,
    installedAt: record.installedAt,
    updatedAt: record.updatedAt,
    enabled: record.enabled,
  };
}

function printTable(log, installs) {
  if (installs.length === 0) {
    log("No extensions installed.");
    return;
  }
  const rows = installs.map((e) => [e.id, e.version, e.enabled ? "yes" : "no", e.packageDigest.slice(0, 12)]);
  const header = ["ID", "VERSION", "ENABLED", "DIGEST"];
  const widths = header.map((h, i) => Math.max(h.length, ...rows.map((r) => r[i].length)));
  const line = (cols) => cols.map((c, i) => c.padEnd(widths[i])).join("  ").replace(/\s+$/, "");
  log(line(header));
  for (const row of rows) log(line(row));
}

export async function run(args, ctx = {}) {
  const log =
    typeof ctx.log === "function" ? ctx.log : (m) => process.stdout.write(`${m}\n`);
  const warn = (m) => process.stderr.write(`list: warning: ${m}\n`);

  const { positionals, flags } = normalizeArgs(args);
  for (const key of Object.keys(flags)) {
    if (key !== "json") throw new UsageError(`unknown flag --${key}`);
  }
  if (positionals.length > 0) throw new UsageError(`unexpected argument: ${positionals[0]}`);

  const installs = await scanInstalls(extensionsRoot(), warn);
  installs.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : a.version < b.version ? -1 : 1));

  const json = flags.json === true || flags.json === "true";
  if (json) return { code: 0, data: installs };
  printTable(log, installs);
  return 0;
}
