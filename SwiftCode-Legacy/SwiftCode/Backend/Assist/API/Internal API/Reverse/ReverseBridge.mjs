// ReverseBridge.mjs — SwiftCode Assist @Reverse bridge (Node.js host).
//
// One request per process. Swift spawns:
//   node ReverseBridge.mjs --rea-dir <rea-agents@6.5.0 dir>
// writes ONE NDJSON request line to stdin, closes stdin, and reads stdout
// to EOF. Stdout carries ONLY protocol frames (progress / result / error),
// one JSON object per line. Diagnostics go to stderr.
//
// FORBIDDEN: this bridge must never use the Model Context Protocol
// transport — no server, no client, no fallback. It talks to REA's real
// implementation only, via two paths:
//   1. DIRECT (preferred): dynamic import of the pinned rea-agents dist
//      module `dist/composition/directAnalysis.js` -> runDirectAnalysis.
//      Verified against 6.5.0: the import resolves and `inspect_artifact`
//      returns real Evidence.
//   2. PINNED-CLI FALLBACK (only for `inspect_with_objdump`): the direct
//      provider does not declare that operation (verified: it returns
//      capability_unavailable / "operation is not declared by this
//      provider"), so the bridge spawns the pinned `rea` CLI with
//      `--format json` and parses the Evidence envelope. This is a
//      documented fallback for ONE operation, never presented as a
//      direct API call, and never used for any other operation.
// Excluded everywhere: free-form Rizin commands, Frida/GDB/Rizin-debug
// sessions, ADB/browser/device ops, firmware extraction, and every
// IDA/JEB/JADX-backed operation.

import { readFileSync, existsSync } from "node:fs";
import { join, resolve, isAbsolute } from "node:path";
import { spawn } from "node:child_process";
import { pathToFileURL } from "node:url";

const PROTOCOL_VERSION = 1;
const PINNED_REA_VERSION = "6.5.0";
const MAX_STDIN_BYTES = 1_048_576;
const MAX_EVIDENCE_BYTES = 8_388_608;

// Allow-list. Must stay in sync with ReverseOperation in ReverseModels.swift.
const ALLOW_LIST = new Set([
  "inspect_artifact",
  "inspect_macho",
  "inspect_plist",
  "inspect_signature",
  "list_architectures",
  "demangle_swift",
  "inspect_go_binary",
  "inspect_managed_artifact",
  "inspect_managed_members",
  "inspect_sqlite_database",
  "inspect_with_objdump",
]);

const OBJDUMP_OPS = new Set([
  "file_headers",
  "section_headers",
  "symbols",
  "relocations",
  "dwarf",
  "disassemble",
  "disassemble_all",
]);

// Native-macOS provider operations: REA reports them unavailable off
// macOS ("unsupported_host"). Availability is computed from the platform.
const NATIVE_MACOS_OPS = new Set([
  "inspect_macho",
  "inspect_plist",
  "inspect_signature",
  "list_architectures",
  "demangle_swift",
]);

let cliChild = null;
process.on("SIGTERM", () => {
  if (cliChild && !cliChild.killed) cliChild.kill("SIGTERM");
  process.exit(143);
});

function send(frame) {
  process.stdout.write(JSON.stringify(frame) + "\n");
}

function progress(id, phase, message, sequence, completed, total) {
  send({
    version: PROTOCOL_VERSION,
    id,
    type: "progress",
    progress: { phase, message, completed: completed ?? null, total: total ?? null, sequence },
  });
}

function errorFrame(id, code, category, message, retryable, remediation, partialEvidence) {
  send({
    version: PROTOCOL_VERSION,
    id,
    type: "error",
    error: {
      code,
      category,
      message,
      retryable,
      remediation: remediation ?? null,
      partialEvidence: partialEvidence ?? null,
    },
  });
}

function parseArgs(argv) {
  const out = { reaDir: null };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--rea-dir" && i + 1 < argv.length) out.reaDir = argv[++i];
  }
  return out;
}

function resolveReaDir(argvReaDir) {
  const candidates = [];
  if (argvReaDir) candidates.push(argvReaDir);
  if (process.env.SWIFTCODE_REVERSE_REA_DIR) candidates.push(process.env.SWIFTCODE_REVERSE_REA_DIR);
  for (const candidate of candidates) {
    const dir = resolve(candidate);
    const pkgPath = join(dir, "package.json");
    try {
      const pkg = JSON.parse(readFileSync(pkgPath, "utf8"));
      if (pkg.name === "rea-agents" && pkg.version === PINNED_REA_VERSION) return dir;
    } catch {
      // Not a usable REA dir; try the next candidate.
    }
  }
  return null;
}

function readStdin() {
  return new Promise((resolvePromise, rejectPromise) => {
    const chunks = [];
    let total = 0;
    process.stdin.on("data", (chunk) => {
      total += chunk.length;
      if (total > MAX_STDIN_BYTES) {
        rejectPromise(new Error("stdin exceeded the 1 MiB limit"));
        return;
      }
      chunks.push(chunk);
    });
    process.stdin.on("end", () => resolvePromise(Buffer.concat(chunks).toString("utf8")));
    process.stdin.on("error", rejectPromise);
  });
}

function isValidEvidence(value) {
  return (
    value !== null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    typeof value.evidence_id === "string" &&
    value.evidence_id.length > 0 &&
    typeof value.operation === "string" &&
    value.operation.length > 0
  );
}

function objdumpAvailable() {
  // GNU objdump presence: probe via `which`-free PATH search.
  const path = process.env.PATH ?? "";
  for (const dir of path.split(":")) {
    if (dir && existsSync(join(dir, "objdump"))) return true;
  }
  return false;
}

const DISPLAY_NAMES = {
  inspect_artifact: "Inspect Artifact",
  inspect_macho: "Inspect Mach-O",
  inspect_plist: "Inspect Plist",
  inspect_signature: "Inspect Signature",
  list_architectures: "List Architectures",
  demangle_swift: "Demangle Swift Symbol",
  inspect_go_binary: "Inspect Go Binary",
  inspect_managed_artifact: "Inspect Managed Artifact",
  inspect_managed_members: "Inspect Managed Members",
  inspect_sqlite_database: "Inspect SQLite Database",
  inspect_with_objdump: "Inspect with objdump",
};

function capabilities(id) {
  const isMacOS = process.platform === "darwin";
  const hasObjdump = objdumpAvailable();
  const list = [...ALLOW_LIST].map((operation) => {
    let available = true;
    let unavailableReason = null;
    if (NATIVE_MACOS_OPS.has(operation) && !isMacOS) {
      available = false;
      unavailableReason = "Native macOS inspection requires macOS (REA reports unsupported_host off macOS).";
    } else if (operation === "inspect_with_objdump" && !hasObjdump) {
      available = false;
      unavailableReason = "GNU objdump was not found on PATH.";
    }
    return {
      operation,
      displayName: DISPLAY_NAMES[operation] ?? operation,
      transport: operation === "inspect_with_objdump" ? "pinnedCLI" : "direct",
      available,
      unavailableReason,
      isStaticOnly: true,
    };
  });
  send({ version: PROTOCOL_VERSION, id, type: "result", capabilities: list });
}

async function runDirect(reaDir, operation, targetPath, params) {
  // Dynamic import of the pinned REA dist module. The module path is
  // built from the verified package directory, never from a bare
  // specifier, so no exports map or install layout is assumed.
  const directPath = join(reaDir, "dist/composition/directAnalysis.js");
  const { createDirectAnalysis } = await import(pathToFileURL(directPath).href);
  const service = createDirectAnalysis(undefined);
  const args = {};
  if (operation === "demangle_swift" && typeof params.symbol === "string" && params.symbol.length > 0) {
    // CLI shape is `demangle-swift <path> <symbols...>`; pass the array form.
    args.symbols = [params.symbol];
  }
  const result = await service.runDirectAnalysis(targetPath, operation, args, {});
  return result;
}

function runPinnedCliObjdump(reaDir, targetPath, objdumpOperation, followDebugLinks) {
  return new Promise((resolvePromise, rejectPromise) => {
    const cliPath = join(reaDir, "scripts/rea.mjs");
    const args = [
      cliPath,
      "inspect-with-objdump",
      targetPath,
      objdumpOperation,
    ];
    if (followDebugLinks) args.push("--follow-debug-links");
    args.push("--format", "json");
    cliChild = spawn(process.execPath, args, { stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    cliChild.stdout.on("data", (c) => {
      stdout += c;
      if (stdout.length > MAX_EVIDENCE_BYTES) {
        cliChild.kill("SIGTERM");
        rejectPromise(new Error("CLI output exceeded the 8 MiB limit"));
      }
    });
    cliChild.stderr.on("data", (c) => {
      stderr += c;
    });
    cliChild.on("error", rejectPromise);
    cliChild.on("close", (code) => {
      cliChild = null;
      if (code !== 0 && stdout.trim() === "") {
        rejectPromise(new Error(`rea CLI exited with code ${code}: ${stderr.slice(0, 500)}`));
        return;
      }
      try {
        const parsed = JSON.parse(stdout);
        resolvePromise(parsed);
      } catch {
        rejectPromise(new Error(`rea CLI returned non-JSON output: ${stdout.slice(0, 500)}`));
      }
    });
  });
}

async function handleAnalyze(id, params, reaDir) {
  progress(id, "starting", "Validating request", 1);
  const operation = params?.operation;
  const targetPath = params?.targetPath;
  if (typeof operation !== "string" || !ALLOW_LIST.has(operation)) {
    errorFrame(id, "reverse_unsupported_operation", "unsupportedOperation",
      `Operation '${String(operation)}' is not in the Reverse allow-list.`, false,
      "Use one of the allow-listed operations reported by the capabilities request.");
    return;
  }
  if (typeof targetPath !== "string" || !isAbsolute(targetPath) || !existsSync(targetPath)) {
    errorFrame(id, "reverse_invalid_target", "invalidInput",
      "targetPath must be an existing absolute path.", false,
      "Pass the absolute path of a file you are authorized to analyze.");
    return;
  }
  if (operation === "inspect_with_objdump") {
    const objdumpOperation = params?.objdumpOperation;
    if (typeof objdumpOperation !== "string" || !OBJDUMP_OPS.has(objdumpOperation)) {
      errorFrame(id, "reverse_invalid_objdump_op", "invalidInput",
        `objdumpOperation must be one of: ${[...OBJDUMP_OPS].join(", ")}.`, false,
        "Pass a fixed objdumpOperation; free-form command strings are never accepted.");
      return;
    }
    progress(id, "running", "Running pinned REA CLI fallback for inspect_with_objdump", 2);
    try {
      const evidence = await runPinnedCliObjdump(reaDir, targetPath, objdumpOperation, params?.followDebugLinks === true);
      if (!isValidEvidence(evidence)) {
        errorFrame(id, "reverse_invalid_evidence", "upstreamFailure",
          "Pinned REA CLI returned a payload without a valid Evidence envelope.", false);
        return;
      }
      progress(id, "done", "Evidence received", 3);
      send({ version: PROTOCOL_VERSION, id, type: "result", evidence });
    } catch (err) {
      errorFrame(id, "reverse_cli_failed", "upstreamFailure",
        `Pinned REA CLI failed: ${err?.message ?? String(err)}`, true,
        "Verify the target is readable and objdump is installed, then retry.");
    }
    return;
  }

  // Direct path: real REA implementation via runDirectAnalysis.
  progress(id, "running", `Running direct REA operation ${operation}`, 2);
  try {
    const result = await runDirect(reaDir, operation, targetPath, params ?? {});
    if (result && typeof result === "object" && "error" in result) {
      // REA returns typed error payloads (e.g. capability_unavailable)
      // instead of throwing for unsupported targets.
      const code = typeof result.code === "string" ? result.code : "reverse_upstream_error";
      const category = code === "capability_unavailable" ? "unsupportedOperation" : "upstreamFailure";
      errorFrame(id, code, category,
        typeof result.message === "string" ? result.message : "REA direct analysis failed.",
        result.retryable === true,
        typeof result.remediation?.action === "string" ? result.remediation.action : undefined);
      return;
    }
    if (!isValidEvidence(result)) {
      errorFrame(id, "reverse_invalid_evidence", "upstreamFailure",
        "Direct REA analysis returned a payload without a valid Evidence envelope.", false);
      return;
    }
    progress(id, "done", "Evidence received", 3);
    send({ version: PROTOCOL_VERSION, id, type: "result", evidence: result });
  } catch (err) {
    errorFrame(id, "reverse_direct_failed", "upstreamFailure",
      `Direct REA analysis failed: ${err?.message ?? String(err)}`, false);
  }
}

async function main() {
  const { reaDir: argvReaDir } = parseArgs(process.argv.slice(2));
  const reaDir = resolveReaDir(argvReaDir);
  let raw;
  try {
    raw = await readStdin();
  } catch (err) {
    errorFrame("unknown", "reverse_stdin_failed", "bridgeFailure", `Failed to read bridge request: ${err.message}`, false);
    process.exit(1);
  }
  const firstLine = raw.split("\n").find((line) => line.trim().length > 0);
  if (!firstLine) {
    errorFrame("unknown", "reverse_empty_request", "bridgeFailure", "Bridge received an empty request.", false);
    process.exit(1);
  }
  let request;
  try {
    request = JSON.parse(firstLine);
  } catch {
    errorFrame("unknown", "reverse_bad_json", "bridgeFailure", "Bridge request is not valid JSON.", false);
    process.exit(1);
  }
  if (request?.version !== PROTOCOL_VERSION || typeof request?.id !== "string" || typeof request?.method !== "string") {
    errorFrame(typeof request?.id === "string" ? request.id : "unknown", "reverse_bad_request", "bridgeFailure",
      "Bridge request must carry version 1, a string id, and a string method.", false);
    process.exit(1);
  }
  const { id, method, params } = request;
  if (method === "ping") {
    let reaVersion = null;
    try {
      const pkg = JSON.parse(readFileSync(join(reaDir ?? "", "package.json"), "utf8"));
      reaVersion = pkg.version ?? null;
    } catch { /* reaDir may be null; ping still reports platform */ }
    send({
      version: PROTOCOL_VERSION, id, type: "result",
      ping: { reaVersion, nodeVersion: process.version, platform: process.platform, bridgeVersion: PROTOCOL_VERSION },
    });
    return;
  }
  if (method === "capabilities") {
    capabilities(id);
    return;
  }
  if (method === "shutdown") {
    send({ version: PROTOCOL_VERSION, id, type: "result" });
    return;
  }
  if (method === "analyze") {
    if (!reaDir) {
      errorFrame(id, "reverse_rea_missing", "unavailable",
        "The pinned REA package (rea-agents@6.5.0) was not found.",
        false, "Set SWIFTCODE_REVERSE_REA_DIR or pass --rea-dir to a folder containing rea-agents@6.5.0.");
      return;
    }
    await handleAnalyze(id, params ?? {}, reaDir);
    return;
  }
  errorFrame(id, "reverse_unknown_method", "bridgeFailure", `Unknown bridge method '${method}'.`, false);
}

main().catch((err) => {
  try {
    errorFrame("unknown", "reverse_bridge_crash", "bridgeFailure",
      `Bridge crashed: ${err?.message ?? String(err)}`, false);
  } catch { /* stdout may be gone; nothing else to do */ }
  process.exit(1);
});
