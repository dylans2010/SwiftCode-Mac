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
export {};
//# sourceMappingURL=adapter.d.ts.map