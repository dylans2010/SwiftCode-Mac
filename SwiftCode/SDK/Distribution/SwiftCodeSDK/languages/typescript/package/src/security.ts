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

import { SDKError, type HostConnection } from "./ipc.js";
import type {
  SecurityAPI,
  SecurityAddOptions,
  SecurityAddedValue,
  SecurityHTTPRequest,
  SecurityHTTPResponse,
  SecurityOperation,
  SecurityStoredValue,
} from "./types.js";

/**
 * Client-side identifier rule: printable ASCII, no whitespace, 1–256
 * characters. Mirrors the host's keyspace constraints; secrets themselves
 * are never validated here because they never reach this code.
 */
const SECURITY_ID_PATTERN = /^[\x21-\x7E]{1,256}$/;
/** Client-side mirror of the host's HTTP-method rule: a bare method token. */
const HTTP_METHOD_PATTERN = /^[A-Za-z]{1,16}$/;

function validateID(kind: "securityID" | "valueID", id: unknown): string {
  if (typeof id !== "string" || !SECURITY_ID_PATTERN.test(id)) {
    throw new SDKError(
      "INVALID_ARGUMENT",
      `${kind} must be 1–256 printable ASCII characters with no whitespace (e.g. "api-keys" / "github-token").`,
    );
  }
  return id;
}

function validateOptionalLabel(label: unknown): string | undefined {
  if (label === undefined) return undefined;
  if (typeof label !== "string" || label.length === 0 || label.includes("\0")) {
    throw new SDKError(
      "INVALID_ARGUMENT",
      "Security label must be a non-empty string without NUL bytes.",
    );
  }
  return label;
}

/**
 * Validates the HTTPS request the host will perform with the stored
 * secret. Rejects non-HTTPS URLs (secrets must never travel in plaintext),
 * URLs embedding credentials (the secret is attached by the host as the
 * `Authorization` header, never read from the URL), and a client-supplied
 * `Authorization` header (the host owns that header).
 */
function validateHTTPRequest(request: unknown): SecurityHTTPRequest {
  if (typeof request !== "object" || request === null) {
    throw new SDKError(
      "INVALID_ARGUMENT",
      "Security operation request must be an object with {method, url}.",
    );
  }
  const raw = request as Record<string, unknown>;
  const method = raw["method"];
  if (typeof method !== "string" || !HTTP_METHOD_PATTERN.test(method)) {
    throw new SDKError(
      "INVALID_ARGUMENT",
      `Security HTTP method "${String(method)}" is invalid: use a bare method token such as "GET" or "POST".`,
    );
  }
  const url = raw["url"];
  if (typeof url !== "string" || url.length === 0) {
    throw new SDKError("INVALID_ARGUMENT", "Security HTTP request URL must be a non-empty string.");
  }
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw new SDKError(
      "INVALID_ARGUMENT",
      `Security HTTP request URL "${url}" is not a valid absolute URL.`,
    );
  }
  if (parsed.protocol !== "https:") {
    throw new SDKError(
      "INVALID_ARGUMENT",
      `Security HTTP request URL must use https (got "${parsed.protocol}"). Secrets are never sent over plaintext HTTP.`,
    );
  }
  if (parsed.username !== "" || parsed.password !== "") {
    throw new SDKError(
      "INVALID_ARGUMENT",
      "Security HTTP request URL must not embed credentials. The stored secret is attached by the host as the Authorization header.",
    );
  }
  let headers: Record<string, string> | undefined;
  if (raw["headers"] !== undefined) {
    const rawHeaders = raw["headers"];
    if (typeof rawHeaders !== "object" || rawHeaders === null || Array.isArray(rawHeaders)) {
      throw new SDKError("INVALID_ARGUMENT", "Security HTTP request headers must be a string-to-string map.");
    }
    headers = {};
    for (const [name, value] of Object.entries(rawHeaders as Record<string, unknown>)) {
      if (typeof value !== "string") {
        throw new SDKError(
          "INVALID_ARGUMENT",
          `Security HTTP header "${name}" must have a string value.`,
        );
      }
      headers[name] = value;
    }
    if (Object.keys(headers).some((name) => name.toLowerCase() === "authorization")) {
      throw new SDKError(
        "INVALID_ARGUMENT",
        "Security HTTP request must not set the Authorization header: the host attaches the stored secret as that header.",
      );
    }
  }
  const body = raw["body"];
  if (body !== undefined && typeof body !== "string") {
    throw new SDKError("INVALID_ARGUMENT", "Security HTTP request body must be a string.");
  }
  const validated: SecurityHTTPRequest = { method: method.toUpperCase(), url };
  return headers !== undefined
    ? body !== undefined
      ? { ...validated, headers, body }
      : { ...validated, headers }
    : body !== undefined
      ? { ...validated, body }
      : validated;
}

function validateOperation(operation: unknown): SecurityOperation {
  if (typeof operation !== "object" || operation === null) {
    throw new SDKError("INVALID_ARGUMENT", "Security operation must be an object.");
  }
  const raw = operation as Record<string, unknown>;
  if (raw["kind"] !== "httpAuthorization") {
    throw new SDKError(
      "INVALID_ARGUMENT",
      `Unsupported security operation kind "${String(raw["kind"])}". The only supported kind is "httpAuthorization".`,
    );
  }
  return { kind: "httpAuthorization", request: validateHTTPRequest(raw["request"]) };
}

function asRecord(payload: unknown, method: string): Record<string, unknown> {
  if (typeof payload !== "object" || payload === null) {
    throw new SDKError(
      "IPC_MALFORMED",
      `The host returned an invalid ${method} response.`,
      undefined,
    );
  }
  return payload as Record<string, unknown>;
}

function assertAddedValue(payload: unknown): SecurityAddedValue {
  const record = asRecord(payload, "security.addValue");
  const valueID = record["valueID"];
  const created = record["created"];
  if (typeof valueID !== "string" || typeof created !== "boolean") {
    throw new SDKError("IPC_MALFORMED", "The host returned an invalid security.addValue response.", undefined);
  }
  return { valueID, created };
}

function assertHasValue(payload: unknown): boolean {
  const record = asRecord(payload, "security.hasValue");
  if (typeof record["hasValue"] !== "boolean") {
    throw new SDKError("IPC_MALFORMED", "The host returned an invalid security.hasValue response.", undefined);
  }
  return record["hasValue"];
}

function assertStoredValues(payload: unknown): SecurityStoredValue[] {
  const record = asRecord(payload, "security.listValueIDs");
  const values = record["values"];
  if (!Array.isArray(values)) {
    throw new SDKError("IPC_MALFORMED", "The host returned an invalid security.listValueIDs response.", undefined);
  }
  return values.map((entry, index) => {
    if (typeof entry !== "object" || entry === null) {
      throw new SDKError(
        "IPC_MALFORMED",
        `The host returned an invalid security.listValueIDs entry at index ${index}.`,
        undefined,
      );
    }
    const candidate = entry as Record<string, unknown>;
    const valueID = candidate["valueID"];
    const label = candidate["label"];
    const createdAt = candidate["createdAt"];
    if (typeof valueID !== "string" || typeof label !== "string" || typeof createdAt !== "string") {
      throw new SDKError(
        "IPC_MALFORMED",
        `The host returned an invalid security.listValueIDs entry at index ${index}.`,
        undefined,
      );
    }
    return { valueID, label, createdAt };
  });
}

function assertHTTPResponse(payload: unknown): SecurityHTTPResponse {
  const record = asRecord(payload, "security.useValue");
  const status = record["status"];
  const body = record["body"];
  if (typeof status !== "number" || !Number.isInteger(status) || typeof body !== "string") {
    throw new SDKError("IPC_MALFORMED", "The host returned an invalid security.useValue response.", undefined);
  }
  return { status, body };
}

/**
 * The Security API implementation the standalone helpers delegate to.
 * Installed by {@link createSecurityAPI}; a runtime process hosts one
 * active connection at a time, and `createContext` calls
 * `createSecurityAPI` for it, so the standalone helpers resolve against
 * the same connection as `context.security`.
 */
let installedAPI: SecurityAPI | null = null;

/**
 * Builds the real Security API over an IPC connection and installs it as
 * the target of the standalone `security*` helpers. The host must serve
 * the `security.*` routes (the `use.Security` host phase); until then the
 * host answers with a typed error, which surfaces as a rejected
 * {@link SDKError} — never a fabricated result.
 */
export function createSecurityAPI(connection: HostConnection): SecurityAPI {
  const api: SecurityAPI = {
    async addValue(securityID: string, valueID: string, options?: SecurityAddOptions): Promise<SecurityAddedValue> {
      const sid = validateID("securityID", securityID);
      const vid = validateID("valueID", valueID);
      const payload: Record<string, unknown> = { securityID: sid, valueID: vid };
      const label = validateOptionalLabel(options?.label);
      if (label !== undefined) payload["label"] = label;
      const prompt = validateOptionalLabel(options?.prompt);
      if (prompt !== undefined) payload["prompt"] = prompt;
      // Exact method string: the host's security dispatcher route.
      const response = await connection.request<unknown>("security.addValue", payload);
      // Metadata only — the secret never crosses IPC, so there is nothing
      // to redact here; the shape check just rejects malformed hosts.
      return assertAddedValue(response);
    },

    async hasValue(securityID: string, valueID: string): Promise<boolean> {
      const sid = validateID("securityID", securityID);
      const vid = validateID("valueID", valueID);
      const response = await connection.request<unknown>("security.hasValue", {
        securityID: sid,
        valueID: vid,
      });
      return assertHasValue(response);
    },

    async listValueIDs(securityID: string): Promise<SecurityStoredValue[]> {
      const sid = validateID("securityID", securityID);
      const response = await connection.request<unknown>("security.listValueIDs", {
        securityID: sid,
      });
      return assertStoredValues(response);
    },

    async deleteValue(securityID: string, valueID: string): Promise<void> {
      const sid = validateID("securityID", securityID);
      const vid = validateID("valueID", valueID);
      // The host answers with a null payload on success.
      await connection.request<unknown>("security.deleteValue", {
        securityID: sid,
        valueID: vid,
      });
    },

    async useValue(
      securityID: string,
      valueID: string,
      operation: SecurityOperation,
    ): Promise<SecurityHTTPResponse> {
      const sid = validateID("securityID", securityID);
      const vid = validateID("valueID", valueID);
      const validated = validateOperation(operation);
      const payload: Record<string, unknown> = {
        securityID: sid,
        valueID: vid,
        operation: {
          kind: validated.kind,
          request: {
            method: validated.request.method,
            url: validated.request.url,
            ...(validated.request.headers !== undefined ? { headers: validated.request.headers } : {}),
            ...(validated.request.body !== undefined ? { body: validated.request.body } : {}),
          },
        },
      };
      const response = await connection.request<unknown>("security.useValue", payload);
      // Only {status, body} come back: the secret stays host-side.
      return assertHTTPResponse(response);
    },
  };
  installedAPI = api;
  return api;
}

function requireInstalledAPI(): SecurityAPI {
  if (installedAPI === null) {
    throw new SDKError(
      "INVALID_STATE",
      "The Security API has no host connection yet. In extension code use context.security; the standalone helpers work once createContext() (or createSecurityAPI()) has run.",
    );
  }
  return installedAPI;
}

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
export async function securityAddValue(
  securityID: string,
  valueID: string,
  options?: SecurityAddOptions,
): Promise<SecurityAddedValue> {
  return requireInstalledAPI().addValue(securityID, valueID, options);
}

/** True when a value exists for the given IDs. Metadata only, never secrets. */
export async function securityHasValue(securityID: string, valueID: string): Promise<boolean> {
  return requireInstalledAPI().hasValue(securityID, valueID);
}

/** Metadata for every value stored under the security ID. Never secrets. */
export async function securityListValueIDs(securityID: string): Promise<SecurityStoredValue[]> {
  return requireInstalledAPI().listValueIDs(securityID);
}

/** Deletes the stored value. */
export async function securityDeleteValue(securityID: string, valueID: string): Promise<void> {
  return requireInstalledAPI().deleteValue(securityID, valueID);
}

/**
 * Asks the host to perform an HTTPS request with the stored secret
 * attached as the `Authorization` header. The secret never comes back to
 * the extension — only `{status, body}` do. The URL is validated
 * client-side (https only, no embedded credentials) and the host
 * re-validates.
 */
export async function securityUseValue(
  securityID: string,
  valueID: string,
  operation: SecurityOperation,
): Promise<SecurityHTTPResponse> {
  return requireInstalledAPI().useValue(securityID, valueID, operation);
}
