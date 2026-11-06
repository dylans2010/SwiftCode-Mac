# Gap closure — cloud completeness + GitHub remainder

Gap-closure wave (family 5+6) of the Legacy → Mac migration. This
slice closes the honestly-unavailable items Wave 12 (accounts /
cloud / auth) and Wave 10 (GitHub client) left behind:

- App-shell URL-scheme plumbing, which unblocks **both** Appwrite
  OAuth (Wave 12) and Google OAuth (Wave 15).
- Appwrite Storage multipart upload, which unblocks the
  `BackupEngine` upload leg.
- `SupabaseService`, the Database utility's PostgREST client.
- `BackupEngine` migration (list / download / delete legs already
  worked through the `CloudProvider` seam; the engine itself and
  the upload leg did not exist).
- `AppConfig` remainder (Supabase / SwiftCloud / OpenRouter /
  Gemini configuration).
- GitHub remainder: `pushFile` / `getFileSHA`, workflow runs /
  jobs / artifacts / logs, releases, repo ZIP, `createRepository`.

No Swift toolchain exists in this environment, so everything below
is statically checked only — `swift build` / `swift test` and live
runs are pending on Dylan's Mac. No live network was used in tests;
no real credential appears anywhere in this slice.

## 1. URL-scheme plumbing (Appwrite OAuth + Google OAuth)

### What was missing

Verified live before touching anything: there was no registered
custom URL scheme anywhere in the destination (no
`CFBundleURLTypes` in `packaging/macos/Info.plist.in`, no
`onOpenURL` / `application(_:open:)` handler in `swiftcode/Sources`),
while both OAuth systems already had their receiving ends built:

- `CloudAuthManager.beginOAuth(provider:openURL:)` opens the
  authorize URL and waits for `handleOAuthCallback(_:)` to
  deliver the result; without plumbing it waits 5 minutes and
  times out with `.oauthCallbackTimeout`, never faking completion.
- `GoogleAccountAuthService.handleOpenURL(_:)` accepts the
  `swiftcode://` and `antigravity://` schemes, plain `http(s)`
  loopback URLs, and `127.0.0.1` / `localhost` hosts; without
  plumbing, only the loopback listener delivers the callback.

### What landed

`swiftcode/Sources/SwiftCodeUI/App/AppSupport.swift` (owned file):

- `AppDelegate.application(_:open:)` forwards every URL the
  system routes to the app to `AppDelegate.handleOpenedURL(_:)`.
- `handleOpenedURL(_:)` offers the URL to
  `CloudAuthManager.shared.handleOAuthCallback(_:)` first, then
  to `GoogleAccountAuthService.shared.handleOpenURL(_:)`. The
  first handler that claims it wins; the return value says
  whether any handler claimed it.
- `handleOAuthCallback` returns `nil` in two cases — the URL is
  not an Appwrite callback, and it resumed a pending OAuth wait
  — so the router distinguishes them by checking the scheme
  afterwards: a URL on the `appwrite-callback-<project>` scheme
  was consumed even when nothing is left to do with it.
- A standalone verification link (no OAuth wait pending) is
  completed in place via `verifyEmail(userId:secret:)` — that is
  the whole point of the emailed link. A standalone recovery
  link is announced on
  `Notification.Name.appwriteRecoveryLinkReceived` with `userId`
  / `secret` in `userInfo` (also in `AppSupport.swift`); it is
  **not** completed here, because completing a reset needs a new
  password from the user and no reset sheet exists yet (see §1.1).

### `Info.plist.in` — patch for the coordinator (not this slice's file)

`packaging/macos/Info.plist.in` is outside this slice's owned
set, so it is **not edited here**. The coordinator applies this
exact patch (insert before the closing `</dict>`):

```xml
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLName</key>
			<string>com.dylans2010.SwiftCode-Mac.appwrite-callback</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>appwrite-callback-6a670d0b0022e5f964b4</string>
			</array>
		</dict>
		<dict>
			<key>CFBundleURLName</key>
			<string>com.dylans2010.SwiftCode-Mac.swiftcode</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>swiftcode</string>
			</array>
		</dict>
	</array>
```

Notes on the patch:

- The Appwrite scheme is derived from the default project id
  (`AppwriteConfiguration.callbackScheme`); if Dylan ever changes
  the Appwrite project, the plist entry must change with it.
- `antigravity://` is **not** registered: it belongs to another
  app's flow, and registering it would hijack that scheme.
  `GoogleAccountAuthService.handleOpenURL` still accepts it if
  the system ever delivers it.
- The app must be (re)installed / relaunched for Launch Services
  to pick up the new scheme registration; a bare rebuild is not
  enough.
- No `Package.swift` change is needed: `SwiftCodeUI` already depends
  on `SwiftCodeCloud` and `SwiftCodeGoogleAuth`.

### 1.1 Still open: the password-reset sheet

A recovery link opened from an email now reaches the app and is
announced, but nothing in the UI completes the reset: the auth
sheet has login / create-account / forgot-password modes and no
reset-completion mode, and `CloudAuthManager.resetPassword`
needs a user-supplied new password. The follow-up is a reset
sheet that observes `.appwriteRecoveryLinkReceived` and calls
`resetPassword(userId:secret:password:)`.

### Tests

`CloudGapTests`: `beginOAuth` resumes when the app shell
delivers the callback (stub transport, no browser), throws on a
provider-declined callback, and `handleOAuthCallback` returns
standalone recovery / verification links. The delegate method
itself has no test (it needs a running app); the contract it
relies on is what is tested.

## 2. Storage upload (multipart/form-data)

`AppwriteAccountClient.createFile(bucketId:fileId:data:filename:contentType:)`
(`POST /storage/buckets/{bucketId}/files`) builds a real
`multipart/form-data` body — the `fileId` text field, then the
`file` part with filename and content type, then the raw bytes —
and decodes the created `AppwriteFile`. The body builder
(`multipartFormData(boundary:fileId:data:filename:contentType:)`)
is a pure static function so tests assert its shape without a
network call.

`AppwriteStorageProvider.upload` now calls it and returns the
created file's id, instead of throwing. That unblocks the
`BackupEngine` upload leg (§4). The Wave 12 spec's §3.4 / §8
"multipart upload not built" is now closed.

## 3. SupabaseService (PostgREST, Database utility)

`swiftcode/Sources/SwiftCodeCloud/SupabaseService.swift` (new) +
`swiftcode/Sources/SwiftCodeCloud/DatabaseModels.swift` (new), ported
from Legacy's `Views/Utilities/Database/Services/SupabaseService.swift`
and the `Views/Utilities/Database/Models/` + `Helpers/` types it
touches.

- `testConnection(connection:)` — `GET {url}/rest/v1/`, anon key
  as `apikey` + `Bearer` when present, `true` on HTTP 200,
  `.connectionFailed` with the status otherwise. Invalid project
  URL throws `.connectionFailed("Invalid Supabase Project URL.")`.
- `fetchTables(connection:)` — parses the PostgREST OpenAPI
  schema's `definitions` into `[DatabaseTable]`, sorted by name:
  `properties` become columns (`type` uppercased, primary key
  when named `id`, nullable unless in `required`, `description`
  as the comment). No `definitions` yields `[]`.
- The service is a value type with an injected `URLSession`
  (`.shared` by default), following the `GitHubClient` /
  `AppwriteAccountClient` pattern; Legacy read
  `URLSession.shared` directly. `postgrestRequest` and
  `parseTables(from:)` are exposed for tests via `@testable`.

Models ported verbatim: `DatabaseProvider`, `DatabaseInfo`,
`DatabaseConnection`, `DatabaseTable`, `DatabaseColumn`,
`DatabaseRelationship` (+ `RelationshipType`,
`ReferentialAction`), `DatabaseIndex`, `DatabaseTrigger`,
`DatabaseError`. `fetchTables` does not populate relationships
/ indexes / triggers — PostgREST's OpenAPI schema does not
describe them — the types are carried over so `DatabaseTable`
keeps its shape.

### Honest correction: `executeSQL`

Legacy's `executeSQL` did not execute anything: it logged the
SQL and returned the hardcoded string "SQL statement successfully
executed in Supabase project." PostgREST exposes no SQL-execution
endpoint, and Legacy configured no RPC for one, so this port
throws `.queryExecutionFailed` naming the missing RPC (or a
direct Postgres connection) instead of reporting a success that
never happened. This is a deliberate deviation from Legacy, in
the direction Dylan's real-thing standard requires.

## 4. BackupEngine

`swiftcode/Sources/SwiftCodeCloud/BackupModels.swift` (new) +
`swiftcode/Sources/SwiftCodeCloud/BackupEngine.swift` (new), ported from
Legacy's `Frameworks/Internal/Backups/Models/BackupModels.swift`
and `Frameworks/Internal/Backups/Engine/BackupEngine.swift`.

### What changed in the port

| Legacy | This port | Why |
|---|---|---|
| ZIPFoundation `Archive` | `/usr/bin/zip` (create) + `/usr/bin/unzip` (extract) via `Foundation.Process` | No ZIPFoundation dependency in the destination; same precedent as `SwiftCodeExtensions.PackageService`, which extracts with `/usr/bin/unzip` on macOS and Linux. Missing tool fails honestly as `.missingTool` naming the tool. |
| CryptoKit `SHA256` | Pure-Swift `SHA256Digest` (already in `SwiftCodeCloud`) | No new dependency; same digest. |
| `Host.current().localizedName` | `ProcessInfo.processInfo.hostName` | AppKit-only API; portable. |
| `AuthManager.shared` read directly | Injected `CloudAuthManager` (default `.shared`) | Testable with a stub transport, like `CloudManager`. |
| `os.Logger` | No logging | `os.log` is Apple-only; the hash is kept in `lastArchiveSHA256` instead of only being logged. |
| `@Observable` | Plain `@MainActor` class | No Observation dependency in the target; state is MainActor-isolated either way. |

### Behaviour kept, including the sharp edges

- Every operation requires an authenticated Appwrite session
  **and** a SwiftCode id, else `.unauthenticated` (Legacy's
  `NSError` 401).
- `performBackup(provider:)` archives the whole `Application
  Support/SwiftCode` directory except `Backups` itself (staged
  through a temp directory so the exclusion is exact), hashes
  the archive, and uploads it to the `backups` bucket as
  `<uuid>.zip` (`application/zip`) when a provider is given.
  Progress runs 0 → 0.5 local, 0.9 after upload, 1.0 done.
- `fetchCloudBackups` merges cloud `.zip` manifests as
  cloud-stored, newest first. Cloud manifests carry `Date()` and
  size `0` — Legacy had no remote metadata to fill those in.
- `restore` downloads the ZIP first when cloud-stored, then
  **erases the current local application state** (everything
  under `Application Support/SwiftCode` except `Backups`) and
  extracts, then calls `CloudSyncEngine.shared.triggerSync()`.
  The erase is Legacy's behaviour and is destructive; callers
  must confirm with the user first. A missing local archive
  returns `RestoreResult(isSuccess: false, ...)` instead of
  throwing, as in Legacy. The archive hash is computed but, as
  in Legacy, compared against nothing.
- `delete` removes the local file and the remote copy when
  cloud-stored.
- The bucket is `backups`; Legacy's "Supabase backups bucket"
  wording is corrected to Appwrite in status strings — the calls
  go through `cloudProvider.storage` (Appwrite Storage), and the
  Supabase URL in `AppConfig` is separate backup configuration,
  not a dependency.
- The archive/unarchive steps are injected closures (defaulting
  to the system tools) so tests substitute fakes and never shell
  out or touch the real Application Support directory. One test
  does exercise the real `zip`/`unzip` round-trip (both ship on
  macOS and are present on the Linux workstation).

## 5. AppConfig remainder

`swiftcode/Sources/SwiftCodeCloud/AppConfig.swift` (new), ported from
Legacy's `SwiftCode/Config/AppConfig.swift`: the five
configuration entries, read from the same Info.plist keys
(`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `OPENROUTER_API_KEY`,
`GEMINI_API_KEY`, `SWIFTCLOUD_API_URL`), with the same
sanitizing rule (empty / `$`-prefixed / `placeholder`-containing
values count as unconfigured) and the same `runDiagnostics()`
(`LOADED` / `MISSING` per key, values never included).

Defaults kept verbatim (public configuration, not secrets):
Supabase URL `https://secctbuzkfbketdihzui.supabase.co`,
SwiftCloud API URL `https://api.swiftcloud.ai/v1`. Unconfigured
API keys read as `""`, as Legacy did for OpenRouter/Gemini.

### Deliberate correction: the Supabase anon-key fallback

Legacy's `supabaseAnonKey` fell back to a hardcoded JWT whose
signature segment is literally `mock-key-signature` — a
placeholder, not a usable credential. That string is **not**
carried over: copying it would ship a fake credential that
authenticates nothing and reads as a leaked key to every
scanner. This port returns `""` when no anon key is configured,
and diagnostics reports it `MISSING`, so the gap is visible
instead of papered over. Dylan supplies a real anon key via the
Info.plist key (or the Database utility's per-connection key)
when he wants Supabase backup configuration to be live.

The keys Dylan actually signs in with live in the secret store
(Wave 9) and are read from there, not from `AppConfig`.

## 6. GitHub remainder

`swiftcode/Sources/SwiftCodeGitHub/GitHubClient.swift` (extended) +
`swiftcode/Sources/SwiftCodeGitHub/GitHubModels.swift` (extended),
ported from Legacy's `Backend/GitHub/GitHubAPI.swift` (+
`GitHubBuilds.swift` for the workflow helpers). Same
conventions as Wave 10: token per request via `tokenProvider`,
never stored, never logged; writes are client methods — the
approval gate lives in the MCP tool layer, as for the rest of
Wave 10, and no MCP tool is added or changed here.

New client methods (all real calls against `api.github.com`):

| Method | Endpoint | Notes |
|---|---|---|
| `getFileSHA(owner:repo:path:)` | `GET /repos/{o}/{r}/contents/{path}` | `nil` on 404 only. Legacy returned `nil` for *every* non-200, which would hide an expired token as "file does not exist"; this port throws on non-404 failures (documented deviation). |
| `pushFile(owner:repo:path:content:message:sha:branch:)` | `PUT /repos/{o}/{r}/contents/{path}` | Content is base64-encoded here; callers pass plain text. `sha` (from `getFileSHA`) turns a create into an update; `branch` is additive (Legacy had none). Returns the created/updated `GitHubFileContent`. Needs `contents: write` / classic `repo`. |
| `listWorkflowRuns(owner:repo:perPage:)` | `GET /repos/{o}/{r}/actions/runs` | |
| `getWorkflowRun(owner:repo:runID:)` | `GET /repos/{o}/{r}/actions/runs/{id}` | |
| `listWorkflowJobs(owner:repo:runID:)` | `GET /repos/{o}/{r}/actions/runs/{id}/jobs` | |
| `getJobLogs(owner:repo:jobID:)` | `GET /repos/{o}/{r}/actions/jobs/{id}/logs` | Returns the log text (UTF-8, else `""`, as in Legacy). |
| `getWorkflowRunLogsURL(owner:repo:runID:)` | `GET /repos/{o}/{r}/actions/runs/{id}/logs` | Returns the temporary download URL. Legacy stopped at the 302 with a no-redirect delegate; this port lets `URLSession` follow the redirect and returns `response.url` — the same URL, at the cost of downloading the log body once. |
| `listWorkflowArtifacts(owner:repo:runID:)` | `GET /repos/{o}/{r}/actions/runs/{id}/artifacts` | |
| `downloadArtifact(owner:repo:artifactID:)` | `GET /repos/{o}/{r}/actions/artifacts/{id}/zip` | Returns the ZIP bytes; the caller decides where to save them. |
| `listReleases(owner:repo:perPage:)` | `GET /repos/{o}/{r}/releases` | |
| `downloadRepositoryZip(owner:repo:branch:)` | `GET /repos/{o}/{r}/zipball/{branch}` | Returns the ZIP bytes. Legacy wrote them straight to the user's Documents folder; this client does not pick a user-visible path. |
| `createRepository(name:description:isPrivate:)` | `POST /user/repos` | `auto_init: false`, as in Legacy. Needs `public_repo` / `repo` (classic) or `administration: write` (fine-grained). Throws `.missingToken` before any network call when no token is configured. |

New models (ported from Legacy's `GitHubService.swift`):
`GitHubWorkflowRun` (with Legacy's `isRunning` /
`statusBadge`), `GitHubWorkflowJob`, `GitHubWorkflowStep`,
`GitHubArtifact`, `GitHubRelease`, `GitHubReleaseAsset`
(Legacy's `GitHubAsset`, renamed to avoid clashing with the
asset catalog's types).

Refactor, behaviour-preserving: `perform` is now built on a
new `performRaw` (raw bytes + HTTP response, rate-limit
recording, no status mapping); every `performRaw` caller
validates with `validate(_:data:)` before using the bytes,
except `getFileSHA`, which checks 404 first. Existing callers
are unaffected (`perform` still validates, then decodes).

### Scopes Dylan's PAT may lack

Reads of public repositories work unauthenticated; private
reads need `repo` (classic) or the fine-grained `contents: read`
/ `actions: read`. `pushFile` needs `contents: write`,
`createRepository` needs `public_repo`/`repo`, artifact/log
downloads need `actions: read`. A token without the scope fails
honestly at runtime with 401/403 mapped by the existing error
type — no scope is probed or worked around here.

### Not ported

- `GitHubBuilds.fetchLogsURL` / `fetchLogContent` as a
  separate type: the two methods above (`getWorkflowRunLogsURL`
  + a download from the returned URL) are the same capability;
  `statusSummary(for:)` / `isRunning(_:)` live on
  `GitHubWorkflowRun` as `statusBadge` / `isRunning`.
- No MCP tools were added: the client is the unblocker; which
  tools surface these calls is a coordinator decision, and the
  MCP catalogue count (433) is unchanged.
- No GitLab / Bitbucket (Wave 10 scope decision, unchanged).

## 7. Tests

`swiftcode/Tests/SwiftCodeCloudTests/CloudGapTests.swift` — 26 tests
(Swift Testing, stub transport, hand-written fixtures, no live
network, no real credentials):

| Tests | Covers |
|---|---|
| 3 | Multipart body shape, `createFile` request + decoding, storage-provider upload returning the created file id |
| 3 | `beginOAuth` resume on callback, provider-declined callback, standalone recovery/verification links |
| 8 | Supabase `testConnection` (200 + headers, non-200, bad URL), `fetchTables` (parse, empty, non-200), honest `executeSQL` failure, request without anon key |
| 3 | `AppConfig` defaults/diagnostics, configured values, placeholder/`$` values treated as unconfigured |
| 9 | BackupEngine auth guard, local listing, local-only backup (hash + reload), upload leg, cloud fetch merge, cloud restore (download + erase + extract + count), missing-archive result, delete (local + remote), real `zip`/`unzip` round-trip |

`swiftcode/Tests/SwiftCodeGitHubTests/GitHubGapTests.swift` — 17 tests:

| Tests | Covers |
|---|---|
| 6 | `getFileSHA` (found / 404-nil / 401-throws), `pushFile` create (PUT, base64, no `sha`), update (`sha` + `branch` sent), 422 |
| 7 | Workflow runs (list + single, actor, badge), jobs (+ steps), job logs text, logs URL, artifacts list, artifact download bytes |
| 4 | Releases (+ assets), repo ZIP bytes + branch path, `createRepository` (request body + decoded repo), missing-token throw with zero requests |

## 8. What is live, what is honestly unavailable

| Capability | Status |
|---|---|
| Appwrite OAuth (Google/GitHub) completion | Live once the `Info.plist.in` patch (§1) is applied and the app is reinstalled — the handler and the plumbing are both landed; the plist registration is the only missing piece, and it is delivered as an exact patch, not an edit, because the file is outside this slice. |
| Google OAuth completion | Same: the `swiftcode://` scheme registration in the same patch + the existing `handleOpenURL` forwarding. The loopback listener already worked without it. |
| Storage upload / BackupEngine upload leg | Live. |
| BackupEngine (local + cloud legs) | Live; restore erases local state by design (Legacy behaviour). |
| Supabase PostgREST client | Live; `executeSQL` honestly unavailable (no endpoint, no RPC configured). |
| AppConfig remainder | Live as configuration; real keys come from the secret store / Dylan-supplied Info.plist values. |
| GitHub remainder (all 12 methods) | Live as client calls; scope failures surface as 401/403. |
| Password-reset completion from an emailed link | Announced, not completed — needs a reset sheet (§1.1). |

## 9. Package.swift wiring needed

None. `SwiftCodeCloud` gains no dependency (Foundation +
`SwiftCodeAssistant` only); `SwiftCodeGitHub` gains none; `SwiftCodeUI`
already depends on `SwiftCodeCloud` and `SwiftCodeGoogleAuth`, so the
app-shell forwarding needs no new wiring. No new target, no new
product, no new test-target dependency.

## Evidence

Per the destination `AGENTS.md` clean-room protocol (rule 4)
and the migration's Legacy carve-out: Legacy is Dylan's own
code and direct porting was authorised by Dylan under MIT, so
the implementation below was derived from Legacy source plus
public API documentation (Appwrite Storage REST + multipart
upload, GitHub REST API endpoint shapes). No reference Xcode
copy, Ghidra, simulator IPSW, `research/dirty/`, or Apple
Xcode/Simulator observation was opened, read, or run.

| Claim | Evidence |
|---|---|
| No URL-scheme plumbing existed in the destination | `grep` over `swiftcode/Sources` for `onOpenURL` / `handleOpenURL` / `CFBundleURLSchemes` (only the IDE's own Info.plist *editor* model mentions `CFBundleURLTypes`; no handler, no registration) + `packaging/macos/Info.plist.in` read directly (no `CFBundleURLTypes`) |
| Appwrite OAuth client side + `handleOAuthCallback` contract | `swiftcode/Sources/SwiftCodeCloud/CloudAuthManager.swift` + `AppwriteAccountClient.swift`, read directly |
| Google `handleOpenURL` contract + `swiftcode` scheme + loopback | `swiftcode/Sources/SwiftCodeGoogleAuth/GoogleAccountAuthService.swift` (line ~1076) + `GoogleOAuthConfiguration.swift`, read directly |
| Appwrite Storage file creation is multipart `fileId` + `file` | Appwrite REST API documentation (public); response shape is the same `AppwriteFile` the list call returns |
| SupabaseService behaviour (PostgREST `rest/v1/`, `apikey` + `Bearer`, OpenAPI `definitions` parsing, faked `executeSQL`) | Legacy `Views/Utilities/Database/Services/SupabaseService.swift`, read directly |
| Database models | Legacy `Views/Utilities/Database/Models/Database*.swift` + `Helpers/DatabaseErrorHandler.swift`, read directly |
| BackupEngine behaviour (401 guard, `backups` bucket, ZIP snapshot of `SwiftCode/` minus `Backups`, hash, erase-on-restore, `triggerSync`) | Legacy `Frameworks/Internal/Backups/Engine/BackupEngine.swift` + `Models/BackupModels.swift`, read directly |
| `zip`/`unzip` extraction precedent | `swiftcode/Sources/SwiftCodeExtensions/PackageService.swift` (`/usr/bin/unzip -q -o` on macOS and Linux) |
| AppConfig entries, Info.plist keys, sanitizing rule, diagnostics | Legacy `SwiftCode/Config/AppConfig.swift`, read directly; the anon-key fallback JWT carries the literal `mock-key-signature` segment |
| GitHub endpoints + request/response shapes | Legacy `Backend/GitHub/GitHubAPI.swift` + `Backend/Git/GitHubService.swift` (models) + `Backend/GitHub/GitHubBuilds.swift`, read directly |
| No MCP tool calls the new GitHub methods yet | `grep` for `pushFile` / `getFileSHA` / `listWorkflowRuns` / `createRepository` / `downloadRepositoryZip` / `listReleases` over `swiftcode/Sources/SwiftCodeMCP/` + `SwiftCodeAssistant/` (0 hits) |
| `SwiftCodeUI` already depends on `SwiftCodeCloud` + `SwiftCodeGoogleAuth` | `swiftcode/Package.swift` (line ~209), read directly |
