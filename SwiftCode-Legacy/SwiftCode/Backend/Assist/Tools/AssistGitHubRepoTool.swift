import Foundation

// MARK: - github_repo
//
//  Retrieves and analyzes the actual contents of GitHub repositories:
//  metadata, directory listings, recursive trees, individual file contents,
//  client-side code search, and bounded full-repository retrieval.
//
//  Endpoints used (all validated against the live GitHub REST API):
//    GET /repos/{owner}/{repo}                        repository metadata
//    GET /repos/{owner}/{repo}/contents/{path}        file / directory listing
//    GET /repos/{owner}/{repo}/git/trees/{ref}        recursive file tree
//  File bodies come from the Contents API (base64) with a raw-download
//  fallback for large files. Code search is performed client-side over the
//  fetched tree + file contents so it works identically for public and
//  private repositories.
//
//  Authentication: the user's existing GitHub credential
//  (KeychainService.githubToken, "github_personal_access_token") is attached
//  as a Bearer token when present. Public repositories work without it;
//  private repositories return a clear authorization error when no
//  credential is available. Tokens are never logged, never embedded in
//  output, and never appear in error messages.
//
//  Security: HTTPS-only, GitHub host allow-list, per-hop redirect
//  validation, SSRF guards, pagination, rate-limit detection with reset
//  timing, timeouts, bounded concurrency, response-size caps, binary-file
//  detection, and explicit truncation reporting. Repository contents are
//  untrusted data: they are returned inside the tool result and must never
//  override system instructions or authorize tool use.
//
//  This tool only READS repositories. It never executes repository code,
//  never runs build scripts, never installs dependencies, and never
//  modifies remote repositories.

public struct AssistGitHubRepoTool: AssistTool {
    public let id = "github_repo"
    public let name = "GitHub Repository Inspector"
    public let description = "Reads real GitHub repositories: metadata, file trees, directory listings, source file contents, code search, and bounded full-repository retrieval. Public repos need no login; private repos use the user's saved GitHub credential."

    public init() {}

    public var capability: ToolCapability { .repositoryDiscovery }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var knownLimitations: [String] {
        [
            "Code search is performed client-side over fetched files (the GitHub Code Search API requires authentication); very large repositories are searched within the file/byte budgets.",
            "Recursive trees are capped by the GitHub API (truncated flag is reported); fetch_repository retrieves text files within maxBytes and reports everything it skips.",
            "Binary files are classified, never decoded as text, and listed separately.",
            "Rate limits apply: unauthenticated callers share 60 requests/hour; the tool reports reset timing instead of retrying."
        ]
    }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Inspects a GitHub repository. 'operation' is required; identify the repo with owner+repo or url.",
            properties: [
                "operation": JSONSchema(
                    type: "string",
                    description: "One of: repository_info, list_files, get_file, get_directory, get_tree, search_code, fetch_repository."
                ),
                "owner": JSONSchema(type: "string", description: "Repository owner or organization, e.g. 'dylans2010'."),
                "repo": JSONSchema(type: "string", description: "Repository name, e.g. 'SwiftCode-Mac'."),
                "url": JSONSchema(
                    type: "string",
                    description: "GitHub repository URL, e.g. https://github.com/dylans2010/SwiftCode-Mac. Alternative to owner+repo."
                ),
                "ref": JSONSchema(
                    type: "string",
                    description: "Branch, tag, or commit SHA. Defaults to the repository's default branch."
                ),
                "path": JSONSchema(
                    type: "string",
                    description: "Repository-relative file or directory path for list_files, get_file, get_directory."
                ),
                "recursive": JSONSchema(
                    type: "boolean",
                    description: "For get_tree: fetch the full recursive tree (default true). For list_files: recurse into subdirectories via the tree."
                ),
                "includeContent": JSONSchema(
                    type: "boolean",
                    description: "For list_files/get_directory: also fetch each file's content (bounded by maxBytes). Default false."
                ),
                "maxResults": JSONSchema(
                    type: "integer",
                    description: "Maximum entries/files/matches to return. Defaults: 100 (listings), 5000 (tree), 50 (search), 50 (fetch_repository)."
                ),
                "maxBytes": JSONSchema(
                    type: "integer",
                    description: "Maximum aggregate content bytes to return (fetch_repository, includeContent). Default 262144 (256 KB), hard cap 2097152 (2 MB)."
                ),
                "query": JSONSchema(
                    type: "string",
                    description: "For search_code: text to find. For fetch_repository: prioritizes files whose path or name matches."
                )
            ],
            required: ["operation"]
        )
    }

    // MARK: - Execution

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let startedAt = Date()
        guard let operation = (input["operation"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !operation.isEmpty else {
            return .failure("Missing required parameter: operation.", code: .missingArgument)
        }
        guard Self.supportedOperationsList.contains(operation) else {
            return .failure(
                "Unsupported operation '\(operation)'. Supported: \(Self.supportedOperationsList.joined(separator: ", ")).",
                code: .unsupportedOperation
            )
        }

        let repoRef: RepoReference
        do {
            repoRef = try Self.resolveRepo(
                owner: input["owner"] as? String,
                repo: input["repo"] as? String,
                urlString: input["url"] as? String
            )
        } catch let fetchError as AssistRemoteFetchError {
            return .failure("Invalid repository reference: \(fetchError.localizedDescription)", code: .invalidInput)
        }

        let client = GitHubAPIClient()
        let ref = ((input["ref"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        let path = ((input["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        let recursive = AssistInputNumbers.boolean(input["recursive"]) ?? true
        let includeContent = AssistInputNumbers.boolean(input["includeContent"]) ?? false
        let maxResults = AssistInputNumbers.integer(input["maxResults"]) ?? Self.defaultMaxResults(for: operation)
        let maxBytes = min(AssistInputNumbers.integer(input["maxBytes"]) ?? 262_144, 2_097_152)
        let query = (input["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        await context.logger.info("github_repo '\(operation)' on \(repoRef.owner)/\(repoRef.repo).", toolId: id)

        do {
            switch operation {
            case "repository_info":
                return try await opRepositoryInfo(client: client, repo: repoRef, context: context, startedAt: startedAt)
            case "list_files", "get_directory":
                return try await opListFiles(client: client, repo: repoRef, operation: operation, ref: ref, path: path ?? "", recursive: recursive,
                                             includeContent: includeContent, maxResults: max(1, maxResults), maxBytes: maxBytes,
                                             context: context, startedAt: startedAt)
            case "get_file":
                guard let filePath = path, !filePath.isEmpty else {
                    return .failure("get_file requires 'path' (repository-relative file path).", code: .missingArgument)
                }
                return try await opGetFile(client: client, repo: repoRef, ref: ref, path: filePath, context: context, startedAt: startedAt)
            case "get_tree":
                return try await opGetTree(client: client, repo: repoRef, ref: ref, recursive: recursive,
                                           maxResults: max(1, maxResults), context: context, startedAt: startedAt)
            case "search_code":
                guard let q = query, !q.isEmpty else {
                    return .failure("search_code requires 'query'.", code: .missingArgument)
                }
                return try await opSearchCode(client: client, repo: repoRef, ref: ref, query: q,
                                              maxResults: max(1, maxResults), maxBytes: maxBytes,
                                              context: context, startedAt: startedAt)
            case "fetch_repository":
                return try await opFetchRepository(client: client, repo: repoRef, ref: ref, query: query,
                                                   maxResults: max(1, maxResults), maxBytes: maxBytes,
                                                   context: context, startedAt: startedAt)
            default:
                return .failure("Unsupported operation '\(operation)'.", code: .unsupportedOperation)
            }
        } catch let fetchError as AssistRemoteFetchError {
            return mapFetchError(fetchError, operation: operation, repo: repoRef)
        } catch is CancellationError {
            return .failure("GitHub request was cancelled.", code: .cancelled)
        } catch {
            return .failure("GitHub request failed: \(error.localizedDescription)", code: .executionFailed)
        }
    }

    private static let supportedOperationsList = [
        "repository_info", "list_files", "get_file", "get_directory",
        "get_tree", "search_code", "fetch_repository"
    ]

    private static func defaultMaxResults(for operation: String) -> Int {
        switch operation {
        case "get_tree": return 5000
        case "search_code", "fetch_repository": return 50
        default: return 100
        }
    }

    private func mapFetchError(_ error: AssistRemoteFetchError, operation: String, repo: RepoReference) -> AssistToolResult {
        switch error {
        case .badStatus(let code, let detail):
            switch code {
            case 404:
                return .failure(
                    "Not found: \(detail ?? "HTTP 404"). The repository, ref, or path may not exist — or it is private and no GitHub credential is saved.",
                    code: .notFound,
                    suggestedNextActions: ["github_repo"]
                )
            case 401:
                return .failure(
                    "GitHub rejected the saved credential (HTTP 401). Re-authorize GitHub access, then retry. The credential itself is never shown.",
                    code: .permissionDenied
                )
            case 403 where (detail ?? "").lowercased().contains("rate"):
                return .failure("GitHub rate limit: \(detail ?? "quota exhausted").", code: .resourceExhausted)
            case 422:
                return .failure("GitHub could not process the request (HTTP 422): \(detail ?? "validation failed"). Check 'ref' and 'path'.", code: .invalidInput)
            default:
                return .failure("GitHub API error during '\(operation)': \(detail ?? "HTTP \(code)").", code: .executionFailed)
            }
        case .rateLimited(let resetAt):
            if let resetAt {
                return .failure("GitHub rate limit exhausted; resets at \(resetAt). Do not retry before then.", code: .resourceExhausted)
            }
            return .failure("GitHub rate limit exhausted. Wait before retrying.", code: .resourceExhausted)
        case .timeout:
            return .failure("GitHub request timed out.", code: .timeout)
        case .cancelled:
            return .failure("GitHub request was cancelled.", code: .cancelled)
        case .responseTooLarge(let cap):
            return .failure("GitHub response exceeded the \(cap)-byte safety cap. Narrow the request (smaller path, lower maxResults).", code: .resourceExhausted)
        case .disallowedHost, .disallowedScheme, .ssrfBlocked, .redirectToDisallowedHost, .tooManyRedirects:
            return .failure("Blocked unsafe request: \(error.localizedDescription)", code: .invalidInput)
        default:
            return .failure("GitHub request failed: \(error.localizedDescription)", code: .executionFailed)
        }
    }

    // MARK: - Repo reference

    struct RepoReference: Sendable {
        let owner: String
        let repo: String
    }

    /// Resolves owner/repo from explicit fields or a github.com URL.
    static func resolveRepo(owner: String?, repo: String?, urlString: String?) throws -> RepoReference {
        if let o = owner?.trimmingCharacters(in: .whitespacesAndNewlines), !o.isEmpty,
           let r = repo?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty {
            try validateOwnerRepo(owner: o, repo: r)
            return RepoReference(owner: o, repo: r)
        }
        guard let raw = urlString?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let url = URL(string: raw) else {
            throw AssistRemoteFetchError.invalidURL("Provide 'owner' + 'repo', or a GitHub repository 'url'.")
        }
        try AssistURLGuard.validate(url, allowedHosts: ["github.com"])
        // Accept https://github.com/{owner}/{repo}[.git][/tree/...] — only the
        // first two path segments identify the repository.
        let segments = url.path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        guard segments.count >= 2 else {
            throw AssistRemoteFetchError.invalidURL("Could not parse owner/repo from '\(url.host ?? "")\(url.path)'.")
        }
        var repoName = segments[1]
        if repoName.hasSuffix(".git") { repoName = String(repoName.dropLast(4)) }
        try validateOwnerRepo(owner: segments[0], repo: repoName)
        return RepoReference(owner: segments[0], repo: repoName)
    }

    /// GitHub owner/repo naming rules; rejects traversal and injection.
    static func validateOwnerRepo(owner: String, repo: String) throws {
        let pattern = "^[A-Za-z0-9_.-]+$"
        for (label, value) in [("owner", owner), ("repo", repo)] {
            guard value.range(of: pattern, options: .regularExpression) != nil,
                  value.count <= 100, !value.contains("..") else {
                throw AssistRemoteFetchError.invalidURL("Invalid \(label) '\(value)'.")
            }
        }
    }

    // MARK: - Operations

    private func opRepositoryInfo(client: GitHubAPIClient, repo: RepoReference, context: AssistContext, startedAt: Date) async throws -> AssistToolResult {
        let info = try await client.repositoryInfo(owner: repo.owner, repo: repo.repo)
        await context.logger.info("repository_info: \(info.fullName) (\(info.isPrivate ? "private" : "public")).", toolId: id)
        var lines = [
            "# \(info.fullName)",
            "Canonical URL: https://github.com/\(info.fullName)",
            info.isPrivate ? "Visibility: private (accessed with the user's saved GitHub credential)" : "Visibility: public",
            "Default branch: \(info.defaultBranch)",
            "Description: \(info.description ?? "(none)")",
            "Primary language: \(info.language ?? "(unknown)")",
            "Stars: \(info.stargazersCount)  Forks: \(info.forksCount)  Open issues: \(info.openIssuesCount)",
        ]
        if let license = info.licenseName { lines.append("License: \(license)") }
        if let pushed = info.pushedAt { lines.append("Last pushed: \(pushed)") }
        if let size = info.sizeKB { lines.append("Repository size: \(size) KB") }
        lines.append("Contents retrieved from the live GitHub API; inspect files with list_files / get_tree / fetch_repository.")
        return .success(
            "Retrieved repository metadata for \(info.fullName).",
            data: [AssistToolDataKey.content: lines.joined(separator: "\n"), AssistToolDataKey.truncated: "false"],
            diagnostics: ["duration: \(elapsed(startedAt))"]
        )
    }

    private func opListFiles(client: GitHubAPIClient, repo: RepoReference, operation: String, ref: String?, path: String,
                             recursive: Bool, includeContent: Bool,
                             maxResults: Int, maxBytes: Int,
                             context: AssistContext, startedAt: Date) async throws -> AssistToolResult {
        let resolvedRef = try await client.resolveRef(owner: repo.owner, repo: repo.repo, ref: ref)
        var entries: [GitHubContentEntry] = []
        if operation == "list_files", recursive {
            // Recursive listing goes through the tree API (single request).
            let tree = try await client.tree(owner: repo.owner, repo: repo.repo, ref: resolvedRef, recursive: true)
            let prefix = path.isEmpty ? "" : path + "/"
            entries = tree.entries
                .filter { $0.type == "blob" && $0.path.hasPrefix(prefix) }
                .prefix(maxResults)
                .map { GitHubContentEntry(name: ($0.path as NSString).lastPathComponent, path: $0.path, type: "file", size: $0.size, downloadURL: nil) }
        } else {
            // get_directory, or non-recursive list_files: one Contents API level.
            entries = try await client.directoryContents(owner: repo.owner, repo: repo.repo, ref: resolvedRef, path: path, maxResults: maxResults)
        }

        var lines = ["# \(repo.owner)/\(repo.repo) — \(path.isEmpty ? "repository root" : path) @ \(resolvedRef)", ""]
        var totalBytes = 0
        var truncated = false
        for entry in entries {
            try Task.checkCancellation()
            let sizeText = entry.size.map { " (\($0) bytes)" } ?? ""
            if includeContent, entry.type == "file", let size = entry.size, size <= 200_000, totalBytes < maxBytes {
                if let file = try? await client.fileContent(owner: repo.owner, repo: repo.repo, ref: resolvedRef, path: entry.path, maxBytes: maxBytes - totalBytes),
                   case .text(let text) = file {
                    lines.append("- \(entry.path)\(sizeText)")
                    lines.append("```")
                    lines.append(String(text.prefix(maxBytes - totalBytes)))
                    lines.append("```")
                    totalBytes += min(text.utf8.count, maxBytes - totalBytes)
                    continue
                }
            }
            lines.append("- [\(entry.type)] \(entry.path)\(sizeText)")
        }
        if entries.count >= maxResults {
            truncated = true
            lines.append("")
            lines.append("[truncated: listing capped at \(maxResults) entries; narrow 'path' or raise 'maxResults']")
        }
        lines.append("")
        lines.append("Use get_file with 'path' for full contents of a specific file.")
        return .success(
            "Listed \(entries.count) entr\(entries.count == 1 ? "y" : "ies") in \(repo.owner)/\(repo.repo).",
            data: [AssistToolDataKey.content: lines.joined(separator: "\n"),
                   AssistToolDataKey.truncated: truncated ? "true" : "false",
                   AssistToolDataKey.count: "\(entries.count)"],
            diagnostics: ["ref: \(resolvedRef)", "duration: \(elapsed(startedAt))"]
        )
    }

    private func opGetFile(client: GitHubAPIClient, repo: RepoReference, ref: String?, path: String,
                           context: AssistContext, startedAt: Date) async throws -> AssistToolResult {
        let resolvedRef = try await client.resolveRef(owner: repo.owner, repo: repo.repo, ref: ref)
        let file = try await client.fileContent(owner: repo.owner, repo: repo.repo, ref: resolvedRef, path: path, maxBytes: 1_000_000)
        switch file {
        case .text(let text):
            await context.logger.info("get_file: \(path) (\(text.utf8.count) bytes).", toolId: id)
            var lines = ["# \(path)", "Repository: \(repo.owner)/\(repo.repo) @ \(resolvedRef)", ""]
            let capped = text.count > 60_000
            lines.append("```")
            lines.append(capped ? String(text.prefix(60_000)) + "\n[truncated: file exceeds 60,000 characters]" : text)
            lines.append("```")
            return .success(
                "Retrieved '\(path)' (\(text.utf8.count) bytes).",
                data: [AssistToolDataKey.content: lines.joined(separator: "\n"),
                       AssistToolDataKey.truncated: capped ? "true" : "false",
                       AssistToolDataKey.path: path],
                diagnostics: ["duration: \(elapsed(startedAt))"]
            )
        case .binary(let size, let reason):
            return .success(
                "'\(path)' is a binary file (\(size) bytes; \(reason)) and was not decoded as text.",
                data: [AssistToolDataKey.content: "Binary file: \(path) (\(size) bytes) — \(reason). Contents not retrieved.",
                       AssistToolDataKey.truncated: "false",
                       AssistToolDataKey.path: path],
                diagnostics: ["duration: \(elapsed(startedAt))"]
            )
        }
    }

    private func opGetTree(client: GitHubAPIClient, repo: RepoReference, ref: String?, recursive: Bool,
                           maxResults: Int, context: AssistContext, startedAt: Date) async throws -> AssistToolResult {
        let resolvedRef = try await client.resolveRef(owner: repo.owner, repo: repo.repo, ref: ref)
        let tree = try await client.tree(owner: repo.owner, repo: repo.repo, ref: resolvedRef, recursive: recursive)
        let entries = Array(tree.entries.prefix(maxResults))
        await context.logger.info("get_tree: \(tree.entries.count) entries (\(tree.truncated ? "API-truncated" : "complete")).", toolId: id)

        var lines = ["# \(repo.owner)/\(repo.repo) — file tree @ \(resolvedRef)",
                     "Entries: \(tree.entries.count)\(tree.truncated ? " (TRUNCATED by the GitHub API — tree is incomplete)" : "")", ""]
        for entry in entries {
            let sizeText = entry.size.map { " \($0)" } ?? ""
            lines.append("\(entry.type == "tree" ? "d" : "-") \(entry.path)\(sizeText)")
        }
        var truncated = tree.truncated
        if tree.entries.count > maxResults {
            truncated = true
            lines.append("")
            lines.append("[truncated: showing \(maxResults) of \(tree.entries.count) entries; raise 'maxResults']")
        }
        if tree.truncated {
            lines.append("")
            lines.append("The GitHub API truncated this recursive tree. Use get_directory on subdirectories for the remainder.")
        }
        return .success(
            "Retrieved file tree for \(repo.owner)/\(repo.repo) (\(entries.count) shown).",
            data: [AssistToolDataKey.content: lines.joined(separator: "\n"),
                   AssistToolDataKey.truncated: truncated ? "true" : "false",
                   AssistToolDataKey.count: "\(tree.entries.count)"],
            diagnostics: ["apiTruncated: \(tree.truncated)", "duration: \(elapsed(startedAt))"]
        )
    }

    private func opSearchCode(client: GitHubAPIClient, repo: RepoReference, ref: String?, query: String,
                              maxResults: Int, maxBytes: Int,
                              context: AssistContext, startedAt: Date) async throws -> AssistToolResult {
        let resolvedRef = try await client.resolveRef(owner: repo.owner, repo: repo.repo, ref: ref)
        let tree = try await client.tree(owner: repo.owner, repo: repo.repo, ref: resolvedRef, recursive: true)
        let candidates = tree.entries
            .filter { $0.type == "blob" && Self.isSearchablePath($0.path) && ($0.size ?? 0) <= 200_000 }
            .prefix(400)

        struct Match: Sendable { let path: String; let line: Int; let snippet: String }
        var matches: [Match] = []
        var filesSearched = 0
        var bytesUsed = 0
        let loweredQuery = query.lowercased()

        await withTaskGroup(of: (String, [Match], Int).self) { group in
            var inflight = 0
            var iterator = candidates.makeIterator()
            func launchNext() {
                while inflight < 4, let entry = iterator.next() {
                    inflight += 1
                    group.addTask {
                        var local: [Match] = []
                        var used = 0
                        if let file = try? await client.fileContent(owner: repo.owner, repo: repo.repo, ref: resolvedRef, path: entry.path, maxBytes: 200_000),
                           case .text(let text) = file {
                            used = text.utf8.count
                            for (index, line) in text.components(separatedBy: "\n").enumerated() {
                                if line.lowercased().contains(loweredQuery) {
                                    local.append(Match(path: entry.path, line: index + 1, snippet: String(line.trimmingCharacters(in: .whitespaces).prefix(240))))
                                    if local.count >= 5 { break }
                                }
                            }
                        }
                        return (entry.path, local, used)
                    }
                }
            }
            launchNext()
            for await (_, local, used) in group {
                inflight -= 1
                filesSearched += 1
                bytesUsed += used
                for m in local where matches.count < maxResults { matches.append(m) }
                if matches.count < maxResults, bytesUsed < maxBytes { launchNext() }
            }
        }

        await context.logger.info("search_code '\(query)': \(matches.count) matches in \(filesSearched) files.", toolId: id)
        var lines = ["# Code search: \"\(query)\" in \(repo.owner)/\(repo.repo) @ \(resolvedRef)",
                     "Searched \(filesSearched) text files (\(bytesUsed) bytes); client-side search over fetched contents.", ""]
        if matches.isEmpty {
            lines.append("No matches found.")
        } else {
            for m in matches { lines.append("- \(m.path):\(m.line): \(m.snippet)") }
        }
        if matches.count >= maxResults {
            lines.append("")
            lines.append("[truncated: showing \(maxResults) matches; raise 'maxResults' or narrow the query]")
        }
        if tree.truncated { lines.append("[note: the repository tree itself was API-truncated; results may be incomplete]") }
        return .success(
            "Found \(matches.count) match\(matches.count == 1 ? "" : "es") for \"\(query)\".",
            data: [AssistToolDataKey.content: lines.joined(separator: "\n"),
                   AssistToolDataKey.truncated: matches.count >= maxResults ? "true" : "false",
                   AssistToolDataKey.count: "\(matches.count)"],
            diagnostics: ["filesSearched: \(filesSearched)", "duration: \(elapsed(startedAt))"]
        )
    }

    private func opFetchRepository(client: GitHubAPIClient, repo: RepoReference, ref: String?, query: String?,
                                   maxResults: Int, maxBytes: Int,
                                   context: AssistContext, startedAt: Date) async throws -> AssistToolResult {
        let resolvedRef = try await client.resolveRef(owner: repo.owner, repo: repo.repo, ref: ref)
        let tree = try await client.tree(owner: repo.owner, repo: repo.repo, ref: resolvedRef, recursive: true)

        // Classify every entry before fetching anything.
        var textFiles: [AssistGitHubTreeEntry] = []
        var skippedBinary: [String] = []
        var skippedOversize: [String] = []
        var skippedDirs: [String] = []
        for entry in tree.entries {
            if entry.type != "blob" { continue }
            if Self.isSkippedDirectory(entry.path) { skippedDirs.append(entry.path); continue }
            let size = entry.size ?? 0
            if size > 200_000 { skippedOversize.append("\(entry.path) (\(size) bytes)"); continue }
            if Self.isBinaryPath(entry.path) { skippedBinary.append(entry.path); continue }
            textFiles.append(entry)
        }

        // Prioritize: query-relevant paths first, then project configuration,
        // then smaller files (more signal per byte).
        let queryTokens = (query ?? "").lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        textFiles.sort { a, b in
            let aScore = Self.priorityScore(path: a.path, queryTokens: queryTokens)
            let bScore = Self.priorityScore(path: b.path, queryTokens: queryTokens)
            if aScore != bScore { return aScore > bScore }
            return (a.size ?? 0) < (b.size ?? 0)
        }
        let selected = Array(textFiles.prefix(maxResults))

        struct Fetched: Sendable { let path: String; let text: String?; let binary: Bool; let bytes: Int }
        var fetched: [Fetched] = []
        var bytesUsed = 0
        await withTaskGroup(of: Fetched.self) { group in
            var inflight = 0
            var iterator = selected.makeIterator()
            func launchNext() {
                while inflight < 4, let entry = iterator.next(), bytesUsed < maxBytes {
                    inflight += 1
                    group.addTask {
                        guard let file = try? await client.fileContent(owner: repo.owner, repo: repo.repo, ref: resolvedRef, path: entry.path, maxBytes: 200_000) else {
                            return Fetched(path: entry.path, text: nil, binary: false, bytes: 0)
                        }
                        switch file {
                        case .text(let text): return Fetched(path: entry.path, text: text, binary: false, bytes: text.utf8.count)
                        case .binary: return Fetched(path: entry.path, text: nil, binary: true, bytes: 0)
                        }
                    }
                }
            }
            launchNext()
            for await result in group {
                inflight -= 1
                if let text = result.text, bytesUsed + result.bytes <= maxBytes {
                    fetched.append(result)
                    bytesUsed += result.bytes
                } else if result.binary {
                    skippedBinary.append(result.path)
                }
                if bytesUsed < maxBytes { launchNext() }
            }
        }
        fetched.sort { $0.path < $1.path }

        await context.logger.info("fetch_repository: \(fetched.count) files, \(bytesUsed) bytes.", toolId: id)

        var lines = ["# \(repo.owner)/\(repo.repo) @ \(resolvedRef) — repository retrieval",
                     "Text files retrieved: \(fetched.count) (\(bytesUsed) bytes)\(tree.truncated ? " — TREE WAS API-TRUNCATED, SEE BELOW" : "")", ""]
        for f in fetched {
            lines.append("## File: \(f.path)")
            lines.append("```")
            let cap = 30_000
            lines.append(f.text!.count > cap ? String(f.text!.prefix(cap)) + "\n[truncated: file exceeds \(cap) characters]" : f.text!)
            lines.append("```")
            lines.append("")
        }
        lines.append("---")
        lines.append("Retrieval report (explicit — nothing omitted silently):")
        lines.append("- tree entries seen: \(tree.entries.count)\(tree.truncated ? " (TRUNCATED by GitHub API: tree is incomplete; use get_directory per subdirectory)" : "")")
        lines.append("- text files retrieved: \(fetched.count)")
        if !skippedBinary.isEmpty { lines.append("- skipped as binary (\(skippedBinary.count)): \(skippedBinary.prefix(20).joined(separator: ", "))\(skippedBinary.count > 20 ? "…" : "")") }
        if !skippedOversize.isEmpty { lines.append("- skipped as oversize (\(skippedOversize.count)): \(skippedOversize.prefix(20).joined(separator: ", "))\(skippedOversize.count > 20 ? "…" : "")") }
        if !skippedDirs.isEmpty { lines.append("- skipped directories (\(skippedDirs.count)): \(Array(Set(skippedDirs.map { ($0 as NSString).deletingLastPathComponent })).prefix(10).joined(separator: ", "))\(skippedDirs.count > 10 ? "…" : "")") }
        let unselected = textFiles.count - selected.count
        if unselected > 0 { lines.append("- not selected within maxResults (\(unselected) more text files); raise 'maxResults' or use get_file with an exact 'path'") }
        if bytesUsed >= maxBytes { lines.append("- byte budget exhausted (\(maxBytes) bytes); raise 'maxBytes' or fetch specific files with get_file") }
        lines.append("To continue: call get_file with any exact repository-relative 'path' above.")
        let truncated = tree.truncated || unselected > 0 || bytesUsed >= maxBytes

        let output = lines.joined(separator: "\n")
        let capped = output.count > 120_000
        return .success(
            "Retrieved \(fetched.count) files (\(bytesUsed) bytes) from \(repo.owner)/\(repo.repo).\(truncated ? " Result is PARTIAL — see the retrieval report." : "")",
            data: [AssistToolDataKey.content: capped ? String(output.prefix(120_000)) + "\n[truncated: combined output exceeded 120,000 characters; fetch individual files with get_file]" : output,
                   AssistToolDataKey.truncated: (truncated || capped) ? "true" : "false",
                   AssistToolDataKey.count: "\(fetched.count)"],
            diagnostics: ["treeTruncated: \(tree.truncated)", "bytesUsed: \(bytesUsed)", "duration: \(elapsed(startedAt))"],
            suggestedNextActions: truncated ? ["github_repo"] : []
        )
    }

    private func elapsed(_ start: Date) -> String {
        String(format: "%.1fs", Date().timeIntervalSince(start))
    }

    // MARK: - Path classification

    /// Extensions that are never useful as decoded text.
    nonisolated static let binaryExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "ico", "icns", "tiff",
        "pdf", "zip", "gz", "tar", "bz2", "xz", "7z", "dmg", "pkg",
        "mp3", "mp4", "mov", "wav", "aiff", "m4a",
        "o", "a", "so", "dylib", "framework",
        "xcassets", "mlmodel", "mlmodelc", "bin", "dat", "sqlite", "db",
        "ttf", "otf", "woff", "woff2", "eot",
        "pyc", "pyo", "class", "jar", "war",
        "xcarchive", "ipa", "appex"
    ]

    /// Directory prefixes excluded from full-repository retrieval (build
    /// artifacts, vendored dependencies, VCS metadata).
    nonisolated static let skippedDirectoryPrefixes = [
        ".git/", "node_modules/", "Pods/", "Carthage/", "DerivedData/",
        "build/", ".build/", "vendor/", "__pycache__/", ".venv/"
    ]

    nonisolated static func isBinaryPath(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return !ext.isEmpty && binaryExtensions.contains(ext)
    }

    nonisolated static func isSkippedDirectory(_ path: String) -> Bool {
        skippedDirectoryPrefixes.contains { path.hasPrefix($0) || path == String($0.dropLast()) }
    }

    /// Text files worth searching: source, config, docs, data.
    nonisolated static func isSearchablePath(_ path: String) -> Bool {
        if isBinaryPath(path) || isSkippedDirectory(path) { return false }
        return true
    }

    /// Ranking for fetch_repository: query hits > project config > docs > rest.
    nonisolated static func priorityScore(path: String, queryTokens: [String]) -> Int {
        let lower = path.lowercased()
        var score = 0
        for token in queryTokens where !token.isEmpty {
            if lower.contains(token) { score += 10 }
        }
        let name = (lower as NSString).lastPathComponent
        if ["package.swift", "readme.md", ".xcodeproj", "project.pbxproj", "cartfile", "podfile", "makefile"].contains(where: { name == $0 || lower.hasSuffix("/" + $0) }) { score += 5 }
        if lower.hasSuffix(".md") { score += 2 }
        return score
    }

    /// Binary sniffing on raw bytes: NUL byte or invalid UTF-8.
    /// (The 8KB prefix probe below is a sniffing heuristic, not output
    /// truncation — callers report truncation explicitly where it applies.)
    nonisolated static func isBinaryData(_ data: Data) -> Bool {
        if data.contains(0) { return true }
        return String(data: data.prefix(8192), encoding: .utf8) == nil && !data.isEmpty
    }
}

// MARK: - GitHub API client (internal to this tool)

private struct GitHubRepoInfo: Sendable {
    let fullName: String
    let description: String?
    let defaultBranch: String
    let isPrivate: Bool
    let language: String?
    let stargazersCount: Int
    let forksCount: Int
    let openIssuesCount: Int
    let licenseName: String?
    let pushedAt: String?
    let sizeKB: Int?
}

private struct AssistGitHubTreeEntry: Sendable {
    let path: String
    let type: String // "blob" | "tree"
    let size: Int?
    let sha: String
}

private struct GitHubTree: Sendable {
    let entries: [AssistGitHubTreeEntry]
    let truncated: Bool
}

private struct GitHubContentEntry: Sendable {
    let name: String
    let path: String
    let type: String // "file" | "dir" | "symlink" | "submodule"
    let size: Int?
    let downloadURL: String?
}

private enum AssistGitHubFileContent: Sendable {
    case text(String)
    case binary(size: Int, reason: String)
}

/// Thin GitHub REST client honoring the shared secure-fetch contract.
/// The user's saved GitHub token (Keychain) is attached when present;
/// it is never logged and never included in error strings.
private final class GitHubAPIClient: Sendable {
    private static let hosts: Set<String> = ["api.github.com", "raw.githubusercontent.com", "objects.githubusercontent.com"]
    private static let client = AssistSecureHTTPClient()
    private static let cache = AssistRemoteResponseCache(maxEntries: 200, defaultTTL: 600)

    /// The existing user-authorized credential, if the user saved one.
    private var token: String? {
        KeychainService.shared.get(forKey: KeychainService.githubToken)
    }

    private func options(acceptJSON: Bool = true) -> AssistFetchOptions {
        var options = AssistFetchOptions()
        options.allowedHosts = Self.hosts
        options.timeout = 30
        options.maxResponseBytes = 8_000_000
        if acceptJSON {
            options.acceptedContentTypes = ["application/json"]
        }
        options.userAgent = "SwiftCode-Assist/1.0 (macOS)"
        var headers = [
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28"
        ]
        // Attached only in memory, only on the request; never persisted,
        // never logged, never reflected into results or errors.
        if let token = token, !token.isEmpty {
            headers["Authorization"] = "Bearer \(token)"
        }
        options.extraHeaders = headers
        return options
    }

    private func get(_ url: URL, acceptJSON: Bool = true) async throws -> AssistHTTPResponse {
        try Task.checkCancellation()
        // Cache key namespaces by auth state so authed (possibly private)
        // responses are never served to an unauthenticated context.
        let authed = !(token ?? "").isEmpty
        let key = (authed ? "auth:" : "anon:") + url.absoluteString
        if let cached = await Self.cache.get(key) {
            let http = HTTPURLResponse(url: cached.finalURL, statusCode: cached.statusCode, httpVersion: nil, headerFields: nil)!
            return AssistHTTPResponse(data: cached.data, httpResponse: http, finalURL: cached.finalURL)
        }
        let response = try await Self.client.get(url, options: options(acceptJSON: acceptJSON))
        await Self.cache.set(key, data: response.data, contentType: response.contentType, finalURL: response.finalURL, statusCode: response.statusCode)
        return response
    }

    private func apiURL(_ path: String) -> URL {
        URL(string: "https://api.github.com" + path)!
    }

    private func encodedPath(_ path: String) -> String {
        path.split(separator: "/").map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
    }

    // MARK: Repository metadata

    func repositoryInfo(owner: String, repo: String) async throws -> GitHubRepoInfo {
        let response = try await get(apiURL("/repos/\(owner)/\(repo)"))
        guard let obj = try? AssistJSON.parse(response.data), let d = AssistJSON.object(obj) else {
            throw AssistRemoteFetchError.decodingFailed("repository metadata")
        }
        return GitHubRepoInfo(
            fullName: (d["full_name"] as? String) ?? "\(owner)/\(repo)",
            description: d["description"] as? String,
            defaultBranch: (d["default_branch"] as? String) ?? "main",
            isPrivate: (d["private"] as? Bool) ?? false,
            language: d["language"] as? String,
            stargazersCount: (d["stargazers_count"] as? Int) ?? 0,
            forksCount: (d["forks_count"] as? Int) ?? 0,
            openIssuesCount: (d["open_issues_count"] as? Int) ?? 0,
            licenseName: (d["license"] as? [String: Any])?["name"] as? String,
            pushedAt: d["pushed_at"] as? String,
            sizeKB: d["size"] as? Int
        )
    }

    /// Resolves nil/empty refs to the default branch; validates ref shape.
    func resolveRef(owner: String, repo: String, ref: String?) async throws -> String {
        guard let ref = ref, !ref.isEmpty else {
            return try await repositoryInfo(owner: owner, repo: repo).defaultBranch
        }
        guard ref.count <= 256, !ref.contains(".."), !ref.contains("//"),
              ref.range(of: "^[A-Za-z0-9_./-]+$", options: .regularExpression) != nil else {
            throw AssistRemoteFetchError.invalidURL("Invalid ref '\(ref)'.")
        }
        return ref
    }

    // MARK: Trees

    func tree(owner: String, repo: String, ref: String, recursive: Bool) async throws -> GitHubTree {
        var components = URLComponents(url: apiURL("/repos/\(owner)/\(repo)/git/trees/\(encodedPath(ref))"), resolvingAgainstBaseURL: false)!
        if recursive { components.queryItems = [URLQueryItem(name: "recursive", value: "1")] }
        let response = try await get(components.url!)
        guard let obj = try? AssistJSON.parse(response.data), let d = AssistJSON.object(obj),
              let rawEntries = AssistJSON.array(d["tree"]) else {
            throw AssistRemoteFetchError.decodingFailed("repository tree")
        }
        let entries: [AssistGitHubTreeEntry] = rawEntries.compactMap { item in
            guard let e = AssistJSON.object(item),
                  let path = e["path"] as? String,
                  let type = e["type"] as? String,
                  let sha = e["sha"] as? String else { return nil }
            return AssistGitHubTreeEntry(path: path, type: type, size: e["size"] as? Int, sha: sha)
        }
        return GitHubTree(entries: entries, truncated: (d["truncated"] as? Bool) ?? false)
    }

    // MARK: Contents (files & directories)

    /// Directory listing with Link-header pagination.
    func directoryContents(owner: String, repo: String, ref: String, path: String, maxResults: Int) async throws -> [GitHubContentEntry] {
        var entries: [GitHubContentEntry] = []
        var page = 1
        // Root listing has no trailing path segment.
        let basePath = path.isEmpty ? "/repos/\(owner)/\(repo)/contents" : "/repos/\(owner)/\(repo)/contents/\(encodedPath(path))"
        while entries.count < maxResults {
            var components = URLComponents(url: apiURL(basePath), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "ref", value: ref),
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "page", value: "\(page)")
            ]
            let response = try await get(components.url!)
            let items = try parseContentList(response.data)
            entries.append(contentsOf: items)
            if items.count < 100 { break }
            guard hasNextPage(response.httpResponse) else { break }
            page += 1
            if page > 20 { break } // hard pagination bound
        }
        // maxResults cap is reported as [truncated] by the operation handlers.
        return Array(entries.prefix(maxResults))
    }

    private func parseContentList(_ data: Data) throws -> [GitHubContentEntry] {
        guard let obj = try? AssistJSON.parse(data) else {
            throw AssistRemoteFetchError.decodingFailed("directory listing")
        }
        // A path pointing at a file returns a single object, not an array.
        let items = AssistJSON.array(obj) ?? (AssistJSON.object(obj).map { [$0] } ?? [])
        return items.compactMap { item in
            guard let e = AssistJSON.object(item),
                  let name = e["name"] as? String,
                  let path = e["path"] as? String,
                  let type = e["type"] as? String else { return nil }
            return GitHubContentEntry(name: name, path: path, type: type, size: e["size"] as? Int, downloadURL: e["download_url"] as? String)
        }
    }

    private func hasNextPage(_ response: HTTPURLResponse) -> Bool {
        guard let link = response.value(forHTTPHeaderField: "Link") else { return false }
        return link.contains("rel=\"next\"")
    }

    /// File content: Contents API (base64) with a raw-download fallback for
    /// large files the Contents API refuses. Binary files are classified,
    /// never decoded as text.
    func fileContent(owner: String, repo: String, ref: String, path: String, maxBytes: Int) async throws -> AssistGitHubFileContent {
        var components = URLComponents(url: apiURL("/repos/\(owner)/\(repo)/contents/\(encodedPath(path))"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "ref", value: ref)]
        let response = try await get(components.url!)
        guard let obj = try? AssistJSON.parse(response.data), let e = AssistJSON.object(obj) else {
            throw AssistRemoteFetchError.decodingFailed("file content")
        }
        let type = (e["type"] as? String) ?? "file"
        guard type == "file" else {
            throw AssistRemoteFetchError.badStatus(404, "HTTP 404: '\(path)' is not a file.")
        }
        let size = (e["size"] as? Int) ?? 0
        if AssistGitHubRepoTool.isBinaryPath(path) {
            return .binary(size: size, reason: "binary file extension")
        }
        if let encoding = e["encoding"] as? String, encoding == "base64",
           let b64 = e["content"] as? String {
            let cleaned = b64.filter { !$0.isWhitespace }
            guard let data = Data(base64Encoded: cleaned) else {
                throw AssistRemoteFetchError.decodingFailed("base64 file content")
            }
            return classify(data: data, path: path, size: size, maxBytes: maxBytes)
        }
        // Large files: the Contents API omits content — use the raw download.
        if let downloadURLString = e["download_url"] as? String,
           let downloadURL = URL(string: downloadURLString) {
            try AssistURLGuard.validate(downloadURL, allowedHosts: Self.hosts)
            var rawOptions = options(acceptJSON: false)
            rawOptions.maxResponseBytes = max(maxBytes, 1_000_000)
            rawOptions.acceptedContentTypes = []
            let raw = try await Self.client.get(downloadURL, options: rawOptions)
            return classify(data: raw.data, path: path, size: raw.data.count, maxBytes: maxBytes)
        }
        throw AssistRemoteFetchError.decodingFailed("no retrievable content for '\(path)'")
    }

    private func classify(data: Data, path: String, size: Int, maxBytes: Int) -> AssistGitHubFileContent {
        if AssistGitHubRepoTool.isBinaryData(data) {
            return .binary(size: size, reason: "non-text bytes detected")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return .binary(size: size, reason: "not valid UTF-8 text")
        }
        if text.utf8.count > maxBytes {
            // Explicit truncation marker: the byte budget was exceeded.
            return .text(String(text.prefix(maxBytes)) + "\n[truncated: file content exceeded the \(maxBytes)-byte budget]")
        }
        return .text(text)
    }
}

// MARK: - Test hooks (pure logic, no network)

extension AssistGitHubRepoTool {
    static func testResolveRepo(owner: String?, repo: String?, url: String?) throws -> (String, String) {
        let ref = try resolveRepo(owner: owner, repo: repo, urlString: url)
        return (ref.owner, ref.repo)
    }

    static func testValidateOwnerRepo(owner: String, repo: String) -> Bool {
        (try? validateOwnerRepo(owner: owner, repo: repo)) != nil
    }

    static func testIsBinary(path: String, data: Data) -> Bool {
        isBinaryPath(path) || isBinaryData(data)
    }

    static func testPriorityScore(path: String, query: String) -> Int {
        let tokens = query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        return priorityScore(path: path, queryTokens: tokens)
    }

    static func testURLGuardAllows(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return (try? AssistURLGuard.validate(url, allowedHosts: ["api.github.com", "github.com", "raw.githubusercontent.com"])) != nil
    }
}
