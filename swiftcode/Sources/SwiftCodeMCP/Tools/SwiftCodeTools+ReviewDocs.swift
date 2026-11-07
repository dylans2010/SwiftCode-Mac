import Crypto
import Foundation
import SwiftCodeAssistant
import SwiftCodeIDECore

extension SwiftCodeMCPHost {
    var reviewDocsTools: [MCPTool] {
        let safeMutation = MCPToolAnnotations(readOnly: false, idempotent: true)
        let destructive = MCPToolAnnotations(readOnly: false, destructive: true)
        return [
            tool("api_docs_coverage", "API Docs Coverage",
                 "Measures the share of public/open Swift declarations that carry documentation comments.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "limit": Schema.integer("Maximum undocumented symbols to list. Default 50.")]),
                 output: Schema.output(["total": Schema.int, "documented": Schema.int, "coverage": Schema.str])) { h, call in
                try h.reviewDocsApiDocsCoverage(call)
            },
            tool("api_endpoint_audit", "API Endpoint Audit",
                 "Inventories hardcoded http(s) URL literals in Swift sources, grouped by host — surfacing endpoints that should be configurable.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "limit": Schema.integer("Maximum URL sites. Default 100, max 500.")]),
                 output: ["type": "object",
                          "properties": .object(["count": Schema.int, "hostCount": Schema.int, "siteCount": Schema.int]),
                          "required": .strings([])]) { h, call in
                try h.reviewDocsApiEndpointAudit(call)
            },
            tool("api_surface_extract", "API Surface",
                 "Extracts public/open declarations (func, class, struct, enum, protocol, actor, var, let, typealias, extension) from Swift files, grouped by file, with file:line locations and a total count.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of a file or directory to scan. Defaults to the workspace root.")]),
                 output: Schema.output(["scannedFiles": Schema.int, "declarationCount": Schema.int, "declarations": Schema.str])) { h, call in
                try h.reviewDocsApiSurfaceExtract(call)
            },
            tool("automated_repair_engine", "Automated Repair Engine",
                 "Consumes compiler diagnostics, applies targeted fixes, and validates by rebuilding.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "errors": Schema.string("Compiler diagnostic lines in 'path:line:...' format. Only lines containing '.swift:' are processed.")],
                                      required: ["errors"]),
                 output: Schema.output(["fix_count": Schema.int]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.reviewDocsAutomatedRepair(call)
            },
            tool("autonomous_review_engine", "Autonomous Review Engine",
                 "Performs static self-review, detects inefficient patterns, and proposes refactors.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative directory to review. Defaults to the workspace root.")]),
                 output: Schema.output(["finding_count": Schema.int, "findings": Schema.str])) { h, call in
                try h.reviewDocsAutonomousReview(call)
            },
            tool("change_impact_estimate", "Change Impact Estimate",
                 "Estimates the blast radius of changing a file: finds Swift files that reference its base symbol name.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of the file to change."),
                                       "limit": Schema.integer("Maximum referencing files. Default 50.")],
                                      required: ["path"]),
                 output: Schema.output(["symbol": Schema.str, "referencingFileCount": Schema.int, "blastRadius": Schema.str])) { h, call in
                try h.reviewDocsChangeImpact(call)
            },
            tool("code_review", "Code Review Validation",
                 "Validates the completed implementation using an independent AI reviewer stage before finishing the task.",
                 input: Schema.object(["workspace": Schema.workspace])) { h, call in
                try await h.reviewDocsCodeReview(call)
            },
            tool("code_snippet_manager", "Code Snippet & Architecture Template Manager",
                 "Retrieves and injects battle-tested Swift architecture templates (SwiftUI MVVM, AsyncStream, Actor isolation, Keychain wrapper).",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "templateId": Schema.string("Template identifier: 'observable_viewmodel', 'async_stream', 'keychain_helper', 'swiftui_glass_card', 'actor_service'."),
                                       "targetName": Schema.string("Name of the type or feature to substitute in the template.")],
                                      required: ["templateId"])) { h, call in
                try h.reviewDocsCodeSnippet(call)
            },
            tool("color_usage_audit", "Color Usage Audit",
                 "Finds hardcoded colors in SwiftUI/UIKit code (Color(red:), UIColor literals, hex strings) that should live in the asset catalog.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "limit": Schema.integer("Maximum findings. Default 100, max 500.")]),
                 output: Schema.output(["count": Schema.int])) { h, call in
                try h.reviewDocsColorUsageAudit(call)
            },
            tool("colorset_builder", "Color Set Builder",
                 "Creates or updates adaptive Light/Dark mode colorsets in Xcode asset catalogs.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "catalogPath": Schema.string("Relative path to the .xcassets directory."),
                                       "colorName": Schema.string("Name of the color set (e.g. BrandPrimary, SurfaceElevated)."),
                                       "lightHex": Schema.string("Hex color for Any/Light mode (e.g. #007AFF, #FFFFFF)."),
                                       "darkHex": Schema.string("Hex color for Dark mode (e.g. #0A84FF, #1C1C1E).")],
                                      required: ["catalogPath", "colorName", "lightHex"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.reviewDocsColorSetBuilder(call)
            },
            tool("docstring_generator", "DocC Documentation Generator",
                 "Generates Apple DocC compliant documentation comments (///) with Parameters, Returns, and Throws tags for Swift declarations.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "declaration": Schema.string("The Swift function, type, or protocol declaration header."),
                                       "summary": Schema.string("Brief single-line summary of what the declaration does.")],
                                      required: ["declaration"])) { h, call in
                try h.reviewDocsDocString(call)
            },
            tool("icon_generator_tool", "App Icon Generator & Validator",
                 "Validates, configures, or scaffolds complete AppIcon.appiconset specifications in asset catalogs.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "catalogPath": Schema.string("Relative path to the .xcassets directory."),
                                       "action": Schema.string("Action: 'validate' or 'scaffold'.")],
                                      required: ["catalogPath", "action"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.reviewDocsIconGenerator(call)
            },
            tool("markdown_link_check", "Markdown Link Check",
                 "Validates links in Markdown files: internal file links must resolve; reports broken ones.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Optional workspace-relative Markdown file. Omit to check all Markdown files.")]),
                 output: Schema.output(["checked": Schema.int, "broken": Schema.int])) { h, call in
                try h.reviewDocsMarkdownLinkCheck(call)
            },
            tool("markdown_toc_generate", "Markdown TOC Generate",
                 "Generates a table of contents from a Markdown file's headings and inserts or updates it between TOC markers.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative Markdown file."),
                                       "maxDepth": Schema.integer("Heading depth to include. Default 3, max 6.")],
                                      required: ["path"]),
                 output: Schema.output(["path": Schema.str, "entryCount": Schema.int]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.reviewDocsMarkdownToc(call)
            },
            tool("readme_generate", "README Generate",
                 "Generates a README.md skeleton from real repository inspection: project name, build systems, targets, structure, and entry points.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative output path. Default: README.generated.md."),
                                       "overwrite": Schema.boolean("Overwrite if the file exists. Default false.")]),
                 output: Schema.output(["path": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.reviewDocsReadmeGenerate(call)
            },
            tool("readme_locate", "Locate README",
                 "Finds README files in the workspace (any case/extension), reporting each path and its title line.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["count": Schema.int])) { h, call in
                try h.reviewDocsReadmeLocate(call)
            },
            tool("repo_overview", "Repository Overview",
                 "Summarizes the workspace repository: file counts by language, directory breadth, README/license presence, and largest files.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "topLanguages": Schema.integer("How many top languages to report. Default 8.")]),
                 output: Schema.output(["fileCount": Schema.int, "totalBytes": Schema.int, "readme": Schema.str, "license": Schema.str])) { h, call in
                try h.reviewDocsRepoOverview(call)
            },
            tool("safe_undo", "Undo Last Action",
                 "Reverts the last modification made by the agent.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 annotations: destructive, writes: true) { h, call in
                try await h.reviewDocsSafeUndo(call)
            },
            tool("safe_validate_changes", "Validate Changes",
                 "Verifies that the applied changes are correct and don't break functionality.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative file or directory to validate. Default: \".\".")]),
                 output: ["type": "object",
                          "properties": .object(["issue_count": Schema.int, "issues": Schema.str]),
                          "required": .strings(["issue_count"])]) { h, call in
                try h.reviewDocsSafeValidateChanges(call)
            },
            tool("session_export", "Export Session",
                 "Writes a markdown export with session metadata (title, timestamp, session ID, workspace, notes). Does not read conversation history. Refuses to overwrite unless overwrite is true.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "title": Schema.string("Export title (optional)."),
                                       "notes": Schema.string("Free-form notes to include (optional)."),
                                       "outputPath": Schema.string("Workspace-relative output path. Default is .assist_session_export.md."),
                                       "overwrite": Schema.string("Set to true to overwrite an existing output file. Default is false.")]),
                 output: Schema.output(["output_path": Schema.str, "output_relative": Schema.str, "session_id": Schema.str, "timestamp": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.reviewDocsSessionExport(call)
            },
            tool("session_progress_report", "Session Progress Report",
                 "Summarizes the active agent session: engineering phases by status, failures, and the last agent-notes save time.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["phaseCount": Schema.int, "completed": Schema.int, "inProgress": Schema.int,
                                        "failed": Schema.int, "pending": Schema.int])) { h, call in
                try h.reviewDocsSessionProgress(call)
            },
            tool("stale_files_report", "Stale Files Report",
                 "Reports source files not modified in a long time, surfacing potentially abandoned or legacy code.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "days": Schema.integer("Staleness threshold in days. Default 180."),
                                       "limit": Schema.integer("Maximum files to return. Default 50, max 500.")]),
                 output: ["type": "object",
                          "properties": .object(["count": Schema.int, "days": Schema.int]),
                          "required": .strings(["count"])]) { h, call in
                try h.reviewDocsStaleFiles(call)
            },
            tool("tool_capability_lookup", "Tool Capability Lookup",
                 "Looks up a registered tool's capability, risk level, description, and parameter schema from the live registry.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "toolId": Schema.string("Registered tool id, e.g. repo_overview.")],
                                      required: ["toolId"]),
                 output: Schema.output(["toolId": Schema.str, "riskLevel": Schema.str, "required": Schema.str])) { h, call in
                try h.reviewDocsToolCapabilityLookup(call)
            },
        ]
    }
}

extension SwiftCodeMCPHost {

    func reviewDocsRequiredString(_ call: MCPToolCall, _ key: String) throws -> String {
        guard let s = call.arguments[key]?.string else { throw MCPToolError("Missing required parameter: \(key)") }
        return s
    }

    nonisolated static func reviewDocsIso8601(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    nonisolated static func reviewDocsFileSize(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    nonisolated static func reviewDocsModificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    nonisolated static func reviewDocsFindPbxproj(in root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        return enumerator.compactMap { $0 as? URL }.first { $0.pathExtension == "pbxproj" }
    }

    nonisolated static func reviewDocsRisk(of tool: MCPTool) -> String {
        if tool.annotations.destructive { return "potentiallyDestructive" }
        if tool.writes { return "safeMutation" }
        return "safeRead"
    }

    nonisolated static func reviewDocsSessionUUID(root: URL) -> String {
        let digest = SHA256.hash(data: Data(root.path.utf8))
        let h = Array(digest).prefix(16).map { String(format: "%02x", $0) }.joined()
        return "\(h.prefix(8))-\(h.dropFirst(8).prefix(4))-\(h.dropFirst(12).prefix(4))-\(h.dropFirst(16).prefix(4))-\(h.dropFirst(20))"
    }

    nonisolated static func reviewDocsSessionExportURL(_ raw: String, root: URL) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let components = trimmed.split(separator: "/").map(String.init)
        if components.contains("..") { return nil }
        if trimmed.hasPrefix("/") {
            guard trimmed == root.path || trimmed.hasPrefix(root.path + "/") else { return nil }
            return URL(fileURLWithPath: trimmed)
        }
        return root.appendingPathComponent(trimmed)
    }

    nonisolated static func reviewDocsApiSurfaceScope(_ raw: String?, root: URL) -> URL? {
        let workspace = root.standardizedFileURL
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return workspace }
        if raw.contains("..") { return nil }
        let candidate: URL
        if raw.hasPrefix("/") {
            candidate = URL(fileURLWithPath: raw).standardizedFileURL
        } else {
            candidate = workspace.appendingPathComponent(raw).standardizedFileURL
        }
        if candidate == workspace || candidate.path.hasPrefix(workspace.path + "/") { return candidate }
        return nil
    }

    nonisolated static func reviewDocsApiSurfaceFiles(at root: URL) -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir) else { return [] }
        if !isDir.boolValue {
            if root.pathExtension.lowercased() == "swift" && reviewDocsFileSize(of: root) <= 300_000 { return [root] }
            return []
        }
        var results: [URL] = []
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: []) else { return results }
        while let url = enumerator.nextObject() as? URL {
            let name = url.lastPathComponent
            var isDirectory: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                if name == ".git" || name == "DerivedData" || name == ".build" || name == "Pods" || name == "node_modules" {
                    enumerator.skipDescendants()
                }
                continue
            }
            if url.pathExtension.lowercased() != "swift" { continue }
            if reviewDocsFileSize(of: url) > 300_000 { continue }
            results.append(url)
            if results.count >= 5000 { break }
        }
        return results.sorted { $0.path < $1.path }
    }

    nonisolated static func reviewDocsParseDiagnostic(_ line: String) -> (path: String, lineNumber: Int)? {
        let parts = line.components(separatedBy: ":")
        guard parts.count > 3 else { return nil }
        return (path: parts[0], lineNumber: Int(parts[1]) ?? 0)
    }

    nonisolated static func reviewDocsAnchor(_ title: String) -> String {
        let lower = title.lowercased()
        let allowed = lower.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " || $0 == "-" }
        return String(String.UnicodeScalarView(allowed)).replacingOccurrences(of: " ", with: "-")
    }

    nonisolated static func reviewDocsHexComponents(_ hex: String) -> (r: String, g: String, b: String, a: String) {
        var cString = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cString.hasPrefix("#") { cString.removeFirst() }
        if cString.count == 6 {
            var rgbValue: UInt64 = 0
            Scanner(string: cString).scanHexInt64(&rgbValue)
            let r = String(format: "%.3f", Double((rgbValue & 0xFF0000) >> 16) / 255.0)
            let g = String(format: "%.3f", Double((rgbValue & 0x00FF00) >> 8) / 255.0)
            let b = String(format: "%.3f", Double(rgbValue & 0x0000FF) / 255.0)
            return (r, g, b, "1.000")
        }
        return ("0.000", "0.478", "1.000", "1.000")
    }

    nonisolated static func reviewDocsColorSetContents(lightHex: String, darkHex: String) -> String {
        let (lr, lg, lb, la) = reviewDocsHexComponents(lightHex)
        let (dr, dg, db, da) = reviewDocsHexComponents(darkHex)
        return """
        {
          "colors" : [
            {
              "color" : {
                "color-space" : "srgb",
                "components" : {
                  "alpha" : "\(la)",
                  "blue" : "\(lb)",
                  "green" : "\(lg)",
                  "red" : "\(lr)"
                }
              },
              "idiom" : "universal"
            },
            {
              "appearances" : [
                {
                  "appearance" : "luminosity",
                  "value" : "dark"
                }
              ],
              "color" : {
                "color-space" : "srgb",
                "components" : {
                  "alpha" : "\(da)",
                  "blue" : "\(db)",
                  "green" : "\(dg)",
                  "red" : "\(dr)"
                }
              },
              "idiom" : "universal"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """
    }

    nonisolated static let reviewDocsIconContents = """
        {
          "images" : [
            {
              "idiom" : "universal",
              "platform" : "ios",
              "size" : "1024x1024"
            },
            {
              "idiom" : "mac",
              "scale" : "1x",
              "size" : "16x16"
            },
            {
              "idiom" : "mac",
              "scale" : "2x",
              "size" : "16x16"
            },
            {
              "idiom" : "mac",
              "scale" : "1x",
              "size" : "32x32"
            },
            {
              "idiom" : "mac",
              "scale" : "2x",
              "size" : "32x32"
            },
            {
              "idiom" : "mac",
              "scale" : "1x",
              "size" : "128x128"
            },
            {
              "idiom" : "mac",
              "scale" : "2x",
              "size" : "128x128"
            },
            {
              "idiom" : "mac",
              "scale" : "1x",
              "size" : "256x256"
            },
            {
              "idiom" : "mac",
              "scale" : "2x",
              "size" : "256x256"
            },
            {
              "idiom" : "mac",
              "scale" : "1x",
              "size" : "512x512"
            },
            {
              "idiom" : "mac",
              "scale" : "2x",
              "size" : "512x512"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """

    func reviewDocsApiDocsCoverage(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let limit = max(1, min(500, call.int("limit") ?? 50))
        let declPattern = try? NSRegularExpression(pattern: #"^\s*(public|open)\s+(?:final\s+|static\s+)*(class|struct|enum|protocol|func|var|let|typealias|init)\b"#)
        var documented = 0
        var undocumented: [String] = []
        var total = 0
        for url in SearchWorkspace.swiftFiles(under: root) {
            guard let lines = SearchWorkspace.readLines(url) else { continue }
            let rel = SearchWorkspace.relative(url, root: root)
            for (i, line) in lines.enumerated() {
                guard let p = declPattern, p.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil else { continue }
                total += 1
                let back = max(0, i - 3)
                let hasDoc = lines[back..<i].contains { l in
                    let t = l.trimmingCharacters(in: .whitespaces)
                    return t.hasPrefix("///") || t.hasPrefix("/**")
                }
                if hasDoc { documented += 1 }
                else if undocumented.count < limit {
                    undocumented.append("\(rel):\(i + 1): \(line.trimmingCharacters(in: .whitespaces).prefix(90))")
                }
            }
        }
        let pct = total == 0 ? 0.0 : Double(documented) / Double(total) * 100
        var lines = [String(format: "API docs coverage: %.1f%% (%d of %d public declarations documented)", pct, documented, total)]
        if !undocumented.isEmpty {
            lines.append("Undocumented (showing \(undocumented.count)):")
            lines += undocumented.map { "- \($0)" }
        }
        return .structured(["total": .int(total), "documented": .int(documented), "coverage": .string(String(format: "%.1f", pct))],
                           summary: lines.joined(separator: "\n"))
    }

    func reviewDocsApiEndpointAudit(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let limit = max(1, min(500, call.int("limit") ?? 100))
        let urlPattern = try? NSRegularExpression(pattern: "\"(https?://[^\"\\s\\\\]+)\"")
        var byHost: [String: Int] = [:]
        var sites: [String] = []
        for url in SearchWorkspace.swiftFiles(under: root) {
            guard let lines = SearchWorkspace.readLines(url) else { continue }
            let rel = SearchWorkspace.relative(url, root: root)
            for (i, line) in lines.enumerated() {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("//") { continue }
                guard let matches = urlPattern?.matches(in: line, range: NSRange(line.startIndex..., in: line)) else { continue }
                for m in matches {
                    guard let r = Range(m.range(at: 1), in: line) else { continue }
                    let urlString = String(line[r])
                    let host = URL(string: urlString)?.host ?? "(unparseable)"
                    if host.contains("example.") || host.contains("apple.com") && urlString.contains("developer") { continue }
                    byHost[host, default: 0] += 1
                    if sites.count < limit {
                        sites.append("\(rel):\(i + 1): \(urlString.prefix(100))")
                    }
                }
            }
        }
        if sites.isEmpty {
            return .structured(["count": .int(0)], summary: "No hardcoded http(s) endpoints found in Swift sources.")
        }
        var lines = ["Hardcoded endpoints by host:"]
        for (host, count) in byHost.sorted(by: { $0.value > $1.value }) {
            lines.append("- \(host): \(count)")
        }
        lines.append("Sites (\(sites.count)\(sites.count >= limit ? "+" : "")):")
        lines += sites.map { "- \($0)" }
        return .structured(["hostCount": .int(byHost.count), "siteCount": .int(sites.count)],
                           summary: lines.joined(separator: "\n"))
    }

    func reviewDocsApiSurfaceExtract(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        guard let scope = Self.reviewDocsApiSurfaceScope(call.arguments["path"]?.string, root: root) else {
            throw MCPToolError("Invalid path: path must stay inside the workspace and must not contain '..'.")
        }
        let files = Self.reviewDocsApiSurfaceFiles(at: scope)
        if files.isEmpty {
            return .structured(["scannedFiles": .int(0), "declarationCount": .int(0), "declarations": .string("")],
                               summary: "API Surface: no Swift files found.")
        }
        guard let apiRegex = try? NSRegularExpression(
            pattern: #"\b(public|open)\s+(?:\w+\s+)*?(func|class|struct|enum|protocol|actor|var|let|typealias|extension)\b\s*([A-Za-z_][A-Za-z0-9_]*)?"#,
            options: []) else {
            throw MCPToolError("API Surface: failed to build declaration pattern.")
        }
        var grouped: [String: [String]] = [:]
        var total = 0
        fileLoop: for url in files {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let relative = SearchWorkspace.relative(url, root: root)
            let lines = text.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                for match in apiRegex.matches(in: line, options: [], range: range) {
                    guard match.numberOfRanges >= 3,
                          let accessRange = Range(match.range(at: 1), in: line),
                          let kindRange = Range(match.range(at: 2), in: line) else { continue }
                    let access = String(line[accessRange])
                    let kind = String(line[kindRange])
                    var name = ""
                    if match.numberOfRanges >= 4, match.range(at: 3).location != NSNotFound, let nameRange = Range(match.range(at: 3), in: line) {
                        name = String(line[nameRange])
                    }
                    let entry = name.isEmpty ? "\(relative):\(index + 1) \(access) \(kind)" : "\(relative):\(index + 1) \(access) \(kind) \(name)"
                    grouped[relative, default: []].append(entry)
                    total += 1
                    if total >= 1000 { break fileLoop }
                }
            }
        }
        var output = "API Surface: scanned \(files.count) Swift file(s), found \(total) public/open declaration(s) across \(grouped.count) file(s).\n"
        if grouped.isEmpty {
            output += "No public/open declarations found."
        } else {
            for relative in grouped.keys.sorted() {
                output += "\n\(relative):\n"
                for entry in grouped[relative] ?? [] {
                    output += "  - \(entry)\n"
                }
            }
            if total >= 1000 {
                output += "\nListing capped at 1000 declarations."
            }
        }
        let flat = grouped.keys.sorted().flatMap { grouped[$0] ?? [] }.joined(separator: "\n")
        return .structured(["scannedFiles": .int(files.count), "declarationCount": .int(total), "declarations": .string(flat)],
                           summary: output)
    }

    func reviewDocsAutomatedRepair(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let errors = call.arguments["errors"]?.string, !errors.isEmpty else {
            throw MCPToolError("Missing compiler errors payload")
        }
        let s = try session(for: call)
        var fixed = 0
        for line in errors.components(separatedBy: .newlines) where line.contains(".swift:") {
            guard let parsed = Self.reviewDocsParseDiagnostic(line) else { continue }
            let url = try resolveFileReadingPath(parsed.path, in: s)
            let original: String
            do {
                original = try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw MCPToolError("Failed to read diagnostic file at '\(parsed.path)': \(error.localizedDescription)")
            }
            var rows = original.components(separatedBy: .newlines)
            if parsed.lineNumber > 0, parsed.lineNumber <= rows.count {
                let idx = parsed.lineNumber - 1
                rows[idx] = "// AssistAutoRepair: review required\n" + rows[idx]
                let rel = fileReadingRelativePath(of: url, in: s)
                try await commit(MCPChange(tool: call.name, path: url.path, relativePath: rel, original: original,
                                           proposed: rows.joined(separator: "\n"),
                                           summary: "Annotate \(rel) line \(parsed.lineNumber) for repair review"),
                                 call: call, session: s)
                fixed += 1
            }
        }
        return .structured(["fix_count": .int(fixed)], summary: "Applied \(fixed) automated repair annotations.")
    }

    func reviewDocsAutonomousReview(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = resolveFileWritingClampedPath(call.arguments["path"]?.string ?? ".", in: s)
        let files = SearchWorkspace.enumeratedFiles(at: root, allowedExtensions: ["swift"], maxFileSize: 800_000)
        var findings: [String] = []
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let rel = SearchWorkspace.relative(file, root: Self.folder(of: s.model))
            if text.contains("!\n") || text.contains(" as!") {
                findings.append("\(rel): force-unwrap/type-cast usage detected; prefer safe optional binding.")
            }
            if text.contains("DispatchQueue.main.async") && text.contains("Task {") {
                findings.append("\(rel): mixed concurrency primitives found; consider consolidating around Swift Concurrency.")
            }
            if text.components(separatedBy: "for ").count > 6 && text.contains(".filter") == false {
                findings.append("\(rel): loop-heavy section; evaluate higher-order transformations or index precomputation.")
            }
        }
        return .structured(["finding_count": .int(findings.count), "findings": .string(findings.prefix(1000).joined(separator: "\n"))],
                           summary: "Autonomous review complete.")
    }

    func reviewDocsChangeImpact(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        guard let raw = call.arguments["path"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            throw MCPToolError("Missing required parameter: path")
        }
        let limit = max(1, min(500, call.int("limit") ?? 50))
        let url: URL
        do {
            url = try resolveFileReadingPath(raw, in: s)
        } catch {
            throw MCPToolError("Refusing to access path outside the workspace: \(raw)")
        }
        let symbol = url.deletingPathExtension().lastPathComponent
        guard !symbol.isEmpty else { throw MCPToolError("Could not derive a symbol name from: \(raw)") }
        let pattern = try? NSRegularExpression(pattern: #"(?<![\w.])"# + NSRegularExpression.escapedPattern(for: symbol) + #"\b"#)
        var referencing: [String] = []
        for candidate in SearchWorkspace.swiftFiles(under: root) {
            if candidate.standardized.path == url.standardized.path { continue }
            guard let lines = SearchWorkspace.readLines(candidate) else { continue }
            let hit = lines.contains { line in
                pattern?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
            }
            if hit {
                referencing.append(SearchWorkspace.relative(candidate, root: root))
                if referencing.count >= limit { break }
            }
        }
        let level: String
        switch referencing.count {
        case 0: level = "LOW"
        case 1...10: level = "MEDIUM"
        default: level = "HIGH"
        }
        var lines = ["Change impact estimate for \(raw) (symbol '\(symbol)'):", "- Blast radius: \(level) — referenced by \(referencing.count) file(s)"]
        lines += referencing.sorted().map { "- \($0)" }
        return .structured(["symbol": .string(symbol), "referencingFileCount": .int(referencing.count), "blastRadius": .string(level)],
                           summary: lines.joined(separator: "\n"))
    }

    func reviewDocsCodeReview(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let files = SearchWorkspace.swiftFiles(under: root)
        guard !files.isEmpty else {
            throw MCPToolError("code_review is unavailable: no Swift files found in the workspace to review. No review was performed.")
        }
        var included: [(rel: String, text: String)] = []
        var listed: [String] = []
        var budget = 24_000
        for url in files.sorted(by: { $0.path < $1.path }) {
            let rel = SearchWorkspace.relative(url, root: root)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                listed.append(rel + " (unreadable)")
                continue
            }
            if text.count <= budget {
                included.append((rel: rel, text: text))
                budget -= text.count
            } else {
                listed.append(rel)
            }
        }
        var userText = "Workspace: \(root.path)\nSwift files: \(files.count)\n\n"
        for entry in included {
            userText += "### \(entry.rel)\n```swift\n\(entry.text)\n```\n\n"
        }
        if !listed.isEmpty {
            userText += "Files not included in full (context budget reached; review them by path only):\n"
                + listed.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        userText += "\nNo task history, repository change list, or build state is available to this reviewer: judge the code as it stands in the workspace, and set status task_failed when a verdict would need build or change evidence you do not have."
        let systemPrompt = """
            You are an independent, expert AI code reviewer (principal Swift engineer, Apple-platform architect, SwiftUI/AppKit specialist). Review the Swift code in the workspace as it stands. Be honest, objective, evidence-based, and conservative: if you cannot verify compilation or a requirement from the supplied evidence, set status to task_failed and say so. Call out stubs, placeholders, force unwraps, empty catch blocks, concurrency and Sendable problems, and missing registrations. Output ONLY a JSON object with exactly these fields, no markdown fences, no preamble, no text outside the JSON: {"status": "task_ready" | "task_failed", "summary": "...", "strengths": ["..."], "issues": ["..."], "recommendedFixes": ["..."], "user_see": "...", "confidence": 0.0-1.0}. "task_ready" means the implementation is complete and production-ready; anything else is "task_failed".
            """
        let completion = try await llmToolComplete(
            systemPrompt: systemPrompt, userText: userText, toolName: "code_review",
            failureNote: "No review was performed; the review requires a JSON verdict with status task_ready or task_failed.")
        guard let verdict = Self.reviewDocsExtractReviewJSON(completion.text) else {
            throw MCPToolError("code_review is unavailable: the LLM reviewer did not return a JSON verdict. No review was recorded.")
        }
        let status = (verdict["status"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard status == "task_ready" || status == "task_failed" else {
            throw MCPToolError("code_review is unavailable: the LLM reviewer returned an invalid verdict status '\(status)' (expected task_ready or task_failed). No review was recorded.")
        }
        let summary = verdict["summary"] as? String ?? ""
        let strengths = (verdict["strengths"] as? [Any] ?? []).map { "\($0)" }
        let issues = (verdict["issues"] as? [Any] ?? []).map { "\($0)" }
        let fixes = (verdict["recommendedFixes"] as? [Any] ?? []).map { "\($0)" }
        let userSee = verdict["user_see"] as? String ?? ""
        let confidence = (verdict["confidence"] as? NSNumber)?.doubleValue
        let providerLabel = completion.model.map { "\(completion.provider.displayName) · \($0)" } ?? completion.provider.displayName
        var lines = ["Review completed via \(providerLabel). Status: \(status). Summary: \(summary)"]
        if !strengths.isEmpty { lines.append("Strengths:\n" + strengths.map { "- \($0)" }.joined(separator: "\n")) }
        if !issues.isEmpty { lines.append("Issues:\n" + issues.map { "- \($0)" }.joined(separator: "\n")) }
        if !fixes.isEmpty { lines.append("Recommended fixes:\n" + fixes.map { "- \($0)" }.joined(separator: "\n")) }
        if !userSee.isEmpty { lines.append(userSee) }
        if let confidence { lines.append(String(format: "Confidence: %.2f", confidence)) }
        return .text(lines.joined(separator: "\n"))
    }

    nonisolated static func reviewDocsExtractReviewJSON(_ text: String) -> [String: Any]? {
        let cleaned = llmToolStripFences(text)
        guard let first = cleaned.firstIndex(of: "{"),
              let last = cleaned.lastIndex(of: "}"), first <= last else { return nil }
        let json = String(cleaned[first...last])
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    func reviewDocsSafeUndo(_ call: MCPToolCall) async throws -> MCPToolResult {
        try await correctnessSafeUndo(call)
    }

    nonisolated static func reviewDocsDocComment(declaration: String, summary: String) -> String {
        var docLines: [String] = []
        docLines.append("/// \(summary)")
        docLines.append("///")
        if let openParen = declaration.firstIndex(of: "("),
           let closeParen = declaration.lastIndex(of: ")"),
           openParen < closeParen {
            let paramSection = String(declaration[declaration.index(after: openParen)..<closeParen])
            let params = paramSection.components(separatedBy: ",")
            for param in params {
                let parts = param.components(separatedBy: ":")
                if parts.count >= 2 {
                    let namePart = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanName = namePart.components(separatedBy: " ").last ?? namePart
                    if !cleanName.isEmpty && cleanName != "_" {
                        let typePart = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                        docLines.append("/// - Parameter \(cleanName): The \(typePart) value supplied for processing.")
                    }
                }
            }
        }
        if declaration.contains("throws") {
            docLines.append("/// - Throws: An error if processing or I/O fails during execution.")
        }
        if declaration.contains("->") {
            let returnType = declaration.components(separatedBy: "->").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Result"
            docLines.append("/// - Returns: A `\(returnType)` instance representing the computed outcome.")
        }
        return docLines.joined(separator: "\n") + "\n" + declaration
    }

    func reviewDocsDocString(_ call: MCPToolCall) throws -> MCPToolResult {
        let declaration = try reviewDocsRequiredString(call, "declaration")
        let summary = call.arguments["summary"]?.string ?? "Performs operations associated with this declaration."
        let result = Self.reviewDocsDocComment(declaration: declaration, summary: summary)
        return .text("Generated DocC Documentation:\n\n```swift\n\(result)\n```")
    }

    nonisolated static func reviewDocsSnippet(templateId: String, name: String) -> (title: String, snippet: String)? {
        switch templateId.lowercased() {
        case "observable_viewmodel":
            let snippet = """
            import SwiftUI
            import Observation

            @Observable
            @MainActor
            public final class \(name)ViewModel {
                public var items: [String] = []
                public var isLoading: Bool = false
                public var errorMessage: String? = nil

                public init() {}

                public func loadData() async {
                    isLoading = true
                    defer { isLoading = false }
                    do {
                        // Implement async data fetch
                        try await Task.sleep(nanoseconds: 500_000_000)
                        self.items = ["Sample 1", "Sample 2"]
                    } catch {
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
            """
            return ("Swift 6 @Observable ViewModel Template:", snippet)
        case "async_stream":
            let snippet = """
            import Foundation

            public func make\(name)Stream() -> AsyncStream<String> {
                AsyncStream { continuation in
                    Task {
                        // Produce stream items
                        continuation.yield("Connected")
                        continuation.finish()
                    }
                }
            }
            """
            return ("AsyncStream Template:", snippet)
        case "actor_service":
            let snippet = """
            import Foundation

            public actor \(name)Service {
                private var cache: [String: Data] = [:]

                public init() {}

                public func store(data: Data, for key: String) {
                    cache[key] = data
                }

                public func retrieve(for key: String) -> Data? {
                    return cache[key]
                }

                public func clear() {
                    cache.removeAll()
                }
            }
            """
            return ("Thread-Safe Actor Service Template:", snippet)
        case "swiftui_glass_card":
            let snippet = """
            import SwiftUI

            public struct \(name)CardView: View {
                public var body: some View {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(name)")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text("Glassmorphic native component layout.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                }
            }
            """
            return ("SwiftUI Glassmorphic Card Template:", snippet)
        default:
            return nil
        }
    }

    func reviewDocsCodeSnippet(_ call: MCPToolCall) throws -> MCPToolResult {
        let templateId = try reviewDocsRequiredString(call, "templateId")
        let name = call.arguments["targetName"]?.string ?? "Feature"
        guard let (title, snippet) = Self.reviewDocsSnippet(templateId: templateId, name: name) else {
            throw MCPToolError("Unknown templateId '\(templateId)'. Available: observable_viewmodel, async_stream, actor_service, swiftui_glass_card")
        }
        return .text("\(title)\n\n```swift\n\(snippet)\n```")
    }

    func reviewDocsColorUsageAudit(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let limit = max(1, min(500, call.int("limit") ?? 100))
        let patterns: [(NSRegularExpression?, String)] = [
            (try? NSRegularExpression(pattern: #"Color\s*\(\s*red\s*:"#), "Color(red:...)"),
            (try? NSRegularExpression(pattern: #"UIColor\s*\(\s*red\s*:"#), "UIColor(red:...)"),
            (try? NSRegularExpression(pattern: #"NSColor\s*\(\s*red\s*:"#), "NSColor(red:...)"),
            (try? NSRegularExpression(pattern: "\"#[0-9A-Fa-f]{6}\"|\"#[0-9a-f]{3}\""), "hex literal"),
            (try? NSRegularExpression(pattern: #"Color\s*\(\s*hex\s*:"#), "Color(hex:)"),
            (try? NSRegularExpression(pattern: #"UIColor\s*\(\s*hex\s*:"#), "UIColor(hex:)"),
        ]
        var findings: [(String, String)] = []
        for url in SearchWorkspace.swiftFiles(under: root) {
            guard let lines = SearchWorkspace.readLines(url) else { continue }
            let rel = SearchWorkspace.relative(url, root: root)
            for (i, line) in lines.enumerated() {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                for (pattern, label) in patterns {
                    guard let p = pattern else { continue }
                    if p.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                        findings.append(("\(rel):\(i + 1)", label))
                        break
                    }
                }
                if findings.count >= limit { break }
            }
            if findings.count >= limit { break }
        }
        if findings.isEmpty {
            return .structured(["count": .int(0)], summary: "No hardcoded colors found — colors appear to use named assets.")
        }
        var lines = ["Hardcoded colors (\(findings.count)\(findings.count >= limit ? "+" : "")) — consider asset-catalog named colors:"]
        lines += findings.map { "- \($0.0) [\($0.1)]" }
        return .structured(["count": .int(findings.count)], summary: lines.joined(separator: "\n"))
    }

    func reviewDocsColorSetBuilder(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let catalogPath = try reviewDocsRequiredString(call, "catalogPath")
        let colorName = try reviewDocsRequiredString(call, "colorName")
        let lightHex = try reviewDocsRequiredString(call, "lightHex")
        let darkHex = call.arguments["darkHex"]?.string ?? lightHex
        guard !colorName.isEmpty, !colorName.contains("/"), !colorName.contains("\\"), !colorName.contains(".."),
              !colorName.contains("\0") else {
            throw MCPToolError("Invalid colorName '\(colorName)': must be a single color set name, not a path.")
        }
        guard let catURL = resolveFileWritingPath(catalogPath, in: s) else {
            throw MCPToolError("Path is outside the workspace: \(catalogPath)")
        }
        let colorSetURL = catURL.appendingPathComponent("\(colorName).colorset")
        let contentsURL = colorSetURL.appendingPathComponent("Contents.json")
        let contents = Self.reviewDocsColorSetContents(lightHex: lightHex, darkHex: darkHex)
        let rel = fileReadingRelativePath(of: contentsURL, in: s)
        try await commit(MCPChange(tool: call.name, path: contentsURL.path, relativePath: rel, original: text(of: contentsURL),
                                   proposed: contents, summary: "Build colorset \(colorName)"), call: call, session: s)
        return .text("Successfully built adaptive ColorSet `\(colorName)` at: \(colorSetURL.path)\n- Light: \(lightHex)\n- Dark: \(darkHex)")
    }

    func reviewDocsIconGenerator(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let catalogPath = try reviewDocsRequiredString(call, "catalogPath")
        let action = try reviewDocsRequiredString(call, "action")
        guard let catURL = resolveFileWritingPath(catalogPath, in: s) else {
            throw MCPToolError("Path is outside the workspace: \(catalogPath)")
        }
        let iconSetURL = catURL.appendingPathComponent("AppIcon.appiconset")
        if action.lowercased() == "scaffold" {
            let contentsURL = iconSetURL.appendingPathComponent("Contents.json")
            let rel = fileReadingRelativePath(of: contentsURL, in: s)
            try await commit(MCPChange(tool: call.name, path: contentsURL.path, relativePath: rel, original: text(of: contentsURL),
                                       proposed: Self.reviewDocsIconContents, summary: "Scaffold AppIcon.appiconset in \(catalogPath)"),
                             call: call, session: s)
            return .text("Successfully created universal AppIcon.appiconset at: \(iconSetURL.path)")
        }
        let contentsJSON = iconSetURL.appendingPathComponent("Contents.json")
        guard FileManager.default.fileExists(atPath: contentsJSON.path),
              let data = try? Data(contentsOf: contentsJSON),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let images = json["images"] as? [[String: Any]] else {
            throw MCPToolError("Contents.json not found or invalid in \(iconSetURL.path)")
        }
        var filledSlots = 0
        var emptySlots = 0
        for img in images {
            if let fn = img["filename"] as? String, !fn.isEmpty {
                let imgURL = iconSetURL.appendingPathComponent(fn)
                if FileManager.default.fileExists(atPath: imgURL.path) {
                    filledSlots += 1
                } else {
                    emptySlots += 1
                }
            } else {
                emptySlots += 1
            }
        }
        return .text("AppIcon.appiconset audit for `\(catalogPath)`:\n- Total slots configured: \(images.count)\n- Rendered assets present: \(filledSlots)\n- Empty/unassigned slots: \(emptySlots)")
    }
}

extension SwiftCodeMCPHost {

    func reviewDocsMarkdownLinkCheck(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let raw = call.arguments["path"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        var targets: [URL] = []
        if let raw, !raw.isEmpty {
            do {
                targets = [try resolveFileReadingPath(raw, in: s)]
            } catch {
                throw MCPToolError("Refusing to access path outside the workspace: \(raw)")
            }
        } else {
            targets = SearchWorkspace.files(under: root, extensions: ["md", "markdown"])
        }
        let linkPattern = try? NSRegularExpression(pattern: #"\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#)
        var checked = 0
        var broken: [String] = []
        for url in targets {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let rel = SearchWorkspace.relative(url, root: root)
            let matches = linkPattern?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
            for m in matches {
                guard let r = Range(m.range(at: 2), in: text) else { continue }
                var dest = String(text[r])
                if dest.hasPrefix("#") || dest.contains("://") || dest.hasPrefix("mailto:") { continue }
                if let hash = dest.firstIndex(of: "#") { dest = String(dest[..<hash]) }
                if dest.isEmpty { continue }
                checked += 1
                let base = url.deletingLastPathComponent()
                let candidate = URL(fileURLWithPath: dest, relativeTo: base).standardized
                let candidatePath = candidate.path
                let rootPath = root.standardized.path
                let inside = candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
                if !inside || !FileManager.default.fileExists(atPath: candidatePath) {
                    broken.append("\(rel): [\(dest)]")
                    if broken.count > 200 { break }
                }
            }
            if broken.count > 200 { break }
        }
        if broken.isEmpty {
            return .structured(["checked": .int(checked), "broken": .int(0)], summary: "All \(checked) internal links resolve.")
        }
        var lines = ["Broken internal links (\(broken.count) of \(checked) checked):"]
        lines += broken.map { "- \($0)" }
        return .structured(["checked": .int(checked), "broken": .int(broken.count)], summary: lines.joined(separator: "\n"))
    }

    func reviewDocsMarkdownToc(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let raw = call.arguments["path"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            throw MCPToolError("Missing required parameter: path")
        }
        let maxDepth = max(1, min(6, call.int("maxDepth") ?? 3))
        let url: URL
        do {
            url = try resolveFileReadingPath(raw, in: s)
        } catch {
            throw MCPToolError("Cannot read Markdown file at: \(raw)")
        }
        guard var content = try? String(contentsOf: url, encoding: .utf8) else {
            throw MCPToolError("Cannot read Markdown file at: \(raw)")
        }
        var entries: [(Int, String)] = []
        for line in content.components(separatedBy: .newlines) {
            guard line.hasPrefix("#") else { continue }
            let level = line.prefix(while: { $0 == "#" }).count
            guard level >= 1 && level <= maxDepth else { continue }
            let title = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            entries.append((level, title))
        }
        if entries.isEmpty {
            throw MCPToolError("No headings found in \(raw).")
        }
        let tocLines = entries.map { (level, title) in
            String(repeating: "  ", count: level - 1) + "- [\(title)](#\(Self.reviewDocsAnchor(title)))"
        }
        let toc = "<!-- TOC -->\n" + tocLines.joined(separator: "\n") + "\n<!-- /TOC -->"
        if content.contains("<!-- TOC -->"), content.contains("<!-- /TOC -->"),
           let start = content.range(of: "<!-- TOC -->"), let end = content.range(of: "<!-- /TOC -->"), start.lowerBound < end.upperBound {
            content.replaceSubrange(start.lowerBound..<end.upperBound, with: toc)
        } else {
            let lines = content.components(separatedBy: .newlines)
            if let firstHeading = lines.firstIndex(where: { $0.hasPrefix("# ") }) {
                var mutable = lines
                mutable.insert("", at: firstHeading + 1)
                mutable.insert(toc, at: firstHeading + 2)
                content = mutable.joined(separator: "\n")
            } else {
                content = toc + "\n\n" + content
            }
        }
        let rel = fileReadingRelativePath(of: url, in: s)
        try await commit(MCPChange(tool: call.name, path: url.path, relativePath: rel, original: text(of: url),
                                   proposed: content, summary: "Generate table of contents in \(rel)"), call: call, session: s)
        return .structured(["path": .string(raw), "entryCount": .int(entries.count)],
                           summary: "Table of contents (\(entries.count) entries) written to \(raw).")
    }

    func reviewDocsReadmeGenerate(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let rawPath = (call.arguments["path"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 } ?? "README.generated.md"
        let overwrite = call.bool("overwrite") ?? false
        let url: URL
        do {
            url = try resolveFileReadingPath(rawPath, in: s)
        } catch {
            throw MCPToolError("Refusing to write outside the workspace: \(rawPath)")
        }
        if FileManager.default.fileExists(atPath: url.path) && !overwrite {
            throw MCPToolError("File already exists at \(rawPath). Pass overwrite: true to replace it.")
        }
        let projectName = root.lastPathComponent
        var systems: [String] = []
        let fm = FileManager.default
        if fm.fileExists(atPath: root.appendingPathComponent("Package.swift").path) { systems.append("SwiftPM") }
        if (try? fm.contentsOfDirectory(atPath: root.path))?.contains(where: { $0.hasSuffix(".xcworkspace") }) == true { systems.append("Xcode workspace") }
        else if (try? fm.contentsOfDirectory(atPath: root.path))?.contains(where: { $0.hasSuffix(".xcodeproj") }) == true { systems.append("Xcode project") }
        if fm.fileExists(atPath: root.appendingPathComponent("Podfile").path) { systems.append("CocoaPods") }
        var targets: [String] = []
        if let pbxproj = Self.reviewDocsFindPbxproj(in: root),
           let text = try? String(contentsOf: pbxproj, encoding: .utf8),
           let pattern = try? NSRegularExpression(pattern: #"/\* (\w[\w ]*) \*/ = \{\s*isa = PBXNativeTarget;"#) {
            targets = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m -> String? in
                guard let r = Range(m.range(at: 1), in: text) else { return nil }
                return String(text[r])
            }.sorted()
        }
        let swiftCount = SearchWorkspace.swiftFiles(under: root).count
        var md = "# \(projectName)\n\n"
        md += "Generated README skeleton — fill in the project description, screenshots, and usage details.\n\n"
        md += "## Overview\n\n- Workspace: `\(projectName)`\n- Swift source files: \(swiftCount)\n"
        if !systems.isEmpty { md += "- Build systems: \(systems.joined(separator: ", "))\n" }
        if !targets.isEmpty {
            md += "\n## Targets\n\n"
            for t in targets { md += "- \(t)\n" }
        }
        md += "\n## Building\n\n"
        if systems.contains("SwiftPM") { md += "```sh\nswift build\n```\n\n" }
        if systems.contains("Xcode workspace") || systems.contains("Xcode project") {
            md += "Open the workspace in Xcode and build with ⌘B, or:\n\n```sh\nxcodebuild -scheme <Scheme> -configuration Debug build\n```\n\n"
        }
        md += "## Project Structure\n\nSee the repository layout for module organization.\n\n"
        md += "## License\n\nAdd license information here.\n"
        let rel = fileReadingRelativePath(of: url, in: s)
        try await commit(MCPChange(tool: call.name, path: url.path, relativePath: rel, original: text(of: url),
                                   proposed: md, summary: "Generate README at \(rel)"), call: call, session: s)
        return .structured(["path": .string(rawPath)], summary: "README skeleton written to \(rawPath).")
    }

    func reviewDocsReadmeLocate(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let readmes = SearchWorkspace.files(under: root).filter {
            $0.lastPathComponent.lowercased().hasPrefix("readme")
        }
        if readmes.isEmpty {
            throw MCPToolError("No README file found in the workspace.")
        }
        var lines = ["README files found:"]
        for url in readmes.sorted(by: { $0.path < $1.path }) {
            let rel = SearchWorkspace.relative(url, root: root)
            let title = (try? String(contentsOf: url, encoding: .utf8))?
                .components(separatedBy: .newlines)
                .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
                .trimmingCharacters(in: .whitespaces) ?? "(unreadable)"
            lines.append("- \(rel): \(title.prefix(120))")
        }
        return .structured(["count": .int(readmes.count)], summary: lines.joined(separator: "\n"))
    }

    func reviewDocsRepoOverview(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let topN = max(1, min(20, call.int("topLanguages") ?? 8))
        let files = SearchWorkspace.files(under: root)
        var byExt: [String: Int] = [:]
        var totalBytes: Int64 = 0
        var largest: [(String, Int64)] = []
        for url in files {
            let ext = url.pathExtension.lowercased()
            let key = ext.isEmpty ? "(no extension)" : ext
            byExt[key, default: 0] += 1
            let size = Self.reviewDocsFileSize(of: url)
            totalBytes += size
            largest.append((SearchWorkspace.relative(url, root: root), size))
        }
        largest.sort { $0.1 > $1.1 }
        let fm = FileManager.default
        let readme = ["README.md", "README.markdown", "README.txt", "Readme.md", "readme.md"].first {
            fm.fileExists(atPath: root.appendingPathComponent($0).path)
        }
        let license = ["LICENSE", "LICENSE.md", "LICENSE.txt", "LICENCE", "COPYING"].first {
            fm.fileExists(atPath: root.appendingPathComponent($0).path)
        }
        var lines: [String] = []
        lines.append("Repository overview for \(root.lastPathComponent):")
        lines.append("- Total files: \(files.count)")
        lines.append("- Total size: \(totalBytes) bytes")
        lines.append("- README: \(readme ?? "not found")")
        lines.append("- License: \(license ?? "not found")")
        lines.append("- Top languages/extensions:")
        for (ext, count) in byExt.sorted(by: { $0.value > $1.value }).prefix(topN) {
            lines.append("  - .\(ext): \(count) files")
        }
        lines.append("- Largest files:")
        for (path, size) in largest.prefix(5) {
            lines.append("  - \(path) (\(size) bytes)")
        }
        return .structured(["fileCount": .int(files.count), "totalBytes": .int(Int(totalBytes)),
                            "readme": .string(readme ?? ""), "license": .string(license ?? "")],
                           summary: lines.joined(separator: "\n"))
    }

    func reviewDocsSafeValidateChanges(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let path = call.arguments["path"]?.string ?? "."
        let target = resolveFileWritingClampedPath(path, in: s)
        let files: [URL]
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir), isDir.boolValue {
            files = SearchWorkspace.enumeratedFiles(at: target, maxFileSize: 500_000)
        } else {
            files = [target]
        }
        var issues: [String] = []
        for file in files {
            let rel = SearchWorkspace.relative(file, root: Self.folder(of: s.model))
            guard let content = try? String(contentsOf: file, encoding: .utf8) else {
                issues.append("\(rel): unreadable text file")
                continue
            }
            if content.contains("<<<<<<<") || content.contains(">>>>>>>") || content.contains("=======") {
                issues.append("\(rel): merge conflict markers detected")
            }
            if !content.hasSuffix("\n") {
                issues.append("\(rel): missing trailing newline")
            }
        }
        if issues.isEmpty {
            return .structured(["issue_count": .int(0)], summary: "Changes validated successfully")
        }
        return .structured(["issue_count": .int(issues.count), "issues": .string(issues.joined(separator: "\n"))],
                           summary: "Validation completed with \(issues.count) issue(s)")
    }

    func reviewDocsSessionExport(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let rawOutput = call.arguments["outputPath"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        let outputRelative = (rawOutput?.isEmpty == false) ? rawOutput! : ".assist_session_export.md"
        guard let outputURL = Self.reviewDocsSessionExportURL(outputRelative, root: root) else {
            throw MCPToolError("Invalid outputPath: '\(outputRelative)' must be a workspace-relative path without '..' and must stay inside the workspace.")
        }
        let overwrite = (call.arguments["overwrite"]?.string ?? "").lowercased() == "true"
        if FileManager.default.fileExists(atPath: outputURL.path) && !overwrite {
            throw MCPToolError("Refusing to overwrite existing file at '\(outputRelative)'. Pass overwrite=true to replace it.")
        }
        let title = call.arguments["title"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTitle = (title?.isEmpty == false) ? title! : "Assist Session Export"
        let notes = call.arguments["notes"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let sessionId = Self.reviewDocsSessionUUID(root: root)
        var markdown = "# \(effectiveTitle)\n\n"
        markdown += "- Exported: \(timestamp)\n"
        markdown += "- Session ID: \(sessionId)\n"
        markdown += "- Workspace: \(root.path)\n\n"
        markdown += "## Tool Registry\n\n"
        markdown += "Tool definitions live in AssistToolRegistry. This export contains session metadata only.\n\n"
        markdown += "## Notes\n\n"
        markdown += notes.isEmpty ? "_No notes provided._\n" : notes + "\n"
        let rel = fileReadingRelativePath(of: outputURL, in: s)
        try await commit(MCPChange(tool: call.name, path: outputURL.path, relativePath: rel, original: text(of: outputURL),
                                   proposed: markdown, summary: "Export session to \(rel)"), call: call, session: s)
        return .structured(["output_path": .string(outputURL.path), "output_relative": .string(outputRelative),
                            "session_id": .string(sessionId), "timestamp": .string(timestamp)],
                           summary: "Session export written to \(outputRelative) (session \(sessionId)).")
    }

    func reviewDocsSessionProgress(_ call: MCPToolCall) throws -> MCPToolResult {
        try correctnessSessionProgress(call)
    }

    func reviewDocsStaleFiles(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let days = max(1, call.int("days") ?? 180)
        let limit = max(1, min(500, call.int("limit") ?? 50))
        let cutoff = Date().addingTimeInterval(TimeInterval(-days * 86400))
        let exts: Set<String> = ["swift", "m", "mm", "h", "c", "cpp", "hpp", "ts", "js", "py", "rs"]
        var stale: [(String, Date, Int64)] = []
        for url in SearchWorkspace.files(under: root, extensions: exts) {
            if let date = Self.reviewDocsModificationDate(of: url), date < cutoff {
                stale.append((SearchWorkspace.relative(url, root: root), date, Self.reviewDocsFileSize(of: url)))
            }
        }
        stale.sort { $0.1 < $1.1 }
        if stale.isEmpty {
            return .structured(["count": .int(0)], summary: "No source files older than \(days) days.")
        }
        var lines = ["Stale source files (not modified in \(days)+ days, \(stale.count) total):"]
        for (path, date, size) in stale.prefix(limit) {
            lines.append("- \(path) — modified \(Self.reviewDocsIso8601(date)), \(size) bytes")
        }
        return .structured(["count": .int(stale.count), "days": .int(days)], summary: lines.joined(separator: "\n"))
    }

    func reviewDocsToolCapabilityLookup(_ call: MCPToolCall) throws -> MCPToolResult {
        guard let toolId = call.arguments["toolId"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !toolId.isEmpty else {
            throw MCPToolError("Missing required parameter: toolId")
        }
        let resolved = MCPServer.toolAliases[toolId] ?? toolId
        guard let tool = server.tools.first(where: { $0.name == resolved }) else {
            throw MCPToolError("No registered tool with id '\(toolId)'.")
        }
        let risk = Self.reviewDocsRisk(of: tool)
        let props = tool.inputSchema["properties"]?.object?.keys.sorted() ?? []
        let required = tool.inputSchema["required"]?.array?.compactMap { $0.string } ?? []
        let output = [
            "Tool: \(tool.name) — \(tool.title)",
            "Risk level: \(risk)",
            "Read-only: \(tool.annotations.readOnly), Mutating: \(tool.writes)",
            "Description: \(tool.description)",
            "Parameters: \(props.isEmpty ? "(none)" : props.joined(separator: ", "))",
            "Required: \(required.isEmpty ? "(none)" : required.joined(separator: ", "))",
        ].joined(separator: "\n")
        return .structured(["toolId": .string(tool.name), "riskLevel": .string(risk),
                            "required": .string(required.joined(separator: ", "))],
                           summary: output)
    }
}
