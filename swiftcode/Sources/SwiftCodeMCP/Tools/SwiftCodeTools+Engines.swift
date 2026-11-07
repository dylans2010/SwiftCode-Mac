import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwiftCodeAssistant
import SwiftCodeIDECore

extension SwiftCodeMCPHost {
    var engineTools: [MCPTool] {
        let safeMutation = MCPToolAnnotations(readOnly: false, idempotent: true)
        let execution = MCPToolAnnotations(readOnly: false, idempotent: false)
        let external = MCPToolAnnotations(readOnly: false, idempotent: false, openWorld: true)
        let externalRead = MCPToolAnnotations(readOnly: true, idempotent: true, openWorld: true)
        return [
            tool("code_mutation_engine", "Controlled Mutation Engine",
                 "Applies safe, minimal source mutations scoped to a symbol or an exact range.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of the file to mutate."),
                                       "replacement": Schema.string("Replacement source text."),
                                       "symbol": Schema.string("Symbol name whose body will be replaced. Provide either symbol or target."),
                                       "target": Schema.string("Exact text to replace (all occurrences). Provide either symbol or target.")],
                                      required: ["path", "replacement"]),
                 output: Schema.output(["bytes_before": Schema.int, "bytes_after": Schema.int]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.mutateCode(call)
            },
            tool("dependency_resolution_engine", "Dependency Resolution Engine",
                 "Resolves the workspace project's existing Swift Package dependencies via xcodebuild.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "packageURL": Schema.string("Package URL label for the resolution report. The tool resolves the project's existing dependencies; it does not add this package.")],
                                      required: ["packageURL"]),
                 output: Schema.output(["output": Schema.str, "package": Schema.str, "exitCode": Schema.int]),
                 annotations: execution, writes: true) { h, call in
                try await h.resolveDependencies(call)
            },
            tool("external_resource_gateway", "External Resource Gateway",
                 "Fetches external APIs and returns structured JSON response data.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "url": Schema.string("Fully qualified HTTPS URL to fetch. Must return a JSON body. http://, file://, and other schemes are rejected.")],
                                      required: ["url"]),
                 output: Schema.output(["status_code": Schema.int, "json": Schema.str]),
                 annotations: external, writes: true) { h, call in
                try await h.fetchExternalResource(call)
            },
            tool("patch_application_engine", "Patch Application Engine",
                 "Generates and applies line-level patches with integrity validation.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of the file to patch."),
                                       "original": Schema.string("Block that must exist verbatim in the file."),
                                       "updated": Schema.string("Replacement block.")],
                                      required: ["path", "original", "updated"]),
                 output: Schema.output(["diff": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.applyPatch(call)
            },
            tool("fetch_documentation", "Fetch Apple Documentation",
                 "Retrieves real Apple Developer documentation: API references (Swift/ObjC), framework guides, declarations, availability, and code examples from official Apple sources.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "query": Schema.string("Natural-language topic, framework, API symbol, or question. Examples: 'SwiftUI View', 'URLSession', 'AppStorage property wrapper', 'how to request camera permission'."),
                                       "url": Schema.string("Direct Apple Developer documentation URL, e.g. https://developer.apple.com/documentation/swiftui/view."),
                                       "framework": Schema.string("Framework or technology to scope the lookup, e.g. 'SwiftUI', 'Foundation', 'AppKit'."),
                                       "platform": Schema.string("Target platform for availability filtering, e.g. 'iOS', 'macOS', 'watchOS'. Informational: full availability is still reported."),
                                       "language": Schema.string("Preferred declaration language: 'swift' or 'objc'. Defaults to Swift when both exist."),
                                       "includeExamples": Schema.boolean("Include code examples from the documentation. Defaults to true."),
                                       "maxResults": Schema.integer("Maximum documentation pages to return (1-5). Defaults to 3.")]),
                 output: Schema.output(["content": Schema.str, "truncated": Schema.bool, "count": Schema.int]),
                 annotations: externalRead) { h, call in
                try await h.fetchDocumentation(call)
            },
            tool("reverse_analyze", "Reverse Analyze",
                 "Analyze an authorized binary or artifact with the native Reverse subsystem (REA rea-agents@6.5.0, static inspection only). Use when the user invoked @Reverse, or when an investigation needs artifact structure, Mach-O/plist/signature facts, Go/managed metadata, SQLite schema, or objdump output. Never use for circumventing DRM, license checks, anti-cheat, or authentication. targetPath must be an absolute path inside the open project, ~/Downloads, ~/Desktop, or ~/Documents.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "targetPath": Schema.string("Absolute path of the artifact to analyze (must be in scope: open project, ~/Downloads, ~/Desktop, ~/Documents)."),
                                       "operation": Schema.string("Allow-listed operation: inspect_artifact, inspect_macho, inspect_plist, inspect_signature, list_architectures, demangle_swift, inspect_go_binary, inspect_managed_artifact, inspect_managed_members, inspect_sqlite_database, inspect_with_objdump."),
                                       "task": Schema.string("The user's investigation request (what to determine about the artifact)."),
                                       "objdumpOperation": Schema.string("Required for inspect_with_objdump: file_headers, section_headers, symbols, relocations, dwarf, disassemble, disassemble_all."),
                                       "symbol": Schema.string("Swift symbol to demangle (demangle_swift only)."),
                                       "timeoutSeconds": ["type": "number", "description": .string("Timeout in seconds (default 300, clamped to 10...1800).")]],
                                      required: ["targetPath"]),
                 annotations: .read) { h, call in
                try await h.reverseAnalyze(call)
            },
        ]
    }
}

extension SwiftCodeMCPHost {

    func mutateCode(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let path = call.string("path") else {
            throw MCPToolError("Missing path")
        }
        guard let replacement = call.arguments["replacement"]?.string else {
            throw MCPToolError("Missing replacement")
        }
        guard let url = resolveFileWritingPath(path, in: s) else {
            throw MCPToolError("Path not allowed: \(path)")
        }
        let original: String
        do {
            original = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw MCPToolError("Cannot read \(path): \(Self.fileWritingErrorText(error))")
        }
        var updated = original

        if let symbol = call.arguments["symbol"]?.string, !symbol.isEmpty {
            if let range = EnginesMutation.symbolBodyRange(for: symbol, in: original) {
                updated.replaceSubrange(range, with: replacement)
            } else {
                throw MCPToolError("Unable to locate symbol body for: \(symbol)")
            }
        } else if let target = call.arguments["target"]?.string, !target.isEmpty {
            guard updated.contains(target) else {
                throw MCPToolError("Target text not found")
            }
            updated = updated.replacingOccurrences(of: target, with: replacement)
        } else {
            throw MCPToolError("Provide either symbol or target")
        }

        guard updated != original else {
            throw MCPToolError("No mutation produced")
        }
        let rel = relative(url.path, in: s)
        try await commit(MCPChange(tool: call.name, path: url.path, relativePath: rel, original: original, proposed: updated,
                                   summary: "Apply minimal mutation to \(rel)"), call: call, session: s)
        return .structured(["bytes_before": .int(original.count), "bytes_after": .int(updated.count)],
                           summary: "Applied minimal mutation to \(path)")
    }

    func applyPatch(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let path = call.string("path") else {
            throw MCPToolError("Missing path")
        }
        guard let originalBlock = call.arguments["original"]?.string,
              let newBlock = call.arguments["updated"]?.string else {
            throw MCPToolError("Missing patch blocks: original/updated")
        }
        guard let url = resolveFileWritingPath(path, in: s) else {
            throw MCPToolError("Path not allowed: \(path)")
        }
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw MCPToolError("Cannot read \(path): \(Self.fileWritingErrorText(error))")
        }
        guard content.contains(originalBlock) else {
            throw MCPToolError("Patch integrity check failed: original block not found")
        }
        let patched = content.replacingOccurrences(of: originalBlock, with: newBlock)
        let diff = EnginesPatch.unifiedDiff(old: content, new: patched, file: path)
        let rel = relative(url.path, in: s)
        try await commit(MCPChange(tool: call.name, path: url.path, relativePath: rel, original: content, proposed: patched,
                                   summary: "Apply patch to \(rel)"), call: call, session: s)
        return .structured(["diff": .string(diff)], summary: "Patch applied to \(path)")
    }

    func resolveDependencies(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let packageURL = call.string("packageURL") else {
            throw MCPToolError("Missing packageURL")
        }
        #if os(macOS)
        let root = Self.folder(of: s.model)
        guard let located = EnginesXcodeProject.locate(in: root) else {
            throw MCPToolError("No Xcode project (.xcodeproj/.xcworkspace) found in the workspace root; cannot resolve package dependencies.")
        }
        try await terminalApproveChange(tool: call.name,
                                        summary: "Resolve Swift Package dependencies for \(packageURL) (xcodebuild -resolvePackageDependencies)",
                                        in: s, call: call)
        guard FileManager.default.fileExists(atPath: "/usr/bin/xcodebuild") else {
            throw MCPToolError("Failed to run xcodebuild: /usr/bin/xcodebuild was not found.")
        }
        let result = (await Task.detached {
            Self.terminalRunFixed("/usr/bin/xcodebuild",
                                  located.xcodebuildArgs + ["-resolvePackageDependencies"],
                                  workingDirectory: root, timeout: 300)
        }.value)
        guard let result else {
            throw MCPToolError("Failed to run xcodebuild: could not launch /usr/bin/xcodebuild.")
        }
        if result.timedOut {
            throw MCPToolError("xcodebuild -resolvePackageDependencies timed out after 300s (killed).")
        }
        let output = result.stdout + result.stderr
        guard result.exitCode == 0 else {
            throw MCPToolError("Dependency resolution failed (exit code \(result.exitCode)): \(output.suffix(1500))")
        }
        return .structured(["output": .string(output), "package": .string(packageURL), "exitCode": .int(Int(result.exitCode))],
                           summary: "Resolved dependencies for \(packageURL)")
        #else
        _ = packageURL
        throw MCPToolError("Dependency resolution requires macOS runtime")
        #endif
    }

    func fetchExternalResource(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let urlString = call.string("url"), let url = URL(string: urlString) else {
            throw MCPToolError("Missing or invalid url")
        }
        guard url.scheme?.lowercased() == "https", url.host != nil else {
            throw MCPToolError("Only HTTPS URLs with a host are allowed (got '\(urlString)').")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let response: HTTP.Response
        do {
            response = try await HTTP.send(request, timeout: 30)
        } catch {
            throw MCPToolError("Fetch failed: \(error.localizedDescription)")
        }
        guard (200...299).contains(response.status) else {
            throw MCPToolError("HTTP \(response.status) from \(urlString).")
        }
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: response.body)
        } catch {
            throw MCPToolError("Response was not valid JSON: \(error.localizedDescription)")
        }
        let normalized = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
        let payload = String(data: normalized, encoding: .utf8) ?? "{}"
        return .structured(["status_code": .int(response.status), "json": .string(payload)],
                           summary: "Fetched external resource.")
    }
}

extension SwiftCodeMCPHost {

    func fetchDocumentation(_ call: MCPToolCall) async throws -> MCPToolResult {
        let startedAt = Date()
        let rawQuery = (call.arguments["query"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rawURL = (call.arguments["url"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let framework = call.string("framework")
        let platform = call.string("platform")
        let language = ((call.arguments["language"]?.string ?? "swift").trimmingCharacters(in: .whitespacesAndNewlines)).lowercased()
        let includeExamples = call.bool("includeExamples") ?? true
        let maxResults = min(max(call.int("maxResults") ?? 3, 1), 5)

        guard !rawQuery.isEmpty || !rawURL.isEmpty else {
            throw MCPToolError("Provide at least one of 'query' or 'url'.")
        }
        guard ["swift", "objc", "objective-c"].contains(language) else {
            throw MCPToolError("Unsupported language '\(language)'. Use 'swift' or 'objc'.")
        }

        let candidates: [EnginesDocs.Candidate]
        do {
            candidates = try EnginesDocs.resolveCandidates(query: rawQuery, urlString: rawURL, framework: framework)
        } catch let error as EnginesHTTPError {
            throw MCPToolError(fetchDocumentationFailure(error))
        } catch {
            throw MCPToolError("Could not resolve the documentation request: \(error.localizedDescription)")
        }

        var pages: [EnginesDocs.Page] = []
        var tried: [String] = []
        var lastNotFoundDetail: String? = nil

        for candidate in candidates {
            if pages.count >= maxResults { break }
            try Task.checkCancellation()
            tried.append(candidate.canonicalURL.absoluteString)
            do {
                if let page = try await fetchDocumentationCandidate(candidate: candidate, language: language,
                                                                    includeExamples: includeExamples) {
                    pages.append(page)
                } else {
                    lastNotFoundDetail = "No documentation found at \(candidate.canonicalURL.absoluteString)."
                }
            } catch let error as EnginesHTTPError {
                switch error {
                case .timeout:
                    throw MCPToolError("Documentation fetch timed out.")
                case .rateLimited:
                    throw MCPToolError("Apple documentation endpoint rate-limited the request. Try again shortly.")
                default:
                    lastNotFoundDetail = fetchDocumentationFailure(error)
                    continue
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastNotFoundDetail = error.localizedDescription
                continue
            }
        }

        guard !pages.isEmpty else {
            let triedList = tried.joined(separator: "\n- ")
            throw MCPToolError(
                "No Apple documentation found for this request.\nTried:\n- \(triedList)\n\(lastNotFoundDetail ?? "")\nTip: pass the exact documentation 'url' from developer.apple.com, or a 'framework' plus the API symbol name.")
        }

        let rendered = EnginesDocs.render(pages: pages, platform: platform, query: rawQuery.isEmpty ? rawURL : rawQuery)
        let truncated = rendered.count > 20_000
        let output = truncated
            ? String(rendered.prefix(20_000)) + "\n\n[truncated: output exceeded 20,000 characters; narrow the query or request a single url for the full page]"
            : rendered
        let retrieval = pages.map { "\($0.title) [\($0.retrievalMethod)]" }.joined(separator: "; ")
        let duration = String(format: "%.1f", Date().timeIntervalSince(startedAt))
        return .structured(["content": .string(output), "truncated": .bool(truncated), "count": .int(pages.count)],
                           summary: "Retrieved \(pages.count) Apple documentation page(s) via \(retrieval) in \(duration)s.")
    }

    func fetchDocumentationFailure(_ error: EnginesHTTPError) -> String {
        switch error {
        case .invalidURL(let message):
            return "Rejected documentation URL: \(message)"
        case .timeout:
            return "Documentation fetch timed out."
        case .rateLimited:
            return "Apple documentation endpoint rate-limited the request. Try again shortly."
        case .badStatus(let code):
            return "Documentation fetch failed: HTTP \(code)."
        case .tooLarge(let max):
            return "Documentation fetch failed: response exceeded the \(max)-byte cap."
        case .invalidResponse:
            return "Documentation fetch failed: invalid HTTP response."
        case .fetchFailed(let message):
            return "Documentation fetch failed: \(message)"
        }
    }

    func fetchDocumentationCandidate(candidate: EnginesDocs.Candidate, language: String,
                                     includeExamples: Bool) async throws -> EnginesDocs.Page? {
        do {
            if let page = try await fetchDocumentationDocPage(candidate: candidate, language: language,
                                                              includeExamples: includeExamples) {
                return page
            }
        } catch let error as EnginesHTTPError {
            switch error {
            case .badStatus(let code) where code == 404:
                break
            default:
                throw error
            }
        }
        do {
            return try await fetchDocumentationHTMLFallback(candidate: candidate)
        } catch let error as EnginesHTTPError {
            if case .badStatus(let code) = error, code == 404 { return nil }
            throw error
        }
    }

    func fetchDocumentationDocPage(candidate: EnginesDocs.Candidate, language: String,
                                   includeExamples: Bool) async throws -> EnginesDocs.Page? {
        let cacheKey = "docjson:" + candidate.docPath
        let data: Data
        let finalURL: URL
        if let cached = await EnginesDocCache.shared.get(cacheKey) {
            data = cached.data
            finalURL = cached.finalURL
        } else {
            var request = URLRequest(url: candidate.doccJSONURL)
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let fetched = try await EnginesHTTP.fetch(request, maxBytes: 2_000_000, allowedHosts: EnginesDocs.appleHosts)
            guard (200...299).contains(fetched.status) else {
                if fetched.status == 429 { throw EnginesHTTPError.rateLimited }
                throw EnginesHTTPError.badStatus(fetched.status)
            }
            data = fetched.data
            finalURL = fetched.finalURL
            await EnginesDocCache.shared.set(cacheKey, data: data, finalURL: finalURL)
        }
        return EnginesDocs.parseDocCJSON(data: data, canonicalURL: candidate.canonicalURL,
                                         finalJSONURL: finalURL, language: language,
                                         includeExamples: includeExamples)
    }

    func fetchDocumentationHTMLFallback(candidate: EnginesDocs.Candidate) async throws -> EnginesDocs.Page? {
        let cacheKey = "dochtml:" + candidate.docPath
        let html: String
        let finalURL: URL
        if let cached = await EnginesDocCache.shared.get(cacheKey), let text = String(data: cached.data, encoding: .utf8) {
            html = text
            finalURL = cached.finalURL
        } else {
            var request = URLRequest(url: candidate.canonicalURL)
            request.timeoutInterval = 30
            request.setValue("text/html", forHTTPHeaderField: "Accept")
            let fetched = try await EnginesHTTP.fetch(request, maxBytes: 1_000_000, allowedHosts: EnginesDocs.appleHosts)
            guard (200...299).contains(fetched.status) else {
                if fetched.status == 429 { throw EnginesHTTPError.rateLimited }
                throw EnginesHTTPError.badStatus(fetched.status)
            }
            guard let text = String(data: fetched.data, encoding: .utf8) else { return nil }
            html = text
            finalURL = fetched.finalURL
            await EnginesDocCache.shared.set(cacheKey, data: fetched.data, finalURL: finalURL)
        }
        let title = EnginesDocs.htmlTitle(html) ?? finalURL.lastPathComponent
        let description = EnginesDocs.htmlMetaDescription(html) ?? ""
        let bodyText = EnginesDocs.htmlBodyText(html)
        let discussion = [description, bodyText].filter { !$0.isEmpty }.joined(separator: "\n\n")
        guard !title.isEmpty, !discussion.isEmpty else { return nil }
        return EnginesDocs.Page(
            title: title,
            canonicalURL: finalURL,
            retrievalMethod: "html-fallback",
            abstract: description,
            declarations: [],
            availability: [],
            discussion: String(discussion.prefix(6000)),
            examples: [],
            relatedLinks: []
        )
    }

    func reverseAnalyze(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let operationRaw = (call.arguments["operation"]?.string ?? EnginesReverseOperation.inspectArtifact.rawValue)
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let operation = EnginesReverseOperation(rawValue: operationRaw) else {
            throw MCPToolError("Unsupported Reverse operation '\(operationRaw)'. Allow-listed: \(EnginesReverseOperation.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        let task = call.arguments["task"]?.string ?? ""
        if let refusal = EnginesReverseValidator.refusalMessage(forTask: task) {
            throw MCPToolError(refusal)
        }
        let targetPath: String
        switch EnginesReverseValidator.validateTarget(path: call.arguments["targetPath"]?.string,
                                                      workspaceRoot: Self.folder(of: s.model)) {
        case .success(let validated):
            targetPath = validated
        case .failure(let error):
            throw MCPToolError(error.message)
        }
        if operation == .inspectWithObjdump {
            let raw = (call.arguments["objdumpOperation"]?.string ?? EnginesReverseObjdumpOperation.fileHeaders.rawValue)
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard EnginesReverseObjdumpOperation(rawValue: raw) != nil else {
                throw MCPToolError("Invalid objdumpOperation '\(raw)'. Fixed choices: \(EnginesReverseObjdumpOperation.allCases.map(\.rawValue).joined(separator: ", ")).")
            }
        }
        let symbol = call.string("symbol")
        let timeout = EnginesReverseValidator.clampTimeout(call.arguments["timeoutSeconds"])
        let objdumpOp: String? = operation == .inspectWithObjdump
            ? (call.arguments["objdumpOperation"]?.string ?? EnginesReverseObjdumpOperation.fileHeaders.rawValue)
            : nil
        let evidence = try await reverseBridgeAnalyze(operation: operation.rawValue, targetPath: targetPath,
                                                      objdumpOperation: objdumpOp, symbol: symbol, timeout: timeout)
        let markdown = Self.reverseRenderEvidence(evidence)
        let (capped, _) = Self.terminalCappedOutput(markdown)
        let evidenceID = evidence["evidence_id"] as? String ?? ""
        let provider = evidence["provider"] as? String ?? "rea-agents@\(Self.reversePinnedREAVersion)"
        let confidence: AnyJSON
        if let c = evidence["confidence"] as? Double { confidence = .double(c) }
        else if let c = evidence["confidence"] as? Int { confidence = .int(c) }
        else { confidence = .null }
        return .structured(["evidence_id": .string(evidenceID), "operation": .string(operation.rawValue),
                            "provider": .string(provider), "confidence": confidence,
                            "subject_digest": .string(evidence["subject_digest"] as? String ?? "")],
                           summary: capped)
    }
}
