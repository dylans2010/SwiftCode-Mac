import Foundation
import YcodeIDECore
import YcodeMachO

/// The ported Legacy security / privacy / platform audit tool family (Wave 6, slice C).
///
/// Behaviour source: Legacy's `AssistSecurityAuditTool`,
/// `AssistNetworkSecurityAuditorTool`, `AssistPermissionsAuditTool`,
/// `AssistPrivacyManifestAuditorTool`, `AssistAccessibilityAuditTool`,
/// `AssistAccessibilityAuditScannerTool`, `AssistAccessLevelAuditTool`,
/// `AssistDependencyLicensesTool`, `AssistFrameworkLinkerAuditorTool`,
/// `AssistMemoryLeakDetectorTool`, `AssistMachOBinaryAnalyzerTool`,
/// `AssistCoreDataModelInspectorTool`,
/// `AssistSwiftDataSchemaAuditorTool`, `AssistBundleResourceAuditorTool`,
/// `AssistBinarySizeReportTool`, `AssistImageAssetSizeReportTool`,
/// `AssistLicenseHeaderCheckTool` and `AssistSecretsScanTool` (Dylan's
/// own code, ported under MIT), as specified in
/// `specs/ide/assist-testing-audits.md`.
///
/// Conventions, following Waves 1–5:
///
/// * Tool IDs, names, descriptions and property descriptions are
///   Legacy's verbatim. The array order is Legacy's
///   `registerAllTools()` order. Legacy's parameter-name aliases
///   (`filePath`, `file_path`, `required_text`, …) are NOT supported:
///   Ycode's argument validation rejects unknown arguments before the
///   handler runs (same as Waves 1–2).
/// * Structured data keeps Legacy's keys, with typed JSON values
///   (integers and booleans) the way Ycode's other tools do — Legacy's
///   string-only map is not reproduced. Tools whose Legacy result
///   carries no data return a plain text result instead.
/// * Path resolution follows each Legacy tool's own resolver shape.
///   Tools that in Legacy appended the raw path to the workspace root
///   with no validation (`security_audit_scanner`,
///   `memory_leak_detector`, `accessibility_audit_scanner`,
///   `mach_o_binary_analyzer`, and the explicit path of
///   `network_security_auditor` / `core_data_model_inspector`) use the
///   session-aware `resolveFileReadingPath` (plain relative paths
///   resolve against the `dir_cd` working directory; `..` that stays
///   inside the workspace is allowed). Tools with Legacy's strict
///   per-tool resolvers (`accessibility_audit`, `secrets_scan`,
///   `access_level_audit`, `license_header_check`,
///   `binary_size_report`) use `auditResolveStrictPath` below, which
///   rejects any `..`, resolves plain relative paths against the
///   workspace root (never the session directory), and requires an
///   absolute path to lie under the root. No path is ever allowed to
///   escape the workspace — Legacy's unguarded appends are confined,
///   not reproduced.
/// * Approval gating: `privacy_manifest_auditor` is the only writing
///   tool in this family (Legacy `riskLevel` `safeMutation`; its
///   `generate` action writes `PrivacyInfo.xcprivacy`). Its write goes
///   through `commit()` (the Wave 1 helper); the `audit` action writes
///   nothing and needs no approval. The other 17 tools are Legacy
///   `safeRead` and are registered `writes: false` with the default
///   read-only annotations. There is no Autopilot, no second gate, and
///   no bypass of `MCPWritePolicy`.
/// * `memory_leak_detector` is a static source scan in Legacy (retain
///   cycles, strong-`self` captures, unowned hazards, non-weak
///   delegates); it never ran Instruments or a live process, and the
///   port does not either. Its findings are heuristics, as Legacy's
///   messages say ("Potential retain cycle", "Retain cycle risk").
///
/// Deliberate deviations from Legacy, recorded here:
///
/// * `mach_o_binary_analyzer` does NOT shell out to `/usr/bin/file`
///   and `xcrun otool` (macOS-only CLIs; `xcrun` does not exist on
///   Linux). It parses the binary with Ycode's own `YcodeMachO`
///   target (`MachOFile` / `MachOImage`: fat containers, per-slice
///   CPU type, file type, segments, linked dylibs with kind and
///   versions, install name, UUID, build version, rpaths, code
///   signature, encryption flag) and reports that instead of the
///   `file` / `otool -L` output text. A file that is not a Mach-O, or
///   a 32-bit Mach-O (`MachOImage` parses 64-bit images only), fails
///   honestly with the parser's message instead of reporting
///   fabricated architectures. The `binaryPath` parameter name is
///   kept verbatim (it is the only tool in this family whose Legacy
///   parameter is not called `path`).
/// * `framework_linker_auditor`, `swift_data_schema_auditor` and
///   `bundle_resource_auditor` declare an optional `path` parameter
///   in Legacy but never read it — they always scan the workspace
///   root. The port keeps the parameter in the schema and likewise
///   ignores it.
/// * `dependency_licenses` is Legacy capability `repositoryDiscovery`
///   (the only non-`diagnostics` tool here); Ycode's `MCPTool` has no
///   capability field, so the distinction is recorded in the spec
///   only.
/// * `accessibility_audit`'s findings are sorted (Legacy appended
///   them in enumeration order); `core_data_model_inspector`'s
///   entities are reported in name order (Legacy iterated a
///   dictionary). Both changes make output deterministic; the
///   finding text itself is unchanged.
/// * `permissions_audit`'s workspace scan uses Legacy's exact skip
///   set (`.git`, `DerivedData`, `.build`, `Pods`, `node_modules`,
///   `.swiftpm`, `Carthage`, `vendor`); the other whole-workspace
///   scans use Ycode's shared `SearchWorkspace` skip set where Legacy
///   used `AssistWorkspaceScan`, as Waves 3–4 do.
/// * `secrets_scan` never outputs a matched secret value or a source
///   line — findings are `file:line:pattern-label` only, exactly as
///   Legacy does. The `accessibility_audit` / `secrets_scan` /
///   `access_level_audit` / `license_header_check` /
///   `binary_size_report` strict resolvers reject `..` as text, as
///   Legacy's do.
extension YcodeMCPHost {
    var auditTools: [MCPTool] {
        let safeMutation = MCPToolAnnotations(readOnly: false, idempotent: true)
        return [
            tool("memory_leak_detector", "Memory Leak Detector",
                 "Scans Swift source code for retain cycles, strong self capture in escaping closures, and unowned reference risks.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to a Swift file or directory.")],
                                      required: ["path"])) { h, call in
                try await h.auditMemoryLeaks(call)
            },
            tool("security_audit_scanner", "Security Audit Scanner",
                 "Scans Swift source files for hardcoded secrets, API keys, insecure HTTP endpoints, and unsafe storage practices.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to a directory or Swift file.")],
                                      required: ["path"])) { h, call in
                try await h.auditSecurity(call)
            },
            tool("bundle_resource_auditor", "Bundle Resource Auditor",
                 "Audits project resources, asset catalogs, and bundle copy phases for missing or orphaned assets.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Optional directory path to scan. Defaults to workspace root.")])) { h, call in
                try await h.auditBundleResources(call)
            },
            tool("core_data_model_inspector", "Core Data Model Inspector",
                 "Locates, inspects, and parses Core Data .xcdatamodeld schemas, entities, attributes, and relationships.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Optional path to the .xcdatamodeld bundle. If omitted, the workspace is scanned.")])) { h, call in
                try await h.auditCoreDataModel(call)
            },
            tool("swift_data_schema_auditor", "SwiftData Schema Auditor",
                 "Audits SwiftData models (@Model), attributes, relationships, and migration schemas across the workspace.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Optional directory path to scan. Defaults to workspace root.")])) { h, call in
                try await h.auditSwiftDataSchema(call)
            },
            tool("privacy_manifest_auditor", "Privacy Manifest Auditor",
                 "Audits or scaffolds Apple Privacy Manifests (PrivacyInfo.xcprivacy) for Required Reason API compliance.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "action": Schema.string("Action: 'audit' (scan codebase for API usage) or 'generate' (scaffold a valid PrivacyInfo.xcprivacy template).")],
                                      required: ["action"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.auditPrivacyManifest(call)
            },
            tool("mach_o_binary_analyzer", "Mach-O Binary Analyzer",
                 "Inspects built application binaries, architectures (arm64, x86_64), and linked dynamic libraries via otool and file.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "binaryPath": Schema.string("Relative or absolute path to the compiled binary or executable file.")],
                                      required: ["binaryPath"])) { h, call in
                try await h.auditMachOBinary(call)
            },
            tool("framework_linker_auditor", "Framework Linker Auditor",
                 "Inspects PBXFrameworksBuildPhase in Xcode projects to audit linked system and dynamic frameworks.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Optional path to .xcodeproj. Defaults to workspace root.")])) { h, call in
                try await h.auditFrameworkLinker(call)
            },
            tool("network_security_auditor", "Network Security & ATS Auditor",
                 "Audits NSAppTransportSecurity in Info.plist for insecure HTTP and ATS exceptions.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Optional path to Info.plist. Defaults to searching workspace.")])) { h, call in
                try await h.auditNetworkSecurity(call)
            },
            tool("accessibility_audit_scanner", "Accessibility Audit Scanner",
                 "Audits SwiftUI views for missing accessibility labels, hints, and VoiceOver tap targets.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Relative path to Swift file or directory.")],
                                      required: ["path"])) { h, call in
                try await h.auditAccessibilityScanner(call)
            },
            tool("license_header_check", "License Header Check",
                 "Checks the first 15 lines of each Swift file for required header text (default: \"Copyright\") and reports files missing it.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of a file or directory to check. Defaults to the workspace root."),
                                       "requiredText": Schema.string("Header text that must appear in the first 15 lines. Case-insensitive. Default: \"Copyright\".")]),
                 output: Schema.output(["scannedFiles": Schema.int, "withHeader": Schema.int,
                                        "missingHeader": Schema.int, "missingFiles": Schema.str])) { h, call in
                try await h.auditLicenseHeaders(call)
            },
            tool("access_level_audit", "Access Level Audit",
                 "Counts Swift declarations by access level (public, open, internal, private, fileprivate; default internal when unspecified) and lists the files with the most public API. Heuristic: access is inferred from keywords on the declaration line, with public/open taking precedence over private(set).",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of a file or directory to audit. Defaults to the workspace root.")]),
                 output: Schema.output(["scannedFiles": Schema.int, "public": Schema.int, "open": Schema.int,
                                        "internal": Schema.int, "private": Schema.int, "fileprivate": Schema.int,
                                        "total": Schema.int, "topPublicFiles": Schema.str])) { h, call in
                try await h.auditAccessLevels(call)
            },
            tool("binary_size_report", "Binary Size Report",
                 "Reports total size and the 10 largest files for each .app bundle under the workspace build directory or an explicit in-workspace path. DerivedData is never scanned.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Optional workspace-relative path to a .app bundle or a directory to search for .app bundles. Default: build/.")]),
                 output: Schema.output(["appCount": Schema.int, "totalBytes": Schema.int, "apps": Schema.str])) { h, call in
                try await h.auditBinarySizes(call)
            },
            tool("secrets_scan", "Secrets Scan",
                 "Scans source and config files for secret patterns. Reports file:line:pattern only and never outputs matched secret values.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative directory or file to scan (optional).")]),
                 output: Schema.output(["finding_count": Schema.int, "files_scanned": Schema.int,
                                        "files_with_findings": Schema.int])) { h, call in
                try await h.auditSecrets(call)
            },
            tool("permissions_audit", "Permissions Audit",
                 "Audits Info.plist usage descriptions, entitlements, and PrivacyInfo.xcprivacy entries, and flags API usage missing a usage description.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["usage_description_count": Schema.int, "entitlement_count": Schema.int,
                                        "privacy_api_count": Schema.int, "missing_count": Schema.int,
                                        "privacy_tracking": Schema.str])) { h, call in
                try await h.auditPermissions(call)
            },
            tool("accessibility_audit", "Accessibility Audit",
                 "Heuristic SwiftUI accessibility audit: flags Button/Image without accessibility labels, TextField with empty labels, and color-only state.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative directory or file to audit (optional).")]),
                 output: Schema.output(["finding_count": Schema.int, "files_scanned": Schema.int])) { h, call in
                try await h.auditAccessibility(call)
            },
            tool("dependency_licenses", "Dependency Licenses",
                 "Inventories third-party dependencies from Package.resolved and Podfile.lock, reporting versions for license review.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["count": Schema.int])) { h, call in
                try await h.auditDependencyLicenses(call)
            },
            tool("image_asset_size_report", "Image Asset Size Report",
                 "Reports oversized image files inside .xcassets catalogs — candidates for compression or vectorization.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "thresholdKB": Schema.integer("Size threshold in KB. Default 500.")]),
                 output: Schema.output(["imageCount": Schema.int, "oversizedCount": Schema.int,
                                        "totalBytes": Schema.int])) { h, call in
                try await h.auditImageAssetSizes(call)
            },
        ]
    }
}

extension YcodeMCPHost {
    // MARK: - Memory leaks, security, bundle resources, data models, privacy

    func auditMemoryLeaks(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let raw = try fileReadingRequiredString(call, "path")
        let targetURL = try resolveFileReadingPath(raw, in: s)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDir) else {
            throw MCPToolError("Path not found: \(raw)")
        }
        var files: [URL] = []
        if isDir.boolValue {
            if let enumerator = FileManager.default.enumerator(at: targetURL, includingPropertiesForKeys: nil) {
                while let fileURL = enumerator.nextObject() as? URL {
                    if fileURL.pathExtension == "swift" {
                        files.append(fileURL)
                    }
                }
            }
        } else if targetURL.pathExtension == "swift" {
            files.append(targetURL)
        }
        var findings: [String] = []
        for fileURL in files {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let relPath = fileReadingRelativePath(of: fileURL, in: s)
            let lines = content.components(separatedBy: .newlines)
            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("//") { continue }
                // 1. Strong self capture in escaping closure.
                if (trimmed.contains(".sink") || trimmed.contains("Task {") || trimmed.contains("DispatchQueue."))
                    && trimmed.contains("self.") && !trimmed.contains("[weak self]") && !trimmed.contains("[unowned self]") {
                    findings.append("\(relPath):\(idx + 1) Potential retain cycle: escaping closure captures strong 'self'. Consider adding '[weak self]'.")
                }
                // 2. Unowned self hazard in async / network call.
                if trimmed.contains("[unowned self]") && (trimmed.contains("async") || trimmed.contains("await") || trimmed.contains("URLSession")) {
                    findings.append("\(relPath):\(idx + 1) Memory crash hazard: '[unowned self]' used in asynchronous or network context. Use '[weak self]' instead.")
                }
                // 3. Delegate property declared without 'weak'.
                if (trimmed.hasPrefix("var delegate:") || trimmed.hasPrefix("public var delegate:") || trimmed.hasPrefix("weak var delegate:"))
                    && !trimmed.contains("weak ") {
                    findings.append("\(relPath):\(idx + 1) Retain cycle risk: Delegate property should be declared 'weak var delegate'.")
                }
            }
        }
        if findings.isEmpty {
            return .text("Memory Leak Scan passed: No retain cycles or strong self closure hazards detected across \(files.count) files in '\(raw)'.")
        }
        return .text("Memory Leak Scan found \(findings.count) potential issues across \(files.count) files in '\(raw)':\n\n"
            + findings.prefix(25).joined(separator: "\n") + (findings.count > 25 ? "\n...and \(findings.count - 25) more." : ""))
    }

    func auditSecurity(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let raw = try fileReadingRequiredString(call, "path")
        let targetURL = try resolveFileReadingPath(raw, in: s)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDir) else {
            throw MCPToolError("Path does not exist: \(raw)")
        }
        var files: [URL] = []
        if isDir.boolValue {
            if let enumerator = FileManager.default.enumerator(at: targetURL, includingPropertiesForKeys: nil) {
                while let fileURL = enumerator.nextObject() as? URL {
                    if fileURL.pathExtension == "swift" || fileURL.pathExtension == "plist" {
                        files.append(fileURL)
                    }
                }
            }
        } else {
            files.append(targetURL)
        }
        var findings: [String] = []
        for fileURL in files {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let relPath = fileReadingRelativePath(of: fileURL, in: s)
            let lines = content.components(separatedBy: .newlines)
            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("//") { continue }
                // 1. Plain HTTP URLs (ATS violation).
                if trimmed.contains("\"http://") && !trimmed.contains("localhost") && !trimmed.contains("127.0.0.1") {
                    findings.append("\(relPath):\(idx + 1) [ATS] Insecure plaintext HTTP URL detected: '\(trimmed)'. Upgrade to HTTPS.")
                }
                // 2. Hardcoded secret / token patterns.
                let lower = trimmed.lowercased()
                if (lower.contains("api_key = \"") || lower.contains("apikey = \"") || lower.contains("secret = \"") || lower.contains("password = \""))
                    && !trimmed.contains("\"\"") {
                    findings.append("\(relPath):\(idx + 1) [Credential] Potential hardcoded credential or secret assignment. Use Keychain or Environment variables.")
                }
                // 3. Sensitive logging.
                if trimmed.contains("print(\"token") || trimmed.contains("print(\"password") || trimmed.contains("print(\"apiKey") {
                    findings.append("\(relPath):\(idx + 1) [Privacy] Sensitive credential leaked into debug console print statement.")
                }
            }
        }
        if findings.isEmpty {
            return .text("Security Audit passed: 0 vulnerabilities or hardcoded secrets found across \(files.count) files in '\(raw)'.")
        }
        return .text("Security Audit flagged \(findings.count) items in '\(raw)':\n\n"
            + findings.prefix(20).joined(separator: "\n") + (findings.count > 20 ? "\n...and \(findings.count - 20) more." : ""))
    }

    func auditBundleResources(_ call: MCPToolCall) async throws -> MCPToolResult {
        // Legacy declares `path` but never reads it: the workspace root
        // is always scanned.
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        var assetCatalogs: [String] = []
        var jsonResources: [String] = []
        var fontFiles: [String] = []
        var orphanedEntries: [String] = []
        let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let fileURL = enumerator?.nextObject() as? URL {
            let rel = fileReadingRelativePath(of: fileURL, in: s)
            if fileURL.pathExtension == "xcassets" {
                assetCatalogs.append(rel)
            } else if fileURL.pathExtension == "json" && !rel.contains("DerivedData") && !rel.contains("Pods") {
                jsonResources.append(rel)
            } else if ["ttf", "otf"].contains(fileURL.pathExtension.lowercased()) {
                fontFiles.append(rel)
            }
            // Check if Contents.json has missing image files.
            if fileURL.lastPathComponent == "Contents.json" && rel.contains(".imageset") {
                if let data = try? Data(contentsOf: fileURL),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let images = json["images"] as? [[String: Any]] {
                    let parentDir = fileURL.deletingLastPathComponent()
                    for img in images {
                        if let filename = img["filename"] as? String {
                            let imgURL = parentDir.appendingPathComponent(filename)
                            if !FileManager.default.fileExists(atPath: imgURL.path) {
                                orphanedEntries.append("Missing image asset: `\(rel)` references `\(filename)` which is not on disk.")
                            }
                        }
                    }
                }
            }
        }
        var report = "### Bundle Resource Audit Report:\n\n"
        report += "- **Asset Catalogs**: \(assetCatalogs.count) found (\(assetCatalogs.prefix(5).joined(separator: ", ")))\n"
        report += "- **Bundled JSON Resources**: \(jsonResources.count) files\n"
        report += "- **Custom Font Files**: \(fontFiles.count) files\n\n"
        if orphanedEntries.isEmpty {
            report += "✅ All asset catalog image sets and resource declarations verified on disk."
        } else {
            report += "#### ⚠️ Discrepancies Detected:\n"
            for item in orphanedEntries.prefix(15) {
                report += "- \(item)\n"
            }
        }
        return .text(report)
    }

    func auditCoreDataModel(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        var modelDirURL: URL?
        if let p = call.string("path"), !p.isEmpty {
            modelDirURL = try resolveFileReadingPath(p, in: s)
        } else {
            let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                            options: [.skipsHiddenFiles, .skipsPackageDescendants])
            while let u = enumerator?.nextObject() as? URL {
                if u.pathExtension == "xcdatamodeld" {
                    modelDirURL = u
                    break
                }
            }
        }
        guard let modelURL = modelDirURL, FileManager.default.fileExists(atPath: modelURL.path) else {
            return .text("No .xcdatamodeld Core Data models found in the workspace.")
        }
        // Find contents file inside the current version.
        var contentsURL: URL?
        if let subitems = try? FileManager.default.contentsOfDirectory(at: modelURL, includingPropertiesForKeys: nil) {
            for sub in subitems {
                if sub.pathExtension == "xcdatamodel" {
                    let c = sub.appendingPathComponent("contents")
                    if FileManager.default.fileExists(atPath: c.path) {
                        contentsURL = c
                        break
                    }
                }
            }
        }
        guard let contents = contentsURL, let xmlString = try? String(contentsOf: contents, encoding: .utf8) else {
            return .text("Found model at \(modelURL.lastPathComponent), but contents XML was unreadable.")
        }
        // Simple XML attribute and entity parsing.
        var entities: [String: [String]] = [:]
        let entityRegex = try? NSRegularExpression(pattern: #"<entity name="([^"]+)""#, options: [])
        let attributeRegex = try? NSRegularExpression(pattern: #"<attribute name="([^"]+)"[^>]*attributeType="([^"]+)""#, options: [])
        var currentEntity = "Entity"
        for line in xmlString.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let nsTrimmed = trimmed as NSString
            if let eMatch = entityRegex?.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: nsTrimmed.length)) {
                currentEntity = nsTrimmed.substring(with: eMatch.range(at: 1))
                entities[currentEntity] = []
            } else if let aMatch = attributeRegex?.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: nsTrimmed.length)) {
                let attrName = nsTrimmed.substring(with: aMatch.range(at: 1))
                let attrType = nsTrimmed.substring(with: aMatch.range(at: 2))
                entities[currentEntity, default: []].append("\(attrName): \(attrType)")
            }
        }
        // Entities are reported in name order (Legacy iterated a
        // dictionary); the per-entity text is Legacy's.
        var report = "### Core Data Model: `\(modelURL.lastPathComponent)` (\(entities.count) entities):\n\n"
        for (name, attrs) in entities.sorted(by: { $0.key < $1.key }) {
            report += "#### Entity `\(name)`:\n"
            if attrs.isEmpty {
                report += "  _(No attributes defined or managed via relationships)_\n"
            } else {
                for a in attrs {
                    report += "  - `\(a)`\n"
                }
            }
            report += "\n"
        }
        return .text(report)
    }

    func auditSwiftDataSchema(_ call: MCPToolCall) async throws -> MCPToolResult {
        // Legacy declares `path` but never reads it: the workspace root
        // is always scanned.
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        var models: [(name: String, file: String, line: Int, properties: [String])] = []
        let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            guard text.contains("@Model") else { continue }
            let relPath = fileReadingRelativePath(of: fileURL, in: s)
            let lines = text.components(separatedBy: .newlines)
            var isNextClass = false
            var currentModelName = ""
            var currentLine = 0
            var currentProps: [String] = []
            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("@Model") {
                    isNextClass = true
                } else if isNextClass && (trimmed.hasPrefix("class ") || trimmed.hasPrefix("final class ") || trimmed.hasPrefix("public class ")) {
                    let parts = trimmed.components(separatedBy: .whitespaces)
                    if let cIdx = parts.firstIndex(of: "class"), cIdx + 1 < parts.count {
                        currentModelName = parts[cIdx + 1].components(separatedBy: ":").first ?? "Unknown"
                        currentLine = idx + 1
                        currentProps = []
                        isNextClass = false
                    }
                } else if !currentModelName.isEmpty {
                    if trimmed.hasPrefix("var ") || trimmed.hasPrefix("@Attribute") || trimmed.hasPrefix("@Relationship") {
                        currentProps.append(trimmed)
                    } else if trimmed == "}" {
                        models.append((name: currentModelName, file: relPath, line: currentLine, properties: currentProps))
                        currentModelName = ""
                    }
                }
            }
        }
        if models.isEmpty {
            return .text("No SwiftData `@Model` classes discovered in the workspace.")
        }
        var report = "### Discovered SwiftData Models (\(models.count) found):\n\n"
        for m in models {
            report += "#### `@Model class \(m.name)` (`\(m.file):\(m.line)`):\n"
            if m.properties.isEmpty {
                report += "  _(No explicit stored var properties detected)_\n"
            } else {
                for p in m.properties.prefix(12) {
                    report += "  - `\(p)`\n"
                }
            }
            report += "\n"
        }
        return .text(report)
    }

    func auditPrivacyManifest(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let action = call.arguments["action"]?.string, !action.isEmpty else {
            throw MCPToolError("Missing required parameter: action ('audit' or 'generate')")
        }
        let root = Self.folder(of: s.model)
        if action.lowercased() == "generate" {
            let manifestURL = root.appendingPathComponent("PrivacyInfo.xcprivacy")
            let original = text(of: manifestURL)
            try await commit(MCPChange(tool: call.name, path: manifestURL.path, relativePath: "PrivacyInfo.xcprivacy",
                                       original: original, proposed: Self.auditPrivacyManifestTemplate,
                                       summary: "Generate PrivacyInfo.xcprivacy at workspace root"),
                             call: call, session: s)
            return .text("Successfully generated compliant PrivacyInfo.xcprivacy at workspace root.")
        }
        // Action: audit (any action other than 'generate' audits, as in Legacy).
        var userDefaultsUsage = 0
        var fileTimestampUsage = 0
        var diskSpaceUsage = 0
        var bootTimeUsage = 0
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" || fileURL.pathExtension == "m" else { continue }
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            if text.contains("UserDefaults") { userDefaultsUsage += 1 }
            if text.contains("contentModificationDate") || text.contains("fileModificationDate") { fileTimestampUsage += 1 }
            if text.contains("volumeAvailableCapacity") || text.contains("systemFreeSize") { diskSpaceUsage += 1 }
            if text.contains("systemUptime") || text.contains("mach_absolute_time") { bootTimeUsage += 1 }
        }
        let manifestFile = root.appendingPathComponent("PrivacyInfo.xcprivacy")
        let manifestExists = FileManager.default.fileExists(atPath: manifestFile.path)
        var report = "### Apple Required Reason API Audit Report:\n\n"
        report += "- **PrivacyInfo.xcprivacy Present**: \(manifestExists ? "✅ Yes" : "❌ No (Action recommended)")\n"
        report += "- **UserDefaults Usage**: \(userDefaultsUsage) file(s) (Requires Category `NSPrivacyAccessedAPICategoryUserDefaults`)\n"
        report += "- **File Timestamp Usage**: \(fileTimestampUsage) file(s) (Requires Category `NSPrivacyAccessedAPICategoryFileTimestamp`)\n"
        report += "- **Disk Space API Usage**: \(diskSpaceUsage) file(s) (Requires Category `NSPrivacyAccessedAPICategoryDiskSpace`)\n"
        report += "- **System Boot Time Usage**: \(bootTimeUsage) file(s) (Requires Category `NSPrivacyAccessedAPICategorySystemBootTime`)\n\n"
        if !manifestExists && (userDefaultsUsage > 0 || fileTimestampUsage > 0) {
            report += "⚠️ Required Reason APIs detected without PrivacyInfo.xcprivacy. Run with `action: 'generate'` to scaffold the required manifest."
        } else {
            report += "Compliance check complete."
        }
        return .text(report)
    }
}

extension YcodeMCPHost {
    // MARK: - Mach-O, frameworks, network security, accessibility scanner, headers, access levels

    func auditMachOBinary(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let raw = try fileReadingRequiredString(call, "binaryPath")
        let url = try resolveFileReadingPath(raw, in: s)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MCPToolError("Binary file not found at: \(url.path)")
        }
        // Legacy shelled out to `/usr/bin/file` and `xcrun otool -L`
        // (macOS-only). The port parses the binary with Ycode's own
        // `YcodeMachO` target instead; a file that is not a Mach-O, or
        // a 32-bit Mach-O, fails honestly with the parser's message.
        let file: MachOFile
        do {
            file = try MachOFile(contentsOf: url)
        } catch {
            throw MCPToolError("Not a Mach-O binary: \(error)")
        }
        var report = "### Mach-O Binary Analysis for `\(url.lastPathComponent)`:\n\n"
        report += "#### Architectures (\(file.slices.count)):\n"
        var dylibLines: [String] = []
        var seenDylibs = Set<String>()
        for slice in file.slices {
            let image: MachOImage
            do {
                image = try MachOImage(file.reader, at: slice.offset)
            } catch {
                throw MCPToolError("Not a Mach-O binary: \(error)")
            }
            let fileType = image.fileType.map { "\($0)" } ?? "file type \(hex(image.fileTypeRaw))"
            report += "- `\(slice.name)` (\(fileType), \(image.segments.count) segment(s), \(image.dylibs.count) linked librar\(image.dylibs.count == 1 ? "y" : "ies"))\n"
            if let installName = image.installName {
                report += "  - Install name: `\(installName)`\n"
            }
            if let uuid = image.uuid {
                report += "  - UUID: `\(uuid.uuidString)`\n"
            }
            if let build = image.buildVersion {
                let platform = build.platform.map { "\($0)" } ?? "platform \(hex(build.platformRaw))"
                report += "  - Build version: \(platform), minimum OS \(build.minOS), SDK \(build.sdk)\n"
            }
            if !image.rpaths.isEmpty {
                report += "  - Rpaths: \(image.rpaths.map { "`\($0)`" }.joined(separator: ", "))\n"
            }
            if image.codeSignature != nil {
                report += "  - Code signature: present\n"
            }
            if image.isEncrypted {
                report += "  - Encrypted: yes (cryptid nonzero; Ycode never decrypts)\n"
            }
            for dylib in image.dylibs {
                let key = "\(dylib.kind.rawValue):\(dylib.path)"
                guard !seenDylibs.contains(key) else { continue }
                seenDylibs.insert(key)
                dylibLines.append("`\(dylib.path)` (\(dylib.kind.rawValue), current \(dylib.currentVersion), compatibility \(dylib.compatibilityVersion))")
            }
        }
        report += "\n#### Linked Dynamic Libraries (\(dylibLines.count)):\n"
        for line in dylibLines.prefix(25) {
            report += "- \(line)\n"
        }
        return .text(report)
    }

    func auditFrameworkLinker(_ call: MCPToolCall) async throws -> MCPToolResult {
        // Legacy declares `path` but never reads it: the workspace is
        // always searched for project.pbxproj.
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        var pbxURL: URL?
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let item = enumerator?.nextObject() as? URL {
            if item.lastPathComponent == "project.pbxproj" {
                pbxURL = item
                break
            }
        }
        guard let targetPBX = pbxURL, let text = try? String(contentsOf: targetPBX, encoding: .utf8) else {
            return .text("No project.pbxproj file found in workspace.")
        }
        var linkedFrameworks: [String] = []
        let lines = text.components(separatedBy: .newlines)
        var inFrameworksPhase = false
        for line in lines {
            if line.contains("/* Frameworks */ = {") || line.contains("isa = PBXFrameworksBuildPhase;") {
                inFrameworksPhase = true
            } else if inFrameworksPhase && line.contains("};") {
                inFrameworksPhase = false
            } else if inFrameworksPhase {
                if let start = line.range(of: "/* "), let end = line.range(of: " in Frameworks */") {
                    linkedFrameworks.append(String(line[start.upperBound..<end.lowerBound]))
                }
            }
        }
        var report = "### Framework Linker Audit (`\(targetPBX.deletingLastPathComponent().lastPathComponent)`):\n\n"
        if linkedFrameworks.isEmpty {
            report += "No frameworks explicitly linked in PBXFrameworksBuildPhase (e.g. Pure SPM or auto-linked modules).\n"
        } else {
            report += "#### Linked Frameworks & Dependencies (\(linkedFrameworks.count)):\n"
            for f in linkedFrameworks {
                report += "- `\(f)`\n"
            }
        }
        return .text(report)
    }

    func auditNetworkSecurity(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        var plistURL: URL?
        if let explicit = call.string("path"), !explicit.isEmpty {
            plistURL = try resolveFileReadingPath(explicit, in: s)
        } else {
            let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                            options: [.skipsHiddenFiles, .skipsPackageDescendants])
            while let item = enumerator?.nextObject() as? URL {
                if item.lastPathComponent == "Info.plist" {
                    plistURL = item
                    break
                }
            }
        }
        guard let targetPlist = plistURL, FileManager.default.fileExists(atPath: targetPlist.path),
              let data = try? Data(contentsOf: targetPlist),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return .text("No valid Info.plist found in workspace.")
        }
        guard let ats = plist["NSAppTransportSecurity"] as? [String: Any] else {
            return .text("✅ NSAppTransportSecurity is in default secure mode (all plain HTTP requests blocked, TLS 1.2+ required).")
        }
        var report = "### App Transport Security (ATS) Audit (`\(targetPlist.lastPathComponent)`):\n\n"
        let allowsArbitrary = ats["NSAllowsArbitraryLoads"] as? Bool ?? false
        let allowsLocal = ats["NSAllowsLocalNetworking"] as? Bool ?? false
        let exceptionDomains = ats["NSExceptionDomains"] as? [String: Any] ?? [:]
        report += "- **Allows Arbitrary HTTP Loads**: \(allowsArbitrary ? "⚠️ YES (Potential App Store Review Risk)" : "✅ NO")\n"
        report += "- **Allows Local Networking**: \(allowsLocal ? "YES" : "NO")\n"
        report += "- **Exception Domains**: \(exceptionDomains.count) configured\n\n"
        if !exceptionDomains.isEmpty {
            report += "#### Configured Domain Exceptions:\n"
            for (domain, config) in exceptionDomains {
                report += "- **\(domain)**: `\(config)`\n"
            }
        }
        return .text(report)
    }

    func auditAccessibilityScanner(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let raw = try fileReadingRequiredString(call, "path")
        let targetURL = try resolveFileReadingPath(raw, in: s)
        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            throw MCPToolError("Path not found: \(raw)")
        }
        var filesToScan: [URL] = []
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDir), isDir.boolValue {
            let enumerator = FileManager.default.enumerator(at: targetURL, includingPropertiesForKeys: nil,
                                                            options: [.skipsHiddenFiles, .skipsPackageDescendants])
            while let u = enumerator?.nextObject() as? URL {
                if u.pathExtension == "swift" { filesToScan.append(u) }
            }
        } else {
            filesToScan.append(targetURL)
        }
        var warnings: [String] = []
        for file in filesToScan {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let rel = fileReadingRelativePath(of: file, in: s)
            let lines = content.components(separatedBy: .newlines)
            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Check for Image(systemName: ...) without accessibilityLabel.
                if trimmed.contains("Image(systemName:") && !trimmed.contains("accessibilityLabel") && !trimmed.contains("accessibilityHidden") {
                    // Check next few lines to see if modifier is chained.
                    let nextSnippet = lines.dropFirst(idx).prefix(4).joined(separator: "\n")
                    if !nextSnippet.contains(".accessibilityLabel") && !nextSnippet.contains(".accessibilityHidden") {
                        warnings.append("`\(rel):\(idx + 1)`: SF Symbol Image has no explicit `.accessibilityLabel` or `.accessibilityHidden(true)`.")
                    }
                }
                // Check for Button with empty string or plain image label.
                if trimmed.hasPrefix("Button(\"\")") || trimmed.hasPrefix("Button(\" \")") {
                    warnings.append("`\(rel):\(idx + 1)`: Button with empty label has no VoiceOver text description.")
                }
            }
        }
        var report = "### Accessibility Audit Report (\(filesToScan.count) files scanned):\n\n"
        if warnings.isEmpty {
            report += "✅ No obvious accessibility omissions found. All scanned interactive elements have labels or standard descriptions."
        } else {
            report += "#### ⚠️ Potential VoiceOver & Accessibility Gaps (\(warnings.count)):\n"
            for w in warnings.prefix(25) {
                report += "- \(w)\n"
            }
        }
        return .text(report)
    }

    func auditLicenseHeaders(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let root = auditResolveStrictPath(call.string("path"), in: s) else {
            throw MCPToolError("Invalid path: path must stay inside the workspace and must not contain '..'.")
        }
        // Legacy also accepts the `required_text` alias; Ycode's
        // argument validation rejects unknown arguments, so only
        // `requiredText` is accepted here.
        let rawRequired = call.arguments["requiredText"]?.string
        let requiredText = (rawRequired?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Copyright"
        let files = Self.auditEnumerateSwiftFiles(at: root)
        if files.isEmpty {
            return .structured(["scannedFiles": .int(0), "withHeader": .int(0), "missingHeader": .int(0), "missingFiles": .string("")],
                               summary: "License Header Check: no Swift files found.")
        }
        var missing: [String] = []
        var withHeader = 0
        for url in files {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let relative = Self.auditRelativePath(url, root: Self.folder(of: s.model))
            let header = text.components(separatedBy: "\n").prefix(15).joined(separator: "\n")
            if header.lowercased().contains(requiredText.lowercased()) {
                withHeader += 1
            } else {
                missing.append(relative)
            }
        }
        var output = "License Header Check: scanned \(files.count) Swift file(s) for header text \"\(requiredText)\" in the first 15 lines — \(withHeader) with header, \(missing.count) missing.\n"
        if missing.isEmpty {
            output += "All scanned files contain the required header text."
        } else {
            output += "Files missing the header text:\n"
            output += missing.map { "- \($0)" }.joined(separator: "\n")
        }
        return .structured(["scannedFiles": .int(files.count), "withHeader": .int(withHeader),
                            "missingHeader": .int(missing.count), "missingFiles": .string(missing.joined(separator: "\n"))],
                           summary: output)
    }

    func auditAccessLevels(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let root = auditResolveStrictPath(call.string("path"), in: s) else {
            throw MCPToolError("Invalid path: path must stay inside the workspace and must not contain '..'.")
        }
        let files = Self.auditEnumerateSwiftFiles(at: root)
        if files.isEmpty {
            return .structured(["scannedFiles": .int(0), "public": .int(0), "open": .int(0), "internal": .int(0),
                                "private": .int(0), "fileprivate": .int(0), "total": .int(0), "topPublicFiles": .string("")],
                               summary: "Access Level Audit: no Swift files found.")
        }
        guard let declRegex = try? NSRegularExpression(pattern: "\\b(func|class|struct|enum|protocol|actor|var|let|typealias|extension)\\b", options: []) else {
            throw MCPToolError("Access Level Audit: failed to build declaration pattern.")
        }
        var counts: [String: Int] = ["public": 0, "open": 0, "internal": 0, "private": 0, "fileprivate": 0]
        var publicPerFile: [String: Int] = [:]
        var total = 0
        for url in files {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let relative = Self.auditRelativePath(url, root: Self.folder(of: s.model))
            for line in text.components(separatedBy: "\n") {
                let range = NSRange(line.startIndex..., in: line)
                guard declRegex.firstMatch(in: line, options: [], range: range) != nil else { continue }
                let level = Self.auditAccessLevel(of: line)
                counts[level, default: 0] += 1
                total += 1
                if level == "public" || level == "open" {
                    publicPerFile[relative, default: 0] += 1
                }
            }
        }
        let topPublic = publicPerFile.sorted { $0.value > $1.value }.prefix(10)
        var output = "Access Level Audit: scanned \(files.count) Swift file(s), \(total) declaration(s) — public: \(counts["public"] ?? 0), open: \(counts["open"] ?? 0), internal: \(counts["internal"] ?? 0), private: \(counts["private"] ?? 0), fileprivate: \(counts["fileprivate"] ?? 0).\n"
        if topPublic.isEmpty {
            output += "No public/open declarations found."
        } else {
            output += "Files with the most public/open API:\n"
            for entry in topPublic {
                output += "- \(entry.key): \(entry.value) public/open declaration(s)\n"
            }
        }
        let topText = topPublic.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        return .structured(["scannedFiles": .int(files.count), "public": .int(counts["public"] ?? 0),
                            "open": .int(counts["open"] ?? 0), "internal": .int(counts["internal"] ?? 0),
                            "private": .int(counts["private"] ?? 0), "fileprivate": .int(counts["fileprivate"] ?? 0),
                            "total": .int(total), "topPublicFiles": .string(topText)],
                           summary: output)
    }
}

extension YcodeMCPHost {
    // MARK: - Binary sizes, image assets, secrets, permissions, accessibility, licenses

    func auditBinarySizes(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let pathRaw = ((call.string("path"))?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "build/"
        guard let searchRoot = auditResolveStrictPath(pathRaw, in: s) else {
            throw MCPToolError("path must be inside the workspace and must not contain '..'.")
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: searchRoot.path, isDirectory: &isDir) else {
            throw MCPToolError("Path not found at '\(pathRaw)'. Build the project first or pass a path to an existing .app bundle.")
        }
        var appBundles: [URL] = []
        if searchRoot.pathExtension == "app" {
            appBundles = [searchRoot]
        } else if isDir.boolValue {
            appBundles = Self.auditFindAppBundles(under: searchRoot)
        } else {
            throw MCPToolError("path '\(pathRaw)' is neither a .app bundle nor a directory.")
        }
        if appBundles.isEmpty {
            return .structured(["appCount": .int(0), "totalBytes": .int(0), "apps": .string("")],
                               summary: "No .app bundles found under '\(pathRaw)'. DerivedData is intentionally never scanned.")
        }
        var output = "Binary size report: \(appBundles.count) .app bundle(s)."
        var grandTotal: Int64 = 0
        var summaryParts: [String] = []
        for app in appBundles.sorted(by: { $0.path < $1.path }) {
            let files = Self.auditSizedFiles(in: app)
            let total = files.reduce(0) { $0 + $1.size }
            grandTotal += total
            let largest = files.sorted { $0.size > $1.size }.prefix(10)
            output += "\n\n\(Self.auditRelativePath(app, root: Self.folder(of: s.model))) — total \(Self.auditFormatBytes(total)) (\(total) bytes), \(files.count) file(s)"
            for entry in largest {
                output += "\n  - \(Self.auditRelativePath(entry.url, root: Self.folder(of: s.model))): \(Self.auditFormatBytes(entry.size)) (\(entry.size) bytes)"
            }
            summaryParts.append("\(app.lastPathComponent)=\(total)")
        }
        output += "\n\nGrand total: \(Self.auditFormatBytes(grandTotal)) (\(grandTotal) bytes)"
        return .structured(["appCount": .int(appBundles.count), "totalBytes": .int(Int(grandTotal)),
                            "apps": .string(summaryParts.joined(separator: ","))],
                           summary: output)
    }

    func auditImageAssetSizes(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let threshold = Int64(max(1, call.int("thresholdKB") ?? 500)) * 1024
        let root = Self.folder(of: s.model)
        let exts: Set<String> = ["png", "jpg", "jpeg", "heic", "webp", "tiff", "pdf"]
        var oversized: [(String, Int64)] = []
        var total = 0
        var totalBytes: Int64 = 0
        for url in SearchWorkspace.files(under: root, extensions: exts) {
            guard url.path.contains(".xcassets/") else { continue }
            total += 1
            let size = Self.auditFileSize(of: url)
            totalBytes += size
            if size >= threshold {
                oversized.append((SearchWorkspace.relative(url, root: root), size))
            }
        }
        if total == 0 {
            return .structured(["imageCount": .int(0), "oversizedCount": .int(0), "totalBytes": .int(0)],
                               summary: "No image files found inside .xcassets catalogs.")
        }
        oversized.sort { $0.1 > $1.1 }
        var lines = ["Asset catalog images: \(total) files, \(totalBytes) bytes total.",
                     "Oversized (≥\(threshold / 1024) KB): \(oversized.count)"]
        for (path, size) in oversized.prefix(50) {
            lines.append(String(format: "- %@ — %.1f KB", path, Double(size) / 1024.0))
        }
        if oversized.isEmpty {
            lines.append("All images are under the threshold.")
        }
        return .structured(["imageCount": .int(total), "oversizedCount": .int(oversized.count),
                            "totalBytes": .int(Int(totalBytes))],
                           summary: lines.joined(separator: "\n"))
    }

    func auditSecrets(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let rawPath = call.string("path")
        let scanRoot: URL
        if let rawPath, !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let resolved = auditResolveStrictPath(rawPath, in: s) else {
                throw MCPToolError("Invalid path: '\(rawPath)' must be a workspace-relative path without '..' and must stay inside the workspace.")
            }
            scanRoot = resolved
        } else {
            scanRoot = Self.folder(of: s.model)
        }
        let patterns: [(label: String, pattern: String, options: NSRegularExpression.Options)] = [
            (label: "AWS Access Key ID", pattern: "AKIA[0-9A-Z]{16}", options: []),
            (label: "GitHub token", pattern: "ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}", options: []),
            (label: "OpenAI-style API key", pattern: "sk-[A-Za-z0-9]{20,}", options: []),
            (label: "api_key assignment", pattern: "api[_-]?key\\s*=\\s*['\"][^'\"]+['\"]", options: [.caseInsensitive]),
            (label: "password assignment", pattern: "password\\s*=\\s*['\"][^'\"]+['\"]", options: [.caseInsensitive]),
            (label: "Private key block", pattern: "-----BEGIN [^-]* PRIVATE KEY-----", options: [])
        ]
        var compiled: [(label: String, regex: NSRegularExpression)] = []
        for entry in patterns {
            do {
                let regex = try NSRegularExpression(pattern: entry.pattern, options: entry.options)
                compiled.append((label: entry.label, regex: regex))
            } catch {
                throw MCPToolError("Failed to compile secret pattern '\(entry.label)': \(error.localizedDescription)")
            }
        }
        let files = Self.auditListScannableFiles(under: scanRoot)
        var findings: [String] = []
        var seen = Set<String>()
        var filesWithFindings = Set<String>()
        for fileURL in files {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let relative = Self.auditRelativePath(fileURL, root: Self.folder(of: s.model))
            let lines = content.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                for entry in compiled {
                    let range = NSRange(line.startIndex..<line.endIndex, in: line)
                    if entry.regex.firstMatch(in: line, options: [], range: range) != nil {
                        // NEVER include the matched value or the line content.
                        let finding = "\(relative):\(index + 1):\(entry.label)"
                        if !seen.contains(finding) {
                            seen.insert(finding)
                            findings.append(finding)
                            filesWithFindings.insert(relative)
                        }
                    }
                }
            }
        }
        let sorted = findings.sorted()
        var output = "Secrets scan: \(sorted.count) finding(s) in \(filesWithFindings.count) file(s), \(files.count) file(s) scanned."
        if sorted.isEmpty {
            output += " No secret patterns found."
        } else {
            output += "\n" + sorted.joined(separator: "\n")
        }
        return .structured(["finding_count": .int(sorted.count), "files_scanned": .int(files.count),
                            "files_with_findings": .int(filesWithFindings.count)],
                           summary: output)
    }

    func auditPermissions(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        var usageDescriptions: [String] = []
        var usageFiles: [String] = []
        var entitlementKeys: [String] = []
        var entitlementFiles: [String] = []
        var privacyAPITypes: [String] = []
        var privacyTracking: String = "not declared"
        var privacyFiles: [String] = []
        let allFiles = Self.auditListAllFiles(under: Self.folder(of: s.model))
        for fileURL in allFiles {
            let name = fileURL.lastPathComponent
            let relative = Self.auditRelativePath(fileURL, root: Self.folder(of: s.model))
            if name == "Info.plist" {
                if let plist = Self.auditReadPlist(at: fileURL) {
                    for key in plist.keys.sorted() where key.contains("UsageDescription") {
                        usageDescriptions.append(key)
                        if !usageFiles.contains(relative) { usageFiles.append(relative) }
                    }
                }
            } else if fileURL.pathExtension == "entitlements" {
                if let plist = Self.auditReadPlist(at: fileURL) {
                    for key in plist.keys.sorted() {
                        entitlementKeys.append(key)
                    }
                    entitlementFiles.append(relative)
                }
            } else if name == "PrivacyInfo.xcprivacy" {
                if let plist = Self.auditReadPlist(at: fileURL) {
                    if let tracking = plist["NSPrivacyTracking"] as? Bool {
                        privacyTracking = tracking ? "true" : "false"
                    }
                    if let apiTypes = plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]] {
                        for entry in apiTypes {
                            if let apiType = entry["NSPrivacyAccessedAPIType"] as? String {
                                privacyAPITypes.append(apiType)
                            }
                        }
                    }
                    privacyFiles.append(relative)
                }
            }
        }
        // Heuristic: API usage in Swift files that normally needs a usage description.
        let checks: [(marker: String, requiredKey: String)] = [
            (marker: "AVCaptureDevice", requiredKey: "NSCameraUsageDescription"),
            (marker: "CLLocationManager", requiredKey: "NSLocationWhenInUseUsageDescription"),
            (marker: "PHPhotoLibrary", requiredKey: "NSPhotoLibraryUsageDescription"),
            (marker: "CNContactStore", requiredKey: "NSContactsUsageDescription"),
            (marker: "AVAudioRecorder", requiredKey: "NSMicrophoneUsageDescription"),
            (marker: "EKEventStore", requiredKey: "NSCalendarsUsageDescription"),
            (marker: "HKHealthStore", requiredKey: "NSHealthShareUsageDescription"),
            (marker: "SFSpeechRecognizer", requiredKey: "NSSpeechRecognitionUsageDescription")
        ]
        let swiftFiles = allFiles.filter { $0.pathExtension == "swift" }
        var missing: [String] = []
        let usageSet = Set(usageDescriptions)
        for check in checks {
            var usedIn: [String] = []
            for fileURL in swiftFiles {
                guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
                if content.contains(check.marker) {
                    usedIn.append(Self.auditRelativePath(fileURL, root: Self.folder(of: s.model)))
                }
            }
            if !usedIn.isEmpty && !usageSet.contains(check.requiredKey) {
                // Location also accepts the Always key as an alternative.
                if check.requiredKey == "NSLocationWhenInUseUsageDescription" && usageSet.contains("NSLocationAlwaysUsageDescription") {
                    continue
                }
                missing.append("\(check.marker) used in \(usedIn.prefix(3).joined(separator: ", ")) but \(check.requiredKey) is missing")
            }
        }
        var lines: [String] = []
        lines.append("Usage descriptions (\(usageDescriptions.count)): \(usageDescriptions.sorted().joined(separator: ", "))")
        lines.append("Usage description files: \(usageFiles.joined(separator: ", "))")
        lines.append("Entitlement keys (\(entitlementKeys.count)): \(Array(Set(entitlementKeys)).sorted().joined(separator: ", "))")
        lines.append("Entitlement files: \(entitlementFiles.joined(separator: ", "))")
        lines.append("PrivacyInfo files: \(privacyFiles.joined(separator: ", "))")
        lines.append("NSPrivacyTracking: \(privacyTracking)")
        lines.append("NSPrivacyAccessedAPITypes (\(privacyAPITypes.count)): \(privacyAPITypes.sorted().joined(separator: ", "))")
        if missing.isEmpty {
            lines.append("Missing usage descriptions: none detected by heuristic.")
        } else {
            lines.append("Missing usage descriptions (\(missing.count)):")
            lines.append(contentsOf: missing.map { "  - \($0)" })
        }
        let output = "Permissions audit complete.\n" + lines.joined(separator: "\n")
        return .structured(["usage_description_count": .int(usageDescriptions.count),
                            "entitlement_count": .int(Set(entitlementKeys).count),
                            "privacy_api_count": .int(privacyAPITypes.count),
                            "missing_count": .int(missing.count),
                            "privacy_tracking": .string(privacyTracking)],
                           summary: output)
    }

    func auditAccessibility(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let scanRoot: URL
        if let rawPath = call.string("path"), !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let resolved = auditResolveStrictPath(rawPath, in: s) else {
                throw MCPToolError("Invalid path: '\(rawPath)' must be a workspace-relative path without '..' and must stay inside the workspace.")
            }
            scanRoot = resolved
        } else {
            scanRoot = Self.folder(of: s.model)
        }
        let swiftFiles = Self.auditListSwiftFiles(under: scanRoot)
        var findings: [String] = []
        for fileURL in swiftFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let relative = Self.auditRelativePath(fileURL, root: Self.folder(of: s.model))
            findings.append(contentsOf: Self.auditAccessibilityFindings(content: content, relativePath: relative))
        }
        let sorted = findings.sorted()
        var output = "Accessibility audit: \(sorted.count) finding(s) in \(swiftFiles.count) Swift file(s). Findings are heuristics; verify each one."
        if sorted.isEmpty {
            output += " No issues detected."
        } else {
            output += "\n" + sorted.joined(separator: "\n")
        }
        return .structured(["finding_count": .int(sorted.count), "files_scanned": .int(swiftFiles.count)],
                           summary: output)
    }

    func auditDependencyLicenses(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let fm = FileManager.default
        var rows: [[String]] = []
        let resolved = root.appendingPathComponent("Package.resolved")
        if fm.fileExists(atPath: resolved.path),
           let data = try? Data(contentsOf: resolved),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let pins = (json["pins"] as? [[String: Any]]) ?? (json["object"] as? [String: Any])?["pins"] as? [[String: Any]] ?? []
            for pin in pins {
                let identity = (pin["identity"] as? String) ?? (pin["package"] as? String) ?? "unknown"
                let version = ((pin["state"] as? [String: Any])?["version"] as? String) ?? "unknown"
                rows.append([identity, "SwiftPM", version, "see package repository"])
            }
        }
        let podLock = root.appendingPathComponent("Podfile.lock")
        if fm.fileExists(atPath: podLock.path), let text = try? String(contentsOf: podLock, encoding: .utf8) {
            var inPods = false
            for line in text.components(separatedBy: .newlines) {
                if line == "PODS:" { inPods = true; continue }
                if inPods {
                    if line.isEmpty || !line.hasPrefix(" ") { break }
                    let name = line.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
                    if !name.isEmpty && !name.hasPrefix("-") { rows.append([name, "CocoaPods", "", "see podspec"]) }
                }
            }
        }
        if rows.isEmpty {
            return .structured(["count": .int(0)],
                               summary: "No resolvable dependency lockfiles found (checked Package.resolved, Podfile.lock).")
        }
        let table = Self.auditMarkdownTable(headers: ["Dependency", "Manager", "Version", "License"], rows: rows)
        return .structured(["count": .int(rows.count)],
                           summary: "Dependency license inventory:\n\(table)\n\nNote: license text lives in each package's repository; verify before distribution.")
    }
}

extension YcodeMCPHost {
    // MARK: - Shared helpers for the audit tools

    /// The strict per-tool resolver (Legacy's per-tool `resolvePath` /
    /// `resolveInsideWorkspace` shape): a missing or blank path is the
    /// workspace root; any `..` component is rejected; a leading-`/`
    /// path is used as an absolute filesystem path and must lie under
    /// the root; a relative path resolves against the workspace root,
    /// never the session working directory. Returns `nil` on any
    /// violation and the caller reports its own Legacy message.
    func auditResolveStrictPath(_ raw: String?, in s: WorkspaceSession) -> URL? {
        let root = Self.folder(of: s.model).standardizedFileURL
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return root }
        guard !raw.components(separatedBy: "/").contains("..") else { return nil }
        let candidate: URL
        if raw.hasPrefix("/") {
            candidate = URL(fileURLWithPath: raw).standardizedFileURL
        } else {
            candidate = root.appendingPathComponent(raw).standardizedFileURL
        }
        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else { return nil }
        return candidate
    }

    /// Legacy `AssistPermissionsAuditTool.listAllFiles`: every file
    /// under `root`, skipping hidden files and the `.git`,
    /// `DerivedData`, `.build`, `Pods`, `node_modules`, `.swiftpm`,
    /// `Carthage`, `vendor` directories, sorted by path.
    nonisolated static func auditListAllFiles(under root: URL) -> [URL] {
        var found: [URL] = []
        let skipped = Set([".git", "DerivedData", ".build", "Pods", "node_modules", ".swiftpm", "Carthage", "vendor"])
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                              options: [.skipsHiddenFiles]) else {
            return found
        }
        for case let url as URL in enumerator {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                if skipped.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            found.append(url)
        }
        return found.sorted(by: { $0.path < $1.path })
    }

    /// Legacy `AssistAccessibilityAuditTool.listSwiftFiles`: Swift
    /// files under `root` (a single file root yields itself when it is
    /// Swift), skipping hidden files and the `.git`, `DerivedData`,
    /// `.build`, `Pods`, `node_modules`, `.swiftpm`, `Carthage`,
    /// `vendor` directories, sorted by path.
    nonisolated static func auditListSwiftFiles(under root: URL) -> [URL] {
        var found: [URL] = []
        let skipped = Set([".git", "DerivedData", ".build", "Pods", "node_modules", ".swiftpm", "Carthage", "vendor"])
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), !isDir.boolValue {
            return root.pathExtension == "swift" ? [root] : []
        }
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                              options: [.skipsHiddenFiles]) else {
            return found
        }
        for case let url as URL in enumerator {
            var itemIsDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &itemIsDir), itemIsDir.boolValue {
                if skipped.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            if url.pathExtension == "swift" {
                found.append(url)
            }
        }
        return found.sorted(by: { $0.path < $1.path })
    }

    /// Legacy `AssistAccessLevelAuditTool` / `AssistLicenseHeaderCheckTool`
    /// `enumerateSwiftFiles`: Swift files under `root` at most 300 KB
    /// each, at most 5000 files, skipping the `.git`, `DerivedData`,
    /// `.build`, `Pods`, `node_modules` directories, sorted by path.
    /// Hidden files are NOT skipped (Legacy passes no enumerator
    /// options here).
    nonisolated static func auditEnumerateSwiftFiles(at root: URL) -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir) else { return [] }
        if !isDir.boolValue {
            if root.pathExtension.lowercased() == "swift" && auditFileSize(of: root) <= 300_000 {
                return [root]
            }
            return []
        }
        var results: [URL] = []
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                                              options: []) else { return results }
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
            if auditFileSize(of: url) > 300_000 { continue }
            results.append(url)
            if results.count >= 5000 { break }
        }
        return results.sorted { $0.path < $1.path }
    }

    /// Legacy `AssistSecretsScanTool.listScannableFiles`: every file
    /// under `root` except binary-extension files, skipping the `.git`,
    /// `DerivedData`, `.build`, `Pods`, `node_modules`, `.swiftpm`,
    /// `Carthage`, `vendor`, `.doccarchive` directories. Hidden files
    /// are NOT skipped (Legacy passes no enumerator options here). A
    /// single-file root yields itself regardless of extension.
    nonisolated static func auditListScannableFiles(under root: URL) -> [URL] {
        var found: [URL] = []
        let skippedDirs = Set([".git", "DerivedData", ".build", "Pods", "node_modules", ".swiftpm", "Carthage", "vendor", ".doccarchive"])
        let skippedExtensions = Set(["png", "jpg", "jpeg", "gif", "pdf", "zip", "a", "o", "dylib", "car", "icns", "mp3", "mp4", "mov", "sqlite", "db", "xcarchive", "framework", "app", "ipa"])
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), !isDir.boolValue {
            return [root]
        }
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: []) else {
            return found
        }
        for case let url as URL in enumerator {
            var itemIsDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &itemIsDir), itemIsDir.boolValue {
                if skippedDirs.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            if skippedExtensions.contains(url.pathExtension.lowercased()) { continue }
            found.append(url)
        }
        return found.sorted(by: { $0.path < $1.path })
    }

    /// Workspace-relative display path (`"."` for the root itself),
    /// as Legacy's per-tool `relativePath` helpers compute it.
    nonisolated static func auditRelativePath(_ url: URL, root: URL) -> String {
        let rootPath = root.standardized.path
        let path = url.standardized.path
        if path == rootPath { return "." }
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return url.lastPathComponent
    }

    /// A plist file as a top-level dictionary, or `nil` when it cannot
    /// be read or is not a dictionary (Legacy's `readPlist`).
    nonisolated static func auditReadPlist(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any] else {
            return nil
        }
        return plist
    }

    /// A simple Markdown table (`| A | B |` with a `---` separator
    /// row), the shape Legacy's `AssistTextFormat.markdownTable`
    /// renders for `dependency_licenses`.
    nonisolated static func auditMarkdownTable(headers: [String], rows: [[String]]) -> String {
        var lines: [String] = []
        lines.append("| " + headers.joined(separator: " | ") + " |")
        lines.append("| " + headers.map { _ in "---" }.joined(separator: " | ") + " |")
        for row in rows {
            let cells = (0..<headers.count).map { i in
                i < row.count ? row[i].replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") : ""
            }
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }

    /// Legacy `AssistBinarySizeReportTool.formatBytes`.
    nonisolated static func auditFormatBytes(_ bytes: Int64) -> String {
        let value = Double(bytes)
        if value >= 1_048_576 {
            return String(format: "%.2f MB", value / 1_048_576)
        }
        if value >= 1_024 {
            return String(format: "%.1f KB", value / 1_024)
        }
        return "\(bytes) bytes"
    }

    /// A file's size in bytes (0 when it cannot be read), as Legacy's
    /// `AssistWorkspaceScan.fileSize` reports it.
    nonisolated static func auditFileSize(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    /// `.app` bundles under `root`, never descending into
    /// `DerivedData` (or `.git`), as Legacy's `findAppBundles` does.
    nonisolated static func auditFindAppBundles(under root: URL) -> [URL] {
        var results: [URL] = []
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                              options: [.skipsHiddenFiles]) else { return [] }
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name == ".git" || name == "DerivedData" {
                enumerator.skipDescendants()
                continue
            }
            if url.pathExtension == "app" {
                results.append(url)
                enumerator.skipDescendants()
            }
        }
        return results
    }

    /// Regular files inside an `.app` bundle with their sizes.
    nonisolated static func auditSizedFiles(in app: URL) -> [(url: URL, size: Int64)] {
        var results: [(url: URL, size: Int64)] = []
        guard let enumerator = FileManager.default.enumerator(at: app, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                                              options: [.skipsHiddenFiles]) else { return [] }
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            if let size = values.fileSize {
                results.append((url: url, size: Int64(size)))
            }
        }
        return results
    }

    /// Legacy `AssistAccessibilityAuditTool.auditFile`: the per-file
    /// heuristic — a `Button(`/`Image(` with no accessibility modifier
    /// within 10 / 5 following lines, a `TextField(` with an empty
    /// label, and a red/green/orange `foregroundColor` with no
    /// accessibility modifier.
    nonisolated static func auditAccessibilityFindings(content: String, relativePath: String) -> [String] {
        let lines = content.components(separatedBy: .newlines)
        var findings: [String] = []
        var pendingButtonLine: Int?
        var pendingButtonDeadline = 0
        var pendingImageLine: Int?
        var pendingImageDeadline = 0
        func flushButton(upTo index: Int) {
            if let line = pendingButtonLine, index > pendingButtonDeadline {
                findings.append("\(relativePath):\(line):Button without .accessibilityLabel (heuristic)")
                pendingButtonLine = nil
            }
        }
        func flushImage(upTo index: Int) {
            if let line = pendingImageLine, index > pendingImageDeadline {
                findings.append("\(relativePath):\(line):Image without .accessibilityLabel / .accessibilityHidden (heuristic)")
                pendingImageLine = nil
            }
        }
        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            let line = rawLine
            flushButton(upTo: lineNumber)
            flushImage(upTo: lineNumber)
            let hasA11y = line.contains("accessibilityLabel") || line.contains("accessibilityHidden") || line.contains("accessibilityElement")
            if hasA11y {
                pendingButtonLine = nil
                pendingImageLine = nil
            }
            if line.contains("Button(") {
                if !hasA11y {
                    if pendingButtonLine != nil {
                        flushButton(upTo: pendingButtonDeadline + 1)
                    }
                    pendingButtonLine = lineNumber
                    pendingButtonDeadline = lineNumber + 10
                }
            }
            if line.contains("Image(") {
                if !hasA11y {
                    if pendingImageLine != nil {
                        flushImage(upTo: pendingImageDeadline + 1)
                    }
                    pendingImageLine = lineNumber
                    pendingImageDeadline = lineNumber + 5
                }
            }
            if line.contains("TextField(") && line.contains("\"\"") {
                findings.append("\(relativePath):\(lineNumber):TextField with empty label (heuristic)")
            }
            if line.contains("foregroundColor") && (line.contains(".red") || line.contains(".green") || line.contains(".orange")) && !hasA11y {
                findings.append("\(relativePath):\(lineNumber):Color-only state via foregroundColor (heuristic) - pair with a label or icon")
            }
        }
        flushButton(upTo: lines.count + 100)
        flushImage(upTo: lines.count + 100)
        return findings
    }

    /// Legacy `AssistAccessLevelAuditTool.accessLevel`: public/open
    /// take precedence over fileprivate/private; anything else is the
    /// default internal level. `private(set)` still counts as private
    /// only when no higher keyword is present.
    nonisolated static func auditAccessLevel(of line: String) -> String {
        if auditContainsWord(line, "public") { return "public" }
        if auditContainsWord(line, "open") { return "open" }
        if auditContainsWord(line, "fileprivate") { return "fileprivate" }
        if auditContainsWord(line, "private") { return "private" }
        return "internal"
    }

    nonisolated static func auditContainsWord(_ line: String, _ word: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b", options: []) else { return false }
        let range = NSRange(line.startIndex..., in: line)
        return regex.firstMatch(in: line, options: [], range: range) != nil
    }

    /// Legacy's `PrivacyInfo.xcprivacy` scaffold template, verbatim:
    /// tracking off, no tracking domains, no collected data types, and
    /// the UserDefaults (`CA92.1`) and File Timestamp (`C617.1`)
    /// required-reason categories.
    nonisolated static let auditPrivacyManifestTemplate = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>NSPrivacyTracking</key>
            <false/>
            <key>NSPrivacyTrackingDomains</key>
            <array/>
            <key>NSPrivacyCollectedDataTypes</key>
            <array/>
            <key>NSPrivacyAccessedAPITypes</key>
            <array>
                <dict>
                    <key>NSPrivacyAccessedAPIType</key>
                    <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
                    <key>NSPrivacyAccessedAPITypeReasons</key>
                    <array>
                        <string>CA92.1</string>
                    </array>
                </dict>
                <dict>
                    <key>NSPrivacyAccessedAPIType</key>
                    <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
                    <key>NSPrivacyAccessedAPITypeReasons</key>
                    <array>
                        <string>C617.1</string>
                    </array>
                </dict>
            </array>
        </dict>
        </plist>
        """
}
