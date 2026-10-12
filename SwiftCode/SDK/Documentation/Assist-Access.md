# Assist Access — third-party Assist authorization

**Status:** Part B of `Docs/Intro-to-SDK.md` (§9–§16) · **Branch:** `feature/swiftcode-sdk`

How third-party apps get Assist access, what the two SDK variants unlock,
how enforcement works, and how access is revoked. Assist is deny-by-default
for extensions; this document describes the deliberate, entitled path that
opens it.

## 1. The application form

Developers apply in SwiftCode Studio → Assist Access
(`SwiftCode/SDK/Studio/Views/AssistAccessFormView.swift`). Every field is
required and validated; the answers are stored verbatim with the request
(`SDKAssistApplication` in `SwiftCode/SDK/Host/APIKeys/SDKAssistApplication.swift`).

| Field | Rule |
|---|---|
| App identity (extension ID + display name) | Both non-empty. The extension ID must match an installed/registered app — checked against `SDKExtensionRegistry` at submit time. |
| Developer API key | Picker. The key the entitlements will be bound to; must exist, not be revoked or expired. |
| SDK variant | Radio: `assistSDK.UI` or `assistSDK` (§2). |
| "How will Assist be used in your app?" | Free text, minimum 40 characters (measured trimmed), stored verbatim. |
| "Do you have your own UI for Assist responses?" | Required yes/no choice; a description is required when yes. Informs the variant. |
| "Will third-party models outside SwiftCode be used?" | Required yes/no; when yes, the providers/models must be listed. A "yes" answer makes approval also grant the cloud entitlement. |
| "Does user data leave the device?" | Required yes/no; when yes, the destination must be described. A "yes" answer makes approval also grant the cloud entitlement. |
| Contact email | Required; must match a basic email format. |

Incomplete forms are rejected with field-level errors keyed by
`SDKAssistApplicationField`, rendered inline next to each field. Submitted
forms persist as `pending` in the Keychain (`sdk.assistapp.<uuid>` — the
same protection level as API-key metadata).

## 2. The two SDK variants

- **`assistSDK.UI`** (TypeScript: `assistUI.ts`, `createAssistUIAPI`): embeds
  the host's REAL Assist main view inside the developer's app. The host
  presents it (`SDKAssistUIOpener` posts the real "show Assist" notification
  for viewId `"assist.main"`); the extension never touches Assist internals
  and gets no custom Assist chrome. There are deliberately no headless
  session/streaming APIs in this module.
- **`assistSDK`** (TypeScript: `assist.ts`, `createAssistAPI`): the full
  Assist API surface EXCEPT UI — sessions, streaming responses, tool access
  per the approved scope — over the dedicated entitled IPC route
  `assist.invoke` with an `op` discriminator (`session.create`,
  `session.list`, `message.send`, `message.stream`, `tool.invoke`,
  `session.close`). The developer renders everything themselves. There is
  intentionally no view-opening path in this module.

Neither variant works without the entitlement (§3): every call fails with
the §5 error.

## 3. Entitlements (key-bound, never manifest-bound)

Two entitlements, stored ON the developer's API key record
(`SDKAPIKey.entitlements`), granted only through the application approval
flow (`SDKAssistApplicationStore.approve` → `SDKAPIKeyStore.grantEntitlement`):

- `com.SwiftCode.developer-AI-Assist` — unlocks both Assist SDK variants.
  Granted on every approval.
- `com.SwiftCode.developer-AI-Allows-Cloud` — unlocks the SwiftCode cloud
  model for the app (gates the existing `use.SwiftCodeModel` capability).
  Granted on approval when the application declares third-party models or
  data leaving the device.

**Binding rule:** the API key token presented at call time must carry the
entitlement. A claim of the entitlement in the manifest, the package name,
or client code is ignored — enforcement reads only
`caller.apiKey?.entitlements`, the verified key record re-read on every
request (`SDKAPIKeyStore.verify`). The manifest's `"assist": {"requested":
true}` flag is descriptive metadata only (`SDKAssistGate.manifestRequestsAssist`).

## 4. Enforcement — where the checks happen

Every Assist/cloud-model call passes these gates, in order:

1. **IPC gate** (`SDKIPCDispatcher.dispatch`, step 3): `SDKAssistGate.check`
   runs BEFORE any routing or payload decoding. Every method containing a
   denied substring (`assist`, `llm.`, `agent_runner`, `chat`,
   `sendMessage`) is denied — except the exact method `assist.invoke`, the
   entitled Part-B route, which passes through to step 2.
2. **Session key verification** (`dispatch`, step 3b): the session's
   presented API key is verified against `SDKAPIKeyStore` on EVERY request
   (fail closed). Revocation and expiry take effect immediately; a forged
   key fails the whole request before any Assist route is reached.
3. **Dispatcher route** (`route`, `case "assist.invoke"`): the caller key's
   `com.SwiftCode.developer-AI-Assist` entitlement is required. Absent →
   typed `.assistDenied` with the verbatim §5 message + audit. The `op`
   discriminator is then decoded strictly; malformed ops and forged payload
   claims → typed `.invalidArgument` — never a crash, never passthrough.
   (`case "ui.openView"` with viewId `"assist.main"` is carved out to
   `SDKAssistUIOpener.openAssistView`, which enforces the same entitlement —
   the view is entitlement-only and never grantable, so the grant-store path
   would deny even entitled callers.)
4. **Service boundary** (`SDKAssistService`, every public method): the
   entitlement is re-checked per call, reading only the verified key
   record. Session ownership is enforced (a session only answers its owning
   extension ID). Tool access is limited to the session's `allowedToolIDs`,
   snapshotted from the extension's active grants at creation.
5. **Cloud gate** (`SDKCapabilityBroker.authorize`, `use.SwiftCodeModel`):
   when the caller presents a verified API key, the key-bound
   `com.SwiftCode.developer-AI-Allows-Cloud` entitlement is the ONLY
   authorization — the grant store is not consulted. Absent → typed
   `.cloudModelDenied` with the §5 cloud message + audit. Present → the
   call is authorized here; the host's quota gate (`SCCloudRateLimiter`,
   10 requests / rolling 24 h) is still enforced by
   `SDKCloudModelAdapter` on every call. Keyless sessions keep the
   pre-Part-B grant path.

**Single source of truth:** the exact user strings live once, on
`SDKAssistGate.assistDeniedUserMessage` /
`SDKAssistGate.cloudModelDeniedUserMessage`. Every Swift-side denied path
— gate, dispatcher, service, UI opener, broker — emits exactly those
strings. The TypeScript layer never fabricates them: `assist.ts` /
`assistUI.ts` translate only the host's typed `ASSIST_DENIED` into
`SDKAssistAccessError`, and `context.ts`'s `cloudModel.complete` translates
only the typed `CLOUD_MODEL_DENIED` into `SDKCloudModelAccessError`. Any
other host rejection propagates untouched.

## 5. The exact user errors

Assist denial — **verbatim, do not reword**:

> This app is not allowed to use Assist because access has not yet been verified. Please check with the app developer for further information.

Cloud-model denial — **proposed wording** (Dylan finalizes the exact text;
until then this is the string every Swift/TS denial path emits):

> This app is not allowed to use the SwiftCode Cloud Model because access has not yet been verified. Please check with the app developer for further information.

Every denial is written to `SDKAuditLog` with the extension ID, the
correlation ID, and (in internal diagnostics only) the key ID — never
conversation content, never credentials.

## 6. Revocation

- **Entitlement revocation** (`SDKAPIKeyStore.revokeEntitlement`): takes
  effect immediately — `verify(secret:)` re-reads metadata on every call,
  so the next authorization-boundary check sees it. In-flight Assist
  sessions owned by that key are closed at the same time
  (`SDKAssistService.closeSessions(forKeyID:)`); closing is pure host-side
  bookkeeping, so it is always safe. Audited per revocation (key ID +
  entitlement ID + sessions closed).
- **Key revocation** (`SDKAPIKeyStore.revoke(id:)`): the key fails
  verification on the next call, and its Assist sessions are closed too.
- **Uninstall** (`SDKExtensionManager.uninstall`): uninstalling the app
  removes its entitlement bindings —
  `SDKAssistApplicationStore.revokeEntitlementsForExtension` revokes every
  Assist entitlement bound to the app's approved applications (each through
  `revokeEntitlement`, so each is immediate and audited), and the app's open
  Assist sessions are closed. The uninstall audit record notes how many
  entitlements were revoked and sessions closed. Application records
  themselves are kept as historical attestation; the entitlement is the
  binding, and removing it is what revokes the approval's effect.

## 7. Approval policy (v1)

**Recorded self-attestation with revocation-on-abuse.** There is no human
review queue in v1: approval is an explicit host action (Studio → Assist
Access → Approve) that records the developer's answers as their attestation
and grants the entitlements. Abuse after approval is handled by entitlement
revocation (§6), which takes effect immediately at the authorization
boundary and is recorded in the audit log.

## 8. Known limitation — the recorded blocker (out of scope)

The headless variant's `send` / `sendStreaming` / `executeTool` stop at a
real, typed boundary: there is currently NO per-extension Assist backend
they can call. The candidates were audited and rejected —
`AssistManager.shared.sendMessage` (drives the user's shared visible
conversation; no caller identity; returns `Void`),
`AssistManager.shared.agentSession.start` (singleton-owned; user's
settings; no extension identity), and `LLMService.sendChatRequest`
(spends the user's configured model/keys; no caller identity, no quota, no
tool pipeline). Until extension caller identity is plumbed through the real
Assist choke points (`AssistManager`, `AssistAPIRouter.route`,
`LLMService`, the Antigravity bridge Unix socket), these methods throw a
typed `.serviceUnavailable` naming the missing plumbing — they NEVER
fabricate a response, stream delta, or tool result. Everything up to that
boundary (entitlement, validation, session bookkeeping, tool-scope policy,
revocation) is implemented for real.

## 9. Tests

- TypeScript (`SwiftCode/SDK/TypeScript/package/tests/`, run here):
  `assist-variants.test.mjs` pins the `assist.invoke` wire format for all
  six ops and the verbatim denial mapping on every public function;
  `cloudmodel.test.mjs` pins the `CLOUD_MODEL_DENIED` → verbatim-message
  mapping and that unrelated denials propagate untouched.
  `npm run build` (tsc clean) + `npm test` must stay green.
- Swift (`SwiftCode/SDK/Host/APIKeys/SDKAssistApplicationTests.swift`,
  `SDKAssistEnforcementTests.swift`): form validation, application store
  (submit/approve→grant/deny→no grant), entitlement grant/revoke/require,
  enforcement routes (entitled vs not, wrong-key, forged manifest claim
  ignored), the cloud gate, and revocation mid-session. Registered in the
  xcodeproj as source references only (no XCTest target exists yet) —
  statically verified here; run on Dylan's Mac with xcodebuild.

## 10. Cross-references

- Spec: `Docs/Intro-to-SDK.md` §9–§16.
- Architecture: `SwiftCode/SDK/Documentation/SDK-Architecture.md`,
  `Capabilities-and-Permissions.md` (capability model),
  `Runtime-and-Security.md` (IPC + key verification),
  `Security-Keychain.md` (key/entitlement storage).
- Code: `SDKAssistGate.swift`, `SDKIPCDispatcher.swift`,
  `SDKAssistService.swift`, `SDKAssistUIOpener.swift`,
  `SDKCapabilityBroker.swift`, `SDKCloudModelAdapter.swift`,
  `SDKAPIKeyStore.swift`, `SDKAssistApplication.swift`,
  `SDKExtensionManager.swift`; TypeScript `assist.ts`, `assistUI.ts`,
  `context.ts` (cloud mapping), `types.ts`.
