# Security and Keychain (`use.Security`)

**Status:** Implemented — uncommitted working tree · **Branch:** `feature/swiftcode-sdk` · **Date:** 2026-10-12
**Spec:** `Docs/Intro-to-SDK.md` §§8, 16 · **ADRs:** `SDK-Architecture.md` §§5, 11

> **Implementation-status warning:** as of this writing every piece below
> exists as **uncommitted working-tree changes** (not yet committed or
> reviewed). The capability IDs, audit event types, scope-list entries, the
> TypeScript client (`security.ts`), the host store
> (`Host/Security/KeychainSDK.swift`), the host service
> (`Host/Security/SDKSecurityService.swift`), the `security.*` routes in
> `SDKIPCDispatcher`, the secure-prompt coordinator
> (`SDKSensitiveValuePrompt`), and the entry UI (`EnterSecuritySDKView`)
> are all present in the tree. Re-verify every claim in this doc against
> committed code once the work lands.

## What `use.Security` grants

`use.Security` is a **high-risk capability** ("Use Security (Keychain)") that
lets an extension *use* user-provided secrets through the host — never hold
them. Five granular capability IDs pair 1:1 with the five IPC methods
(`SDKCapability.swift`, `ScopesIDLists.swift`/`ScopesIDLists.ts`):

| Capability ID | IPC method | Risk | What it allows |
|---|---|---|---|
| `security.addValue` | `security.addValue` | high | Store a named secret; the host presents the secure prompt and writes the value — the extension never sees plaintext |
| `security.hasValue` | `security.hasValue` | medium | Check whether a named secret exists, without revealing it |
| `security.listValueIDs` | `security.listValueIDs` | medium | List stored value names and metadata — never values |
| `security.deleteValue` | `security.deleteValue` | high | Permanently delete one stored value |
| `security.useValue` | `security.useValue` | high | Ask the host to inject a stored secret into an approved host operation |

The five granular IDs are **method scopes, not separately grantable
permissions** (`grantableInCurrentRelease: false` in `SDKCapability.swift`).
The user grants the single `use.Security` capability; the host authorizes
**only** the umbrella at the broker on every `security.*` call
(`SDKSecurityService.authorize` checks `.useSecurity` and nothing else —
checking a non-grantable ID would deny every call). The granular IDs exist
so audit events, scope listings, and approval UX can name the exact method
scope in play; they can never appear in a grant.

The TypeScript `security` namespace requires the `use.Security` grant
(`types.ts`); the five sub-IDs are the per-method scope records that ride
along in audit detail and scope listings, not permission checks.

## What it explicitly does NOT grant

- **The extension never sees plaintext.** No IPC response ever carries the
  secret. `addValue` resolves to `{ valueID, created }` — metadata only.
  `hasValue` returns a boolean. `listValueIDs` returns `{ valueID, label,
  createdAt }[]` — names, never values. `useValue` returns `{ status, body }`,
  never the secret. A secret in transit to the extension is a contract
  violation.
- **Host-mediated use only.** There is no "read the secret" method — on the
  host side `KeychainSDK.readValue` is deliberately `internal`
  (HOST-ONLY), so it cannot be reached through any public or IPC path. The
  only supported operation kind is `httpAuthorization`
  (`SecurityOperation`): the host attaches the secret as the `Authorization`
  header and performs the HTTPS request itself. URLs must be HTTPS
  (client-side validation rejects plaintext HTTP, credential-embedding URLs,
  and an extension-supplied `Authorization` header; the host re-validates).
  If no host operation exists for a request, it fails with a typed error —
  the extension cannot improvise its own use.
- **Per-app namespaces, by construction.** Every app gets its own Keychain
  service partition: `com.swiftcode.sdk.security.<securityID>`, built in
  exactly one place (`KeychainSDK.namespacedService(for:)`); no method
  accepts a raw service string, and every query exact-matches
  `kSecAttrService`. A value stored for extension A is invisible to
  extension B, even for the same Security ID and Value ID. One extension's
  grant never unlocks another's secrets.
- **No export, no sync, no plaintext cache.** `KeychainSDK` upholds the same
  hard rules as `SDKKeychain` (`Capabilities-and-Permissions.md`): secrets
  live only in the Keychain (`kSecClassGenericPassword`, service namespaced
  as above), accessibility `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`,
  no `kSecAttrSynchronizable`, **no UserDefaults fallback**, **no
  in-memory cache** — every read hits the Keychain. Keychain failures fail
  closed (`SERVICE_UNAVAILABLE`), never by degrading to a weaker store.

## Security ID and Security Value ID

Two identifiers, two jobs:

| Identifier | Answers | Example |
|---|---|---|
| **Security ID** (`securityID`) | *Which app's vault* — the per-app namespace, assigned by the host | `com.example.myapp` |
| **Security Value ID** (`valueID`) | *Which stored value* — the named slot inside that vault | `openai-key`, `google-client-secret` |

The pair resolves one Keychain item (service =
`com.swiftcode.sdk.security.<securityID>`, account = `<valueID>`, label =
human label). One app can hold several values for different purposes, and
re-storing a value updates it in place (`addValue` returns `created: false`
on update; a `nil` label on update preserves the existing label).

**OpenAI-key vs Google-client-secret example:** an app stores
`securityID = "com.example.myapp"`, `valueID = "openai-key"` — the host
resolves the item in the app's own partition. `useValue` on
`valueID = "google-client-secret"` in the same partition resolves a
*different* item; entering the OpenAI key does not authorize, or reveal the
existence of, the Google client secret beyond the `hasValue` boolean the app
already asked about. Cross-app, cross-value isolation holds simultaneously:
another app's `com.example.otherapp` partition is a different Keychain
service string, unreachable by construction.

Identity binding: the Security ID is tied to the app's **verified extension
identity** (manifest + registry) — never taken from an extension-supplied
IPC payload. The payload's `securityID` is validated against format rules
and must resolve to the calling app's own partition; arbitrary strings
cannot reach other partitions because `namespacedService(for:)` validates
every ID before building the service string. The dispatcher-side binding is
built: `SDKSecurityService.namespacedSecurityID` derives the composed
namespace from the session-bound caller identity and rejects a payload
`securityID` that already carries the session's extension namespace.

Identifier rules, enforced on both sides (the client is early-friendly; the
host is the real boundary):
- **Client** (`security.ts`): `securityID`/`valueID` must be 1–256 printable
  ASCII characters, no whitespace.
- **Host** (`KeychainSDK`): Security IDs are reverse-DNS — 1–128 chars, at
  least two dot-separated segments (a bare word like `keychain` is
  rejected), segments 1–63 chars of ASCII letters/digits with interior `-`
  only. Value IDs are single kebab-ish labels — 1–128 chars, ASCII
  letters/digits with interior `.`/`-`/`_`, never leading/trailing.
  Rejected outright on both: `/`, whitespace, control characters,
  leading/trailing dots, empty segments, and any `..` (path-traversal
  shape) — nothing that could alias or escape the partition.

## The `security.*` TypeScript API

The client is `TypeScript/package/src/security.ts` (real implementation, in
the working tree, uncommitted; 281 lines of `node:test` coverage in
`tests/security.test.mjs`). Types live in `types.ts` (`SecurityAPI`,
`SecurityAddOptions`, `SecurityAddedValue`, `SecurityStoredValue`,
`SecurityOperation`, `SecurityHTTPRequest`, `SecurityHTTPResponse`).
Extension code uses `context.security` (wired by `createContext`, which calls
`createSecurityAPI(connection)`); standalone `securityAddValue` /
`securityHasValue` / `securityListValueIDs` / `securityDeleteValue` /
`securityUseValue` helpers delegate to the installed connection and throw
`INVALID_STATE` before one is installed. Method names are the exact IPC
routes the host's Security dispatcher will serve:

```ts
// Store a secret: triggers the host's secure popup; the user types the
// value directly into the host. addValue takes NO secret argument — the
// extension never handles it. Resolves with metadata only.
const added: SecurityAddedValue = await ctx.security.addValue(
  "com.example.myapp",
  "openai-key",
  { label: "OpenAI API key", prompt: "Used only to call the models endpoint" },
);
// added → { valueID: "openai-key", created: true }

// Check presence without touching the secret.
const present: boolean = await ctx.security.hasValue("com.example.myapp", "openai-key");

// List names/metadata — never values.
const values: SecurityStoredValue[] =
  await ctx.security.listValueIDs("com.example.myapp");
// → [{ valueID: "openai-key", label: "OpenAI API key", createdAt: "2026-10-12T…" }]

// Host performs the HTTPS request with the secret attached as the
// Authorization header. Only {status, body} comes back.
const res: SecurityHTTPResponse = await ctx.security.useValue(
  "com.example.myapp",
  "openai-key",
  {
    kind: "httpAuthorization",          // the only supported kind
    request: {
      method: "GET",
      url: "https://api.openai.com/v1/models",
      // No Authorization header here — an extension-supplied one is
      // rejected client-side; the host attaches the stored secret.
    },
  },
);
// res → { status: 200, body: "…" }

// Delete a stored value. The host answers with a null payload on success.
await ctx.security.deleteValue("com.example.myapp", "openai-key");
```

Client-side validation (mirrors the `context.ts` pattern: early, friendly,
never a security boundary — the host re-validates everything):
- IDs: 1–256 printable ASCII, no whitespace (`SECURITY_ID_PATTERN`).
- Method: bare token (`/^[A-Za-z]{1,16}$/`), uppercased before sending.
- URL: must be an absolute HTTPS URL; URLs embedding credentials are
  rejected; a client-supplied `Authorization` header is rejected; body, when
  present, must be a string.
- `operation.kind` must be `"httpAuthorization"` — anything else is
  `INVALID_ARGUMENT`.
- Malformed host responses throw `IPC_MALFORMED` (shape-asserted:
  `{valueID, created}`, `{hasValue}`, `{values:[…]}`, integer `status` +
  string `body`).

**IPC contract details:** the wire payloads are
`{"securityID","valueID","label?","prompt?"}` →
`{"valueID","created"}`; `{"securityID","valueID"}` → `{"hasValue"}`;
`{"securityID"}` → `{"values":[…]}`; `{"securityID","valueID"}` → null;
`{"securityID","valueID","operation"}` → `{"status","body"}`. The host routes
exist in `SDKIPCDispatcher`; every route runs inside the dispatcher's 60 s
per-request watchdog, and each authorizes only the `use.Security` umbrella
at the broker before any Keychain touch (the granular `security.*` IDs are
method scopes, not permission checks — see "What `use.Security` grants").

## The secure-prompt entry flow

The entry UI is `EnterSecuritySDKView`, presented by the host-only
coordinator `SDKSensitiveValuePrompt` (`Host/Security/`); both exist in the
working tree. `SDKSensitiveValuePrompt.requestValue(securityID:appDisplayName:valueID:label:prompt:)`
is the single narrow surface the IPC layer and Studio both call.

- **Who presents it:** the host — SwiftCode Studio — in its own titled
  window on the main actor (`SDKSensitiveValuePrompt` follows the
  `SDKStudioWindowManager` pattern: `NSHostingController`, `center`,
  `makeKeyAndOrderFront`), triggered by the `security.addValue` IPC request
  (or from the Studio Security manager, below). The extension cannot render
  the view itself, cannot inject its own fields, and cannot observe
  keystrokes; it only receives the `{ valueID, created }` result when the
  prompt resolves. One window per request, so concurrent prompts do not
  block each other; the coordinator waits with no timeout of its own
  (fetching a secret is user-paced — the dispatcher's 60 s per-request
  watchdog still bounds the IPC call).
- **What the user sees:** the app's identity (host-known display name +
  Security ID — the exact Keychain namespace the secret lands in; the
  validated package digest is not shown because the contract does not carry
  it), the `label` and `prompt` the extension supplied, and a secure text
  field. The prompt states plainly that *the extension will never see this
  value — SwiftCode stores it in the Mac's Keychain under this app's
  private namespace, and only uses it for the operations you approve.*
  Buttons: **Store** / **Cancel**. The typed text lives in view-local
  `@State` and is cleared before the outcome callbacks fire.
- **What happens on Store:** the view writes the value straight to the
  Keychain via `KeychainSDK.addValue(...)` under the app's namespaced
  partition (Studio never sees the value) and the coordinator records a
  `securityValueAdded` audit event before resolving. On Cancel or dismissal
  (including the title-bar close), nothing is stored; the coordinator
  surfaces `CancellationError`, which `SDKSecurityService.addValue`
  converts to the typed `USER_CANCELLED` `SDKError` — the wire code the
  extension's `addValue` promise rejects with.

### Studio Security manager

`SDKSecurityManagerView.swift` (Studio → Security) is the management
surface, not the entry UI: it lists every app (Security ID) that has stored
values, with metadata only — value IDs, labels, creation dates. There is
deliberately no reveal button and no copy-secret button. It supports
deleting individual values and wiping an app's whole namespace, calling only
the narrow host surface: `KeychainSDK.listValueIDs(_:)`,
`KeychainSDK.deleteValue(securityID:valueID:)`,
`KeychainSDK.deleteAllValues(securityID:)`, and
`SDKSensitiveValuePrompt.requestValue(...)` for the Add flow — the same
secure-prompt coordinator the IPC layer uses. It defines no storage of its
own. Secret values are never listed, displayed, or passed through this view.
Namespace enumeration is a private attributes-only Keychain query in the
view (no secret data requested), filtered to `KeychainSDK.servicePrefix`.

## Uninstall, revocation, and audit

- **Uninstall wipes:** uninstalling an extension calls
  `SDKSecurityService.deleteAllValues(securityID:)` from
  `SDKExtensionRegistry.removeInstallRecord` — the service's host-only
  method (not reachable from extension IPC), which enumerates every Keychain
  service under `com.swiftcode.sdk.security.<extensionID>.` and deletes
  every value in each partition via `KeychainSDK`. Other apps' partitions
  are untouched by construction. The wipe is part of the uninstall path, not
  a separate user step, and is recorded as `securityValuesWipedOnUninstall`
  (detail: app Security ID + wiped-value count). Deleting a value is
  idempotent. Fail-closed: a Keychain failure aborts the uninstall so
  secrets can never silently survive it.
- **Revocation:** revoking the grant (via the Studio grant manager,
  tombstoned like all grants per `Capabilities-and-Permissions.md`) takes
  effect at the broker's next check — there is no cached verdict.
  Revocation blocks all five `security.*` methods but does **not** delete
  stored values; the user may re-grant and keep using them, or delete
  values explicitly. Deleting a value and revoking the grant are separate,
  independently audited actions.
- **Audit events** (`SDKAuditEventType`, in the working tree, uncommitted —
  additive cases, a minor SDK bump per the taxonomy rules in
  `Capabilities-and-Permissions.md`). The detail fields carry identifiers
  only; the secrets contract for these events is the strictest part of the
  file's redaction policy:
  - `securityValueAdded` — detail: app Security ID + value ID. Never the
    secret bytes.
  - `securityValueUsed` — detail: app Security ID + value ID + operation
    kind. **Never** the secret bytes, and never the request body or any
    other string that could contain them.
  - `securityValueDeleted` — detail: app Security ID + value ID.
  - `securityValuesWipedOnUninstall` — detail: app Security ID (+
    wiped-value count when known).
  - `securityPermissionDenied` — detail: app Security ID + value ID (when
    one was targeted) + reason.
  - Extensions cannot read or modify the audit log. The Studio Logs viewer
    already renders these five events (`SDKStudioLogsView.swift`, in the
    working tree, uncommitted).

## Honest limitations

- **Keychain behavior needs macOS and is not testable in this
  environment.** `KeychainSDK` is Swift/`Security.framework` code; the node
  test suite covers the TS client only. All Keychain claims — accessibility
  behavior, locked-device behavior, failure modes — are verified by code
  review until a macOS run with `xcodebuild` and the SDK test suite.
- **Access control constant:** `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
  (verified against `SDKKeychain`, which uses the same constant).
  Consequences: secrets never migrate via iCloud Keychain sync, and they
  are **unavailable while the device is locked**.
- **Device locked:** any `security.*` call that needs the secret while the
  device is locked fails with `SERVICE_UNAVAILABLE` — the host does not
  prompt to unlock, does not fall back to another store, and does not queue
  the operation for later. An `errSecAuthFailed` status surfaces as an
  actionable Keychain-auth failure, not a generic outage. A locked-device
  error is distinguishable from "no value stored"; implementations must
  surface the error, not coerce it to `hasValue: false`.
- **No background use while locked** is intentional and matches the
  workstation threat model of the SDK Keychain design.
- **Diagnostics never carry free text.** Error diagnostics carry only the
  operation name, the numeric OSStatus, and a machine reason, passed through
  `SDKLogRedaction` — labels are excluded because free-text labels could
  themselves contain pasted secrets.
- **Host-operation coverage is the real limit.** Today `useValue` supports
  exactly one operation kind, `httpAuthorization`. Until a host operation
  exists for a given need, the extension cannot turn a stored secret into
  anything else. `use.Security` without matching host operations is storage
  with no spend.
- **Prompt vs. the 60 s IPC watchdog.** The secure prompt waits for the
  user with no timeout of its own, but the `security.addValue` IPC call
  runs inside the dispatcher's 60 s per-request watchdog. If the user takes
  longer than 60 s, the extension sees `IPC_TIMEOUT` — while the prompt
  window stays open and a later Store still writes the secret to the
  Keychain (the abandoned call is simply never observed). Extensions must
  treat a timeout as "unknown outcome" and re-check with `hasValue`, not
  as "nothing was stored".
- **In-flight concurrency risk:** the working-tree changes this doc
  describes are uncommitted and unreviewed, written alongside a parallel
  agent's work. Re-verify every claim against committed code once the work
  lands.

## Drift checklist (re-verify as the implementation lands)

1. The five `security.*` capability IDs + `use.Security` are in
   `SDKCapability.swift`, the manifest validator, and `Compatibility.md`.
2. `ScopesIDLists.swift` and `ScopesIDLists.ts` stay in two-way sync (the
   sync test must pass).
3. `security.*` routes exist in `SDKIPCDispatcher`, authorize ONLY the
   `use.Security` umbrella per call (never the granular method-scope IDs),
   and bind the payload's `securityID` to the caller's host-verified
   identity (never payload-trusted).
4. The secure prompt exists (as `EnterSecuritySDKView` +
   `SDKSensitiveValuePrompt`), is host-presented, and the extension cannot
   observe the entry.
5. Uninstall calls `deleteAllValues`; revocation tombstones and takes
   effect at the next broker check; values survive revocation.
6. All five audit event types fire as documented and carry no secret
   values or request bodies.
