/**
 * Real implementation of the developer-facing SDK context
 * (Docs/Intro-to-SDK.md §6.2, §11.2, §11.3).
 *
 * Method list is taken from the Swift host's `SDKIPCDispatcher` routing
 * table — only methods the dispatcher actually supports are called:
 *
 *   sourceControl.getStatus   payload {}
 *   sourceControl.getDiff     payload {"options": {...}} (optional)
 *   build.run                 payload {"target","configuration?","destination?"}
 *                             → {"handleId"}
 *   build.wait                payload {"handleId"} → BuildResult
 *   build.cancel              payload {"handleId"}
 *   cloudModel.complete       payload {"prompt","history?","systemPrompt?","modelIdentifier?"}
 *                             → {"response"}
 *   assist.invoke             payload {"op", ...} — the entitled headless
 *                             Assist route (see assist.ts); handled by
 *                             createAssistAPI, not by the context object
 *   terminalSandbox.run       payload {"command","args","workingDirectory?","timeout?"}
 *                             → TerminalSandboxResult
 *   commands.register         payload {"id","title"}
 *   commands.unregister       payload {"commandID"}
 *   ui.openView                 payload {"viewId"} — viewId is the view's
 *                               own capability ID (e.g. "sandbox.view")
 *   log.debug|info|warn|error payload {"message","correlationId?"}
 *   security.addValue       payload {"securityID","valueID","label?","prompt?"}
 *                             → {"valueID","created"} (metadata only, never the secret)
 *   security.hasValue       payload {"securityID","valueID"} → {"hasValue"}
 *   security.listValueIDs   payload {"securityID"} → {"values":[…]}
 *   security.deleteValue    payload {"securityID","valueID"}
 *   security.useValue       payload {"securityID","valueID","operation"}
 *                             → {"status","body"} (the host attaches the
 *                               secret as the Authorization header; it never
 *                               comes back to the extension)
 *
 * `security.*` routes are served by the host's Security dispatcher (the
 * `use.Security` host phase, capability ID "use.Security"). Until the
 * routes land, the host answers with a typed error — calls reject with an
 * {@link SDKError}, never a fabricated result.
 *
 * `project.getCurrent` is NOT in the dispatcher routing table. It is sent
 * as `project.getCurrent` anyway, and the host answers with a typed error
 * (`IPC_MALFORMED`: "Unknown method") until the method lands in a later
 * host phase. This method never fabricates a project — a failed request
 * surfaces as an {@link SDKError}, never a fake `ProjectInfo`.
 */
import type { ExtensionInfo, SwiftCodeContext } from "./types.js";
import { type HostConnection } from "./ipc.js";
export interface CreatedContext {
    readonly context: SwiftCodeContext;
    /**
     * Returns the handler for a registered command ID, or undefined.
     * Used by the runtime to dispatch `commands.execute` host events.
     */
    getCommandHandler(id: string): ((payload?: unknown) => Promise<unknown>) | undefined;
}
/**
 * Builds the real extension context over an IPC connection.
 *
 * The runtime wires `commands.execute` host events to registered handlers
 * via the returned `getCommandHandler`. `log.*` calls are fire-and-forget:
 * they are sent but never awaited, so logging can never stall an extension.
 */
export declare function createContext(connection: HostConnection, extensionInfo: ExtensionInfo): CreatedContext;
