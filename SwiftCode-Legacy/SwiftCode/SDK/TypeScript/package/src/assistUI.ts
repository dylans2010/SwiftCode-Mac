/**
 * UI Assist SDK variant: `assistSDK.UI` (Docs/Intro-to-SDK.md §11, task B2).
 *
 * Exposes ONLY embedding of the host's real Assist main view inside the
 * developer's app. The host presents it; the extension never touches
 * Assist internals. There are deliberately NO headless session/streaming
 * APIs in this module — those belong to `assistSDK` (`assist.ts`).
 *
 * Presentation path: the single public function calls
 * `ui.openView({ viewId: ASSIST_VIEW_ID })` — no custom Assist chrome, no
 * other view-opening path.
 *
 * HOST DEPENDENCY (deterministic viewId rule): no Assist main view is
 * registered in `SwiftCode/SDK/Host/ViewOpener/SDKViewOpenerBuiltIns.swift`
 * as of this change, so this module defines and uses
 * `ASSIST_VIEW_ID = "assist.main"`. The host MUST register an opener for
 * exactly this viewId (a sibling Swift task owns the view-opener
 * registration and follows the same rule: use the registered Assist main
 * view's exact viewId when one exists). Until the host registers it,
 * `openAssistView` rejects with the host's typed unknown-view error.
 *
 * ENTITLEMENT HONESTY: the TS layer cannot know entitlement state itself
 * and never fabricates it. Only the host's typed `ASSIST_DENIED` denial
 * is translated into {@link SDKAssistAccessError} (carrying the verbatim
 * §13 user message); every other rejection propagates untouched.
 */

import { SDKError, type HostConnection } from "./ipc.js";
import { SDKAssistAccessError, type AssistUIAPI } from "./types.js";

/**
 * The viewId payload value sent to `ui.openView` to embed the host's
 * Assist main view. Deterministic per the rule documented above: no
 * Assist view is registered in `SDKViewOpenerBuiltIns.swift` yet, so the
 * SDK defines `"assist.main"` and the host must register it.
 */
export const ASSIST_VIEW_ID = "assist.main";

/**
 * Translates ONLY the host's typed Assist denial into the user-facing
 * error. Everything else rethrows unchanged.
 */
function mapAssistDenial(error: unknown): never {
  if (error instanceof SDKError && error.code === "ASSIST_DENIED") {
    throw new SDKAssistAccessError(error.correlationId);
  }
  throw error;
}

/**
 * Builds the real UI Assist API over an IPC connection. The single call
 * performs a genuine `ui.openView` round-trip; nothing is simulated. In
 * extension code prefer `context.assistUI` (wired by `createContext` in
 * `context.ts`).
 */
export function createAssistUIAPI(connection: HostConnection): AssistUIAPI {
  return {
    async openAssistView(): Promise<void> {
      try {
        // CALL SITE — exact method string: the Swift dispatcher's
        // "ui.openView" route. The host authorizes the view's capability
        // at the broker before the opener runs; the Assist entitlement
        // check for this variant happens on the host side (task B4, the
        // sibling's dispatcher/gate work — same dependency as assist.ts).
        await connection.request<unknown>("ui.openView", { viewId: ASSIST_VIEW_ID });
      } catch (error) {
        mapAssistDenial(error);
      }
    },
  };
}
