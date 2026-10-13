/**
 * Public developer contract for the SwiftCode SDK (TypeScript).
 *
 * Finalized from Docs/Intro-to-SDK.md §6.2 (TypeScript developer contract
 * intent) and §11.2/§11.3 (API minimums), matched against the Swift host
 * contracts in `SwiftCode/SDK/Contracts/Protocol/`.
 *
 * These are types only. The real implementations of the IPC client and the
 * context live in `ipc.ts` and `context.ts`.
 */
/* ------------------------------------------------------------------ */
/* Assist SDK variants (task B2: `assistSDK` and `assistSDK.UI`)       */
/* ------------------------------------------------------------------ */
/**
 * The exact user-facing message the host produces when an Assist call is
 * denied for lack of a verified entitlement (Docs/Intro-to-SDK.md §13).
 *
 * VERBATIM — do not reword. The TypeScript layer never fabricates this:
 * it is thrown only when the host answers with the typed `ASSIST_DENIED`
 * denial, via {@link SDKAssistAccessError}.
 */
export const ASSIST_ACCESS_DENIED_MESSAGE = "This app is not allowed to use Assist because access has not yet been verified. Please check with the app developer for further information.";
/**
 * Typed denial for Assist calls. Thrown ONLY when the host answers with
 * the typed `ASSIST_DENIED` error — i.e. the host has checked the
 * key-bound `com.SwiftCode.developer-AI-Assist` entitlement and found it
 * missing or revoked.
 *
 * The TS layer cannot know entitlement state itself and must NOT
 * fabricate it: any other host rejection (including `PERMISSION_DENIED`
 * for unrelated reasons) propagates as the original {@link SDKErrorShape}
 * untouched. Catch this class specifically to show the user the exact
 * §13 message.
 */
export class SDKAssistAccessError extends Error {
    /** Always `"ASSIST_DENIED"`: the typed host denial code. */
    code = "ASSIST_DENIED";
    /** Correlation ID of the denied request, for host-side log lookup. */
    correlationId;
    constructor(correlationId) {
        super(ASSIST_ACCESS_DENIED_MESSAGE);
        this.name = "SDKAssistAccessError";
        // randomUUID is called lazily to avoid importing node:crypto at module
        // load for pure-type consumers of this file.
        this.correlationId =
            typeof correlationId === "string" && correlationId.length > 0
                ? correlationId
                : "unknown";
    }
}
/** Metadata for one headless Assist session. Never carries contents. */
/* ------------------------------------------------------------------ */
/* Cloud-model access denial (Docs/Intro-to-SDK.md §12–§13, task B4)    */
/* ------------------------------------------------------------------ */
/**
 * The exact user-facing message the host produces when a cloud-model call
 * is denied for lack of a verified entitlement (Docs/Intro-to-SDK.md §13).
 *
 * PROPOSED WORDING — Dylan finalizes the exact text. The TypeScript layer
 * never fabricates this: it is thrown only when the host answers with the
 * typed `CLOUD_MODEL_DENIED` denial, via {@link SDKCloudModelAccessError}.
 */
export const CLOUD_MODEL_ACCESS_DENIED_MESSAGE = "This app is not allowed to use the SwiftCode Cloud Model because access has not yet been verified. Please check with the app developer for further information.";
/**
 * Typed denial for cloud-model calls. Thrown ONLY when the host answers
 * with the typed `CLOUD_MODEL_DENIED` error — i.e. the host has checked
 * the key-bound `com.SwiftCode.developer-AI-Allows-Cloud` entitlement and
 * found it missing or revoked.
 *
 * Mirrors {@link SDKAssistAccessError}: the TS layer cannot know
 * entitlement state itself and must NOT fabricate it. Any other host
 * rejection (including `PERMISSION_DENIED` for unrelated reasons or
 * `RESOURCE_LIMIT_EXCEEDED` for quota) propagates as the original
 * {@link SDKErrorShape} untouched. Catch this class specifically to show
 * the user the exact §13 message.
 */
export class SDKCloudModelAccessError extends Error {
    /** Always `"CLOUD_MODEL_DENIED"`: the typed host denial code. */
    code = "CLOUD_MODEL_DENIED";
    /** Correlation ID of the denied request, for host-side log lookup. */
    correlationId;
    constructor(correlationId) {
        super(CLOUD_MODEL_ACCESS_DENIED_MESSAGE);
        this.name = "SDKCloudModelAccessError";
        // randomUUID is called lazily to avoid importing node:crypto at module
        // load for pure-type consumers of this file.
        this.correlationId =
            typeof correlationId === "string" && correlationId.length > 0
                ? correlationId
                : "unknown";
    }
}
//# sourceMappingURL=types.js.map