import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import {
  createContext,
  createStdioConnection,
  SDK_PROTOCOL_VERSION,
} from "@swiftcode/sdk";
import type {
  CreatedContext,
  HostConnection,
  SwiftCodeExtension,
} from "@swiftcode/sdk";

const DEACTIVATE_BUDGET_MS = 5_000;
const FLUSH_BUDGET_MS = 1_000;

const USAGE = `Usage: node dist/adapter.js --entrypoint <path> [--manifest <swiftcode.json>] [--id <id>] [--version <v>] [--name <n>]

Options:
  --entrypoint <path>   Path (absolute or cwd-relative) to the entry module. Required.
  --manifest <path>     Path to swiftcode.json. Supplies id/name/version.
  --id <id>             Identity override. Precedence: flag > manifest > module id.
  --name <name>         Display-name override. Precedence: flag > manifest > module id.
  --version <version>   Version override. Precedence: flag > manifest > "0.0.0".
  --help, -h            Print this usage and exit 0.
`;

function diagnose(message: string): void {
  process.stderr.write(`[@swiftcode/runtime-adapter] ${message}\n`);
}

async function flushStdout(): Promise<void> {
  await Promise.race([
    new Promise<void>((resolve) => {
      process.stdout.write("", () => resolve());
    }),
    new Promise<void>((resolve) => {
      setTimeout(resolve, FLUSH_BUDGET_MS);
    }),
  ]);
}

interface CliOptions {
  entrypoint: string;
  manifestPath: string | undefined;
  id: string | undefined;
  name: string | undefined;
  version: string | undefined;
}

function parseArgs(argv: string[]): CliOptions | "help" {
  let entrypoint: string | undefined;
  let manifestPath: string | undefined;
  let id: string | undefined;
  let name: string | undefined;
  let version: string | undefined;

  const takeValue = (flag: string, i: number): string => {
    const value = argv[i + 1];
    if (value === undefined || value.startsWith("--")) {
      throw new Error(`flag ${flag} requires a value`);
    }
    return value;
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    switch (arg) {
      case "--help":
      case "-h":
        return "help";
      case "--entrypoint":
        entrypoint = takeValue(arg, i);
        i += 1;
        break;
      case "--manifest":
        manifestPath = takeValue(arg, i);
        i += 1;
        break;
      case "--id":
        id = takeValue(arg, i);
        i += 1;
        break;
      case "--name":
        name = takeValue(arg, i);
        i += 1;
        break;
      case "--version":
        version = takeValue(arg, i);
        i += 1;
        break;
      default:
        throw new Error(`unknown argument: ${arg}`);
    }
  }

  if (entrypoint === undefined) {
    throw new Error("--entrypoint <path> is required");
  }
  return { entrypoint, manifestPath, id, name, version };
}

interface ManifestShape {
  id?: unknown;
  name?: unknown;
  version?: unknown;
}

async function loadManifest(manifestPath: string): Promise<ManifestShape> {
  let raw: string;
  try {
    raw = await readFile(manifestPath, "utf8");
  } catch (error) {
    throw new Error(
      `cannot read manifest ${manifestPath}: ${error instanceof Error ? error.message : String(error)}`,
    );
  }
  try {
    return JSON.parse(raw) as ManifestShape;
  } catch (error) {
    throw new Error(
      `cannot parse manifest ${manifestPath}: ${error instanceof Error ? error.message : String(error)}`,
    );
  }
}

function asNonEmptyString(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function asExtension(module: unknown): SwiftCodeExtension {
  const candidate =
    typeof module === "object" && module !== null
      ? (module as Record<string, unknown>)["default"]
      : undefined;
  if (typeof candidate !== "object" || candidate === null) {
    throw new Error(
      "entry module's default export must be an object { id, activate, deactivate }",
    );
  }
  const record = candidate as Record<string, unknown>;
  if (typeof record["activate"] !== "function" || typeof record["deactivate"] !== "function") {
    throw new Error(
      "entry module's default export must have function-valued activate and deactivate",
    );
  }
  return candidate as SwiftCodeExtension;
}

async function deactivateBestEffort(
  extensionModule: SwiftCodeExtension,
): Promise<void> {
  try {
    await Promise.race([
      extensionModule.deactivate(),
      new Promise<void>((resolve) => {
        setTimeout(resolve, DEACTIVATE_BUDGET_MS);
      }),
    ]);
  } catch {
  }
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function resultError(
  invocationId: string,
  code: string,
  message: string,
  correlationId?: string,
): Record<string, unknown> {
  return {
    invocationId,
    ok: false,
    error: { code, message, correlationId: correlationId ?? invocationId },
  };
}

async function main(): Promise<number> {
  let options: CliOptions;
  try {
    const parsed = parseArgs(process.argv.slice(2));
    if (parsed === "help") {
      process.stdout.write(USAGE);
      return 0;
    }
    options = parsed;
  } catch (error) {
    process.stderr.write(`error: ${errorMessage(error)}\n${USAGE}`);
    return 1;
  }

  let manifest: ManifestShape = {};
  if (options.manifestPath !== undefined) {
    try {
      manifest = await loadManifest(options.manifestPath);
    } catch (error) {
      process.stderr.write(`error: ${errorMessage(error)}\n`);
      return 1;
    }
  }

  let extensionModule: SwiftCodeExtension;
  try {
    const entrypointAbs = path.resolve(options.entrypoint);
    const imported: unknown = await import(pathToFileURL(entrypointAbs).href);
    extensionModule = asExtension(imported);
  } catch (error) {
    process.stderr.write(`error: ${errorMessage(error)}\n`);
    return 1;
  }

  const extensionId =
    options.id ?? asNonEmptyString(manifest.id) ?? asNonEmptyString(extensionModule.id);
  if (extensionId === undefined) {
    process.stderr.write(
      "error: no extension id: pass --id, set it in the manifest, or export it from the entry module\n",
    );
    return 1;
  }
  const extensionName =
    options.name ?? asNonEmptyString(manifest.name) ?? extensionId;
  const extensionVersion =
    options.version ?? asNonEmptyString(manifest.version) ?? "0.0.0";

  const connection: HostConnection = createStdioConnection();
  const created: CreatedContext = createContext(connection, {
    id: extensionId,
    name: extensionName,
    version: extensionVersion,
  });

  let teardownStarted = false;
  let exitCode = 0;

  const teardown = async (code: number): Promise<void> => {
    if (teardownStarted) return;
    teardownStarted = true;
    exitCode = code;
    await deactivateBestEffort(extensionModule);
    try {
      created.context.subscriptions.disposeAll();
    } catch {
    }
    connection.close();
    await flushStdout();
    process.exit(exitCode);
  };

  connection.onEvent((event) => {
    if (event.name === "commands.execute") {
      void (async () => {
        const payload =
          typeof event.payload === "object" && event.payload !== null
            ? (event.payload as Record<string, unknown>)
            : {};
        const commandId = payload["commandId"];
        const invocationId = payload["invocationId"];
        if (typeof commandId !== "string" || typeof invocationId !== "string") {
          diagnose("ignoring malformed commands.execute event (missing commandId/invocationId)");
          return;
        }
        const handler = created.getCommandHandler(commandId);
        if (handler === undefined) {
          connection.sendEvent("commands.executeResult", resultError(
            invocationId,
            "UNKNOWN_COMMAND",
            `Unknown command "${commandId}".`,
          ));
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
          const code =
            typeof error === "object" && error !== null && "code" in error
              ? String((error as Record<string, unknown>)["code"])
              : "COMMAND_FAILED";
          const correlationId =
            typeof error === "object" && error !== null && "correlationId" in error
              ? String((error as Record<string, unknown>)["correlationId"])
              : undefined;
          connection.sendEvent(
            "commands.executeResult",
            resultError(invocationId, code, errorMessage(error), correlationId),
          );
        }
      })();
      return;
    }
    if (event.name === "shutdown") {
      void teardown(0);
      return;
    }
  });

  process.on("uncaughtException", (error: unknown) => {
    const message = errorMessage(error);
    connection.sendEvent("extension.error", {
      extensionId,
      message,
      detail: error instanceof Error && error.stack !== undefined ? error.stack : message,
    });
    void teardown(1);
  });
  process.on("unhandledRejection", (reason: unknown) => {
    const message = errorMessage(reason);
    connection.sendEvent("extension.error", {
      extensionId,
      message,
      detail: reason instanceof Error && reason.stack !== undefined ? reason.stack : message,
    });
    void teardown(1);
  });

  process.stdin.on("end", () => void teardown(0));
  process.stdin.on("close", () => void teardown(0));
  process.on("SIGTERM", () => void teardown(0));

  try {
    await extensionModule.activate(created.context);
  } catch (error) {
    const message = errorMessage(error);
    connection.sendEvent("extension.activationFailed", { extensionId, message });
    await deactivateBestEffort(extensionModule);
    try {
      created.context.subscriptions.disposeAll();
    } catch {
    }
    connection.close();
    await flushStdout();
    process.stderr.write(`error: activation failed: ${message}\n`);
    return 1;
  }

  connection.sendEvent("extension.ready", {
    extensionId,
    version: extensionVersion,
    protocolVersion: SDK_PROTOCOL_VERSION,
  });
  return 0;
}

main()
  .then((code) => {
    if (code !== 0) {
      void flushStdout().then(() => process.exit(code));
    }
  })
  .catch((error: unknown) => {
    process.stderr.write(`error: ${errorMessage(error)}\n`);
    void flushStdout().then(() => process.exit(1));
  });
