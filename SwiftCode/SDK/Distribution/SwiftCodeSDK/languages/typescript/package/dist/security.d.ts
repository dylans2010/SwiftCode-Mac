/**
 * Real TypeScript client for the SDK's Security (Keychain) API.
 *
 * The wire methods below are the exact IPC routes the host's Security
 * dispatcher serves (the `use.Security` host phase builds alongside this
 * client; see `SDKCapabilityID.useSecurity` = "use.Security"):
 *
 *   security.addValue    payload {"securityID","valueID","label?","prompt?"}
 *                        → {"valueID","created"}
 *   security.hasValue    payload {"securityID","valueID"} → {"hasValue"}
 *   security.listValueIDs payload {"securityID"} → {"values":[{"valueID","label","createdAt"}]}
 *   security.deleteValue payload {"securityID","valueID"} → null
 *   security.useValue    payload {"securityID","valueID","operation"}
 *                        → {"status","body"}
 *
 * The design invariant: plaintext secrets NEVER cross this boundary in
 * either direction. `addValue` resolves with metadata only (the user types
 * the secret into the host's secure popup); `useValue` asks the host to
 * attach the secret as the `Authorization` header and perform the HTTPS
 * request itself, returning only `{status, body}`.
 *
 * Client-side validation here mirrors the host's rules so developers get
 * early, friendly failures (invalid IDs, non-HTTPS URLs, credentials
 * embedded in URLs, a client-supplied `Authorization` header). The host
 * re-validates everything; this is not the security boundary.
 *
 * Usage: in extension code prefer `context.security` (wired by
 * `createContext` in `context.ts`). The standalone `security*` helpers
 * delegate to the connection installed by `createSecurityAPI` — a single
 * runtime process hosts one active connection at a time, and
 * `createContext` calls `createSecurityAPI` for it.
 */
import { type HostConnection } from "./ipc.js";
import type { SecurityAPI, SecurityAddOptions, SecurityAddedValue, SecurityHTTPResponse, SecurityOperation, SecurityStoredValue } from "./types.js";
/**
 * Builds the real Security API over an IPC connection and installs it as
 * the target of the standalone `security*` helpers. The host must serve
 * the `security.*` routes (the `use.Security` host phase); until then the
 * host answers with a typed error, which surfaces as a rejected
 * {@link SDKError} — never a fabricated result.
 */
export declare function createSecurityAPI(connection: HostConnection): SecurityAPI;
/**
 * Triggers the host's secure popup to store a secret under the given IDs.
 * Resolves with metadata ONLY (`{valueID, created}`) — the secret is
 * entered by the user directly into the host and never reaches extension
 * code.
 *
 * Requires the `use.Security` capability grant. Delegates to the
 * connection installed by `createSecurityAPI` (which `createContext` calls
 * for the active runtime connection).
 */
export declare function securityAddValue(securityID: string, valueID: string, options?: SecurityAddOptions): Promise<SecurityAddedValue>;
/** True when a value exists for the given IDs. Metadata only, never secrets. */
export declare function securityHasValue(securityID: string, valueID: string): Promise<boolean>;
/** Metadata for every value stored under the security ID. Never secrets. */
export declare function securityListValueIDs(securityID: string): Promise<SecurityStoredValue[]>;
/** Deletes the stored value. */
export declare function securityDeleteValue(securityID: string, valueID: string): Promise<void>;
/**
 * Asks the host to perform an HTTPS request with the stored secret
 * attached as the `Authorization` header. The secret never comes back to
 * the extension — only `{status, body}` do. The URL is validated
 * client-side (https only, no embedded credentials) and the host
 * re-validates.
 */
export declare function securityUseValue(securityID: string, valueID: string, operation: SecurityOperation): Promise<SecurityHTTPResponse>;
