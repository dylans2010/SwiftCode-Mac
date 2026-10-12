/**
 * uninstall.mjs — remove an installed SwiftCode extension (spec §3.1).
 *
 * Usage:
 *   swiftcode uninstall <id> --version <v>
 *   swiftcode uninstall <id> --all
 *
 * Non-interactive by design: removing every version requires the explicit
 * --all flag; a bare `uninstall <id>` fails with UsageError instead of
 * prompting. Mirrors SDKExtensionRegistry.removeInstallRecord: deletes the
 * <root>/<id>/<version>/ tree and drops the now-empty parent id directory.
 *
 * Note: the CLI removes installed files only. Deactivating a RUNNING
 * extension (stopping its process, clearing runtime state) is the host's
 * job — stop it in SwiftCode Studio before or after uninstalling.
 */

import { readdir, rm, stat } from "node:fs/promises";
import path from "node:path";
import { UsageError } from "../errors.mjs";
import { extensionsRoot, normalizeArgs } from "./_shared.mjs";

export const definition = {
  name: "uninstall",
  description: "Remove an installed SwiftCode extension (one version, or every version with --all).",
  usage: "swiftcode uninstall <id> (--version <v> | --all)",
};

async function dirExists(dir) {
  try {
    return (await stat(dir)).isDirectory();
  } catch {
    return false;
  }
}

export async function run(args, ctx = {}) {
  const log =
    typeof ctx.log === "function" ? ctx.log : (m) => process.stdout.write(`${m}\n`);

  const { positionals: rawPos, flags } = normalizeArgs(args);
  const positionals = [...rawPos];

  // Greedy-parser defense (see install.mjs): `uninstall --all <id>`
  // arrives as all="<id>".
  let all = false;
  if (flags.all === true || flags.all === "true") {
    all = true;
  } else if (typeof flags.all === "string") {
    positionals.unshift(flags.all);
    all = true;
  }
  let json = flags.json === true || flags.json === "true";
  if (typeof flags.json === "string" && flags.json !== "true" && flags.json !== "false") {
    positionals.unshift(flags.json);
    json = true;
  }
  const version = typeof flags.version === "string" ? flags.version : null;
  if (flags.version === true) throw new UsageError("flag --version requires a value");
  for (const key of Object.keys(flags)) {
    if (key !== "version" && key !== "all" && key !== "json") {
      throw new UsageError(`unknown flag --${key}`);
    }
  }

  if (positionals.length === 0) throw new UsageError("missing extension id");
  if (positionals.length > 1) throw new UsageError(`unexpected argument: ${positionals[1]}`);
  const id = positionals[0];

  if (!version && !all) {
    throw new UsageError("refusing to guess: pass --version <v> to remove one version, or --all to remove every installed version");
  }
  if (version && all) throw new UsageError("pass either --version <v> or --all, not both");

  const root = extensionsRoot();
  const idDir = path.join(root, id);

  let targets;
  if (version) {
    const dir = path.join(idDir, version);
    if (!(await dirExists(dir))) {
      throw new Error(`${id}@${version} is not installed`);
    }
    targets = [{ version, dir }];
  } else {
    let entries;
    try {
      entries = await readdir(idDir, { withFileTypes: true });
    } catch (error) {
      if (error && error.code === "ENOENT") throw new Error(`${id} is not installed`);
      throw error;
    }
    const versions = entries
      .filter((e) => e.isDirectory())
      .map((e) => e.name)
      .sort();
    if (versions.length === 0) throw new Error(`${id} is not installed (no version directories)`);
    targets = versions.map((v) => ({ version: v, dir: path.join(idDir, v) }));
  }

  const removed = [];
  for (const { version: v, dir } of targets) {
    await rm(dir, { recursive: true, force: true });
    removed.push({ id, version: v, path: dir });
    log(`Removed ${id}@${v} (${dir})`);
  }

  // Drop the now-empty parent id directory (mirrors the Swift registry).
  try {
    if ((await readdir(idDir)).length === 0) {
      await rm(idDir, { recursive: true, force: true });
    }
  } catch {
    /* already gone */
  }

  if (json) return { code: 0, data: { removed } };
  log(
    `Note: file removal only — if ${id} is currently running, stop/deactivate it in SwiftCode Studio; the CLI does not touch runtime state.`
  );
  return 0;
}
