# GitHub service — the `YcodeGitHub` client, the GitHub tools, and remote git

Wave 10 of the Legacy → Mac migration. Before this wave, Ycode's MCP
host had no GitHub API client and no GitHub credential flow: `github_repo`
(Wave 3, §71.4 of the Assist catalogue), the seven Agentic GitHub tools,
and `git_pull` / `git_push` / `git_clone` (Wave 8) were all registered
but honestly failing, and `version_control_operator` rejected every
remote action. This wave removes all of those prerequisites:

- **Part 1** — the new `YcodeGitHub` SwiftPM target: a small `URLSession`
  client for `api.github.com`, with Keychain-stored token, rate-limit
  handling, pagination, and typed errors.
- **Part 2** — the seven Agentic GitHub tools plus `github_repo`, wired
  to the client for real.
- **Part 3** — real remote git: `git_pull` / `git_push` / `git_clone`
  and `version_control_operator` push/pull/fetch/clone, with an
  approval gate, a remote-URL policy, and stdin-only credential
  seeding for github.com HTTPS remotes.

No Swift toolchain exists in this environment, so everything below is
statically checked only — `swift build` / `swift test` and live runs
against `api.github.com` are pending on Dylan's Mac. Dylan must supply
a GitHub personal access token (Settings ▸ Coding Assistant ▸ GitHub)
to enable the authenticated tools; public reads work without one at
GitHub's lower rate limit.

## Part 1 — The `YcodeGitHub` client

`public struct GitHubClient: Sendable` is the single `api.github.com`
client the assistant's GitHub tools and the settings pane share. It is
a value type with no stored token: the token is read from the secret
store on every request through a `@Sendable () -> String?`
`tokenProvider`, so a token saved or removed in Settings takes effect
without rebuilding the client. Implementation:
`ycode/Sources/YcodeGitHub/` (`GitHubClient.swift`, `GitHubModels.swift`,
`GitHubError.swift`, `GitHubRepoReference.swift`).

- Base URL is the constant `https://api.github.com` — not
  configurable, matching Legacy (`GitHubAPIBackend.baseURL`).
- One `URLSession`, injected (`.shared` by default; tests inject a
  session backed by a `URLProtocol` stub). No live network in tests.
- `lastRateLimit` is `public private(set)`; the mutable state lives in
  a locked box (`RateLimitBox`) because a struct's computed setter is
  implicitly mutating — the setter is `nonmutating set`, following the
  `YcodeDarwinKernel` precedent (`ExtendedBSD.swift` `ioPolicies`).
- Decoding is one shared `JSONDecoder`:
  `.convertFromSnakeCase` + `.iso8601`, as in Legacy's
  `snakeCaseDecoder()`. Nested objects (`owner.login`, `head.ref`,
  `commit.author.date`, `repository.full_name`) are decoded with
  custom `init(from:)`; the `private` JSON key maps to `isPrivate`.
- `per_page` is clamped to 1...100 on every method that takes it;
  `page` is clamped to ≥ 1. Owner/repo segments are rejected when
  empty or containing `/` (`.invalidRepo`); file paths are
  percent-encoded with `.urlPathAllowed` (slashes stay separators),
  as Legacy does in `getFileContent`.

### 1.1 Headers (every request)

| Header | Value |
|---|---|
| `Accept` | `application/vnd.github+json` |
| `X-GitHub-Api-Version` | `2022-11-28` |
| `User-Agent` | `Ycode` |
| `Authorization` | `Bearer <token>` — only when the provider returns a non-empty token |
| `Content-Type` | `application/json` — POST/PATCH only |

The token is optional: unauthenticated requests work for public reads
at GitHub's lower rate limit. The token is never logged and never
stored by the client.

### 1.2 Endpoints

| Method | Path | Notes |
|---|---|---|
| `rateLimit()` | `GET /rate_limit` | Returns the `rate` object; also refreshes `lastRateLimit` |
| `getAuthenticatedUser()` | `GET /user` | Requires a token, else `.missingToken` |
| `getRepository(owner:repo:)` | `GET /repos/{owner}/{repo}` | |
| `listBranches(owner:repo:perPage:)` | `GET /repos/{owner}/{repo}/branches?per_page=` | Default 30 |
| `listCommits(owner:repo:branch:perPage:)` | `GET /repos/{owner}/{repo}/commits?sha={branch}&per_page=` | Defaults `main`, 20 |
| `getFileContent(owner:repo:path:ref:)` | `GET /repos/{owner}/{repo}/contents/{path}?ref=` | `ref` omitted when nil |
| `getFileText(owner:repo:path:ref:)` | (same as above) | Base64-decodes `content` (newlines stripped first); throws `.decoding` on failure |
| `getRepoTree(owner:repo:ref:recursive:)` | `GET /repos/{owner}/{repo}/git/trees/{ref}?recursive=1` | Defaults `main`, `true`; unwraps the `tree` array |
| `listIssues(owner:repo:state:perPage:page:)` | `GET /repos/{owner}/{repo}/issues` | Defaults `open`, 30, 1. Pull requests appear here too (`isPullRequest`) |
| `getIssue(owner:repo:number:)` | `GET /repos/{owner}/{repo}/issues/{number}` | |
| `createIssue(owner:repo:title:body:labels:)` | `POST /repos/{owner}/{repo}/issues` | Body `title`, `body`, `labels` (default `[]`) |
| `updateIssue(owner:repo:number:title:body:state:)` | `PATCH /repos/{owner}/{repo}/issues/{number}` | Only non-nil fields are sent (nil keys omitted by `Encodable`) |
| `searchIssues(query:perPage:page:)` | `GET /search/issues?q=&per_page=&page=` | |
| `getPullRequest(owner:repo:number:)` | `GET /repos/{owner}/{repo}/pulls/{number}` | |
| `listPullRequests(owner:repo:state:perPage:)` | `GET /repos/{owner}/{repo}/pulls` | Defaults `open`, 30 |
| `createPullRequest(owner:repo:title:body:head:base:draft:)` | `POST /repos/{owner}/{repo}/pulls` | Body `title`, `body`, `head`, `base`, `draft` (default `false`) |
| `listPullRequestFiles(owner:repo:number:)` | `GET /repos/{owner}/{repo}/pulls/{number}/files` | |
| `listPullRequestReviews(owner:repo:number:)` | `GET /repos/{owner}/{repo}/pulls/{number}/reviews` | |
| `searchCode(query:perPage:)` | `GET /search/code?q=&per_page=` | |

Not ported in this wave (Legacy has them; later work if needed):
`pushFile` / `getFileSHA`, workflow runs/jobs/artifacts/logs,
releases, `downloadRepositoryZip`, `createRepository`.

### 1.3 Auth flow

1. The user pastes a personal access token into Settings ▸ Coding
   Assistant ▸ GitHub (a `SecureField`; `secretRow` in the Wave 9
   style). Save writes it to the secret store under
   `SecretAccount.githubToken = "github.api-key"` (Keychain on macOS,
   0600 files on Linux); Remove deletes it. The token is never
   displayed back.
2. The Validate button reads the token once, builds a `GitHubClient`
   with a provider returning that value, and calls
   `getAuthenticatedUser()`. Success shows `Signed in as <login>.`;
   failure shows the error's message (missing token, 401, rate
   limit, network).
3. Every client request adds `Authorization: Bearer <token>` when
   the provider returns a non-empty token, and omits the header
   otherwise. `getAuthenticatedUser()` throws `.missingToken`
   before any request when there is no token.

### 1.4 Rate-limit behaviour

After every response — success or error — the client parses
`X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`
(Unix seconds → `Date`) and `Retry-After` into
`public private(set) var lastRateLimit: GitHubRateLimit?`. A response
with no rate-limit headers leaves the last known state alone.
`GitHubRateLimit.isExhausted` is `remaining == 0`.

`GET /rate_limit` decodes the `rate` object of the response and also
stores it in `lastRateLimit`. The client never retries or waits on a
limit itself; it reports the reset time and lets the caller decide.

### 1.5 Error mapping

`GitHubError: Error, LocalizedError, Equatable`. GitHub's error JSON
`message` field is used where present.

| Situation | Error |
|---|---|
| No token for `getAuthenticatedUser()` | `.missingToken` — "No GitHub token saved. Add a personal access token in Settings ▸ Coding Assistant ▸ GitHub." |
| HTTP 401 | `.unauthorized` |
| HTTP 403, quota exhausted (`X-RateLimit-Remaining: 0`, or the message says "rate limit") | `.forbidden(message:, rateLimited: true, resetAt:)` — `resetAt` from `X-RateLimit-Reset` |
| HTTP 403, anything else | `.forbidden(message:, rateLimited: false, resetAt: nil)` |
| HTTP 429 | `.forbidden(message:, rateLimited: true, resetAt:)` |
| HTTP 404 | `.notFound` |
| HTTP 422 | `.unprocessable(message:)` |
| Any other non-2xx | `.http(status:, message:)` |
| Body does not decode / file content is not valid base64 or UTF-8 | `.decoding` |
| Transport failure / non-HTTP response | `.network` |
| Empty owner/repo, or a segment containing `/` | `.invalidRepo("owner/repo")` |

Messages name the fix where there is one. Error strings never
contain the token.

### 1.6 Models

All public, `Decodable` with `.convertFromSnakeCase` + `.iso8601`:

- `GitHubUser` — login, id, name?, avatarUrl?, htmlUrl?
- `GitHubRepository` — name, fullName, ownerLogin, description?,
  isPrivate, htmlUrl, defaultBranch?, stargazersCount, forksCount,
  language?, createdAt?, updatedAt?, pushedAt?
- `GitHubIssue` — number, title, body?, state, userLogin, labels:
  [String] (label names), createdAt?, updatedAt?, htmlUrl,
  isPullRequest (true when the `pull_request` key is present)
- `GitHubPullRequest` — number, title, body?, state, headRef, headSha?,
  baseRef, userLogin, draft, merged?, htmlUrl, createdAt?, updatedAt?
- `GitHubPullRequestFile` — filename, status, additions, deletions, changes
- `GitHubReview` — id, userLogin, state, body?, submittedAt?
- `GitHubBranch` — name, commitSha (`commit.sha`)
- `GitHubCommit` — sha, message, authorName?, authorDate?
  (`commit.message`, `commit.author.name/date`)
- `GitHubTreeEntry` — path, type, sha, size?
- `GitHubFileContent` — name, path, sha, size, content (base64, may
  contain newlines), encoding
- `GitHubSearchResult<T: Decodable & Sendable>` — totalCount, items
- `GitHubCodeItem` — repositoryFullName (`repository.full_name`),
  path, name
- `GitHubRateLimit` — limit, remaining, resetAt: Date?,
  retryAfter: TimeInterval?; `parse(from: HTTPURLResponse)`;
  `Decodable` from the `/rate_limit` `rate` object (`reset` is Unix
  seconds)

### 1.7 Repo references

`public enum GitHubRepoReference` (pure string parsing, no network):

- `parse(_:)` — `owner/repo`: trims whitespace, strips a trailing
  `.git`, rejects anything with more or fewer than two non-empty
  segments (including empty segments and embedded whitespace).
- `parseRemoteURL(_:)` — `https://github.com/owner/repo(.git)`,
  `git@github.com:owner/repo(.git)`,
  `ssh://git@github.com/owner/repo(.git)` (trailing slashes
  tolerated). Returns nil for any other host.

### 1.8 API contract (exact — tools are written against this)

```swift
public struct GitHubClient: Sendable {
    public init(session: URLSession = .shared, tokenProvider: @escaping @Sendable () -> String? = { nil })
    public static let baseURL: URL // https://api.github.com
    public private(set) var lastRateLimit: GitHubRateLimit?
    public func rateLimit() async throws -> GitHubRateLimit
    public func getAuthenticatedUser() async throws -> GitHubUser
    public func getRepository(owner: String, repo: String) async throws -> GitHubRepository
    public func listBranches(owner: String, repo: String, perPage: Int = 30) async throws -> [GitHubBranch]
    public func listCommits(owner: String, repo: String, branch: String = "main", perPage: Int = 20) async throws -> [GitHubCommit]
    public func getFileContent(owner: String, repo: String, path: String, ref: String? = nil) async throws -> GitHubFileContent
    public func getFileText(owner: String, repo: String, path: String, ref: String? = nil) async throws -> String
    public func getRepoTree(owner: String, repo: String, ref: String = "main", recursive: Bool = true) async throws -> [GitHubTreeEntry]
    public func listIssues(owner: String, repo: String, state: String = "open", perPage: Int = 30, page: Int = 1) async throws -> [GitHubIssue]
    public func getIssue(owner: String, repo: String, number: Int) async throws -> GitHubIssue
    public func createIssue(owner: String, repo: String, title: String, body: String?, labels: [String] = []) async throws -> GitHubIssue
    public func updateIssue(owner: String, repo: String, number: Int, title: String?, body: String?, state: String?) async throws -> GitHubIssue
    public func searchIssues(query: String, perPage: Int = 30, page: Int = 1) async throws -> GitHubSearchResult<GitHubIssue>
    public func getPullRequest(owner: String, repo: String, number: Int) async throws -> GitHubPullRequest
    public func listPullRequests(owner: String, repo: String, state: String = "open", perPage: Int = 30) async throws -> [GitHubPullRequest]
    public func createPullRequest(owner: String, repo: String, title: String, body: String?, head: String, base: String, draft: Bool = false) async throws -> GitHubPullRequest
    public func listPullRequestFiles(owner: String, repo: String, number: Int) async throws -> [GitHubPullRequestFile]
    public func listPullRequestReviews(owner: String, repo: String, number: Int) async throws -> [GitHubReview]
    public func searchCode(query: String, perPage: Int = 30) async throws -> GitHubSearchResult<GitHubCodeItem>
}

public enum GitHubError: Error, LocalizedError, Equatable {
    case missingToken
    case unauthorized
    case forbidden(message: String, rateLimited: Bool, resetAt: Date?)
    case notFound
    case unprocessable(message: String)
    case http(status: Int, message: String)
    case decoding
    case network
    case invalidRepo(String)
}

public enum GitHubRepoReference: Sendable {
    public static func parse(_ string: String) -> (owner: String, repo: String)?
    public static func parseRemoteURL(_ string: String) -> (owner: String, repo: String)?
}
```

Package wiring: `YcodeGitHub` library product + target, plus
`YcodeGitHubTests`; `YcodeMCP` and `YcodeUI` (the settings pane
imports it) depend on `YcodeGitHub`.

## Part 2 — The GitHub tools, wired to the client

Host helpers live in `ycode/Sources/YcodeMCP/YcodeGitHubHost.swift`
(135 lines): `gitHubClient()` (token provider = `secretStore.string(for: .githubToken)`),
`resolveGitHubRepo` (explicit `repository` argument → workspace git
remote origin → a clear error naming the missing repository),
`requireGitHubToken` (before the approval gate), and `gitHubToolError`
(Legacy's `makeToolError` message shape: the tool name, then the
human-readable detail, with `GitHubError.forbidden` mapped to
`"GitHub rate limit exceeded…"` when rate-limited).

The seven Agentic GitHub tools keep their Legacy IDs, schemas, and
descriptions, and the canned stubs they returned in Wave 8 are
replaced by real results. `read_issues` already had `repository`
required; the other six gain an **optional** `repository` parameter
— a Wave 10 addition, not a Legacy port. Without it the workspace
repo is used (same rule as `git_pr_summary`). The repo may be
`owner/repo`, a `github.com` URL, or an `owner/repo` string in the
`repository` field; `parseRemoteURL` covers `https://`,
`git@github.com:` and `ssh://git@github.com` forms. Private repos need
the token; public reads work without one at the lower rate limit.

### 2.1 `create_pull_request` — Create Pull Request

`POST /repos/{owner}/{repo}/pulls`. `title`, `body`, `head`, `base`
come from the arguments; the repository comes from `repository` or
the workspace remote. Requires a token. Registered `writes: true`
with `annotations: external`. Approval gate: `MCPChange(relativePath:
".", kind: .file, summary: "Create a pull request in <owner/repo>:
<title>")`, checked before the API call. Failure message:
`"<tool>: <detail>"` (`GitHubError` mapped through `gitHubToolError`).
Success: `PR #<number> created: <title> (<html_url>)`. Data keys:
`number`, `url`, `title`, `state`, `draft`.

### 2.2 `review_pull_request` — Review Pull Request

Read-only summary of a PR's review state: `GET
/repos/{owner}/{repo}/pulls/{number}` (title, state, head/base,
author, draft, merged, URL) + `GET .../pulls/{number}/reviews`
(latest review per reviewer: state + author, newest first).
`repository` optional; `prNumber` required; no token required for a
public repo. Legacy has no `body`/`event` parameter in its schema,
so there is no submit-a-review path — no parameter was invented.
Failure message: `"<tool>: <detail>"`. Success: `PR #<number>:
<title> — <state> (<head> → <base>) by <author>. Reviews: <count>
(<latest>): <reviewer> <state>, …` — or `No reviews yet.` when the
review list is empty. Data keys: `number`, `title`, `state`,
`headBranch`, `baseBranch`, `author`, `draft`, `merged`, `url`,
`reviewCount`, `reviews` (comma-joined `"<author> <state>"`).

### 2.3 `read_pull_request` — Read Pull Request

`GET /repos/{owner}/{repo}/pulls/{number}` plus `GET
.../pulls/{number}/files`. `repository` optional; `prNumber`
required; no token required for a public repo. Success:
`PR #<number>: <title> — <state> (<head> → <base>) by <author>.
<n> file(s) changed: <filename> (+<additions>/−<deletions>), …` —
the file list is capped at 30 entries (Legacy capped at 50;
matching the tool's own 30-result listing shape here). Data keys:
`number`, `title`, `state`, `headBranch`, `baseBranch`, `author`,
`draft`, `merged`, `url`, `fileCount`, `files` (comma-joined
`"<filename> (+a/-d)"`).

### 2.4 `read_issues` — Read Issues

`GET /repos/{owner}/{repo}/issues?state=open&per_page=30&page=1`.
`repository` required (as in Legacy). Returns open issues, PRs
excluded (`isPullRequest`). No token required for a public repo.
Success: `Found <n> open issue(s) in <owner/repo>:` followed by
`#<number>: <title> (<state>) by <author>` per issue, or
`No open issues in <owner/repo>.` when empty. Data keys: `issues`
(the lines above joined), `count`, `repository`.

### 2.5 `create_issue` — Create Issue

`POST /repos/{owner}/{repo}/issues` with `title`, `body`, and no
labels. `repository` optional; `title` required; `body` optional
and defaults to `""` (Legacy's handler does the same). Requires a
token. Registered `writes: true` with `annotations: external`.
Approval gate: `MCPChange(relativePath: ".", kind: .file, summary:
"Create an issue in <owner/repo>: <title>")`, before the API call.
Failure message: `"<tool>: <detail>"`. Success:
`Issue #<number> created: <title> (<html_url>)`. Data keys: `number`,
`url`, `title`, `state`.

### 2.6 `update_issue` — Update Issue

`PATCH /repos/{owner}/{repo}/issues/{number}`. `issueNumber`
required; `title` and `body` optional. When neither is supplied,
the tool fails with
`"update_issue: no fields to update — pass title and/or body"`.
`repository` optional. Requires a token. Registered `writes: true`
with `annotations: external`. Approval gate: `MCPChange(relativePath:
".", kind: .file, summary: "Update issue #<number> in
<owner/repo>")`, before the API call. Success:
`Issue #<number> updated: <title> (<html_url>)`. Data keys:
`number`, `url`, `title`, `state`.

### 2.7 `search_issues` — Search Issues

`GET /search/issues?q=<query>&per_page=30&page=1`. `query`
required; `repository` optional and, when supplied, appends
`repo:<owner>/<repo>` to the query (Legacy's schema has no
`repository` argument; this is a Wave 10 addition, not a Legacy
port). No token required for a public search. Success:
`Found <total> issue(s) matching '<query>':` followed by
`<owner/repo> #<number>: <title> (<state>)` per result, or
`No issues found matching '<query>'.` when empty. Data keys:
`results` (the lines above joined), `totalCount`.

### 2.8 `github_repo` — GitHub Repository Inspector (Assist)

All seven operations now run against the live GitHub API through
`YcodeGitHub`; the Wave 3 honest failure is gone. The tool keeps
its Legacy ID, title, description, and schema (Assist catalogue
§82), and the same repository resolution as the Agentic tools
(`owner`+`repo`, `url`, or the workspace git remote origin).

| Operation | Behaviour |
|---|---|
| `repository_info` | `GET /repos/{owner}/{repo}` — `name`, `fullName`, `description`, `stars`, `forks`, `language`, `isPrivate`, `url`, `defaultBranch`, `createdAt`, `updatedAt`, `pushedAt`; summary: `Repository <owner/repo> (<name>): <description> — <stars> stars, <forks> forks, <language>, default branch <branch>.` |
| `list_files` | `GET /repos/{owner}/{repo}/git/trees/{ref}?recursive=1`, paths joined with `\n`; `includeContent` fetches each file's content through the same client, aggregate-capped at `maxBytes` |
| `get_directory` | `GET /repos/{owner}/{repo}/contents/{path}?ref=`, entries listed one per line as `<name> (<type>)`; `includeContent` fetches file entries, aggregate-capped at `maxBytes` |
| `get_file` | `GET /repos/{owner}/{repo}/contents/{path}?ref=`, base64-decoded; the content is capped at `maxBytes` (not Legacy's 60,000 characters) |
| `get_tree` | `GET /repos/{owner}/{repo}/git/trees/{ref}?recursive=1` — `"<path> (<type>)"` per entry; `maxResults` default 5000; the API's `truncated` flag is not surfaced |
| `search_code` | `GET /search/code?q=<query> repo:<owner>/<repo>` — **server-side** Code Search API, not Legacy's client-side search over fetched files; result lines `<repo> <path>` |
| `fetch_repository` | `getRepoTree` + `getFileContent` for each file (skipped by extension allowlist); total content capped at `maxBytes` (default 262144, hard cap 2097152); files are fetched **sequentially** (no batching) |

Every operation's failure is `"<tool>: <detail>"` with
`GitHubError` mapped through `gitHubToolError`. Rate limiting is
reported with the reset time from `GitHubRateLimit`, never retried.
An unknown operation fails with
`"github_repo: unknown operation '<op>'"`.

### 2.9 Deviations from Legacy (recorded, not hidden)

- Legacy's seven Agentic GitHub tools were canned stubs with no
  network at all and (except `read_issues`) no repository parameter:
  replacing them with real API results is the Wave 10 point.
- `create_pull_request` gains `repository` (Legacy had no repo
  parameter at all); `review_pull_request` is a read-only summary —
  no submit path invented.
- `github_repo` code search is the server-side Code Search API, not
  Legacy's client-side search over fetched files. `get_file` caps at
  `maxBytes`, not Legacy's 60,000 characters. The tree-truncation
  flag is dropped (not surfaced). `repository_info` drops Legacy's
  open-issues count, license, and size lines (not in
  `GitHubRepository`). `fetch_repository` fetches files sequentially
  (no batching).
- `update_issue` with no field to change fails instead of sending an
  empty PATCH.

## Part 3 — Remote git

### 3.1 The three Agentic tools

`git_pull`, `git_push`, and `git_clone` are now real. They keep their
Legacy IDs, schemas, and descriptions, run through the existing git
runner (`YcodeTools+Git.swift`, argument vector, never a shell, the
same non-interactive environment as the local tools), and are
approval-gated. All three are now registered `writes: true` with
`annotations: safeMutation` (a remote write is still a safe
mutation in the Wave 2 taxonomy — a client-side destructive
classification was never applied to these).

- `git_pull` — `git pull` in `repositoryPath` (default `.`). Gate:
  `MCPChange(relativePath: ".", kind: .file, summary: "Pull from the
  remote into <repositoryPath>")`. Success: `Successfully pulled
  changes` (Legacy's message). Failure: `git_pull: git pull failed:
  <stderr>`.
- `git_push` — `git push` in `repositoryPath` (default `.`). Gate:
  `MCPChange(relativePath: ".", kind: .file, summary: "Push
  <repositoryPath> to the remote")`. Success: `Push successful`
  (Legacy's message). Failure: `git_push: git push failed: <stderr>`.
- `git_clone` — `git clone <remoteURL> <destinationPath>` (no
  working directory), with the remote URL checked by the §3.3 policy
  first. Gate: `MCPChange(relativePath: "<destinationPath>", kind:
  .directory, summary: "Clone <remoteURL> to <destinationPath>")`.
  Success: `Successfully cloned <remoteURL> to <destinationPath>`
  (Legacy's message). Failure: `git_clone: git clone failed:
  <stderr>`.

The tools need a real remote configured; there is no local-path
clone workaround. A clone target that already exists fails with
git's own error.

### 3.2 `version_control_operator` remote sub-ops

The Wave 3 rejection is replaced by real sub-ops. These are a Ycode
addition, not a Legacy port — Legacy implements no remote sub-ops
and its schema accepts only `status, commit, branch, rollback,
diff`. The `action` enum gains `push`, `pull`, `fetch`, `clone`,
plus the optional parameters `remote`, `url`, and `destination`.
Remote sub-ops are approval-gated with `MCPChange(relativePath:
".", kind: .file, summary: "git <action> on <cwd>")` before git
runs; read-only `fetch` still requires approval because the tool
is registered `writes: true` (the Wave 2 dry-run precedent). The
`action` description now reads: "The git action to perform: status,
commit, branch, rollback, diff, push, pull, fetch, or clone. Unknown
actions are rejected."

| Action | Runs | Parameters |
|---|---|---|
| `push` | `git push` | `remote` (optional; default configured upstream) |
| `pull` | `git pull` | `remote` (optional) |
| `fetch` | `git fetch` | `remote` (optional) |
| `clone` | `git clone <url> <destination>` | `url` (required), `destination` (required) |

Unknown actions still fail with `Unknown git action '<action>':
expected status, commit, branch, rollback, diff, push, pull, fetch,
or clone.`

### 3.3 Remote-URL policy

A remote URL is accepted only when it is `https://`, an SCP-like
`git@host:path` SSH form, or a local path inside the workspace. It
is rejected when it uses another scheme, embeds credentials, or
starts with `-` (the flag-injection guard). `git pull` and `git push`
operate on the remote already configured in the repo; only
`git_clone` (and the `clone` sub-op) takes a URL.

### 3.4 Credential seeding for github.com HTTPS

When a PAT is stored (`SecretAccount.githubToken`), `git_pull`,
`git_push`, `git_clone`, and the `clone` sub-op seed it for github.com
HTTPS remotes through `git credential approve` fed on stdin only.
The token is never placed in argv, the URL, or any log. The
implementation uses Foundation `Process` directly (`Subprocess.run`
cannot feed stdin). The secret store is read in the tool handler,
not cached.

The test seam is `agenticGitTestSecretStore` (settable from tests,
nil in production), matching the existing `agenticGitTestHost`
pattern in `YcodeTools+AgenticGit.swift`.

### 3.5 What is NOT in this wave

- No hosted-git provider API beyond GitHub (GitLab, Bitbucket).
- No `git credential` UI beyond the Settings token field.
- No SSH-agent management: SSH remotes rely on the user's existing
  agent/config.
- No `fetch_repository` batching and no `truncated`-flag surfacing
  (recorded in §2.9).

## Evidence

This spec is a port of Dylan's own Legacy SwiftCode code (authorised
for direct porting under MIT), not dirty-room analysis of Apple
software — no reference Xcode copy, Ghidra output, IPSW, or
`research/dirty/` material was used for any claim below. Evidence
levels follow the AGENTS.md ladder where it applies; Legacy source
and public GitHub API documentation are the operative sources here.

| Claim | Evidence |
|---|---|
| `GitHubAPIBackend` design (URLSession, `api.github.com`, `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28`, Bearer token, snake-case + ISO 8601 decoding, rate-limit parsing of `X-RateLimit-*` + `Retry-After`) | Legacy `SwiftCode/Backend/Assist/RemoteService/Client/GitHubAPI.swift`, `GitHubAuth.swift`, `GitHubModels.swift`, `AssistRemoteFetchSupport.swift` (read-only source inspection) |
| Token in Keychain account `"github-pat"`; credential seeding via `git credential approve` on stdin | Legacy `SwiftCode/Backend/Assist/RemoteService/Client/GitCredentialProvider.swift`, `GitHubAuth.swift` |
| The seven Agentic GitHub tools are canned stubs with no network and (except `read_issues`) no repository parameter | Legacy `SwiftCode/Backend/Assist/Tools/Agentic/Registry/.../CreatePullRequest.swift`, `ReviewPullRequest.swift`, `ReadPullRequest.swift`, `ReadIssues.swift`, `CreateIssue.swift`, `UpdateIssue.swift`, `SearchIssues.swift` |
| `github_repo` operations (`repository_info`, `list_files`, `get_file`, `get_directory`, `get_tree`, `search_code`, `fetch_repository`), client-side code search, 60,000-character file cap, 60 req/hour unauthenticated limit | Legacy `SwiftCode/Backend/Assist/Tools/AssistGitHubRepoTool.swift` |
| `git_pull` / `git_push` / `git_clone` are plain `/usr/bin/git` subprocesses; `version_control_operator` has no remote sub-ops in Legacy | Legacy `SwiftCode/Backend/Assist/Tools/Agentic/Registry/.../GitPullTool.swift`, `GitPushTool.swift`, `GitCloneTool.swift`; Assist `version_control_operator` implementation |
| GitHub REST endpoints, header names, error payload shape, rate-limit headers, Code Search API, `per_page` ≤ 100 | GitHub public REST API documentation (public docs, evidence level 1) |
| Destination conventions (approval gate, `MCPChange`, argument-vector subprocesses, `SecretAccount`, settings-pane style, test seams) | Destination specs `assist-approval-model.md`, `assist-tool-catalogue.md` §§71, 82, 84, `agentic-tool-catalogue.md` §§43–45, 65–71, and the Wave 9 provider specs |

## Status

- **Wave 10, 2026-11-06.** Client, tool wiring, remote git, specs,
  tests, and ledger updates landed uncommitted on destination main
  @ `640bc1dc`. Tool count unchanged at 433 (no new registrations).
- **Pending:** `swift build` / `swift test` and live runs against
  `api.github.com` on Dylan's Mac (no Swift toolchain in this
  environment). Dylan must supply a GitHub personal access token in
  Settings ▸ Coding Assistant ▸ GitHub to enable the authenticated
  tools.
- **Follow-ups recorded:** `getRepoTree` discards the API `truncated`
  flag; `GitHubRepository` has no open-issues count / license / size;
  `lastRateLimit` is not surfaced in the UI (fresh client per call);
  `fetch_repository` fetches sequentially; Slice C's clone test
  relies on `.invalid` never resolving (could hang on SSH if a
  sandbox DNS ever resolved it).
