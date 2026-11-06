# Cloud accounts — the `YcodeCloud` target, Appwrite auth, and the Cloud framework

Wave 12 (slice A) of the Legacy → Mac migration. Before this wave,
Ycode had no account system at all: Settings ▸ Accounts was an
explicit empty state ("Ycode does not sign in to accounts"), there
was no cloud backend, no sync engine, and no user-account model
(destination audit §5). Legacy's account system was Appwrite auth
plus a hand-rolled cloud framework. This wave ports it:

- **Part 1** — the new `YcodeCloud` SwiftPM target: a small
  `URLSession` REST client for the Appwrite Account API, with
  Keychain-stored session secret, typed models and errors.
- **Part 2** — `CloudAuthManager`: Legacy's `AuthManager` flows
  (email/password, OAuth2, recovery, verification, account
  management) on the REST client.
- **Part 3** — the Cloud framework types and orchestration
  (`CloudManager`, `CloudSyncEngine`, cache, queue, conflict
  resolution, provider protocols), ported faithfully — including
  the parts of Legacy that never actually synced anything.
- **Part 4** — tests with stubbed transport and hand-written
  fixtures. No live network in tests.

No Swift toolchain exists in this environment, so everything below
is statically checked only — `swift build` / `swift test` and live
runs against the Appwrite endpoint are pending on Dylan's Mac.
Dylan must supply nothing to build this: the backend coordinates
are Legacy's own (public endpoint + project id), and sign-in uses
his existing Appwrite account. The settings UI for all of this is
slice B's job; this slice builds the model and client only.

## 1. The dependency decision: a REST client, not the Appwrite SDK

Appwrite is accessed via a small `URLSession` REST client
(`AppwriteAccountClient`), NOT the Appwrite SDK (`sdk-for-apple`).
The decision rests on three independent pieces of evidence —
version, platform, and dependency weight — and only the platform
one is actually a hard blocker. The version story is subtler than
it first looked, and is recorded honestly here.

### 1.1 What Legacy pinned

Legacy's root `Package.swift` declares `sdk-for-apple from:
"15.0.0"` (product `Appwrite`) and `supabase-swift from: "2.0.0"`
(product `Supabase`). Legacy's `Package.resolved` pins
`sdk-for-apple 15.0.0`, `supabase-swift 2.1.0`, and `swift-crypto
5.0.1`. Ycode's `ycode/Package.swift` declares swift-crypto as
`"3.0.0"..<"5.0.0"` and pins `4.5.2`. A naive reading says the
Appwrite SDK cannot coexist with Ycode's range because its graph
pins swift-crypto 5.0.1. That reading is wrong in detail and right
in conclusion; the detail matters.

### 1.2 Where the swift-crypto 5.0.1 pin actually comes from

Verified live 2026-11-06 from the GitHub blob pages at the
lockfile's pinned versions:

- Neither `sdk-for-apple 15.0.0` nor `supabase-swift 2.1.0`
  declares swift-crypto directly. `sdk-for-apple 15.0.0` depends
  only on `async-http-client from: "1.19.0"` and `swift-nio from:
  "2.58.0"`; `supabase-swift 2.1.0` depends on KeychainAccess,
  swift-snapshot-testing, xctest-dynamic-overlay, and
  swift-concurrency-extras.
- The swift-crypto 5.0.1 pin in Legacy's `Package.resolved` comes
  transitively through the Appwrite side: `sdk-for-apple` →
  `async-http-client` (1.36.2; declares `swift-nio-ssl from:
  "2.30.0"`) → `swift-nio-ssl` 2.37.5 (declares
  `swift-certificates from: "1.19.4"`) → `swift-certificates`
  1.21.0 → `.package(url:
  "https://github.com/apple/swift-crypto.git", "3.12.3"..<"6.0.0")`
  — the only swift-crypto requirement anywhere in the graph; the
  range spans majors, so SPM picked the highest available release
  at resolve time (5.0.1). Supabase contributes nothing to this
  chain.
- Nuance, recorded honestly: adding `sdk-for-apple 15.0.0` to Ycode
  would NOT inherently fail resolution — swift-certificates' range
  intersects Ycode's `"3.0.0"..<"5.0.0"` at `3.12.3..<5.0.0`, so SPM
  could resolve with a 3.x/4.x swift-crypto. The real blocker is
  platform, not version: `sdk-for-apple` declares Apple platforms
  only (`.iOS("15.0")`, `.macOS("11.0")`, `.watchOS("7.0")`,
  `.tvOS("13.0")`; README: iOS 15, macOS 12, tvOS 15, watchOS 8+),
  with no Linux support claimed, and its WebAuthComponent/device
  code is Apple-specific by design.

### 1.3 Conclusion

The `URLSession` REST client avoids all of it — no new SPM
dependency, no async-http-client/NIO/certificates/crypto chain, no
Apple-only SDK in the Linux build. Ycode's swift-crypto range is
not widened, no fork is vendored, and `ycode/Package.swift` gains
only the `YcodeCloud` target (plain `.target`, library product,
test target — the Wave 10 `YcodeGitHub` model; its only dependency
is first-party `YcodeAssistant`, for `SecretStore`).

### 1.4 Supabase: a dead dependency, twice over

- **The SDK is dead in Legacy.** `grep ^import Supabase` over
  Legacy's Swift sources returns zero files. `supabase-swift` is
  declared in Legacy's `Package.swift` (`from: "2.0.0"`, pinned
  `2.1.0`) and linked as a product, but never imported. It is not
  ported, and no supabase-swift dependency is added to Ycode.
- **The Supabase that Legacy does use is not the SDK.**
  `Views/Utilities/Database/Services/SupabaseService.swift` (101
  lines, imports only Foundation) is a pure `URLSession` PostgREST
  client for the Database utility: it takes a user-supplied
  `DatabaseConnection` (a Supabase project URL + anon key the user
  typed in) and calls `{url}/rest/v1/` for connection tests and
  table listing. It is NOT part of accounts/auth, it is NOT ported
  in this slice, and it belongs to the Database utility wave.
- **The SDK would not help anyway.** `supabase-swift 2.1.0`'s Auth
  target uses KeychainAccess (Apple Security framework,
  Apple-only) — another reason the supabase-swift product stays
  out of a Linux-buildable target.
- Legacy's `Config/AppConfig.swift` hardcodes a Supabase project
  URL (`https://secctbuzkfbketdihzui.supabase.co`) with an anon key
  loaded from the `SUPABASE_URL` / `SUPABASE_ANON_KEY` environment.
  That is backup configuration (see §8), not auth, and is not
  ported here.

## 2. Backend coordinates (configuration, not credentials)

From Legacy's `Services/Appwrite/AppwriteService.swift` (13 lines,
a global `Client` + global `Account`):

| Setting | Value | Source |
|---|---|---|
| Endpoint | `https://sfo.cloud.appwrite.io/v1` | `AppwriteService.swift` |
| Project id | `6a670d0b0022e5f964b4` | `AppwriteService.swift` |
| Callback scheme | `appwrite-callback-6a670d0b0022e5f964b4://` | `AuthManager` (inline string, four places) |

These are Legacy's own public backend coordinates. The endpoint is
a public URL and the project id is a public identifier carried in
the `X-Appwrite-Project` header of every request; neither is a
secret, and neither is ever logged. They live in
`AppwriteConfiguration` with exactly these defaults, overridable
per client (tests point at nothing — they use a stub transport).
The callback scheme is derived from the project id so the two
cannot drift, where Legacy repeated the literal string in four
places.

## 3. The REST client (`AppwriteAccountClient`)

`public struct AppwriteAccountClient: Sendable` in
`ycode/Sources/YcodeCloud/AppwriteAccountClient.swift`, following
the `GitHubClient` pattern: a value type, an injected `URLSession`
(`.shared` by default; tests inject a session backed by a
`URLProtocol` stub), no stored secret of its own.

### 3.1 Headers (every request)

| Header | Value |
|---|---|
| `X-Appwrite-Project` | the project id |
| `User-Agent` | `Ycode` |
| `Cookie` | `a_session_<project>=<secret>`, when a session is active |
| `Content-Type` | `application/json`, when a body is present |

### 3.2 Session handling (cookies, not tokens)

Appwrite email sessions are cookie-based. Creating a session makes
the server set `a_session_<project>`; the client captures that
cookie's value from the `Set-Cookie` response header, keeps it in a
locked box (`SessionSecretBox`, the `RateLimitBox` precedent from
`YcodeGitHub`), and sends it back as a `Cookie` header. The host
persists it through `onSessionSecretChanged`, which
`CloudAuthManager` wires to the secret store
(`SecretAccount.appwriteSessionSecret`). The secret is never logged
and never written to a file by this client. The session *secret* is
not in the session JSON body — only the cookie carries it, which is
why the client reads response headers instead of the body.

### 3.3 Endpoints covered

Exactly the calls Legacy's `AuthManager` made through the SDK,
plus two the SDK could not or did not do:

| Method | Endpoint | Legacy call |
|---|---|---|
| `POST` | `/account/sessions/email` | `createEmailPasswordSession` |
| `GET` | `/account` | `account.get()` |
| `DELETE` | `/account/sessions/{sessionId}` | `deleteSession(sessionId: "current")` |
| `POST` | `/account` (`userId: "unique()"`) | `account.create(userId: ID.unique(), ...)` |
| `POST` | `/account/recovery` | `createRecovery` |
| `PUT` | `/account/recovery` | `updateRecovery` |
| `POST` | `/account/verification` | `createVerification` |
| `PUT` | `/account/verification` | `updateVerification` |
| `PATCH` | `/account/prefs` | `updatePrefs` (stores `swiftcode_id`) |
| `PATCH` | `/account/email` | `updateEmail` |
| `PATCH` | `/account/password` | `updatePassword` |
| `DELETE` | `/account` | — (Legacy always threw; see §4.3) |
| `GET` | `/ping` | `client.ping()` (server test) |
| `GET` | `/storage/buckets/{bucketId}/files` | — (BackupEngine needs it; §8) |
| `GET` | `/storage/buckets/{bucketId}/files/{fileId}/download` | — (BackupEngine needs it; §8) |
| `DELETE` | `/storage/buckets/{bucketId}/files/{fileId}` | — (BackupEngine needs it; §8) |

`GET /account` without a session secret throws
`.missingSession` without a network call. Error bodies decode to
`AppwriteErrorBody` (`message`, `code`, `type`) and surface as
`AppwriteError.http(status:code:type:message:)`; a body that does
not parse falls back to the raw text or the status. Dates arrive as
ISO 8601 with fractional seconds
(`2026-01-15T10:30:00.000+00:00`), which `JSONDecoder`'s `.iso8601`
strategy does not accept on every platform, so decoding goes
through `AppwriteDecoder` (fractional-seconds formatter, plain
formatter fallback).

### 3.4 What is NOT in the client

- **Multipart upload.** Appwrite file creation is a
  `multipart/form-data` upload; the client does not build one yet.
  `AppwriteStorageProvider.upload` throws honestly. See §8.
- **Realtime / subscriptions.** Nothing in Legacy used them.
- **Databases / collections.** Nothing in Legacy used them either
  (see §6).

## 4. The auth manager (`CloudAuthManager`)

`@MainActor public final class CloudAuthManager` in
`ycode/Sources/YcodeCloud/CloudAuthManager.swift`, ported from
Legacy's `AuthManager` (415 lines). Same observable state
(`currentUser`, `currentSession`, `swiftCodeID`,
`isAuthenticated`, `isLoading`, `authError`), same flows, same
order of operations. Legacy read the shared SDK `Account`;
this manager reads its `AppwriteAccountClient` and its secret
store.

### 4.1 Session restore and the SwiftCode id

`restoreSession()` fetches the account with the stored secret,
then ensures a `swiftcode_id` exists in the user's prefs: reuse
the stored one when present, otherwise mint
`sc_id=` + 32 uppercase hex digits from 16 random bytes and store
it with `PATCH /account/prefs`. A failed prefs write keeps the id
locally and continues, as Legacy did. A failed restore clears all
local state and the stored user id, as Legacy did. The id is
generated with the system random-number generator instead of
`SecRandomCopyBytes` (portable; Legacy's CryptoKit SHA-256 fallback
for a failed random call is unnecessary — the generator cannot
fail). `deterministicUUID(from:)` / `dbUserID(from:)` are ported
verbatim in semantics (SHA-256 of the id, first 16 bytes as a
UUID, with the `sc_id=` / `sc_id_` prefixes stripped); the SHA-256
itself is a pure-Swift implementation (`SHA256Digest`, FIPS
vectors in tests) so the target needs no cryptography dependency.

### 4.2 Email/password, recovery, verification, account changes

`login` → create session → `restoreSession`. `createAccount` →
create with `userId: "unique()"` → `login`. `forgotPassword` →
`createRecovery` with the
`appwrite-callback-<project>://reset-password` URL;
`resetPassword` → `updateRecovery`. `sendVerificationEmail` →
`createVerification` with the `...://verify` URL; `verifyEmail` →
`updateVerification` → `restoreSession`. `changeEmail` /
`changePassword` → the PATCH calls → `restoreSession` for email.
`logout` → `DELETE /account/sessions/current` (a server-side
failure does not stop the local sign-out, as in Legacy) → clear
state, secret, and stored user id. `syncUserProfile` is the same
deprecated no-op Legacy left behind ("Remote profile
synchronization is not configured").

`authError` carries the user-facing message
(`AppwriteError.userFacingMessage`), not the raw server text —
that is Legacy's `CloudAuthViews.mapErrorToUserMessage` mapping,
moved to the error type so every caller gets it (§5).

### 4.3 `deleteAccount` works now (a deliberate improvement)

Legacy's `deleteAccount` always threw a 405: "Account self-deletion
is not supported by the Appwrite Apple SDK." The REST API supports
`DELETE /account`, so this manager deletes for real and then
clears local state. Destructive and irreversible; slice B's UI must
keep Legacy's confirmation alert
(`CloudManagementView.confirmDeleteAccount`) in front of it.

### 4.4 OAuth2 (Google / GitHub) — honestly unavailable pending plumbing

Legacy's `loginWithGoogle` / `loginWithGitHub` called the SDK's
`createOAuth2Session(provider:success:failure:)`, which opened the
authorize URL in a web-auth session and resumed the app on the
`appwrite-callback-<project>://` scheme. Ycode has no URL-scheme
callback plumbing: there is no `onOpenURL` / `handleOpenURL`
handling anywhere in `ycode/Sources`, no registered custom scheme,
and no web-auth session wrapper. So this slice implements the
client side honestly and stops there:

- `oauthAuthorizeURL(provider:)` builds the authorize URL
  (`{endpoint}/account/sessions/oauth2/{provider}` with `project`,
  `success`, `failure` query items, both redirects defaulting to
  the callback scheme) — the exact URL the SDK opened.
- `parseOAuthCallback(_:)` parses a callback URL: success, failure
  (`error` / `error_description`), recovery (`...://reset-password`
  with `userId` + `secret`), verification (`...://verify` with
  `userId` + `secret`). Returns nil for URLs that are not Appwrite
  callbacks.
- `beginOAuth(provider:openURL:)` opens the authorize URL with an
  injected `openURL` closure (the `OpenAIAccount` pattern) and
  waits for `handleOAuthCallback(_:)` to deliver the result. The
  wait times out after 5 minutes with `.oauthCallbackTimeout`.
- Until the app registers the scheme and forwards opened URLs to
  `handleOAuthCallback(_:)`, OAuth cannot complete. It is never
  faked: `beginOAuth` suspends and then times out instead of
  reporting a sign-in that did not happen. Registering the scheme
  and wiring the callback is slice B / app-shell work, listed in
  §8.

## 5. Errors and the messages the UI shows

`AppwriteError` (transport) and `CloudError` (cloud layer) are
separate types. `CloudError` is ported verbatim from Legacy
(`CloudError.swift` — same cases, same messages). `AppwriteError`
preserves the server's `code` / `type` / `message` and adds
`userFacingMessage`, which is Legacy's
`CloudAuthViews.mapErrorToUserMessage` mapping, applied at the
error instead of in the view:

| Server signal | User-facing message |
|---|---|
| 401, or message contains "invalid credentials" | "Invalid email address or password. Please verify and try again." |
| 409, or message contains "already exists" | "An account with this email address is already registered on our servers." |
| Message contains "network" / "connection", or the request never reached the server | "Unable to connect to the authentication server. Please check your network connection." |
| Message contains "weak password", or password-length complaint | "Your password is too weak. Please ensure it is at least 8 characters long." |
| Anything else | the server's message, verbatim |

Slice B's settings views should display `authError` (already
user-facing) or `AppwriteError.userFacingMessage`, and must not
re-implement the string matching.

## 6. The Cloud framework — ported faithfully, including the stubs

Legacy's `Frameworks/Internal/Cloud/` (16 files, ~1,059 lines)
is ported into `YcodeCloud` with Legacy's exact semantics. The
important finding from reading it is how little of it ever did
anything remote — and this port says so instead of inventing the
missing backend.

### 6.1 Types (verbatim ports)

`CloudUser`, `CloudRecord` (including the snake_case wire keys),
`CloudSession`, `CloudDevice`, `SyncPayload`, `SyncMetadata`,
`CloudConflict`, `CloudStatistics`,
`ConflictResolutionStrategy`, `CloudStorageInfo` (5 GB default
limit, nothing ever populated it), `SyncState` (`idle` / `syncing`
/ `paused` / `error` — `CloudSyncView` uppercases `rawValue`),
`CloudError`, `SecureString`, and the five protocols in
`CloudProvider.swift` (`CloudProvider`,
`AuthenticationProvider`, `CloudDatabase`, `SyncProvider`,
`StorageProvider`).

### 6.2 `CloudManager` — the sync is a no-op, and that is the port

`CloudManager.sync()` refuses when unauthenticated and otherwise
only stamps `lastSyncTime` and returns to idle. That is what
Legacy did: no record was ever read from or written to any remote
in `sync()`. This port keeps that exactly (the one change: Legacy
wrapped the stamp in a `do`/`catch` that could never throw; the
dead `catch` is dropped). `initialize` postpones itself while
unauthenticated; `startSync` / `stopSync` flip the persisted
`com.swiftcode.cloud.syncEnabled` flag (shared with
`CloudSyncEngine` and Legacy's `CloudManagementView`
`@AppStorage`); `stopSync` leaves the state `.paused`;
`handleLogout` stops sync, clears the local cache, and resets all
state. The settings views display `syncState`, `lastSyncTime`, and
`currentError` — with the no-op, `lastSyncTime` advances and
nothing else changes, which is what Legacy's UI showed too.

### 6.3 `CloudSyncEngine` — queues into a backend that does not exist

The actor is ported from Legacy's `CloudSyncEngine.swift` (238
lines): provider slot, pending payloads, statistics, 30-second
auto-sync, `queueLocalUpdate` (drops updates when sync is disabled
or unauthenticated), `triggerSync` (pushes pending payloads, pulls
deltas for table `"projects"` since the last sync or 24 hours ago,
ignores deltas belonging to another user). Three honest limits
carried over:

- With no provider configured, `triggerSync` skips and returns.
  **No Legacy code ever configured a provider**: `grep` finds no
  `setProvider` caller and no `CloudProvider` conformance anywhere
  in Legacy. The engine is a queue with nowhere to send.
- `handleInboundPayload` only notes the payload. Legacy's comment:
  "Actual persistence integration must be implemented separately."
- A failed cycle increments `statistics.conflictCount` (Legacy's
  accounting, kept as-is even though a transport failure is not a
  conflict).

One deliberate change: Legacy drove auto-sync with a `Timer` on
the main run loop; this port uses a `Task` sleeping 30 seconds
between cycles, which works on Linux too. A second change forced
by isolation: the engine cannot read the MainActor-isolated
`CloudAuthManager.shared` in its own initializer, so it starts
with no auth manager and the host configures one with
`configure(authManager:)`; sync attempts without one are skipped
like the no-provider skip. Tests use `init(testAuthManager:)`.

### 6.4 Cache, queue, resolver, wiring (real behaviour, ported)

- `LocalCloudCache` + `CloudPersistence`: real. In-memory records
  keyed `"\(recordType):\(recordKey)"`, whole-cache JSON rewrite on
  every mutation, file at `Application Support/SwiftCode/CloudCache
  /cloud_cache.json` — Legacy's path, kept so an existing Legacy
  install's cached records survive. Only `CloudRecord` values are
  ever written there; never sessions or secrets.
- `SyncQueue`: real FIFO (`enqueue` / `dequeue` / pending-upload
  count / remove / update). Nothing in Legacy ever drained it into
  a provider.
- `ConflictResolver`: real last-write-wins (higher version wins;
  on equal versions the newer `updatedAt` wins; ties go local).
- `SyncEngine` (the small actor): ported verbatim including its
  honest limitation — `synchronize()` never moves a byte because
  `CloudProvider` exposes no `saveRecord` / `fetchRecords`.
- `CloudSyncWiring` + `SerializedChatMessage` +
  `LocalChatHistoryStore`: ported verbatim. Chat history is one JSON
  file per session under `Application Support/SwiftCode/Chats/`;
  every save also registers a `chat_history` change with the sync
  engine (which queues it; see §6.3).

### 6.5 The first concrete `CloudProvider`

Legacy defined the `CloudProvider` protocol but nothing conformed
to it. `AppwriteCloudProvider` is the first implementation: real
auth (`AppwriteAuthenticationProvider` over `CloudAuthManager`)
and real storage (`AppwriteStorageProvider` over the client's
Storage calls — `listObjects` / `download` / `delete` on a bucket;
`upload` throws honestly, see §3.4), with
`UnavailableSyncProvider` and `UnavailableCloudDatabase` for the
sync and database seams. Those two throw `CloudError.syncFailed` /
`.databaseError` with a named reason ("no Appwrite database or
collection backs the sync payloads") instead of pretending. A
later wave that defines the backend (database id, collection ids,
conflict policy) replaces them with real implementations; until
then `CloudSyncEngine` + `AppwriteCloudProvider` fails its cycle
honestly and counts it (see §6.3).

`CloudSession` mapping note: Appwrite sessions are cookie-based
with no refresh token, so `accessToken` carries the session secret
and `refreshToken` is empty; `expiresAt` is the session's `expire`
date. Legacy had no guest accounts, so `migrateGuestAccount`
throws; Legacy had no live session stream, so
`sessionStateChanges` yields the current session once and
finishes (callers poll `getActiveSession` after auth actions).

## 7. What the settings views need (slice B's contract)

Read from Legacy's `CloudAuthViews.swift` (371 lines),
`CloudManagementView.swift` (543),
`CloudStatusView.swift` (111), `CloudSyncView.swift` (125) —
behaviour only; the UI itself is slice B's job, in Mac style, not
Legacy's.

- **Auth sheet** (three modes: login / create account / forgot
  password): email + password fields, password-confirmation check
  ("Passwords do not match.") done client-side before any call,
  Google and GitHub branded buttons, success and error text. On
  success the sheet calls `onSuccess` and dismisses (unless it is
  the gate). Errors display `authError` / the mapped message (§5).
- **Account tab**: signed-in email, verification badge (verified /
  unverified from `emailVerification`), the canonical SwiftCode id
  (monospaced, selectable), change-email and change-password
  sheets, send-verification action, sign-out, delete-account with
  Legacy's confirmation alert ("Warning: This will permanently
  delete your user account and all remote credentials on the
  Appwrite authentication server. This action is destructive and
  cannot be undone."). Sign-out and delete both disable sync and
  reload stats.
- **Server test**: a "Test Connection" action calling `ping()`,
  showing "Connection Succeeded (Appwrite Server Reachable)" or
  "Connection Failed: …" with success/failure styling.
- **Sync tab**: `syncState.rawValue` uppercased, `lastSyncTime`
  (abbreviated date, shortened time), the `com.swiftcode.cloud
  .syncEnabled` toggle wired to `CloudSyncEngine.setSyncEnabled`,
  a manual trigger, and the last error.
- **Status tab**: authenticated/unauthenticated + connected/offline
  badges (both driven by `isAuthenticated`), `lastSyncTime`, and
  statistics from `CloudSyncEngine.getStatistics()`.

## 8. What is live, what is honestly unavailable, and follow-ups

### Live in this slice

Email/password sign-in and sign-up, session restore with the
persisted secret, `swiftcode_id` minting and storage, password
recovery and email verification (request + completion),
change-email, change-password, account deletion (real, §4.3),
sign-out, server ping, Storage list/download/delete,
`CloudManager` orchestration with Legacy's exact semantics, the
local cache / queue / conflict resolver, and the
`AppwriteCloudProvider` composition.

### Honestly unavailable (with reasons)

| Capability | Reason |
|---|---|
| OAuth2 Google / GitHub sign-in | No URL-scheme callback plumbing in Ycode (no registered `appwrite-callback-<project>` scheme, no `onOpenURL` handling). Client side is built (§4.4); the app shell must register the scheme and forward URLs to `handleOAuthCallback(_:)`. |
| Record syncing (`CloudManager.sync`, `CloudSyncEngine` push/pull) | Legacy never synced a record and never configured a provider or a backend database/collection. The no-op and the queue are ported faithfully; a real backend needs database/collection ids and a conflict policy from Dylan. |
| Storage upload | Appwrite file creation needs a `multipart/form-data` upload the client does not build yet. List/download/delete work. |
| Guest-account migration, live session stream | Legacy had neither; the seams throw / yield once, honestly. |

### Follow-ups (not this slice)

- **BackupEngine migration (later wave).** Legacy's
  `BackupEngine` (249 lines) uses Appwrite only through the
  `CloudProvider` seam: it requires an authenticated session
  (401 otherwise), lists/uploads/downloads/deletes ZIP snapshots
  in the `backups` bucket, and logs them as "Supabase backups
  bucket" — the bucket naming is Legacy's confusion, not a
  Supabase dependency: the calls go through `cloudProvider.storage`
  (Appwrite Storage), while `AppConfig`'s Supabase URL is separate
  backup configuration. With `AppwriteCloudProvider`, the list /
  download / delete legs now work; the upload leg waits on
  multipart upload (§3.4), and the engine itself is a later wave.
- **Google account auth.** Legacy's
  `Services/GoogleAccountAuthService.swift` (1,773 lines) is a
  separate Google-account auth service (Google Cloud /
  Antigravity), unrelated to Appwrite. Not ported here.
- **SCCloud model discovery is untouched.** Wave 9's
  `SCCloudProvider` already covers SwiftCode Cloud model discovery
  and is reused, not duplicated: the Appwrite account and the
  SCCloud per-device fingerprint are separate identities (the
  SCCloud fingerprint lives in `SecretAccount.scCloudFingerprint`;
  the Appwrite session secret in
  `SecretAccount.appwriteSessionSecret`).
- **Settings UI.** Slice B: the Accounts pane and the Cloud
  views, in Mac style, on the contract in §7.

## 9. Tests

`ycode/Tests/YcodeCloudTests/` — Swift Testing, stub transport
(`StubURLProtocol`, the Wave 10 pattern), hand-written JSON
fixtures, no live network, no real credentials. Test counts are
counted from `@Test` functions:

| File | Tests | Covers |
|---|---|---|
| `AppwriteAccountClientTests.swift` | 22 | Request building (paths, headers, bodies for every Account endpoint), response parsing against fixtures, Set-Cookie capture + `Cookie` header, error mapping (401 / 409 / weak password), OAuth authorize URL + callback parsing, Storage list/download/delete |
| `CloudModelsTests.swift` | 15 | SHA-256 FIPS vectors (empty, `abc`, 56-byte boundary), `deterministicUUID` / `dbUserID`, conflict resolution (version, timestamp, tie), `CloudRecord` wire keys, `SyncQueue` FIFO, `CloudError` text, session expiry, storage info, date parsing, unavailable-provider failures |
| `CloudManagerTests.swift` | 14 | Login / create-account / restore (mint + reuse of `swiftcode_id`) / logout flows, wrong-credentials error, session-secret persistence via `MemorySecretStore` (never the real keychain), `CloudManager` sync no-op + start/stop + `handleLogout`, `CloudAuthProvider` adapter, sync-engine no-provider skip + unavailable-provider failure count |

51 tests total. Message assertions compare structured values
(status codes, decoded fields, error enum cases), never exact
free-text equality on server strings (Wave 4 lesson). The
`handleLogout` test writes the real cache file under the app's own
`Application Support/SwiftCode/CloudCache/` directory and clears
it again in the same test.

## Evidence

Per the destination `AGENTS.md` clean-room protocol (rule 4) and
the migration's Legacy carve-out: Legacy is Dylan's own code and
direct porting was authorised by Dylan under MIT, so the
implementation below was derived from Legacy source plus public
Appwrite API documentation (REST endpoint shapes, cookie session
mechanism, OAuth2 authorize URL format). No reference Xcode copy,
Ghidra, simulator IPSW, `research/dirty/`, or Apple
Xcode/Simulator observation was opened, read, or run.

| Claim | Evidence |
|---|---|
| Appwrite endpoint, project id, callback scheme | Legacy `Services/Appwrite/AppwriteService.swift` (13 lines) + `AuthManager.swift` (415 lines), read directly |
| Auth flows, session restore, `swiftcode_id` handling | Legacy `AuthManager.swift`, read directly |
| Cloud framework types, `CloudManager` no-op sync, `CloudSyncEngine` behaviour, cache/queue/resolver/wiring | Legacy `Frameworks/Internal/Cloud/` (16 files, ~1,059 lines), read directly |
| Settings-view behaviour, error mapping, server ping, delete-account alert | Legacy `Views/Settings/CloudAuthViews.swift`, `CloudManagementView.swift`, `CloudStatusView.swift`, `CloudSyncView.swift`, read for behaviour only |
| BackupEngine's Appwrite usage (Storage via `CloudProvider` seam, `backups` bucket) | Legacy `Frameworks/Internal/Backups/Engine/BackupEngine.swift`, read directly |
| No Legacy Swift file imports Supabase; `SupabaseService` is a URLSession PostgREST client | `grep ^import Supabase` over Legacy Swift sources (0 hits); `SupabaseService.swift` read directly (imports only Foundation) |
| supabase-swift 2.1.0 / sdk-for-apple 15.0.0 dependency graphs; swift-crypto 5.0.1 attribution; Apple-platforms-only SDK | GitHub blob pages at the lockfile's pinned versions, verified live 2026-11-06 (see §1.2) |
| Ycode swift-crypto range `"3.0.0"..<"5.0.0"`, pin 4.5.2; no Appwrite/Supabase in Ycode | `ycode/Package.swift` + `ycode/Package.resolved`, read directly |
| No URL-scheme callback plumbing in Ycode | `grep` over `ycode/Sources` for `onOpenURL` / `handleOpenURL` / URL-scheme handling (no handler found) |
| No concrete `CloudProvider` and no `setProvider` caller in Legacy | `grep` over Legacy Swift sources (0 conformances, 0 callers) |
| `SCCloudProvider` already covers SwiftCode Cloud model discovery | `ycode/Sources/YcodeAssistant/SCCloudProvider.swift`, read directly |
| `SecretStore` pattern, `SecretAccount` cases | `ycode/Sources/YcodeAssistant/SecretStore.swift`, read directly |
| Google OAuth client id, scopes, endpoints, callback scheme, loopback ports | Legacy `Services/GoogleAccountAuthService.swift` (1,773 lines), read directly |
| PKCE helpers, authorize-URL parameters, token exchange/refresh bodies, userinfo/tokeninfo | Legacy `GoogleAccountAuthService.swift`, read directly; RFC 7636 Appendix B vector in tests |
| Loopback listener port order, request-line parsing, success page | Legacy `OAuthLoopbackServer` in `GoogleAccountAuthService.swift`, read directly |
| Antigravity keychain entries, JSON shapes, `go-keyring-base64:` wrapper | Legacy `GoogleAccountAuthService.swift`, read directly |
| ADC file locations, `gcloud` CLI fallback, `agy` CLI discovery and Terminal launch | Legacy `GoogleAccountAuthService.swift`, read directly |
| Error classification kinds, matching order, diagnostic fields | Legacy `GoogleAuthErrorClassification` in `GoogleAccountAuthService.swift`, read directly |
| Client-secret requirement (exchange fails without it) and Settings field | Legacy `GoogleAccountAuthService.swift` + `Views/Settings/AssistSettingsView.swift` (client-id override, client-secret field), read directly |
| No Ycode quota service, no assistant quarantine concept | `grep` over `ycode/Sources` (0 hits for `resetToFresh` / `clearAllQuarantines` / `restartEngine` / `quarantine` in `YcodeAssistant`) |
| `extractOAuthURL(from:)` is dead code in Legacy | `grep` over `GoogleAccountAuthService.swift` (1 hit: the definition only) |
| No URL-scheme callback plumbing in Ycode | `grep` over `ycode/Sources` for `onOpenURL` / `handleOpenURL` (no handler found; Wave 12 evidence) |
| `swift-crypto` `Crypto` product name and package name | `ycode/Package.swift` (`YcodeSimLink` / `YcodeSDK` deps: `.product(name: "Crypto", package: "swift-crypto")`) |

## 10. Google account auth — the `YcodeGoogleAuth` target

Wave 15 (slice C) of the Legacy → Mac migration. Legacy's
`Services/GoogleAccountAuthService.swift` (1,773 lines) is a
separate Google-account auth system (Google Cloud / Antigravity),
unrelated to Appwrite: OAuth2 authorization-code flow with PKCE,
`ASWebAuthenticationSession`, a loopback redirect listener,
token exchange + refresh, and fallback to ambient Application
Default Credentials. This wave ports it faithfully onto Ycode,
including the parts that only work on macOS — which fail honestly
elsewhere instead of being faked.

No Swift toolchain exists in this environment, so everything
below is statically checked only — `swift build` / `swift test`
and live sign-in against Google are pending on Dylan's Mac.
Dylan must supply one thing to sign in end-to-end: his OAuth
client's secret (see §10.2). No live sign-in was attempted.

### 10.1 The target decision: a new target, not `YcodeCloud`

`YcodeGoogleAuth` is a new SwiftPM target
(`ycode/Sources/YcodeGoogleAuth/`, tests in
`ycode/Tests/YcodeGoogleAuthTests/`), following the `YcodeCloud`
model — plain `.target`, library product, test target — with one
dependency: `YcodeAssistant`, for `SecretStore`. It additionally
uses the `Crypto` product of `swift-crypto` for the PKCE SHA-256
(the `YcodeSimLink` / `YcodeSDK` precedent), so the target needs
no Apple-only cryptography import to stay Linux-buildable. The
coordinator wires `ycode/Package.swift` (the slice does not edit
it): the `YcodeGoogleAuth` target + product + test target, and the
`YcodeGoogleAuth` dependency on `YcodeUI` (for the Accounts pane)
and on `YcodeUITests` (for the pane tests).

`YcodeCloud` was the serious alternative and lost on three
counts. First, the Google service is a separate system from
Appwrite — Wave 12's own words — with its own identity, its own
endpoints, and its own Keychain accounts; folding it into the
Appwrite target would blur exactly the boundary the spec draws.
Second, the service's Apple-only pieces (`AuthenticationServices`,
`Network`, `Security`, AppKit) would land in a target that is
currently free of platform-gated imports and Linux-buildable;
isolated in its own target, the Apple-only code is fenced by
`#if canImport(...)` in one place. Third, the Accounts pane
already depends on `YcodeCloud`, so either home wires the UI the
same way — the new target costs one extra `Package.swift` line
and buys the separation. The shared pieces stay shared: the
secret store (`YcodeAssistant`), the stub-transport test pattern
(Wave 12), and the error style (§5).

### 10.2 Configuration (public identifiers) and the client secret (a Dylan-supplied prerequisite)

From Legacy's `GoogleAccountAuthService.swift`, read directly:

| Setting | Value | Source |
|---|---|---|
| OAuth client id | `671720100031-tkph1mke7c5bj3l93t5eemrplti78i77.apps.googleusercontent.com` | Legacy's `swiftCodeClientID` |
| Scopes | `cloud-platform`, `generative-language.retriever`, `userinfo.email`, `userinfo.profile`, `openid` | Legacy's `requiredScopes` |
| Authorize endpoint | `https://accounts.google.com/o/oauth2/v2/auth` | `buildAuthorizationURL` |
| Token endpoint | `https://oauth2.googleapis.com/token` | exchange / refresh |
| Tokeninfo endpoint | `https://www.googleapis.com/oauth2/v3/tokeninfo` | `verifyRuntimeSession` |
| Userinfo endpoint | `https://www.googleapis.com/oauth2/v2/userinfo` | `fetchUserEmail` |
| Callback scheme | `swiftcode` | Legacy's `callbackScheme` |
| Loopback ports | 65000, then 8085...8099, then ephemeral | `OAuthLoopbackServer.start()` |

The client id is a public identifier by design (PKCE public
clients carry it in the clear in the authorize URL) and lives in
`GoogleOAuthConfiguration` with exactly this default, like Wave
12's Appwrite coordinates. The scopes are Legacy's verbatim: the
Gemini Developer API's documented OAuth contract requires
`generative-language.retriever` (without it the API rejects the
token with 403 ACCESS_TOKEN_SCOPE_INSUFFICIENT), and Google's
first-party clients do not have the `generative-language.*`
scopes registered, so the authorization server would reject the
request outright on a borrowed client.

The client id resolves in Legacy's order: the
`GOOGLE_CLIENT_ID` environment variable, then the
`GOOGLE_CLIENT_ID` Info.plist key, then the user-editable
override (Legacy read it from
`AppSettings.assistGoogleOAuthClientIDOverride`; Ycode has no
`AppSettings`, so the service reads the same UserDefaults key,
`assist_google_oauth_client_id_override`, directly — same stored
value, same behaviour), then the built-in id. The override is set
from Settings → Accounts → Google Account.

**The client secret is a Dylan-supplied prerequisite.** Google's
token endpoint rejects the authorization-code exchange without it
for this client (400 invalid_request: "client_secret is
missing."), even though the browser authorization step succeeds
and Google's installed-app docs label the parameter "Optional".
Legacy embedded no secret either: it came from the user's own
OAuth client, entered in Settings and stored in Keychain, or from
the `GOOGLE_CLIENT_SECRET` environment variable / Info.plist key.
This port keeps exactly those sources (secret store →
environment → Info.plist) and never writes a real secret anywhere.
Without a secret, sign-in fails honestly at the exchange with
`.missingClientSecret`, and the UI shows the remediation
(§10.8). A desktop app cannot keep a secret truly confidential —
anyone can extract it from the installed app or its keychain.
That is accepted because Google requires the secret for the
exchange; the secret alone grants nothing without the user's own
authorization grant, and shipping it would let anyone impersonate
SwiftCode's OAuth client. (Legacy's comment, kept.)

### 10.3 The sign-in flow (PKCE + loopback + web-auth session)

`GoogleAccountAuthService.signIn()` (macOS only — see below):

1. Builds a PKCE pair: a verifier of 64 random bytes,
   base64url-encoded (86 characters, inside RFC 7636's 43–128
   range), and the S256 challenge, base64url(SHA-256(ASCII
   (verifier))). The random bytes come from the system generator
   (portable; Legacy's `SecRandomCopyBytes` is Apple-only and the
   generator cannot fail). The RFC 7636 Appendix B vector is in
   tests.
2. Starts the loopback listener (`GoogleLoopbackServer`, §10.4)
   and builds the redirect URI: port 65000 uses
   `http://localhost:65000/auth/callback`, every other port uses
   `http://127.0.0.1:<port>` with no path — Legacy's exact rule,
   kept so an existing Google Cloud Console redirect registration
   keeps working.
3. Builds the authorize URL: `client_id`, `redirect_uri`,
   `response_type=code`, the scopes, `code_challenge`,
   `code_challenge_method=S256`, `state` (a fresh UUID),
   `access_type=offline` (so Google returns a refresh token),
   `prompt=consent` (so it returns one on every sign-in, not just
   the first).
4. Opens it in an `ASWebAuthenticationSession`
   (`callbackURLScheme: swiftcode`, non-ephemeral browser
   session, presentation anchor = the main / key / first visible
   window, Legacy's fallback chain). If the session fails to
   start, the URL opens in the system browser instead (Legacy's
   fallback).
5. The loopback listener and the web-auth session both funnel the
   redirect into `handleCallbackURL`: the `error` query item is
   rejected first, then the state is checked, then the code is
   required — Legacy's order, with Legacy's messages. The code is
   exchanged once (`hasProcessedCallback` guards the second
   delivery), the tokens are stored (§10.5), the email is fetched
   (userinfo, falling back to the id token's `email` claim), and
   the runtime session is verified (§10.6). A scope-upgrade
   re-authentication (`isScopeUpgradeReauth`) ends here regardless
   of outcome and never leaks into a later sign-in (Legacy M-2).

**Linux (and any platform without `AuthenticationServices` and
`Network`) fails honestly.** `signIn()` sets
`.browserSignInUnavailable` and returns; no browser is faked, no
token is invented. The portable pieces — PKCE, token exchange and
refresh, ADC file discovery, Antigravity parsing, error
classification — work everywhere.

The loopback listener serves Legacy's success page verbatim
(dark card, "Authentication Successful", product name SwiftCode
to match the Accounts pane's "SwiftCode Account" naming): it
redirects to `swiftcode://oauth-callback` after 350 ms and closes
the window after 2 seconds.

`handleOpenURL(_:)` accepts the `swiftcode://` and
`antigravity://` schemes, plain `http` URLs, and `127.0.0.1` /
`localhost` hosts (Legacy's exact rule — the loopback redirects
are `http`), and returns false for anything else. It is the
second delivery path for the callback; the app shell must forward
opened URLs to it (see §10.10) — until then, the loopback
listener is the path that actually delivers the callback.

### 10.4 The loopback listener (`GoogleLoopbackServer`)

Ported from Legacy's `OAuthLoopbackServer`: binds the first free
port in `preferredLoopbackPorts` (65000, then 8085...8099),
falling back to an ephemeral port; serves one success page per
connection; hands the full redirect URL (host prefix + path +
query) to `onCallback`. The request-line → callback-URL parsing
is a pure static function (`callbackURL(fromRequestLine:port:)`)
so tests can check loopback URL parsing without a socket. On
platforms without the `Network` framework, `start()` returns nil
and sign-in fails with `.loopbackUnavailable`.

### 10.5 Token storage (Keychain, never files or logs)

Tokens live in the injected `SecretStore` (Keychain on macOS, a
0600 file on Linux — see `SecretStore`), under Ycode-style dotted
account names in `GoogleSecretAccount` (the target does not edit
`YcodeAssistant`'s `SecretAccount` — these keys belong to this
service, so they live here):

| Account | Contents |
|---|---|
| `google.oauth.access-token` | current access token |
| `google.oauth.refresh-token` | refresh token (kept across sign-ins until revoked) |
| `google.oauth.email` | signed-in Google account's email |
| `google.oauth.expires-at` | access-token expiry, seconds since the epoch |
| `google.oauth.scope` | granted scopes, space-joined |
| `google.oauth.client-secret` | user-entered OAuth client secret |

The explicitly-signed-out flag and the client-id override live in
UserDefaults under Legacy's exact key strings
(`google_oauth_explicitly_signed_out`,
`assist_google_oauth_client_id_override`), so an existing
install's override and sign-out state survive the port. Secrets
are never logged and never written to a file by this service.

### 10.6 Session restore, verification, and token accessors

`restoreSessionFromKeychain()` keeps Legacy's order: (1)
Antigravity keychain credentials are imported first — the
CLI-imported access token gets an assumed one-hour expiry (the
CLI does not report a lifetime), so the accessors refresh it when
due instead of serving it unchecked forever (Legacy C-4); (2) a
stored email + token restores the session and verifies it in the
background; a token without an email restores and then fetches
the email; (3) an ADC email restores a session with no token.
An explicit sign-out blocks all of it.

`verifyRuntimeSession(accessToken:depth:)` is Legacy's tokeninfo
probe: 200 → valid; 400/401 → refresh once (bounded recursion,
`depth < 1`) and retry, else drop the dead access token and its
expiry (the refresh token is kept for a later retry), set
`lastTokenRefreshError` and the "session expired or unauthorized"
error, and mark unauthenticated (Legacy M-1); any other status or
a failed probe falls back to the stored expiry (valid when no
expiry was recorded or it is still in the future).

`getValidAccessToken()` (async) and `getValidAccessTokenSync()`
never return a known-expired token (Legacy C-4): a stored token
is returned directly when unexpired (a 60-second skew margin) or
when no expiry was recorded; an expired token is refreshed, then
ambient ADC is tried, and only then — when the expiry is past —
nil is returned so callers surface a re-authentication prompt
instead of sending a dead token. One deviation: the async
accessor is non-throwing (Legacy's `throws` was vestigial — no
path threw). The synchronous accessor keeps Legacy's semaphore
refresh (8-second wait, via a locked box — the `RateLimitBox` /
`Box` precedent — so the data-task completion can write the
result under Swift 6).

`hasRequiredAssistScopes()` is Legacy's check, verbatim: false
when unauthenticated; true when Antigravity credentials exist
(they possess the required scopes); otherwise true when the
stored scope contains `generative-language.retriever` or
`cloud-platform`; true when authenticated with no recorded scope
(to prevent false lockouts). `reAuthenticateForAssistScopes()`
re-runs `signIn()` with the scope-upgrade flag set, keeping the
existing session until the new sign-in succeeds.

`signOut()` deletes all five stored keys, sets the explicit
sign-out flag, cleans up the session, and resets all state.

### 10.7 Ambient credentials (ADC, Antigravity, `agy` CLI)

`checkAmbientADC()` keeps Legacy's order and its H-3 rule (an
explicit sign-out sticks — ambient credentials must not resurrect
the session): (1) Antigravity keychain credentials — a cached
access token is returned directly, otherwise the refresh token is
refreshed under the Antigravity client's own id and secret
(Legacy's `refreshAccessTokenWithDetails`); (2) ADC files — the
`GOOGLE_APPLICATION_CREDENTIALS` environment variable, then
`~/.config/gcloud/application_default_credentials.json` — an
`authorized_user` file refreshes under the file's own client id
and secret, a bare `access_token` is returned directly; (3) the
`gcloud` CLI (`auth print-access-token`, token must start with
`ya29.`). `ambientADCEmail()` reads the ADC file's `client_email`,
else the `account =` line of gcloud's active config
(`config_default`).

Antigravity parsing is ported verbatim: the nested
`{ "token": { "refresh_token", "access_token" } }` shape and the
flat shape, the `go-keyring-base64:` wrapper, a missing
`client_id` falling back to Ycode's own client id, and unknown
scopes staying empty (never fabricated). The keychain fetch reads
service `gemini`, accounts `antigravity` / `antigravity-acp`,
first via `SecItemCopyMatching`, then via the `/usr/bin/security`
CLI fallback. It is Apple-only (`Security` does not exist on
Linux), so on Linux the ADC file and `gcloud` paths are the only
ambient sources.

`importExistingAntigravityCredentials()` refreshes the
Antigravity credentials (falling back to the cached access token
with a one-hour expiry when refresh fails), stores the tokens,
and resolves the email from the id token, then userinfo, then
ADC, then the literal "Google Account (Antigravity)".

`signInViaCLI()` checks the keychain import first, then finds
the `agy` CLI (`AGY_PATH`, `~/.gemini/bin/agy`,
`~/.local/bin/agy`, `/opt/homebrew/bin/agy`, `/usr/local/bin/agy`,
`/usr/bin/agy`), launches it in Terminal via AppleScript
(falling back to a `.command` script when AppleScript reports an
error), and polls for the credentials for up to 120 seconds
(80 × 1.5 s). On a platform without AppleScript/Terminal the CLI
path fails honestly with `.cliSignInUnavailable`.

Testability seam: the Antigravity keychain fetch and the `gcloud`
runner are injectable closures on the service (the defaults read
the real keychain / run the real CLI). Tests neutralize both, so
no test ever reads the user's keychain, refreshes a real token, or
runs the real `gcloud`. The environment, home directory, and user
defaults are likewise injectable, so ADC discovery runs against
fixture files in a temp home.

### 10.8 Errors and the messages the UI shows

`GoogleAuthError` mirrors the Wave 12 error style: the server's
status and message are preserved verbatim in `.http`, and
`userFacingMessage` carries the mapping. A missing client secret
gets Legacy's `actionableSignInError` remediation — the browser
authorization succeeded but Google refused the exchange, enter
the secret in Settings → Accounts → Google Account (the path is
updated from Legacy's Settings → Assist → Google Account, where
the field now lives), stored in Keychain, found in Google Cloud
Console → APIs & Services → Credentials → your OAuth client.
A network failure says the connection failed; anything else passes
the server's message through.

`GoogleAuthErrorClassification` is ported verbatim in semantics
(same kinds, same matching order, same diagnostic fields):
scope-insufficient (carrying the stored scopes, so the caller can
tell a pre-scope token from a real restriction), missing client
secret (checked before the generic credential branch),
quota/rate-limit, invalid API key, invalid/expired credential,
and not-an-auth-error, with the HTTP status, RPC reason, service,
and method parsed from the text. One deliberate change: Legacy's
`classify(_:)` convenience read the granted scopes straight out
of its Keychain service; this port has no such global, so the
caller passes the stored scopes in — the service reads them from
its injected secret store.

### 10.9 The Accounts pane wiring

The Google section is added to the existing Accounts pane
(`YcodeUI/App/CloudAccountsSettings.swift` — the pane is not
duplicated, and the Appwrite section is untouched): a "Google
Account" heading below the SwiftCode tabs, built by
`buildGoogleAccountSection()`. It shows the signed-in email, the
Assist-scope status ("Ready for Assist" / "Re-authentication
needed for Assist"), sign-in (browser) and sign-in-via-`agy`-CLI
buttons when signed out, re-authenticate-for-Assist-scopes and
sign-out buttons when signed in, the OAuth client-secret field
(a secure field that never shows a stored value — it only sets a
new one, with the "Saved in Keychain" state in its placeholder)
and the client-id override field, the missing-secret note when no
secret is configured, and the last error / last refresh failure.
The pane holds the service (`AccountsSettingsPane.googleAuthService`,
injectable, default `.shared`), triggers its one session restore
on first build, and rebuilds on `onStateChange` — the service's
replacement for Legacy's `@Published` observation (the service is
a plain `@MainActor` class, not `NSObject` + `ObservableObject`:
the pane is AppKit and rebuilds imperatively). The pane actions
(`signInWithGoogle`, `signOutGoogle`,
`reAuthenticateGoogleForAssistScopes`, `signInGoogleViaCLI`,
`saveGoogleClientSecret`, `saveGoogleClientIDOverride`) are the
test seams: they call the service and rebuild.

The auth sheet's "Continue with Google" button is unchanged —
it is the Appwrite OAuth flow (§4.4), a different identity from
this Google Cloud account, and the two must not be conflated.

### 10.10 What is live, what is honestly unavailable, and what was not ported

Live in this slice: PKCE challenge/verifier generation and the
authorize URL, the loopback listener and its success page,
callback parsing and the code exchange, token refresh (async and
synchronous), userinfo email and id-token email, tokeninfo
verification with the one-retry rule, session restore and the
never-expired-token accessors, sign-out with the explicit
sign-out flag, Antigravity import and parsing, ADC file discovery
and `gcloud` fallback, the `agy` CLI flow, scope verification and
scope-upgrade re-authentication, error classification with the
missing-secret remediation, the client id/secret configuration,
and the Accounts pane Google section.

Honestly unavailable (with reasons):

| Capability | Reason |
|---|---|
| Browser sign-in on Linux | `ASWebAuthenticationSession` and the `Network` loopback listener are Apple-only. `signIn()` fails with `.browserSignInUnavailable` instead of faking a browser. |
| `agy` CLI sign-in on Linux | Driving the CLI's interactive login needs macOS Terminal / AppleScript. Fails with `.cliSignInUnavailable`. |
| Callback delivery via `handleOpenURL` | No app-shell URL-scheme plumbing exists yet: the app must register the `swiftcode` scheme and forward opened URLs to `GoogleAccountAuthService.handleOpenURL(_:)`. Until then the loopback listener is the delivery path. (Same gap as Appwrite OAuth, §4.4.) |
| End-to-end sign-in without a client secret | Google refuses the token exchange without it; the secret is Dylan-supplied (§10.2). |

Not ported, with the exact blocker or reason:

| Legacy piece | Disposition |
|---|---|
| `AntigravityQuotaService.resetToFresh()` (called on sign-out) | No Ycode counterpart: no quota service exists in Ycode. Dropped, not faked. |
| `AssistModelRouter.clearAllQuarantines()` (called after auth) | No Ycode counterpart: Ycode's assistant has no quarantine concept (`grep quarantine` over `YcodeAssistant` finds nothing). Dropped. |
| `GoogleCloudSDKLifecycleManager.restartEngine()` (called after auth) | No Ycode counterpart: the Google Cloud SDK engine is not ported (it is a Legacy Assist framework, not this slice). Dropped; a later wave that ports the engine re-attaches it. |
| `AppSettings.assistGoogleOAuthClientIDOverride` | Ycode has no `AppSettings`. The service reads the same UserDefaults key directly — same stored value, same behaviour. |
| `KeychainService.shared` | Replaced by the injected `SecretStore` (`YcodeAssistant`). |
| `GoogleAuthErrorClassification.classify(_:)` (keychain-reading overload) | Replaced by passing `storedScopes` explicitly; the service reads the scope from its injected store. |
| `extractOAuthURL(from:)` | Dead code in Legacy (defined but never called anywhere in the file). Not ported. |
| `GoogleAccountAuthService` as `NSObject` + `ObservableObject` with `@Published` | A plain `@MainActor` class with `onStateChange`; the Accounts pane is AppKit and rebuilds imperatively. |

### 10.11 Tests

`ycode/Tests/YcodeGoogleAuthTests/` — Swift Testing, stub
transport (`StubURLProtocol`, the Wave 12 pattern),
hand-written JSON fixtures, temp-home ADC fixtures, no live
network, no real credentials, no real keychain (the Antigravity
and `gcloud` seams are neutralized; the secret store is always a
`MemorySecretStore`). Test counts are counted from `@Test`
functions:

| File | Tests | Covers |
|---|---|---|
| `GooglePKCETests.swift` | 14 | RFC 7636 Appendix B vector, verifier shape and challenge round-trip, base64url encoding, authorize-URL parameters, redirect-URI rule, callback parsing (success / error / state mismatch / missing code), id-token email extraction, loopback URL parsing, success-page content, preferred ports |
| `GoogleTokenClientTests.swift` | 10 | Code-exchange request body and token decoding, secret omitted when unconfigured, missing-secret and generic HTTP error mapping, refresh grant and old-refresh-token retention, `expires_in` Int/Double/String tolerance, undecodable body, userinfo email and Bearer header, tokeninfo status |
| `GoogleAuthErrorClassificationTests.swift` | 11 | Scope-insufficient (with stored scopes), permission-denied scope, missing secret (before the credential branch), quota/rate-limit, API-key invalid, invalid/expired credential, not-an-auth-error, diagnostic summary, actionable remediation text and passthrough, network user-facing message |
| `GoogleADCAndAntigravityTests.swift` | 14 | Antigravity nested/flat/base64 parsing and garbage, ADC file parsing, ADC path order, gcloud config account line, `agy` candidate order, ADC-file refresh under the file's own client, bare access-token ADC file, `GOOGLE_APPLICATION_CREDENTIALS`, explicit sign-out blocking ADC, `ambientADCEmail` |
| `GoogleAccountAuthServiceTests.swift` | 20 (19 on macOS) | Stored-session restore, explicit sign-out blocking restore, sign-out clearing the store, valid/unexpired/no-expiry token accessors, sync accessor, expired-token refresh and refresh failure (nil, no dead token), no-token nil, callback exchange success / state mismatch / authorization error / missing secret / processed-once, tokeninfo verification and 401 token drop, scope checks, client-secret storage and environment source, client-id resolution order, `handleOpenURL` accept/reject, Linux sign-in honest failure (Linux only) |

69 tests total in `YcodeGoogleAuthTests`. `ycode/Tests/YcodeUITests/GoogleAccountsPaneTests.swift`
adds 6 pane tests: the Google section and its buttons when
signed out, the email and scope status when signed in, the
missing-scope status and re-authenticate button, saving the
client secret (and clearing it), saving the client-id override,
and sign-out from the pane. The browser sign-in is never driven
in tests — on macOS it would open a real web-auth session.

Evidence for §10's claims is in the Evidence table above (§9):
Legacy's `GoogleAccountAuthService.swift` was read directly for
the client id, scopes, endpoints, PKCE, loopback, ADC,
Antigravity, and classification claims; the not-ported rows rest
on the `grep` evidence listed there; the clean-room basis is the
same as the rest of this spec (Legacy is Dylan's own code,
direct porting authorised under MIT, plus public Google OAuth
documentation — RFC 7636, RFC 8252, Google's OAuth 2.0 endpoint
shapes). No reference Xcode copy, Ghidra, simulator IPSW,
`research/dirty/`, or Apple Xcode/Simulator observation was
opened, read, or run.
