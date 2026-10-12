#!/usr/bin/env node
/**
 * swiftcode — developer CLI for the SwiftCode SDK platform.
 *
 * Usage: swiftcode <command> [args] [--json] [--help]
 *
 * Commands are auto-discovered from ./commands/<name>.mjs. Each module must
 * follow the contract documented in commands/CONTRACT.md:
 *
 *   export const definition = { name, description, usage };
 *   export async function run(args, ctx) { ... }
 *
 * Exit codes: 0 success · 1 operational failure · 2 usage error.
 * Global flags: --json (machine-readable output), --help.
 */
import { readdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { UsageError } from "./errors.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const COMMANDS_DIR = path.join(here, "commands");

const GLOBAL_USAGE = `usage: swiftcode <command> [args] [--json] [--help]

Commands:`;

/**
 * Minimal hand-rolled argument parser (no dependencies).
 *
 * Rules:
 *   --flag value   → args.flag = "value" (value is the next token unless it
 *                    starts with "-", in which case the flag is boolean)
 *   --flag=value   → args.flag = "value"
 *   --bool         → args.bool = true
 *   -h             → args.help = true (only short flag supported)
 *   --             → everything after is positional, even if it starts with "-"
 *   positional     → appended to args._
 *
 * The global --json flag is passed through to the command in args.json.
 */
export function parseArgs(argv) {
  const args = { _: [] };
  let i = 0;
  while (i < argv.length) {
    const token = argv[i];
    if (token === "--") {
      args._.push(...argv.slice(i + 1));
      break;
    }
    if (token.startsWith("--")) {
      const eq = token.indexOf("=");
      if (eq !== -1) {
        args[token.slice(2, eq)] = token.slice(eq + 1);
      } else {
        const key = token.slice(2);
        const next = argv[i + 1];
        if (next !== undefined && !next.startsWith("-")) {
          args[key] = next;
          i += 1;
        } else {
          args[key] = true;
        }
      }
    } else if (token.startsWith("-") && token.length > 1) {
      if (token === "-h") {
        args.help = true;
      } else {
        throw new UsageError(`unknown flag: ${token}`);
      }
    } else {
      args._.push(token);
    }
    i += 1;
  }
  return args;
}

/**
 * Discover command modules. Each module is imported in isolation: a module
 * that fails to load (syntax error, bad import, contract violation) does
 * NOT crash the CLI. It is listed as failed-to-load in --help, and
 * dispatching it exits 1 with the load error. This keeps one broken or
 * mid-edit module from taking down every other command.
 */
async function discoverCommands() {
  const commands = new Map();
  if (!existsSync(COMMANDS_DIR)) return commands;
  for (const entry of await readdir(COMMANDS_DIR)) {
    if (!entry.endsWith(".mjs")) continue;
    if (entry.startsWith("_")) continue; // shared helpers, not commands
    const fileName = entry.slice(0, -".mjs".length);
    try {
      const mod = await import(pathToFileURL(path.join(COMMANDS_DIR, entry)).href);
      if (!mod.definition || typeof mod.run !== "function") {
        throw new Error(
          `commands/${entry} does not follow the command contract (missing definition or run)`
        );
      }
      const name = mod.definition.name ?? fileName;
      commands.set(name, { definition: mod.definition, run: mod.run, file: entry });
    } catch (error) {
      commands.set(fileName, {
        definition: {
          name: fileName,
          description: `(failed to load: ${error.message ?? String(error)})`,
          usage: `swiftcode ${fileName} [args]`,
        },
        run: null,
        loadError: error,
        file: entry,
      });
    }
  }
  return commands;
}

function printGlobalHelp(commands) {
  const lines = [GLOBAL_USAGE];
  const names = [...commands.keys()].sort();
  for (const name of names) {
    const def = commands.get(name).definition;
    lines.push(`  ${name.padEnd(12)} ${def.description ?? ""}`);
  }
  lines.push("", "Run `swiftcode <command> --help` for command usage.");
  process.stdout.write(lines.join("\n") + "\n");
}

/** Normalize a command's return value to { code, data }. */
function normalizeResult(raw) {
  if (raw === undefined || raw === null) return { code: 0, data: null };
  if (typeof raw === "number") {
    const code = Number.isInteger(raw) ? raw : 1;
    return { code: [0, 1, 2].includes(code) ? code : 1, data: null };
  }
  if (typeof raw === "object") {
    const code = raw.code ?? 0;
    return {
      code: [0, 1, 2].includes(code) ? code : 1,
      data: raw.data === undefined ? null : raw.data,
    };
  }
  throw new Error("command run() must return void, a number, or { code, data }");
}

function isJson(args) {
  return args.json === true || args.json === "true";
}

function emitJson(payload) {
  process.stdout.write(JSON.stringify(payload) + "\n");
}

function makeCtx(commandName, json) {
  return {
    log(msg) {
      if (!json) process.stdout.write(`${msg}\n`);
    },
    error(msg) {
      process.stderr.write(`swiftcode ${commandName}: error: ${msg}\n`);
    },
  };
}

async function main() {
  const raw = process.argv.slice(2);
  const commands = await discoverCommands();

  if (raw.length === 0 || raw[0] === "--help" || raw[0] === "-h") {
    // Bare `swiftcode` with no command is a usage error; explicit --help is fine.
    const explicit = raw[0] === "--help" || raw[0] === "-h";
    const json = raw.includes("--json");
    if (json && explicit) {
      const list = [...commands.keys()].sort().map((n) => ({
        name: n,
        description: commands.get(n).definition.description ?? "",
      }));
      emitJson({ ok: true, command: "help", data: { commands: list } });
      return 0;
    }
    printGlobalHelp(commands);
    return explicit ? 0 : 2;
  }

  const commandName = raw[0];
  if (commandName.startsWith("-")) {
    process.stderr.write(`swiftcode: error: expected a command, got "${commandName}"\n`);
    printGlobalHelp(commands);
    return 2;
  }

  const entry = commands.get(commandName);
  if (!entry) {
    const available = [...commands.keys()].sort().join(", ");
    process.stderr.write(`swiftcode: error: unknown command "${commandName}"\n`);
    if (available) process.stderr.write(`available commands: ${available}\n`);
    return 2;
  }
  if (entry.loadError) {
    process.stderr.write(
      `swiftcode ${commandName}: error: command module failed to load: ${entry.loadError.message ?? String(entry.loadError)}\n`
    );
    return 1;
  }
  const mod = entry;

  let args;
  try {
    args = parseArgs(raw.slice(1));
  } catch (error) {
    process.stderr.write(`swiftcode ${commandName}: error: ${error.message}\n`);
    process.stderr.write(`${mod.definition.usage ?? ""}\n`);
    return 2;
  }
  const json = isJson(args);

  if (args.help === true) {
    const helpText = `${mod.definition.description ?? ""}\n\n${mod.definition.usage ?? ""}`.trim() + "\n";
    if (json) {
      emitJson({ ok: true, command: commandName, data: { help: helpText } });
    } else {
      process.stdout.write(helpText);
    }
    return 0;
  }

  const ctx = makeCtx(commandName, json);
  try {
    const { code, data } = normalizeResult(await mod.run(args, ctx));
    if (json) {
      if (code === 0) {
        emitJson({ ok: true, command: commandName, data });
      } else {
        emitJson({
          ok: false,
          command: commandName,
          error: {
            code: code === 2 ? "USAGE" : "OPERATIONAL",
            message: `command "${commandName}" exited with code ${code}`,
            data,
          },
        });
      }
    }
    return code;
  } catch (error) {
    const usage = error instanceof UsageError;
    const code = usage ? 2 : 1;
    if (json) {
      emitJson({
        ok: false,
        command: commandName,
        error: {
          code: usage ? "USAGE" : "OPERATIONAL",
          message: error.message ?? String(error),
        },
      });
    } else {
      process.stderr.write(`swiftcode ${commandName}: error: ${error.message ?? String(error)}\n`);
      if (usage && mod.definition.usage) {
        process.stderr.write(`\n${mod.definition.usage}\n`);
      }
    }
    return code;
  }
}

main()
  .then((code) => process.exit(code))
  .catch((error) => {
    process.stderr.write(`swiftcode: fatal: ${error.message ?? String(error)}\n`);
    process.exit(1);
  });
