/**
 * _set-enabled.mjs — shared factory for the enable/disable commands.
 *
 * Mirrors SDKExtensionRegistry.setEnabled: flips `enabled` in
 * .sdk-install.json (all installed versions, or one with --version),
 * atomically, leaving updatedAt untouched — a flag flip is not an update
 * of the installed tree.
 *
 * Note: the CLI flips the record only. Stopping/starting a RUNNING
 * extension is the runtime coordinator's job — do that in SwiftCode Studio.
 */

import { readdir, stat } from "node:fs/promises";
import path from "node:path";
import { UsageError } from "../errors.mjs";
import { extensionsRoot, normalizeArgs, readRecord, writeRecord } from "./_shared.mjs";

export function makeSetEnabledCommand(enabled) {
  const verb = enabled ? "enable" : "disable";
  return {
    definition: {
      name: verb,
      description: `${enabled ? "Enable" : "Disable"} an installed SwiftCode extension (flips the enabled flag in its install record).`,
      usage: `swiftcode ${verb} <id> [--version <v>]`,
    },

    async run(args, ctx = {}) {
      const log =
        typeof ctx.log === "function" ? ctx.log : (m) => process.stdout.write(`${m}\n`);

      const { positionals: rawPos, flags } = normalizeArgs(args);
      const positionals = [...rawPos];

      // Greedy-parser defense (see install.mjs): `enable --json <id>`
      // arrives as json="<id>".
      let json = flags.json === true || flags.json === "true";
      if (typeof flags.json === "string" && flags.json !== "true" && flags.json !== "false") {
        positionals.unshift(flags.json);
        json = true;
      }
      const version = typeof flags.version === "string" ? flags.version : null;
      if (flags.version === true) throw new UsageError("flag --version requires a value");
      for (const key of Object.keys(flags)) {
        if (key !== "version" && key !== "json") throw new UsageError(`unknown flag --${key}`);
      }
      if (positionals.length === 0) throw new UsageError("missing extension id");
      if (positionals.length > 1) throw new UsageError(`unexpected argument: ${positionals[1]}`);
      const id = positionals[0];

      const root = extensionsRoot();
      const idDir = path.join(root, id);
      let idStat;
      try {
        idStat = await stat(idDir);
      } catch {
        throw new Error(`${id} is not installed`);
      }
      if (!idStat.isDirectory()) throw new Error(`${id} is not installed`);

      let versionNames;
      if (version) {
        const dir = path.join(idDir, version);
        try {
          if (!(await stat(dir)).isDirectory()) throw new Error("not a dir");
        } catch {
          throw new Error(`${id}@${version} is not installed`);
        }
        versionNames = [version];
      } else {
        const entries = await readdir(idDir, { withFileTypes: true });
        versionNames = entries
          .filter((e) => e.isDirectory())
          .map((e) => e.name)
          .sort();
      }

      const changed = [];
      let touched = 0;
      for (const versionName of versionNames) {
        const dir = path.join(idDir, versionName);
        const record = await readRecord(dir);
        if (!record || record.id !== id) continue;
        if (record.enabled !== enabled) {
          await writeRecord(dir, { ...record, enabled });
        }
        touched += 1;
        changed.push({ id, version: versionName, enabled });
        log(`${id}@${versionName}: ${enabled ? "enabled" : "disabled"}`);
      }

      if (touched === 0) {
        throw new Error(`${id} has no install record to update`);
      }
      if (json) return { code: 0, data: { changed } };
      if (!enabled) {
        log(
          `Note: flag flip only — if ${id} is currently running, stop it in SwiftCode Studio; the CLI does not touch runtime state.`
        );
      }
      return 0;
    },
  };
}
