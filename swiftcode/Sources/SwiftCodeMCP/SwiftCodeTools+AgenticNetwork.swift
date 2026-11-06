import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwiftCodeAssistant
import SwiftCodeGitHub
import SwiftCodeIDECore

/// The ported Legacy Agentic network / packages / GitHub tool family
/// (Wave 8, slice D).
///
/// Behaviour source: Legacy `SwiftCode/Tools/Agentic/FetchURL.swift`,
/// `DownloadFile.swift`, `UploadFile.swift`, `HTTPRequest.swift`,
/// `WebSearch.swift`, `DocumentationSearch.swift`,
/// `APIReferenceSearch.swift`, `PackageSearch.swift`,
/// `DependencyAudit.swift`, `InstallDependencies.swift`,
/// `UpdateDependencies.swift`, `RemoveDependencies.swift`,
/// `CreatePullRequest.swift`, `ReviewPullRequest.swift`,
/// `ReadPullRequest.swift`, `ReadIssues.swift`, `CreateIssue.swift`,
/// `UpdateIssue.swift`, `SearchIssues.swift` (Dylan's own code, ported
/// under MIT). The 19 IDs below were verified live from each file's
/// `static let identifier`.
///
/// Classification against the already-ported MCP tools (checked live:
/// none of the 19 IDs is a registered tool or an entry in
/// `MCPServer.toolAliases`):
///
/// * PORTED (7): `fetch_url`, `download_file`, `upload_file`,
///   `http_request`, `install_dependencies`, `update_dependencies`,
///   `remove_dependencies`. All seven are genuinely distinct from the
///   ported tools: `fetch_url` returns raw text where
///   `external_resource_gateway` requires a JSON body;
///   `http_request` allows any method/headers/body where the gateway
///   is GET-only and JSON-only; `download_file` / `upload_file` have
///   no ported counterpart at all. `install_dependencies` /
///   `update_dependencies` are NOT aliases of `swift_package_manager`
///   / `package_dependency_update`: an alias passes arguments
///   unchanged and `Schema.object` rejects unknown keys, but the
///   Agentic tools require `projectPath` (which neither target has)
///   while `swift_package_manager` additionally requires `action`
///   (which the Agentic tools do not send), and
///   `package_dependency_update` only ever runs in the workspace
///   root. `dependency_audit` is NOT a duplicate of
///   `package_dependency_audit`: the ported tool audits pins, the
///   Agentic tool claims a vulnerability audit.
/// * WIRED (gap-closure): `web_search` (DuckDuckGo Instant Answer
///   API), `documentation_search` / `api_reference_search` (Apple
///   DocC JSON search, symbols only for API search), `package_search`
///   (Swift Package Index search page + GitHub public search
///   fallback). See `SwiftCodeTools+SearchWeb.swift`.
/// * HONESTLY-FAILING (1): `dependency_audit` is wired to a real OSV
///   audit (see below); the remaining honest-fail entry is none.
///   Each formerly-failing tool validates its inputs first, then
///   fails naming the exact missing prerequisite when its backend
///   is unavailable. No behaviour, no endpoint, and no result is
///   invented for any of them.
/// * WIRED (Wave 10): the seven GitHub tools, via the shared
///   `GitHubClient` (`SwiftCodeGitHubHost.swift`). See the Wave 10
///   deviation note below.
/// * ALREADY-SERVED: none. DUPLICATE (aliasable): none.
///
/// Deliberate deviations from Legacy, recorded here:
///
/// * Workspace confinement. Legacy's file arguments (`projectPath`,
///   `destinationPath`, `path`) were absolute filesystem paths
///   subject only to Legacy's own permission checks. The port
///   resolves them inside the open workspace (`resolveFileReadingPath`
///   / `resolveFileWritingPath`): relative paths are workspace
///   relative, absolute paths must stay under the workspace root,
///   and `..` is refused. `install_dependencies` /
///   `update_dependencies` / `remove_dependencies` therefore only
///   operate on packages inside the workspace.
/// * Approval gate. Legacy's Agentic tools run with no approval
///   (its Autopilot mode bypasses approval entirely). The port puts
///   every network fetch that writes, every upload, every mutating
///   HTTP method, every `swift package` run, and the manifest edit
///   behind the SwiftCode approval gate (`approveFileWritingChange` /
///   `terminalApproveChange` / `commit()`), like Wave 5's
///   `dependency_resolution_engine`. Plain `fetch_url` GETs and
///   safe-method `http_request` calls need no approval, like
///   `external_resource_gateway`.
/// * HTTPS only. Legacy passed any URL string to `URLSession`. The
///   port rejects non-HTTPS URLs (and URLs without a host) for all
///   four network tools, the `external_resource_gateway` rule:
///   `http://` would let an agent downgrade a fetch, and `file://`
///   would read local files behind a network label.
/// * Response caps. Legacy buffered responses unboundedly. The port
///   caps response bodies (2 MB for text fetches, 10 MB for file
///   downloads and uploads) and fails past the cap instead of
///   buffering unboundedly, the `EnginesHTTP` rule.
/// * `web_search` is NOT wired to Legacy's endpoint. Legacy called
///   `https://ddg-api.herokuapp.com/search?q=…`, an unofficial
///   DuckDuckGo proxy that is not a supported search backend. The
///   port sends no request to it and invents no results.
/// * `documentation_search`, `api_reference_search`, and
///   `package_search` are NOT wired to a search engine. Legacy's
///   implementations were stubs that returned a canned string
///   ("Documentation for: …" / "API Reference for: …" / "Package
///   search results for: …") without searching anything. Returning
///   those strings would be fake behaviour, so the port fails
///   honestly instead. `fetch_documentation` fetches a known Apple
///   documentation page; it does not search, so it cannot serve
///   these tools.
/// * `dependency_audit` is NOT wired to a vulnerability source.
///   Legacy returned "No vulnerabilities found …" without checking
///   anything — a clean bill of health invented out of nothing.
///   The port fails honestly instead; `package_dependency_audit`
///   remains the tool for pin auditing.
/// * `remove_dependencies` actually removes. Legacy returned
///   "Package … removed from Package.swift at …" without editing
///   anything. The port performs the removal for real: it deletes
///   the matching `.package(...)` entry from the package-level
///   `dependencies:` array and any `.product(name: …)` / bare-string
///   references to it in target `dependencies:` arrays, through
///   the approval gate. Matching is by explicit `name:`, by the
///   last path component of `url:` (without a trailing `.git`), or
///   by the URL itself. A bare string in a target's dependencies
///   is treated as a product reference; the pathological case of a
///   same-package target sharing the package's name would also be
///   removed, which the spec records.
/// * `http_request` method allow-list. Legacy passed any method
///   string through. The port accepts only GET, HEAD, OPTIONS,
///   POST, PUT, PATCH, DELETE.
/// * The seven GitHub tools are wired to the real GitHub API
///   (Wave 10), the Wave 3 `github_repo` precedent resolved: the
///   host now has a GitHub API client (`GitHubClient`, with the
///   token read fresh from `SecretAccount.githubToken`) and a
///   credential flow. The four reads need no approval and no
///   token for public repositories; the three writes
///   (`create_pull_request`, `create_issue`, `update_issue`) fail
///   fast with the client's `missingToken` error when no token is
///   stored, then go through the Wave 2 approval gate
///   (`gitApproveChange`) before calling the client, and are
///   registered `writes: true` so the gate can ever pass (the
///   server wires `approve` to always-false for `writes: false`
///   tools) and so a read-only server refuses them. Legacy's
///   canned return strings ("PR created: …" / "Issue created: …"
///   with no API call behind them) are stubs, not behaviour: the
///   real API results replace them. Each tool gains an optional
///   `repository` argument ("owner/repo", defaulting to the
///   workspace's git remote origin) except `read_issues`, whose
///   `repository` was already required; no ID, description, or
///   required parameter changed. `review_pull_request` is a
///   READ-ONLY review summary: Legacy's schema has no body/event
///   parameter, so posting a review is not expressible and no
///   post path is invented. `update_issue` sends only the
///   supplied fields (`title`/`body`; `state` is not in Legacy's
///   schema and is never added). `search_issues` prepends
///   `repo:owner/repo` to the query when a repository resolves,
///   and otherwise searches unscoped, as Legacy's
///   repository-less schema did.
/// * Subprocess shape. `install_dependencies` /
///   `update_dependencies` run `/usr/bin/swift package resolve` /
///   `update` through `terminalRunFixed` (argument vector, never a
///   shell), the `spmDocsSwiftPackage` shape, with a 300 s timeout.
///   Legacy ran the same commands through its `ProcessRunnerTool`.
/// * No `workspace` argument existed in Legacy; the port adds the
///   optional SwiftCode `workspace` argument to every tool, the same
///   convention every other ported family follows.
extension SwiftCodeMCPHost {
    var agenticNetworkTools: [MCPTool] {
        let external = MCPToolAnnotations(readOnly: false, idempotent: false, openWorld: true)
        let externalRead = MCPToolAnnotations(readOnly: true, idempotent: true, openWorld: true)
        let execution = MCPToolAnnotations(readOnly: false, idempotent: false)
        let safeMutation = MCPToolAnnotations(readOnly: false, idempotent: true)
        return [
            tool("fetch_url", "Fetch URL",
                 "Fetches the content of a URL.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "url": Schema.string("Fully qualified HTTPS URL to fetch.")],
                                      required: ["url"]),
                 output: Schema.output(["status_code": Schema.int, "content": Schema.str]),
                 annotations: externalRead) { h, call in
                try await h.agenticNetworkFetchURL(call)
            },
            tool("download_file", "Download File",
                 "Downloads a file from a URL.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "url": Schema.string("Fully qualified HTTPS URL to download from."),
                                       "destinationPath": Schema.string("Workspace-relative path to write the downloaded file to.")],
                                      required: ["url", "destinationPath"]),
                 output: Schema.output(["url": Schema.str, "destinationPath": Schema.str, "bytes": Schema.int]),
                 annotations: external, writes: true) { h, call in
                try await h.agenticNetworkDownloadFile(call)
            },
            tool("upload_file", "Upload File",
                 "Uploads a file to a URL.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of the file to upload."),
                                       "url": Schema.string("Fully qualified HTTPS URL to upload to (HTTP POST).")],
                                      required: ["path", "url"]),
                 output: Schema.output(["status_code": Schema.int, "content": Schema.str]),
                 annotations: external, writes: true) { h, call in
                try await h.agenticNetworkUploadFile(call)
            },
            tool("http_request", "HTTP Request",
                 "Performs an HTTP request.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "url": Schema.string("Fully qualified HTTPS URL to request."),
                                       "method": Schema.string("HTTP method: GET, HEAD, OPTIONS, POST, PUT, PATCH, or DELETE."),
                                       "headers": Schema.anyObject,
                                       "body": Schema.string("Optional request body text.")],
                                      required: ["url", "method"]),
                 output: Schema.output(["status_code": Schema.int, "content": Schema.str]),
                 annotations: external, writes: true) { h, call in
                try await h.agenticNetworkHTTPRequest(call)
            },
            tool("web_search", "Web Search",
                 "Performs a web search.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "query": Schema.string("Search query."),
                                       "limit": Schema.integer("Maximum results to return (default: 8, max: 20).", minimum: 1)],
                                      required: ["query"]),
                 output: Schema.output(["abstract": Schema.str, "abstractURL": Schema.str, "answer": Schema.str,
                                        "results": Schema.str, "resultCount": Schema.int]),
                 annotations: externalRead) { h, call in
                try await h.searchWeb(call)
            },
            tool("documentation_search", "Documentation Search",
                 "Searches for documentation.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "query": Schema.string("Documentation topic to search for."),
                                       "framework": Schema.string("Optional framework to search within (e.g. 'SwiftUI')."),
                                       "limit": Schema.integer("Maximum results to return (default: 5, max: 10).", minimum: 1)],
                                      required: ["query"]),
                 output: Schema.output(["results": Schema.str, "count": Schema.int]),
                 annotations: externalRead) { h, call in
                try await h.searchDocumentation(call)
            },
            tool("api_reference_search", "API Reference Search",
                 "Searches for API references.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "query": Schema.string("API symbol or framework to search for."),
                                       "framework": Schema.string("Optional framework to search within (e.g. 'SwiftUI')."),
                                       "limit": Schema.integer("Maximum results to return (default: 5, max: 10).", minimum: 1)],
                                      required: ["query"]),
                 output: Schema.output(["results": Schema.str, "count": Schema.int]),
                 annotations: externalRead) { h, call in
                try await h.searchAPIReference(call)
            },
            tool("package_search", "Package Search",
                 "Searches for packages.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "query": Schema.string("Package name or keyword to search for."),
                                       "limit": Schema.integer("Maximum results to return (default: 10, max: 25).", minimum: 1)],
                                      required: ["query"]),
                 output: Schema.output(["results": Schema.str, "count": Schema.int, "source": Schema.str]),
                 annotations: externalRead) { h, call in
                try await h.searchPackage(call)
            },
            tool("dependency_audit", "Dependency Audit",
                 "Audits project dependencies for vulnerabilities.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "projectPath": Schema.string("Workspace-relative path of the project directory to audit.")],
                                      required: ["projectPath"])) { h, call in
                try await h.agenticNetworkDependencyAudit(call)
            },
            tool("install_dependencies", "Install Dependencies",
                 "Installs project dependencies.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "projectPath": Schema.string("Workspace-relative path of the project directory (the one containing Package.swift).")],
                                      required: ["projectPath"]),
                 output: Schema.output(["exitCode": Schema.int, "output": Schema.str]),
                 annotations: execution, writes: true) { h, call in
                try await h.agenticNetworkInstallDependencies(call)
            },
            tool("update_dependencies", "Update Dependencies",
                 "Updates project dependencies.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "projectPath": Schema.string("Workspace-relative path of the project directory (the one containing Package.swift).")],
                                      required: ["projectPath"]),
                 output: Schema.output(["exitCode": Schema.int, "output": Schema.str]),
                 annotations: execution, writes: true) { h, call in
                try await h.agenticNetworkUpdateDependencies(call)
            },
            tool("remove_dependencies", "Remove Dependencies",
                 "Removes a package dependency from the project.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "projectPath": Schema.string("Workspace-relative path of the project directory (the one containing Package.swift)."),
                                       "packageName": Schema.string("Name of the package dependency to remove (its declared name, or the last path component of its URL).")],
                                      required: ["projectPath", "packageName"]),
                 output: Schema.output(["packageName": Schema.str, "projectPath": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.agenticNetworkRemoveDependencies(call)
            },
            tool("create_pull_request", "Create Pull Request",
                 "Creates a pull request.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "repository": Schema.string("owner/repo; defaults to the workspace's git remote origin."),
                                       "title": Schema.string("Pull request title."),
                                       "body": Schema.string("Pull request body."),
                                       "head": Schema.string("Head branch of the pull request."),
                                       "base": Schema.string("Base branch of the pull request.")],
                                      required: ["title", "body", "head", "base"]),
                 annotations: external, writes: true) { h, call in
                try await h.agenticNetworkCreatePullRequest(call)
            },
            tool("review_pull_request", "Review Pull Request",
                 "Reviews a pull request.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "repository": Schema.string("owner/repo; defaults to the workspace's git remote origin."),
                                       "prNumber": Schema.integer("Pull request number to review.")],
                                      required: ["prNumber"])) { h, call in
                try await h.agenticNetworkReviewPullRequest(call)
            },
            tool("read_pull_request", "Read Pull Request",
                 "Reads content of a pull request.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "repository": Schema.string("owner/repo; defaults to the workspace's git remote origin."),
                                       "prNumber": Schema.integer("Pull request number to read.")],
                                      required: ["prNumber"])) { h, call in
                try await h.agenticNetworkReadPullRequest(call)
            },
            tool("read_issues", "Read Issues",
                 "Reads issues for a repository.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "repository": Schema.string("Repository to read issues for, e.g. 'owner/repo'.")],
                                      required: ["repository"])) { h, call in
                try await h.agenticNetworkReadIssues(call)
            },
            tool("create_issue", "Create Issue",
                 "Creates an issue.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "repository": Schema.string("owner/repo; defaults to the workspace's git remote origin."),
                                       "title": Schema.string("Issue title."),
                                       "body": Schema.string("Issue body.")],
                                      required: ["title", "body"]),
                 annotations: external, writes: true) { h, call in
                try await h.agenticNetworkCreateIssue(call)
            },
            tool("update_issue", "Update Issue",
                 "Updates an issue.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "repository": Schema.string("owner/repo; defaults to the workspace's git remote origin."),
                                       "issueNumber": Schema.integer("Issue number to update."),
                                       "title": Schema.string("New issue title (optional)."),
                                       "body": Schema.string("New issue body (optional).")],
                                      required: ["issueNumber"]),
                 annotations: external, writes: true) { h, call in
                try await h.agenticNetworkUpdateIssue(call)
            },
            tool("search_issues", "Search Issues",
                 "Searches for issues.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "repository": Schema.string("owner/repo; defaults to the workspace's git remote origin."),
                                       "query": Schema.string("Issue search query.")],
                                      required: ["query"])) { h, call in
                try await h.agenticNetworkSearchIssues(call)
            },
        ]
    }
}

extension SwiftCodeMCPHost {
    // MARK: - Shared network helpers

    /// Response-body cap for text fetches (fetch_url, http_request,
    /// upload responses): the `EnginesHTTP` rule, not Legacy (which
    /// buffered unboundedly).
    nonisolated static let agenticNetworkTextCap = 2_000_000

    /// Body cap for file downloads and uploads.
    nonisolated static let agenticNetworkFileCap = 10_000_000

    /// Legacy passed any URL string to `URLSession`. The port allows
    /// only HTTPS URLs with a host (the
    /// `external_resource_gateway` rule).
    nonisolated static func agenticNetworkHTTPSURL(_ raw: String) throws -> URL {
        guard let url = URL(string: raw), url.scheme?.lowercased() == "https", url.host != nil else {
            throw MCPToolError("Only HTTPS URLs with a host are allowed (got '\(raw)').")
        }
        return url
    }

    /// Sends `request` with `SwiftCodeAssistant.HTTP.send` (the codebase's
    /// proven one-shot request helper), failing on transport errors,
    /// on non-2xx statuses, and past `maxBytes` of body.
    func agenticNetworkSend(_ request: URLRequest, urlString: String, maxBytes: Int) async throws -> HTTP.Response {
        let response: HTTP.Response
        do {
            response = try await HTTP.send(request, timeout: 30)
        } catch {
            throw MCPToolError("Fetch failed: \(error.localizedDescription)")
        }
        guard (200...299).contains(response.status) else {
            throw MCPToolError("HTTP \(response.status) from \(urlString).")
        }
        guard response.body.count <= maxBytes else {
            throw MCPToolError("Response exceeded the \(maxBytes)-byte cap.")
        }
        return response
    }

    // MARK: - `fetch_url`

    func agenticNetworkFetchURL(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let urlString = call.string("url") else {
            throw MCPToolError("Missing url")
        }
        let url = try Self.agenticNetworkHTTPSURL(urlString)
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let response = try await agenticNetworkSend(request, urlString: urlString, maxBytes: Self.agenticNetworkTextCap)
        let text = String(decoding: response.body, as: UTF8.self)
        return .structured(["status_code": .int(response.status), "content": .string(text)],
                           summary: "Fetched \(urlString) (HTTP \(response.status), \(response.body.count) bytes).")
    }

    // MARK: - `download_file`

    func agenticNetworkDownloadFile(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let urlString = call.string("url") else {
            throw MCPToolError("Missing url")
        }
        guard let destinationRaw = call.string("destinationPath") else {
            throw MCPToolError("Missing url or destinationPath")
        }
        let url = try Self.agenticNetworkHTTPSURL(urlString)
        let s = try session(for: call)
        guard let destination = resolveFileWritingPath(destinationRaw, in: s) else {
            throw MCPToolError("destinationPath must be inside the workspace and must not contain '..'.")
        }
        let rel = relative(destination.path, in: s)
        // Approval gate before the network fetch and the write:
        // a download is an external fetch plus a workspace write.
        try await approveFileWritingChange(tool: call.name, path: destination, relativePath: rel, original: nil,
                                           summary: "Download \(urlString) to \(rel)", call: call)
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let response = try await agenticNetworkSend(request, urlString: urlString, maxBytes: Self.agenticNetworkFileCap)
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try response.body.write(to: destination, options: .atomic)
        } catch {
            throw MCPToolError("cannot write \(rel): \(error.localizedDescription)")
        }
        noteFileWritingChanged(destination, in: s)
        return .structured(["url": .string(urlString), "destinationPath": .string(rel), "bytes": .int(response.body.count)],
                           summary: "Downloaded \(urlString) to \(rel) (\(response.body.count) bytes)")
    }

    // MARK: - `upload_file`

    func agenticNetworkUploadFile(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let pathRaw = call.string("path") else {
            throw MCPToolError("Missing path or url")
        }
        guard let urlString = call.string("url") else {
            throw MCPToolError("Missing path or url")
        }
        let url = try Self.agenticNetworkHTTPSURL(urlString)
        let s = try session(for: call)
        let source: URL
        do {
            source = try resolveFileReadingPath(pathRaw, in: s)
        } catch {
            throw MCPToolError("path must be inside the workspace and must not contain '..'.")
        }
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw MCPToolError("File not found at '\(pathRaw)'.")
        }
        let rel = relative(source.path, in: s)
        // Approval gate before the file leaves the workspace: an
        // upload is an external side effect carrying workspace data.
        try await approveFileWritingChange(tool: call.name, path: source, relativePath: rel, original: nil,
                                           summary: "Upload \(rel) to \(urlString) (HTTP POST)", call: call)
        let data: Data
        do {
            data = try Data(contentsOf: source)
        } catch {
            throw MCPToolError("cannot read \(rel): \(error.localizedDescription)")
        }
        guard data.count <= Self.agenticNetworkFileCap else {
            throw MCPToolError("File exceeds the \(Self.agenticNetworkFileCap)-byte upload cap.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.timeoutInterval = 30
        let response = try await agenticNetworkSend(request, urlString: urlString, maxBytes: Self.agenticNetworkTextCap)
        let text = String(decoding: response.body, as: UTF8.self)
        return .structured(["status_code": .int(response.status), "content": .string(text)],
                           summary: "Uploaded \(rel) to \(urlString) (HTTP \(response.status)).")
    }

    // MARK: - `http_request`

    func agenticNetworkHTTPRequest(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let urlString = call.string("url") else {
            throw MCPToolError("Missing url or method")
        }
        guard let methodRaw = call.string("method") else {
            throw MCPToolError("Missing url or method")
        }
        let method = methodRaw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard ["GET", "HEAD", "OPTIONS", "POST", "PUT", "PATCH", "DELETE"].contains(method) else {
            throw MCPToolError("Unsupported HTTP method '\(methodRaw)'. Use GET, HEAD, OPTIONS, POST, PUT, PATCH, or DELETE.")
        }
        let url = try Self.agenticNetworkHTTPSURL(urlString)
        var headers: [String: String] = [:]
        if let rawHeaders = call.arguments["headers"]?.object {
            for (key, value) in rawHeaders {
                guard let stringValue = value.string else {
                    throw MCPToolError("Header '\(key)' must be a string.")
                }
                headers[key] = stringValue
            }
        }
        // Mutating methods go through the approval gate (and therefore
        // need an open workspace to approve against); safe methods are
        // plain reads like `external_resource_gateway`.
        if !["GET", "HEAD", "OPTIONS"].contains(method) {
            let s = try session(for: call)
            try await terminalApproveChange(tool: call.name,
                                            summary: "Send HTTP \(method) to \(urlString)",
                                            in: s, call: call)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (key, value) in headers { request.addValue(value, forHTTPHeaderField: key) }
        if let body = call.string("body") { request.httpBody = body.data(using: .utf8) }
        request.timeoutInterval = 30
        let response = try await agenticNetworkSend(request, urlString: urlString, maxBytes: Self.agenticNetworkTextCap)
        let text = String(decoding: response.body, as: UTF8.self)
        return .structured(["status_code": .int(response.status), "content": .string(text)],
                           summary: "HTTP \(method) \(urlString) → \(response.status).")
    }

    /// `dependency_audit`: a real OSV audit of the pinned SwiftPM
    /// packages in `Package.resolved` (see
    /// `SwiftCodeTools+DependencyAudit.swift`). Legacy returned "No
    /// vulnerabilities found …" without checking anything — a clean
    /// bill of health invented out of nothing. This port queries
    /// OSV instead and reports "no advisories" as exactly that,
    /// never as a guarantee of safety.
    func agenticNetworkDependencyAudit(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard call.string("projectPath") != nil else {
            throw MCPToolError("Missing projectPath")
        }
        return try await dependencyAudit(call)
    }

    // MARK: - `install_dependencies` / `update_dependencies`

    /// Runs one `swift package` subcommand in a workspace-confined
    /// project directory, the `spmDocsSwiftPackage` shape (argument
    /// vector, never a shell; 300 s timeout), behind the approval
    /// gate: resolving/updating fetches packages over the network
    /// and writes into the package cache and `.build`.
    func agenticNetworkRunSwiftPackage(_ call: MCPToolCall, subcommand: String) async throws -> MCPToolResult {
        guard let projectPath = call.string("projectPath") else {
            throw MCPToolError("Missing projectPath")
        }
        let s = try session(for: call)
        let dir: URL
        do {
            dir = try resolveFileReadingPath(projectPath, in: s)
        } catch {
            throw MCPToolError("projectPath must be inside the workspace and must not contain '..'.")
        }
        let manifestURL = dir.appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw MCPToolError("Package.swift not found at \(manifestURL.path)")
        }
        guard FileManager.default.fileExists(atPath: "/usr/bin/swift") else {
            throw MCPToolError("Swift not found at /usr/bin/swift.")
        }
        try await terminalApproveChange(tool: call.name,
                                        summary: "Run swift package \(subcommand) in \(projectPath)",
                                        in: s, call: call)
        guard let run = await Task.detached {
            Self.terminalRunFixed("/usr/bin/swift", ["package", subcommand], workingDirectory: dir, timeout: 300)
        }.value else {
            throw MCPToolError("Failed to execute swift package \(subcommand): could not start /usr/bin/swift.")
        }
        if run.timedOut {
            throw MCPToolError("swift package \(subcommand) timed out after 300 seconds.")
        }
        let output = run.stdout + run.stderr
        if run.exitCode == 0 {
            return .structured(["exitCode": .int(Int(run.exitCode)), "output": .string(output)],
                               summary: "swift package \(subcommand) succeeded in \(projectPath).")
        }
        throw MCPToolError("swift package \(subcommand) failed with exit code \(run.exitCode):\n\(output)")
    }

    func agenticNetworkInstallDependencies(_ call: MCPToolCall) async throws -> MCPToolResult {
        try await agenticNetworkRunSwiftPackage(call, subcommand: "resolve")
    }

    func agenticNetworkUpdateDependencies(_ call: MCPToolCall) async throws -> MCPToolResult {
        try await agenticNetworkRunSwiftPackage(call, subcommand: "update")
    }

    // MARK: - `remove_dependencies`

    func agenticNetworkRemoveDependencies(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let projectPath = call.string("projectPath") else {
            throw MCPToolError("Missing projectPath or packageName")
        }
        guard let packageName = call.string("packageName") else {
            throw MCPToolError("Missing projectPath or packageName")
        }
        let trimmedName = packageName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedName.contains(" "), !trimmedName.contains("/"), !trimmedName.contains("..") else {
            throw MCPToolError("Invalid packageName: must be a single package name without spaces, slashes, or '..'.")
        }
        let s = try session(for: call)
        let dir: URL
        do {
            dir = try resolveFileReadingPath(projectPath, in: s)
        } catch {
            throw MCPToolError("projectPath must be inside the workspace and must not contain '..'.")
        }
        let manifestURL = dir.appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw MCPToolError("Package.swift not found at \(manifestURL.path)")
        }
        let original: String
        do {
            original = try String(contentsOf: manifestURL, encoding: .utf8)
        } catch {
            throw MCPToolError("cannot read Package.swift at \(projectPath): \(error.localizedDescription)")
        }
        var content = original
        guard Self.agenticNetworkRemovePackage(named: trimmedName, from: &content) else {
            throw MCPToolError("Package '\(trimmedName)' not found in Package.swift at \(projectPath): no .package entry with that name or URL was found.")
        }
        let rel = relative(manifestURL.path, in: s)
        try await commit(MCPChange(tool: call.name, path: manifestURL.path, relativePath: rel, original: original,
                                   proposed: content, summary: "Remove package dependency '\(trimmedName)' from Package.swift"),
                         call: call, session: s)
        return .structured(["packageName": .string(trimmedName), "projectPath": .string(projectPath)],
                           summary: "Package \(trimmedName) removed from Package.swift at \(projectPath)")
    }

    // MARK: - GitHub tools (Wave 10: wired to the real GitHub API)

    /// Fetches a pull request with its changed files and its
    /// reviews: the shared read for `read_pull_request` and the
    /// read-only `review_pull_request` (both render from the same
    /// data). GitHub failures become the tool error the model sees
    /// (the client's own message); anything else propagates.
    func agenticNetworkFetchPullRequest(_ client: GitHubClient, owner: String, repo: String, number: Int) async throws
    -> (GitHubPullRequest, [GitHubPullRequestFile], [GitHubReview]) {
        do {
            let pr = try await client.getPullRequest(owner: owner, repo: repo, number: number)
            let files = try await client.listPullRequestFiles(owner: owner, repo: repo, number: number)
            let reviews = try await client.listPullRequestReviews(owner: owner, repo: repo, number: number)
            return (pr, files, reviews)
        } catch let error as GitHubError {
            throw Self.gitHubToolError(error)
        }
    }

    /// The shared pull-request summary lines: number, title, state,
    /// head → base, files changed with additions/deletions, and
    /// existing review states. `asReview` frames it as a review
    /// summary (see `agenticNetworkReviewPullRequest`).
    nonisolated static func agenticNetworkPullRequestLines(pr: GitHubPullRequest, files: [GitHubPullRequestFile],
                                                           reviews: [GitHubReview], asReview: Bool) -> [String] {
        let additions = files.reduce(0) { $0 + $1.additions }
        let deletions = files.reduce(0) { $0 + $1.deletions }
        var lines = [asReview ? "Review of pull request #\(pr.number): \(pr.title)" : "Pull request #\(pr.number): \(pr.title)",
                     "State: \(pr.state) — \(pr.headRef) → \(pr.baseRef)",
                     "URL: \(pr.htmlUrl)",
                     "",
                     "Files changed (\(files.count), +\(additions)/-\(deletions)):"]
        if files.isEmpty {
            lines.append("No files changed.")
        } else {
            for file in files {
                lines.append("- \(file.filename) (+\(file.additions)/-\(file.deletions))")
            }
        }
        lines.append("")
        if reviews.isEmpty {
            lines.append("No reviews yet.")
        } else {
            lines.append("Reviews (\(reviews.count)):")
            for review in reviews {
                lines.append("- \(review.userLogin): \(review.state)")
            }
        }
        if asReview {
            lines.append("")
            lines.append("This is a read-only review summary: review_pull_request has no body/event parameter, so no review was posted to GitHub.")
        }
        return lines
    }

    /// The shared pull-request structured result.
    nonisolated static func agenticNetworkPullRequestJSON(pr: GitHubPullRequest, files: [GitHubPullRequestFile],
                                                          reviews: [GitHubReview]) -> AnyJSON {
        ["number": .int(pr.number), "title": .string(pr.title), "state": .string(pr.state),
         "head": .string(pr.headRef), "base": .string(pr.baseRef), "htmlUrl": .string(pr.htmlUrl),
         "filesChanged": .int(files.count),
         "additions": .int(files.reduce(0) { $0 + $1.additions }),
         "deletions": .int(files.reduce(0) { $0 + $1.deletions }),
         "files": .array(files.map { ["filename": .string($0.filename), "additions": .int($0.additions),
                                      "deletions": .int($0.deletions)] }),
         "reviews": .array(reviews.map { ["user": .string($0.userLogin), "state": .string($0.state)] })]
    }

    /// One issue as a structured entry (shared by `read_issues` and
    /// `search_issues`).
    nonisolated static func agenticNetworkIssueJSON(_ issue: GitHubIssue) -> AnyJSON {
        ["number": .int(issue.number), "title": .string(issue.title), "state": .string(issue.state),
         "url": .string(issue.htmlUrl)]
    }

    /// One issue as a summary line (shared by `read_issues` and
    /// `search_issues`).
    nonisolated static func agenticNetworkIssueLine(_ issue: GitHubIssue) -> String {
        "- #\(issue.number): \(issue.title) [\(issue.state)] \(issue.htmlUrl)"
    }

    func agenticNetworkCreatePullRequest(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let title = call.string("title"), let body = call.string("body"),
              let head = call.string("head"), let base = call.string("base") else {
            throw MCPToolError("Missing title, body, head, or base")
        }
        let s = try session(for: call)
        let repo = try resolveGitHubRepo(call, s)
        do {
            // Fail fast without a token, then the approval gate,
            // then the client — in that order.
            try requireGitHubToken()
            try await gitApproveChange(tool: call.name,
                                       summary: "Create pull request \"\(title)\" in \(repo.owner)/\(repo.repo) (\(head) → \(base))",
                                       in: s, call: call)
            let pr = try await gitHubClient().createPullRequest(owner: repo.owner, repo: repo.repo, title: title,
                                                                body: body, head: head, base: base, draft: false)
            return .structured(["number": .int(pr.number), "title": .string(pr.title), "htmlUrl": .string(pr.htmlUrl)],
                               summary: "Pull request #\(pr.number) created: \(pr.title)")
        } catch let error as GitHubError {
            throw Self.gitHubToolError(error)
        }
    }

    func agenticNetworkReviewPullRequest(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let prNumber = call.int("prNumber") else {
            throw MCPToolError("Missing prNumber")
        }
        let s = try session(for: call)
        let repo = try resolveGitHubRepo(call, s)
        // READ-ONLY review summary: Legacy's schema has no body/event
        // parameter, so posting a review is not expressible and no
        // post path is invented. Reads need no approval and no token
        // for public repositories.
        let (pr, files, reviews) = try await agenticNetworkFetchPullRequest(gitHubClient(), owner: repo.owner,
                                                                            repo: repo.repo, number: prNumber)
        let lines = Self.agenticNetworkPullRequestLines(pr: pr, files: files, reviews: reviews, asReview: true)
        return .structured(Self.agenticNetworkPullRequestJSON(pr: pr, files: files, reviews: reviews),
                           summary: lines.joined(separator: "\n"))
    }

    func agenticNetworkReadPullRequest(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let prNumber = call.int("prNumber") else {
            throw MCPToolError("Missing prNumber")
        }
        let s = try session(for: call)
        let repo = try resolveGitHubRepo(call, s)
        let (pr, files, reviews) = try await agenticNetworkFetchPullRequest(gitHubClient(), owner: repo.owner,
                                                                            repo: repo.repo, number: prNumber)
        let lines = Self.agenticNetworkPullRequestLines(pr: pr, files: files, reviews: reviews, asReview: false)
        return .structured(Self.agenticNetworkPullRequestJSON(pr: pr, files: files, reviews: reviews),
                           summary: lines.joined(separator: "\n"))
    }

    func agenticNetworkReadIssues(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard call.string("repository") != nil else {
            throw MCPToolError("Missing repository")
        }
        let s = try session(for: call)
        let repo = try resolveGitHubRepo(call, s)
        let issues: [GitHubIssue]
        do {
            issues = try await gitHubClient().listIssues(owner: repo.owner, repo: repo.repo)
        } catch let error as GitHubError {
            throw Self.gitHubToolError(error)
        }
        if issues.isEmpty {
            return .structured(["count": .int(0), "issues": .array([])],
                               summary: "No open issues in \(repo.owner)/\(repo.repo).")
        }
        var lines = ["Open issues in \(repo.owner)/\(repo.repo) (\(issues.count)):"]
        lines += issues.map(Self.agenticNetworkIssueLine)
        return .structured(["count": .int(issues.count), "issues": .array(issues.map(Self.agenticNetworkIssueJSON))],
                           summary: lines.joined(separator: "\n"))
    }

    func agenticNetworkCreateIssue(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let title = call.string("title"), let body = call.string("body") else {
            throw MCPToolError("Missing title or body")
        }
        let s = try session(for: call)
        let repo = try resolveGitHubRepo(call, s)
        do {
            try requireGitHubToken()
            try await gitApproveChange(tool: call.name,
                                       summary: "Create issue \"\(title)\" in \(repo.owner)/\(repo.repo)",
                                       in: s, call: call)
            let issue = try await gitHubClient().createIssue(owner: repo.owner, repo: repo.repo, title: title, body: body)
            return .structured(["number": .int(issue.number), "title": .string(issue.title), "htmlUrl": .string(issue.htmlUrl)],
                               summary: "Issue #\(issue.number) created: \(issue.title)")
        } catch let error as GitHubError {
            throw Self.gitHubToolError(error)
        }
    }

    func agenticNetworkUpdateIssue(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let issueNumber = call.int("issueNumber") else {
            throw MCPToolError("Missing issueNumber")
        }
        let title = call.string("title")
        let body = call.string("body")
        guard title != nil || body != nil else {
            throw MCPToolError("Nothing to update: pass 'title' and/or 'body'.")
        }
        let s = try session(for: call)
        let repo = try resolveGitHubRepo(call, s)
        do {
            try requireGitHubToken()
            try await gitApproveChange(tool: call.name,
                                       summary: "Update issue #\(issueNumber) in \(repo.owner)/\(repo.repo)",
                                       in: s, call: call)
            // Only the supplied fields are sent (`state` is not in
            // Legacy's schema and is never sent); the client omits
            // nil fields from the PATCH body.
            let issue = try await gitHubClient().updateIssue(owner: repo.owner, repo: repo.repo, number: issueNumber,
                                                             title: title, body: body, state: nil)
            return .structured(["number": .int(issue.number), "title": .string(issue.title), "htmlUrl": .string(issue.htmlUrl)],
                               summary: "Issue #\(issue.number) updated: \(issue.title)")
        } catch let error as GitHubError {
            throw Self.gitHubToolError(error)
        }
    }

    func agenticNetworkSearchIssues(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let query = call.string("query") else {
            throw MCPToolError("Missing query")
        }
        let s = try session(for: call)
        // An explicit `repository` scopes the query; otherwise the
        // workspace's github.com origin scopes it when there is one.
        // With neither, the query runs unscoped, as Legacy's
        // repository-less schema did.
        let scoped: String
        if call.string("repository") != nil {
            let repo = try resolveGitHubRepo(call, s)
            scoped = "repo:\(repo.owner)/\(repo.repo) \(query)"
        } else if let repo = try? resolveGitHubRepo(call, s) {
            scoped = "repo:\(repo.owner)/\(repo.repo) \(query)"
        } else {
            scoped = query
        }
        let result: GitHubSearchResult<GitHubIssue>
        do {
            result = try await gitHubClient().searchIssues(query: scoped)
        } catch let error as GitHubError {
            throw Self.gitHubToolError(error)
        }
        if result.items.isEmpty {
            return .structured(["totalCount": .int(result.totalCount), "count": .int(0), "issues": .array([])],
                               summary: "No issues matching \"\(query)\".")
        }
        var lines = ["Issues matching \"\(query)\" (\(result.totalCount) total):"]
        lines += result.items.map(Self.agenticNetworkIssueLine)
        return .structured(["totalCount": .int(result.totalCount), "count": .int(result.items.count),
                            "issues": .array(result.items.map(Self.agenticNetworkIssueJSON))],
                           summary: lines.joined(separator: "\n"))
    }
}

extension SwiftCodeMCPHost {
    // MARK: - Package.swift manifest surgery (`remove_dependencies`)

    /// Removes the package `name` from a Package.swift manifest:
    /// the matching `.package(...)` entry in the package-level
    /// `dependencies:` array, plus any `.product(name: …)` / bare
    /// string references to it in target `dependencies:` arrays.
    /// Returns false when no `.package` entry matched (nothing was
    /// changed). See the file header for the matching rules and the
    /// bare-string caveat.
    nonisolated static func agenticNetworkRemovePackage(named name: String, from content: inout String) -> Bool {
        let arrays = agenticNetworkDependenciesArrays(in: content)
        guard let packageArray = arrays.first else { return false }
        let elements = agenticNetworkArrayElements(in: content, arrayRange: packageArray)
        guard let index = elements.firstIndex(where: {
            agenticNetworkPackageEntry(String(content[$0.element]), matches: name)
        }) else {
            return false
        }
        agenticNetworkRemoveArrayElement(at: index, elements: elements, in: &content)
        // Product references live in the target arrays. Re-scan after
        // the package edit (indices shifted) and work from the last
        // array backwards, so removing text in one array cannot shift
        // the ranges of an array still to be processed.
        for array in agenticNetworkDependenciesArrays(in: content).dropFirst().reversed() {
            let targetElements = agenticNetworkArrayElements(in: content, arrayRange: array)
            for idx in targetElements.indices.reversed()
            where agenticNetworkProductReference(String(content[targetElements[idx].element]), matches: name) {
                agenticNetworkRemoveArrayElement(at: idx, elements: targetElements, in: &content)
            }
        }
        return true
    }

    /// Ranges (including brackets) of every `dependencies: [...]`
    /// array literal in `content`, in file order: the package-level
    /// array first, then each target's array. Bracket matching skips
    /// strings, so a `]` inside a URL or version string cannot close
    /// an array early. Multiline strings and string interpolation
    /// are not special-cased; manifests do not use them in
    /// dependency arrays.
    nonisolated static func agenticNetworkDependenciesArrays(in content: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchFrom = content.startIndex
        while let marker = content.range(of: "dependencies:", range: searchFrom..<content.endIndex) {
            guard let open = content.range(of: "[", range: marker.upperBound..<content.endIndex) else { break }
            guard let close = agenticNetworkMatchingBracket(from: open.lowerBound, in: content) else { break }
            ranges.append(open.lowerBound..<close)
            searchFrom = close
        }
        return ranges
    }

    /// The index just past the `]` matching the `[` at `open`.
    nonisolated static func agenticNetworkMatchingBracket(from open: String.Index, in content: String) -> String.Index? {
        var depth = 0
        var inString = false
        var escaped = false
        var i = open
        while i < content.endIndex {
            let c = content[i]
            if inString {
                if escaped {
                    escaped = false
                } else if c == "\\" {
                    escaped = true
                } else if c == "\"" {
                    inString = false
                }
            } else if c == "\"" {
                inString = true
            } else if c == "[" {
                depth += 1
            } else if c == "]" {
                depth -= 1
                if depth == 0 { return content.index(after: i) }
            }
            i = content.index(after: i)
        }
        return nil
    }

    /// One top-level element of a Swift array literal: its trimmed
    /// range in `content`, plus the range of the comma that follows
    /// it (nil for the last element). Commas inside strings, parens,
    /// or nested brackets do not split elements.
    nonisolated static func agenticNetworkArrayElements(in content: String, arrayRange: Range<String.Index>)
    -> [(element: Range<String.Index>, commaAfter: Range<String.Index>?)] {
        var elements: [(Range<String.Index>, Range<String.Index>?)] = []
        var depth = 0
        var inString = false
        var escaped = false
        var elementStart: String.Index? = nil
        var i = content.index(after: arrayRange.lowerBound)
        let end = content.index(before: arrayRange.upperBound)
        while i < end {
            let c = content[i]
            if inString {
                if escaped {
                    escaped = false
                } else if c == "\\" {
                    escaped = true
                } else if c == "\"" {
                    inString = false
                }
            } else if c == "\"" {
                inString = true
            } else if c == "[" || c == "(" {
                depth += 1
                if elementStart == nil { elementStart = i }
            } else if c == "]" || c == ")" {
                depth -= 1
            } else if c == "," && depth == 0 {
                if let start = elementStart {
                    var elementEnd = i
                    while elementEnd > start, content[content.index(before: elementEnd)].isWhitespace {
                        elementEnd = content.index(before: elementEnd)
                    }
                    elements.append((start..<elementEnd, i..<content.index(after: i)))
                }
                elementStart = nil
            } else if elementStart == nil, !c.isWhitespace {
                elementStart = i
            }
            i = content.index(after: i)
        }
        if let start = elementStart {
            var elementEnd = end
            while elementEnd > start, content[content.index(before: elementEnd)].isWhitespace {
                elementEnd = content.index(before: elementEnd)
            }
            if elementEnd > start { elements.append((start..<elementEnd, nil)) }
        }
        return elements
    }

    /// Removes the element at `index` from `content`: the element
    /// plus its trailing comma when it has one (swallowing the one
    /// following newline and the removed line's own indentation, so
    /// the join stays clean), else the comma before it. Callers
    /// removing several elements from one array must go from the
    /// last index backwards, so earlier ranges stay valid.
    nonisolated static func agenticNetworkRemoveArrayElement(at index: Int,
                                                             elements: [(element: Range<String.Index>, commaAfter: Range<String.Index>?)],
                                                             in content: inout String) {
        let target = elements[index]
        var start = target.element.lowerBound
        var end = target.element.upperBound
        if let comma = target.commaAfter {
            end = comma.upperBound
            if end < content.endIndex, content[end] == "\n" { end = content.index(after: end) }
            while start > content.startIndex {
                let prev = content.index(before: start)
                if content[prev] == " " || content[prev] == "\t" { start = prev } else { break }
            }
        } else if index > 0, let prevComma = elements[index - 1].commaAfter {
            start = prevComma.lowerBound
        }
        content.removeSubrange(start..<end)
    }

    /// Whether a `.package(...)` element declares the package
    /// `name`: an explicit `name:`, or the last path component of
    /// its `url:` (without a trailing `.git`), or the URL itself.
    nonisolated static func agenticNetworkPackageEntry(_ element: String, matches name: String) -> Bool {
        guard element.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(".package(") else { return false }
        if let declared = agenticNetworkStringArgument(named: "name", in: element), declared == name { return true }
        if let url = agenticNetworkStringArgument(named: "url", in: element) {
            if url == name { return true }
            var identity = url
            while identity.hasSuffix("/") { identity.removeLast() }
            if identity.hasSuffix(".git") { identity = String(identity.dropLast(4)) }
            if let last = identity.split(separator: "/").last, String(last) == name { return true }
        }
        return false
    }

    /// Whether a target-dependency element references the product
    /// `name`: `.product(name: "<name>", …)` or a bare `"<name>"`
    /// string (SwiftPM lets a target list a dependency product as a
    /// plain string). A same-package target sharing the package's
    /// name would also match; manifests do not do that in practice.
    nonisolated static func agenticNetworkProductReference(_ element: String, matches name: String) -> Bool {
        let trimmed = element.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(".product(") {
            return agenticNetworkStringArgument(named: "name", in: trimmed) == name
        }
        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 {
            return String(trimmed.dropFirst().dropLast()) == name
        }
        return false
    }

    /// The string value of `label: "…"` in `text`, or nil when the
    /// label is absent or not followed by a string literal.
    nonisolated static func agenticNetworkStringArgument(named label: String, in text: String) -> String? {
        guard let labelRange = text.range(of: "\(label):") else { return nil }
        var i = labelRange.upperBound
        while i < text.endIndex, text[i].isWhitespace { i = text.index(after: i) }
        guard i < text.endIndex, text[i] == "\"" else { return nil }
        var value = ""
        i = text.index(after: i)
        while i < text.endIndex, text[i] != "\"" {
            if text[i] == "\\", text.index(after: i) < text.endIndex {
                value.append(text[text.index(after: i)])
                i = text.index(i, offsetBy: 2)
                continue
            }
            value.append(text[i])
            i = text.index(after: i)
        }
        return value
    }
}
