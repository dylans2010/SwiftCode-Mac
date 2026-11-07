import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwiftCodeAssistant
import SwiftCodeGitHub
import SwiftCodeIDECore

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

    nonisolated static let agenticNetworkTextCap = 2_000_000

    nonisolated static let agenticNetworkFileCap = 10_000_000

    nonisolated static func agenticNetworkHTTPSURL(_ raw: String) throws -> URL {
        guard let url = URL(string: raw), url.scheme?.lowercased() == "https", url.host != nil else {
            throw MCPToolError("Only HTTPS URLs with a host are allowed (got '\(raw)').")
        }
        return url
    }

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

    func agenticNetworkDependencyAudit(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard call.string("projectPath") != nil else {
            throw MCPToolError("Missing projectPath")
        }
        return try await dependencyAudit(call)
    }

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
        guard let run = (await Task.detached {
            Self.terminalRunFixed("/usr/bin/swift", ["package", subcommand], workingDirectory: dir, timeout: 300)
        }.value) else {
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

    nonisolated static func agenticNetworkIssueJSON(_ issue: GitHubIssue) -> AnyJSON {
        ["number": .int(issue.number), "title": .string(issue.title), "state": .string(issue.state),
         "url": .string(issue.htmlUrl)]
    }

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
        for array in agenticNetworkDependenciesArrays(in: content).dropFirst().reversed() {
            let targetElements = agenticNetworkArrayElements(in: content, arrayRange: array)
            for idx in targetElements.indices.reversed()
            where agenticNetworkProductReference(String(content[targetElements[idx].element]), matches: name) {
                agenticNetworkRemoveArrayElement(at: idx, elements: targetElements, in: &content)
            }
        }
        return true
    }

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
