#!/usr/bin/env node
/**
 * SwiftCode SDK node runtime adapter
 * (Docs/Intro-to-SDK.md §10 runtime responsibilities, §12.4 entry point).
 *
 * This is what the Swift host's `SDKNodeLauncher` spawns:
 *
 *   node dist/adapter.js --entrypoint <path> [--manifest <swiftcode.json>]
 *                         [--id <id>] [--version <v>] [--name <n>]
 *
 * It loads the extension's declared entry point, builds a real SDK context
 * over the stdio NDJSON channel (`createStdioConnection` + `createContext`
 * from `@swiftcode/sdk`), activates the extension, and then dispatches
 * `commands.execute` host events to the extension's registered command
 * handlers, reporting `commands.executeResult` events back to the host.
 *
 * Lifecycle (§10.5): activation failure triggers best-effort deactivation
 * and cleanup, then exit(1). `shutdown`, stdin EOF/close, and SIGTERM all
 * share one bounded deactivate path that disposes context subscriptions,
 * closes the connection, and exits 0 — the process never hangs.
 */

import { randomUUID } from "crypto";
import { readFile } from "fs/promises";
import { resolve } from "path";
import { pathToFileURL } from "url";
import {
  SDK_PROTOCOL_VERSION,
  SDKError,
  createContext,
  createStdioConnection,
  type ExtensionInfo,
  type SwiftCodeExtension,
} from "@swiftcode/sdk";

/** Bounded budget for the extension's `deactivate()` during teardown. */
const DEACTIVATE_TIMEOUT_MS = 5_000;
/** Bounded budget for flushing stdout before a fatal exit. */
const FLUSH_TIMEOUT_MS = 1_000;

interface AdapterOptions {
  entrypoint: string;
  manifestPath?: string;
  id?: string;
  name?: string;
  version?: string;
}

function usage(): string {
  return [
    "Usage: node dist/adapter.js --entrypoint <path> [--manifest <swiftcode.json>]",
    "                                [--id <id>] [--version <v>] [--name <n>]",
    "",
    "  --entrypoint  Absolute (or cwd-relative) path to the extension entry module. Required.",
    "  --manifest    Path to swiftcode.json; supplies id/name/version. Optional.",
    "  --id/--version/--name  Identity overrides; win over manifest and module values.",
  ].join("\n");
}

/** Parses argv. Exits 1 with usage on any malformed invocation — never hangs. */
function parseArgs(argv: string[]): AdapterOptions {
  const options: AdapterOptions = { entrypoint: "" };
  for (let i = 0; i < argv.length; i++) {
    const flag = argv[i];
    const value = argv[i + 1];
    switch (flag) {
      case "--entrypoint":
      case "--manifest":
      case "--id":
      case "--name":
      case "--version": {
        if (value === undefined || value.startsWith("--")) {
          fail(`Missing value for ${flag}.\n${usage()}`);
        }
        if (flag === "--entrypoint") options.entrypoint = value;
        else if (flag === "--manifest") options.manifestPath = value;
        else if (flag === "--id") options.id = value;
        else if (flag === "--name") options.name = value;
        else options.version = value;
        i++;
        break;
      }
      case "--help":
      case "-h":
        process.stdout.write(`${usage()}\n`);
        process.exit(0);
        break;
      default:
        fail(`Unknown argument: ${flag}\n${usage()}`);
    }
  }
  if (options.entrypoint.length === 0) {
    fail(`Missing required --entrypoint.\n${usage()}`);
  }
  return options;
}

/** Writes a diagnostic to stderr (stdout is the IPC channel). */
function diagnose(message: string): void {
  process.stderr.write(`[swiftcode-runtime-adapter] ${message}\n`);
}

/** Fatal configuration error: stderr + exit(1), never a silent hang. */
function fail(message: string): never {
  diagnose(message);
  process.exit(1);
}

interface ManifestShape {
  id?: unknown;
  name?: unknown;
  version?: unknown;
}

/** Loads swiftcode.json. Any failure is fatal: an invalid package never activates (§10.5). */
async function loadManifest(path: string): Promise<ManifestShape> {
  let raw: string;
  try {
    raw = await readFile(path, "utf8");
  } catch (error) {
    fail(
      `Cannot read manifest "${path}": ${error instanceof Error ? error.message : String(error)}`,
    );
  }
  try {
    const parsed: unknown = JSON.parse(raw);
    if (typeof parsed !== "object" || parsed === null) {
      fail(`Manifest "${path}" is not a JSON object.`);
    }
    return parsed as ManifestShape;
  } catch (error) {
    fail(
      `Manifest "${path}" is not valid JSON: ${error instanceof Error ? error.message : String(error)}`,
    );
  }
}

/**
 * Dynamically imports the entry point and validates the entry-point
 * contract (§12.4): the default export must be `{ id, activate, deactivate }`
 * with function-valued activate/deactivate. A contract violation is an
 * activation contract failure — stderr + exit(1), never a silent hang.
 */
async function loadExtensionModule(entrypoint: string): Promise<SwiftCodeExtension> {
  const absolute = resolve(entrypoint);
  let module: unknown;
  try {
    module = await import(pathToFileURL(absolute).href);
  } catch (error) {
    fail(
      `Cannot import entrypoint "${absolute}": ${error instanceof Error ? error.message : String(error)}`,
    );
  }
  const candidate =
    typeof module === "object" && module !== null
      ? (module as Record<string, unknown>)["default"]
      : undefined;
  const problems: string[] = [];
  if (typeof candidate !== "object" || candidate === null) {
    problems.push("default export is missing or not an object");
  } else {
    const record = candidate as Record<string, unknown>;
    if (typeof record["id"] !== "string" || (record["id"] as string).length === 0) {
      problems.push('default export "id" must be a non-empty string');
    }
    if (typeof record["activate"] !== "function") {
      problems.push('default export "activate" must be a function');
    }
    if (typeof record["deactivate"] !== "function") {
      problems.push('default export "deactivate" must be a function');
    }
  }
  if (problems.length > 0) {
    fail(`Entrypoint "${absolute}" violates the extension contract (§12.4): ${problems.join("; ")}.`);
  }
  return candidate as SwiftCodeExtension;
}

function asNonEmptyString(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

/** Identity precedence: CLI overrides > manifest > module default export. */
function resolveIdentity(
  options: AdapterOptions,
  manifest: ManifestShape | undefined,
  extension: SwiftCodeExtension,
): ExtensionInfo {
  const id = options.id ?? asNonEmptyString(manifest?.id) ?? extension.id;
  const name = options.name ?? asNonEmptyString(manifest?.name) ?? extension.id;
  const version = options.version ?? asNonEmptyString(manifest?.version) ?? "0.0.0";
  return { id, name, version };
}

/**
 * Flushes everything written to stdout so far. The callback of a trailing
 * empty write fires only after earlier chunks are flushed; the whole thing
 * is bounded so a broken pipe can never hang a fatal exit path.
 */
function flushStdout(): Promise<void> {
  return new Promise((resolve) => {
    let done = false;
    const finish = (): void => {
      if (!done) {
        done = true;
        resolve();
      }
    };
    const timer = setTimeout(finish, FLUSH_TIMEOUT_MS);
    timer.unref?.();
    try {
      process.stdout.write("", () => {
        clearTimeout(timer);
        finish();
      });
    } catch {
      clearTimeout(timer);
      finish();
    }
  });
}

/** Runs a promise with a wall-clock budget; rejects with `SDKError` TIMEOUT on expiry. */
function withTimeout<T>(promise: Promise<T>, ms: number, what: string): Promise<T> {
  let timer: NodeJS.Timeout | undefined;
  const timeout = new Promise<T>((_, reject) => {
    timer = setTimeout(() => {
      reject(new SDKError("TIMEOUT", `${what} timed out after ${ms / 1000} seconds.`));
    }, ms);
    timer.unref?.();
  });
  return Promise.race([promise, timeout]).finally(() => {
    if (timer !== undefined) clearTimeout(timer);
  });
}

function errorPayload(error: unknown): { code: string; message: string; correlationId: string } {
  if (error instanceof SDKError) {
    return { code: error.code, message: error.message, correlationId: error.correlationId };
  }
  const record =
    typeof error === "object" && error !== null ? (error as Record<string, unknown>) : null;
  const code =
    record !== null && typeof record["code"] === "string" && record["code"].length > 0
      ? (record["code"] as string)
      : "COMMAND_FAILED";
  const correlationId =
    record !== null && typeof record["correlationId"] === "string"
      ? (record["correlationId"] as string)
      : randomUUID();
  const message = error instanceof Error ? error.message : String(error);
  return { code, message, correlationId };
}

async function main(): Promise<void> {
  const options = parseArgs(process.argv.slice(2));
  const manifest =
    options.manifestPath === undefined ? undefined : await loadManifest(options.manifestPath);
  const extension = await loadExtensionModule(options.entrypoint);
  const extensionInfo = resolveIdentity(options, manifest, extension);

  diagnose(`starting extension "${extensionInfo.id}" v${extensionInfo.version}`);

  const connection = createStdioConnection();
  const { context, getCommandHandler } = createContext(connection, extensionInfo);

  // --- Shared teardown path (§10.5) ---------------------------------------
  // Used by `shutdown`, stdin EOF/close, and SIGTERM. Best-effort
  // deactivate with a 5 s budget, then dispose subscriptions, close the
  // connection, and exit. Guarded so it runs exactly once: the process
  // never hangs and never tears down twice.
  let teardownStarted = false;
  let teardownPromise: Promise<void> | undefined;

  async function teardown(exitCode: 0 | 1, reason: string): Promise<never> {
    if (teardownPromise !== undefined) {
      await teardownPromise;
      process.exit(exitCode);
    }
    teardownStarted = true;
    diagnose(`tearing down (${reason})`);
    teardownPromise = (async () => {
      try {
        await withTimeout(
          Promise.resolve().then(() => extension.deactivate()),
          DEACTIVATE_TIMEOUT_MS,
          "extension.deactivate()",
        );
      } catch (error) {
        diagnose(
          `deactivate() failed (best effort): ${error instanceof Error ? error.message : String(error)}`,
        );
      }
      try {
        context.subscriptions.dispose();
      } catch {
        // Best effort: one bad disposable must not block process exit.
      }
      unsubscribeEvents();
      connection.close();
    })();
    await teardownPromise;
    await flushStdout();
    process.exit(exitCode);
  }

  /** Fatal, unrecoverable failure: best-effort `extension.error` event, stderr, exit(1). */
  async function fatal(message: string, cause?: unknown): Promise<never> {
    if (!teardownStarted) {
      try {
        connection.sendEvent("extension.error", {
          extensionId: extensionInfo.id,
          message,
          detail: cause instanceof Error ? cause.stack ?? cause.message : String(cause ?? ""),
        });
      } catch {
        // Best effort only.
      }
    }
    diagnose(`fatal: ${message}`);
    await flushStdout();
    process.exit(1);
  }

  // --- Host event dispatch ---------------------------------------------------
  async function handleExecute(rawPayload: unknown): Promise<void> {
    const payload =
      typeof rawPayload === "object" && rawPayload !== null
        ? (rawPayload as Record<string, unknown>)
        : {};
    const commandId = typeof payload["commandId"] === "string" ? payload["commandId"] : "";
    const invocationId = typeof payload["invocationId"] === "string" ? payload["invocationId"] : "";
    const handler = commandId.length > 0 ? getCommandHandler(commandId) : undefined;
    if (handler === undefined) {
      connection.sendEvent("commands.executeResult", {
        invocationId,
        ok: false,
        error: {
          code: "UNKNOWN_COMMAND",
          message:
            commandId.length > 0
              ? `Unknown command "${commandId}" for extension "${extensionInfo.id}".`
              : "Missing commandId in commands.execute payload.",
        },
      });
      return;
    }
    try {
      const result = await handler(payload["payload"]);
      connection.sendEvent("commands.executeResult", {
        invocationId,
        ok: true,
        result: result ?? null,
      });
    } catch (error) {
      connection.sendEvent("commands.executeResult", {
        invocationId,
        ok: false,
        error: errorPayload(error),
      });
    }
  }

  const unsubscribeEvents = connection.onEvent((event) => {
    if (event.name === "commands.execute") {
      void handleExecute(event.payload).catch((error: unknown) =>
        diagnose(`command dispatch failed: ${error instanceof Error ? error.message : String(error)}`),
      );
      return;
    }
    if (event.name === "shutdown") {
      void teardown(0, "host shutdown");
    }
  });

  // --- Crash reporting (§10.3): report crashes and unhandled errors ---------
  process.on("uncaughtException", (error: unknown) => {
    void fatal("uncaught exception", error);
  });
  process.on("unhandledRejection", (reason: unknown) => {
    void fatal("unhandled promise rejection", reason);
  });

  // --- Host-driven termination signals --------------------------------------
  process.on("SIGTERM", () => {
    void teardown(0, "SIGTERM");
  });
  const onStdioEnd = (): void => {
    void teardown(0, "stdin closed");
  };
  process.stdin.on("end", onStdioEnd);
  process.stdin.on("close", onStdioEnd);

  // --- Activation ------------------------------------------------------------
  try {
    await extension.activate(context);
  } catch (error) {
    // §10.5: activation failure triggers best-effort deactivation and cleanup.
    const message = error instanceof Error ? error.message : String(error);
    try {
      connection.sendEvent("extension.activationFailed", {
        extensionId: extensionInfo.id,
        message,
      });
    } catch {
      // Best effort only.
    }
    diagnose(`activation failed: ${message}`);
    await teardown(1, "activation failure");
  }

  connection.sendEvent("extension.ready", {
    extensionId: extensionInfo.id,
    version: extensionInfo.version,
    protocolVersion: SDK_PROTOCOL_VERSION,
  });
  diagnose(`extension "${extensionInfo.id}" active; awaiting host events`);
}

void main().catch((error: unknown) => {
  diagnose(`startup failed: ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
});
