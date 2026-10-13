/**
 * Headless Assist SDK variant: `assistSDK` (Docs/Intro-to-SDK.md §11, task B2).
 *
 * The full Assist API surface EXCEPT UI — sessions, streaming responses,
 * tool access per the approved scope. The developer renders everything
 * themselves. There is intentionally NO view-opening path in this module:
 * it never imports or calls `ui.openView` (or anything from
 * `assistUI.ts`); presenting UI belongs to `assistSDK.UI`.
 *
 * WIRE CONTRACT — DEPENDENCY ON THE SIBLING TASK:
 * Every public function routes through the IPC connection to the
 * dedicated entitled route `assist.invoke`, with an `op` discriminator in
 * the payload:
 *
 *   assist.invoke  {"op":"session.create","systemPrompt?","model?"}
 *                  → {"sessionId","createdAt"}
 *   assist.invoke  {"op":"session.list"} → {"sessions":[{"sessionId","createdAt"}]}
 *   assist.invoke  {"op":"message.send","sessionId","message"} → {"reply"}
 *   assist.invoke  {"op":"message.stream","sessionId","message"} → {"accepted":true}
 *   assist.invoke  {"op":"tool.invoke","sessionId","tool","arguments"} → {"tool","result"}
 *   assist.invoke  {"op":"session.close","sessionId"} → null
 *
 * The sibling task implements the `assist.invoke` route in
 * `SDKIPCDispatcher` and carves the entitled path out of
 * `SDKAssistGate.check` (which currently deny-lists the `assist`
 * substring); until that lands, the host answers with the typed
 * `ASSIST_DENIED` denial and every call below throws
 * {@link SDKAssistAccessError}. Nothing here is a stub: calls genuinely
 * go to the host, and host rejections surface as real errors.
 *
 * Streaming: `message.stream` resolves once the host accepts the stream
 * (or rejects with the typed denial). Response chunks arrive as
 * `assist.stream` host events correlated by the request's `requestId`,
 * each with payload `{"delta","done"}`; a final `done: true` chunk ends
 * the stream. A chunk carrying `"error"` fails the iterator with the
 * host's typed error.
 *
 * ENTITLEMENT HONESTY: the TS layer cannot know entitlement state itself
 * and never fabricates it. Only the host's typed `ASSIST_DENIED` denial
 * is translated into {@link SDKAssistAccessError} (carrying the verbatim
 * §13 user message). Every other rejection — including `PERMISSION_DENIED`
 * from unrelated checks — propagates as the original SDKError untouched.
 */
import { type HostConnection } from "./ipc.js";
import { type AssistAPI } from "./types.js";
/**
 * Builds the real headless Assist API over an IPC connection. Every call
 * below performs a genuine `assist.invoke` round-trip; nothing is
 * simulated. In extension code prefer `context.assist` (wired by
 * `createContext` in `context.ts`).
 */
export declare function createAssistAPI(connection: HostConnection): AssistAPI;
