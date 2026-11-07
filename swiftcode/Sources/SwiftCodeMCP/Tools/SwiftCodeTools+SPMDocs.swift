import Foundation
import SwiftCodeAssistant
import SwiftCodeBuild
import SwiftCodeIDECore

extension SwiftCodeMCPHost {
    var spmDocsTools: [MCPTool] {
        let safeMutation = MCPToolAnnotations(readOnly: false, idempotent: true)
        let execution = MCPToolAnnotations(readOnly: false, idempotent: false)
        return [
            tool("swift_package_manager", "Swift Package Manager",
                 "Inspects, resolves, updates, and validates Swift Package Manager (SPM) dependencies.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "action": Schema.string("Action to perform: 'resolve', 'update', 'status', 'dump_manifest', 'describe', or any other single-token 'swift package' subcommand (e.g. 'clean', 'reset', 'show-dependencies')."),
                                       "packageDir": Schema.string("Workspace-relative directory containing Package.swift (defaults to workspace root).")],
                                      required: ["action"]),
                 annotations: execution) { h, call in
                try await h.spmDocsSwiftPackage(call)
            },
            tool("package_manifest_read", "Read Package Manifest",
                 "Reads Package.swift and summarizes the package name, platforms, products, targets, and dependencies.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to Package.swift. Default: \"Package.swift\".")]),
                 output: Schema.output(["packageName": Schema.str, "platforms": Schema.str, "products": Schema.str,
                                        "targets": Schema.str, "dependencies": Schema.str, "productCount": Schema.int,
                                        "targetCount": Schema.int, "dependencyCount": Schema.int])) { h, call in
                try h.spmDocsManifestRead(call)
            },
            tool("package_manifest_validate", "Validate Package Manifest",
                 "Validates Package.swift by running swift package dump-package and reporting the package name and target count.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to Package.swift. Default: \"Package.swift\".")]),
                 output: Schema.output(["packageName": Schema.str, "targetCount": Schema.int, "exitCode": Schema.int]),
                 annotations: execution) { h, call in
                try await h.spmDocsManifestValidate(call)
            },
            tool("package_dependency_add", "Add Package Dependency",
                 "Inserts a .package(url:from:) entry into the dependencies array in Package.swift.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "url": Schema.string("Repository URL of the package (e.g. https://github.com/apple/swift-argument-parser)."),
                                       "requirement": Schema.string("Requirement such as 'from: \"1.0.0\"' or just '1.0.0'. Default: 'from: \"1.0.0\"'."),
                                       "product": Schema.string("Optional product name to wire into a target's dependencies."),
                                       "target": Schema.string("Optional target name whose dependencies array should gain the product.")],
                                      required: ["url"]),
                 output: Schema.output(["url": Schema.str, "requirement": Schema.str, "targetWiring": Schema.str,
                                        "alreadyPresent": Schema.bool]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.spmDocsDependencyAdd(call)
            },
            tool("package_dependency_audit", "Audit Package Dependencies",
                 "Audits Swift package dependencies from Package.swift and Package.resolved, flagging missing pins and unpinned requirements.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["declaredCount": Schema.int, "pinnedCount": Schema.int, "hasResolved": Schema.bool,
                                        "unpinnedCount": Schema.int, "unpinned": Schema.str, "flags": Schema.str])) { h, call in
                try await h.spmDocsDependencyAudit(call)
            },
            tool("package_dependency_update", "Update Package Dependencies",
                 "Runs swift package update in the workspace root to update Swift package dependencies.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "package": Schema.string("Optional single dependency name to update. When omitted, all dependencies are updated.")]),
                 output: Schema.output(["exitCode": Schema.int, "outputTail": Schema.str]),
                 annotations: execution) { h, call in
                try await h.spmDocsDependencyUpdate(call)
            },
            tool("spm_dependency_tree", "SPM Dependency Tree",
                 "Parses Package.resolved and Package.swift to construct the complete resolved dependency tree.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Optional explicit path to Package.resolved. If omitted, workspace is searched.")])) { h, call in
                try h.spmDocsDependencyTree(call)
            },
            tool("carthage_cartfile_inspector", "Carthage Cartfile Inspector",
                 "Inspects Carthage dependencies and resolved versions in Cartfile and Cartfile.resolved.",
                 input: Schema.object(["workspace": Schema.workspace])) { h, call in
                try h.spmDocsCarthageInspector(call)
            },
            tool("podfile_inspector", "Podfile & CocoaPods Inspector",
                 "Inspects CocoaPods dependencies, versions, and target configurations in Podfile and Podfile.lock.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Optional directory containing Podfile. Defaults to workspace root.")])) { h, call in
                try h.spmDocsPodfileInspector(call)
            },
            tool("docc_build", "Build DocC Docs",
                 "Builds DocC documentation with xcodebuild docbuild and verifies a .doccarchive was produced.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "scheme": Schema.string("The scheme to document (required)."),
                                       "destination": Schema.string("xcodebuild destination. Default is platform=macOS."),
                                       "outputPath": Schema.string("Workspace-relative derived-data directory (optional). Default is .docc-derived.")],
                                      required: ["scheme"]),
                 output: Schema.output(["scheme": Schema.str, "destination": Schema.str,
                                        "archive_path": Schema.str, "archive_relative": Schema.str]),
                 annotations: execution) { h, call in
                try await h.spmDocsDoccBuild(call)
            },
            tool("docs_generate", "Generate Docs",
                 "Generates a markdown API document from public Swift declarations in the workspace. Refuses to overwrite unless overwrite is true.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "outputPath": Schema.string("Workspace-relative output path. Default is DOCS_GENERATED.md."),
                                       "title": Schema.string("Document title (optional)."),
                                       "overwrite": Schema.string("Set to true to overwrite an existing output file. Default is false.")]),
                 output: Schema.output(["output_path": Schema.str, "output_relative": Schema.str,
                                        "file_count": Schema.int, "declaration_count": Schema.int]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.spmDocsDocsGenerate(call)
            },
            tool("docs_index_build", "Docs Index Build",
                 "Builds an index of all Markdown files in the workspace: path, title (first heading), and size.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["count": Schema.int])) { h, call in
                try h.spmDocsDocsIndex(call)
            },
            tool("project_changelog", "View Changelog",
                 "Displays the history of project snapshots and changes.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["log": Schema.str])) { h, call in
                try h.spmDocsChangelog(call)
            },
        ]
    }
}

extension SwiftCodeMCPHost {

    func spmDocsSwiftPackage(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let action = call.arguments["action"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !action.isEmpty else {
            throw MCPToolError("Missing required parameter: action")
        }
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let targetDir: URL
        if let packageDir = call.arguments["packageDir"]?.string, !packageDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                targetDir = try resolveFileReadingPath(packageDir, in: s)
            } catch {
                throw MCPToolError("packageDir must be inside the workspace and must not contain '..'.")
            }
        } else {
            targetDir = root
        }
        let packageSwiftPath = targetDir.appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: packageSwiftPath.path) else {
            throw MCPToolError("Package.swift not found at \(packageSwiftPath.path)")
        }
        guard FileManager.default.fileExists(atPath: "/usr/bin/swift") else {
            throw MCPToolError("Swift not found at /usr/bin/swift.")
        }
        var arguments = ["package"]
        switch action.lowercased() {
        case "resolve": arguments.append("resolve")
        case "update": arguments.append("update")
        case "status": arguments.append("status")
        case "dump_manifest": arguments.append("dump-package")
        case "describe": arguments.append("describe")
        default:
            let token = action.lowercased()
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_-")
            guard !token.isEmpty, token.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
                throw MCPToolError("Unsupported action '\(action)'. Valid: resolve, update, status, dump_manifest, describe, or a single-token 'swift package' subcommand.")
            }
            arguments.append(token)
        }
        guard let run = (await Task.detached {
            Self.terminalRunFixed("/usr/bin/swift", arguments, workingDirectory: targetDir, timeout: 300)
        }.value) else {
            throw MCPToolError("Failed to execute swift package: could not start /usr/bin/swift.")
        }
        if run.timedOut {
            throw MCPToolError("SPM \(action) timed out after 300 seconds.")
        }
        if run.exitCode == 0 {
            return .text(run.stdout.isEmpty ? "SPM \(action) completed successfully." : run.stdout)
        }
        throw MCPToolError("SPM \(action) failed with code \(run.exitCode):\n\(run.stderr)\n\(run.stdout)")
    }

    func spmDocsManifestRead(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let rawPath = call.arguments["path"]?.string ?? "Package.swift"
        let url: URL
        do {
            url = try resolveFileReadingPath(rawPath, in: s)
        } catch {
            throw MCPToolError("Invalid path '\(rawPath)': must be inside the workspace and must not contain '..'.")
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MCPToolError("Package manifest not found at '\(rawPath)'.")
        }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            throw MCPToolError("Failed to read Package.swift at '\(rawPath)'.")
        }
        let packageName = Self.spmDocsExtractPackageName(from: content) ?? "unknown"
        let platforms = Self.spmDocsExtractPlatforms(from: content)
        let products = Self.spmDocsExtractNames(after: "products:", in: content, cap: 200)
        let targets = Self.spmDocsExtractTargetNames(from: content)
        let dependencies = Self.spmDocsExtractDependencyURLs(from: content)
        let targetCount = Self.spmDocsCountOccurrences(of: [".target(", ".testTarget(", ".executableTarget(", ".binaryTarget(", ".macro("], in: content)
        let productCount = Self.spmDocsCountOccurrences(of: [".library(", ".executable("], in: content)
        let lines = [
            "Package: \(packageName)",
            "Manifest: \(rawPath)",
            "Platforms: \(platforms.isEmpty ? "none declared" : platforms.joined(separator: ", "))",
            "Products (\(productCount)): \(products.isEmpty ? "none" : products.joined(separator: ", "))",
            "Targets (\(targetCount)): \(targets.isEmpty ? "none" : targets.joined(separator: ", "))",
            "Dependencies (\(dependencies.count)): \(dependencies.isEmpty ? "none" : dependencies.joined(separator: ", "))",
        ]
        return .structured(["packageName": .string(packageName),
                            "platforms": .string(platforms.joined(separator: ",")),
                            "products": .string(products.joined(separator: ",")),
                            "targets": .string(targets.joined(separator: ",")),
                            "dependencies": .string(dependencies.joined(separator: ",")),
                            "productCount": .int(productCount),
                            "targetCount": .int(targetCount),
                            "dependencyCount": .int(dependencies.count)],
                           summary: lines.joined(separator: "\n"))
    }

    func spmDocsManifestValidate(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard FileManager.default.fileExists(atPath: "/usr/bin/swift") else {
            throw MCPToolError("Swift not found at /usr/bin/swift.")
        }
        let s = try session(for: call)
        let rawPath = call.arguments["path"]?.string ?? "Package.swift"
        let manifestURL: URL
        do {
            manifestURL = try resolveFileReadingPath(rawPath, in: s)
        } catch {
            throw MCPToolError("Invalid path '\(rawPath)': must be inside the workspace and must not contain '..'.")
        }
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw MCPToolError("Package manifest not found at '\(rawPath)'.")
        }
        let workingDir = manifestURL.deletingLastPathComponent()
        let root = Self.folder(of: s.model)
        guard Self.isInside(workingDir.standardizedFileURL, root) || workingDir.standardizedFileURL.path == root.standardizedFileURL.path else {
            throw MCPToolError("Manifest directory is outside the workspace.")
        }
        guard let run = (await Task.detached {
            Self.terminalRunFixed("/usr/bin/swift", ["package", "dump-package"], workingDirectory: workingDir, timeout: 300)
        }.value) else {
            throw MCPToolError("Failed to start swift package dump-package: could not start /usr/bin/swift.")
        }
        if run.timedOut {
            throw MCPToolError("swift package dump-package timed out after 300 seconds.")
        }
        if run.exitCode != 0 {
            throw MCPToolError("Package manifest is invalid: swift package dump-package exited with code \(run.exitCode).\n\(String(run.stderr.suffix(2000)))")
        }
        var packageName = "unknown"
        var targetCount = 0
        if let data = run.stdout.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let name = json["name"] as? String { packageName = name }
            if let targets = json["targets"] as? [[String: Any]] { targetCount = targets.count }
        }
        return .structured(["packageName": .string(packageName), "targetCount": .int(targetCount),
                            "exitCode": .int(Int(run.exitCode))],
                           summary: "Package manifest is valid: \(packageName) with \(targetCount) target(s).")
    }

    func spmDocsDependencyAdd(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let url = call.arguments["url"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else {
            throw MCPToolError("Missing required parameter: url")
        }
        if url.contains(" ") || url.contains("\n") || url.contains("\r") || url.contains("\"") {
            throw MCPToolError("Invalid url: must not contain spaces, newlines, or quotes.")
        }
        let requirement = Self.spmDocsNormalizedRequirement(call.arguments["requirement"]?.string ?? "from: \"1.0.0\"")
        let product = call.arguments["product"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = call.arguments["target"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let manifestURL = root.appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw MCPToolError("Package.swift not found in the workspace root.")
        }
        guard var content = try? String(contentsOf: manifestURL, encoding: .utf8) else {
            throw MCPToolError("Failed to read Package.swift.")
        }
        let original = content
        if content.contains(url) {
            return .structured(["url": .string(url), "requirement": .string(requirement),
                                "targetWiring": .string("none"), "alreadyPresent": .bool(true)],
                               summary: "Dependency already present in Package.swift: \(url)")
        }
        guard let depsRange = Self.spmDocsDependenciesArrayRange(in: content) else {
            throw MCPToolError("Could not find a 'dependencies:' array in Package.swift. Add one manually first.")
        }
        let entry = ".package(url: \"\(url)\", \(requirement))"
        guard Self.spmDocsInsertEntry(entry, into: &content, range: depsRange) else {
            throw MCPToolError("Failed to insert the dependency into the dependencies array.")
        }
        var targetWiringNote = "none"
        if let product, !product.isEmpty, let target, !target.isEmpty {
            if Self.spmDocsInsertProductIntoTarget(product: product, target: target, content: &content) {
                targetWiringNote = "wired product '\(product)' into target '\(target)'"
            } else {
                targetWiringNote = "package added but target '\(target)' dependencies array not found; product '\(product)' not wired"
            }
        } else if (product != nil && !(product?.isEmpty ?? true)) || (target != nil && !(target?.isEmpty ?? true)) {
            targetWiringNote = "both product and target are required for target wiring; package added without wiring"
        }
        let rel = fileReadingRelativePath(of: manifestURL, in: s)
        try await commit(MCPChange(tool: call.name, path: manifestURL.path, relativePath: rel,
                                   original: original,
                                   proposed: content, summary: "Add dependency \(url) to Package.swift"),
                         call: call, session: s)
        guard let reRead = try? String(contentsOf: manifestURL, encoding: .utf8), reRead.contains(url) else {
            throw MCPToolError("Verification failed: url not present in Package.swift after write.")
        }
        return .structured(["url": .string(url), "requirement": .string(requirement),
                            "targetWiring": .string(targetWiringNote), "alreadyPresent": .bool(false)],
                           summary: "Added dependency \(url) to Package.swift. Target wiring: \(targetWiringNote)")
    }

    func spmDocsDependencyAudit(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let manifestURL = root.appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw MCPToolError("Package.swift not found in the workspace root.")
        }
        guard let content = try? String(contentsOf: manifestURL, encoding: .utf8) else {
            throw MCPToolError("Failed to read Package.swift.")
        }
        let declared = Self.spmDocsExtractDeclaredDependencies(from: content)
        let resolvedURL = root.appendingPathComponent("Package.resolved")
        var pinned: [String: String] = [:]
        var hasResolved = false
        if FileManager.default.fileExists(atPath: resolvedURL.path) {
            hasResolved = true
            if let data = try? Data(contentsOf: resolvedURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var pins: [[String: Any]] = []
                if let direct = json["pins"] as? [[String: Any]] {
                    pins = direct
                } else if let object = json["object"] as? [String: Any], let nested = object["pins"] as? [[String: Any]] {
                    pins = nested
                }
                for pin in pins {
                    let identity = (pin["identity"] as? String) ?? (pin["package"] as? String) ?? ""
                    var version = ""
                    if let state = pin["state"] as? [String: Any] {
                        version = (state["version"] as? String) ?? (state["revision"] as? String) ?? ""
                    }
                    if !identity.isEmpty { pinned[identity.lowercased()] = version }
                }
            }
        }
        var flags: [String] = []
        if !hasResolved {
            flags.append("Missing Package.resolved: dependencies are not pinned to exact revisions.")
        }
        var unpinned: [String] = []
        var pinnedList: [String] = []
        for dep in declared {
            if dep.isExact { pinnedList.append(dep.url) } else { unpinned.append(dep.url) }
            if hasResolved && pinned[dep.name.lowercased()] == nil && !dep.url.isEmpty {
                flags.append("Declared dependency not in Package.resolved: \(dep.url)")
            }
        }
        var lines: [String] = []
        lines.append("Package dependencies: \(declared.count) declared, \(pinned.count) pinned in Package.resolved")
        lines.append("Package.resolved present: \(hasResolved ? "yes" : "no")")
        lines.append("Exact requirements: \(pinnedList.count); non-exact requirements: \(unpinned.count)")
        if !declared.isEmpty {
            lines.append("Dependencies:")
            for dep in declared {
                lines.append("- \(dep.url) (requirement: \(dep.requirement), resolved: \(pinned[dep.name.lowercased()] ?? "unpinned"))")
            }
        }
        if !flags.isEmpty {
            lines.append("Flags:")
            for flag in flags { lines.append("- \(flag)") }
        }
        let showDeps = (await Task.detached {
            guard FileManager.default.fileExists(atPath: "/usr/bin/swift") else { return "" }
            guard let run = Self.terminalRunFixed("/usr/bin/swift", ["package", "show-dependencies"],
                                                  workingDirectory: root, timeout: 120),
                  !run.timedOut, run.exitCode == 0 else { return "" }
            return String(run.stdout.suffix(2000))
        }.value)
        if !showDeps.isEmpty {
            lines.append("swift package show-dependencies:")
            lines.append(showDeps)
        }
        return .structured(["declaredCount": .int(declared.count), "pinnedCount": .int(pinned.count),
                            "hasResolved": .bool(hasResolved), "unpinnedCount": .int(unpinned.count),
                            "unpinned": .string(unpinned.joined(separator: ",")),
                            "flags": .string(flags.joined(separator: "; "))],
                           summary: lines.joined(separator: "\n"))
    }

    func spmDocsDependencyUpdate(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard FileManager.default.fileExists(atPath: "/usr/bin/swift") else {
            throw MCPToolError("Swift not found at /usr/bin/swift.")
        }
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let manifestURL = root.appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw MCPToolError("Package.swift not found in the workspace root.")
        }
        var args = ["package", "update"]
        if let package = call.arguments["package"]?.string {
            let trimmed = package.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if trimmed.contains(" ") || trimmed.contains("/") || trimmed.contains("..") {
                    throw MCPToolError("Invalid package name: must be a single dependency name without spaces, slashes, or '..'.")
                }
                args.append(trimmed)
            }
        }
        guard let run = (await Task.detached {
            Self.terminalRunFixed("/usr/bin/swift", args, workingDirectory: root, timeout: 300)
        }.value) else {
            throw MCPToolError("Failed to start swift package update: could not start /usr/bin/swift.")
        }
        if run.timedOut {
            throw MCPToolError("swift package update timed out after 300 seconds.")
        }
        let tail = String((run.stdout + "\n" + run.stderr).suffix(2000))
        if run.exitCode == 0 {
            return .structured(["exitCode": .int(Int(run.exitCode)), "outputTail": .string(tail)],
                               summary: "swift package update succeeded (exit 0).\n\(tail)")
        }
        throw MCPToolError("swift package update failed with exit code \(run.exitCode).\n\(tail)")
    }
}

extension SwiftCodeMCPHost {

    func spmDocsDependencyTree(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        var resolvedURL: URL?
        if let explicit = call.arguments["path"]?.string, !explicit.isEmpty {
            do {
                resolvedURL = try resolveFileReadingPath(explicit, in: s)
            } catch {
                throw MCPToolError("Invalid path '\(explicit)': must be inside the workspace and must not contain '..'.")
            }
        } else {
            let candidates = [
                root.appendingPathComponent("Package.resolved"),
                root.appendingPathComponent(".swiftpm/xcode/package.resolved"),
                root.appendingPathComponent("SwiftCode.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"),
            ]
            for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
                resolvedURL = candidate
                break
            }
            if resolvedURL == nil {
                let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                while let item = enumerator?.nextObject() as? URL {
                    if item.lastPathComponent.lowercased() == "package.resolved" {
                        resolvedURL = item
                        break
                    }
                }
            }
        }
        guard let targetFile = resolvedURL, FileManager.default.fileExists(atPath: targetFile.path),
              let data = try? Data(contentsOf: targetFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .text("No Package.resolved file found in workspace.")
        }
        let pins = Self.spmDocsPins(from: json)
        let rel = fileReadingRelativePath(of: targetFile, in: s)
        var report = "### SPM Dependency Tree (`\(rel)`):\n\n"
        report += "- **Total Resolved Packages**: \(pins.count)\n\n"
        for pin in pins.sorted(by: { $0.identity < $1.identity }) {
            report += "- **\(pin.identity)** @ `\(pin.version)` (\(pin.revision))\n  - URL: `\(pin.location)`\n"
        }
        return .text(report)
    }

    func spmDocsCarthageInspector(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let cartfile = root.appendingPathComponent("Cartfile")
        let cartfileResolved = root.appendingPathComponent("Cartfile.resolved")
        guard FileManager.default.fileExists(atPath: cartfile.path) || FileManager.default.fileExists(atPath: cartfileResolved.path) else {
            return .text("No Carthage Cartfile or Cartfile.resolved found in workspace root.")
        }
        var report = "### Carthage Dependencies Report:\n\n"
        if FileManager.default.fileExists(atPath: cartfile.path), let text = try? String(contentsOf: cartfile, encoding: .utf8) {
            let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("#") }
            report += "#### Declared in Cartfile:\n"
            for line in lines { report += "- `\(line)`\n" }
            report += "\n"
        }
        if FileManager.default.fileExists(atPath: cartfileResolved.path), let text = try? String(contentsOf: cartfileResolved, encoding: .utf8) {
            let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            report += "#### Resolved in Cartfile.resolved:\n"
            for line in lines { report += "- `\(line)`\n" }
        }
        return .text(report)
    }

    func spmDocsPodfileInspector(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let podfile = root.appendingPathComponent("Podfile")
        let podfileLock = root.appendingPathComponent("Podfile.lock")
        guard FileManager.default.fileExists(atPath: podfile.path) || FileManager.default.fileExists(atPath: podfileLock.path) else {
            return .text("No CocoaPods Podfile or Podfile.lock found in workspace root.")
        }
        var report = "### CocoaPods Project Inspection:\n\n"
        if FileManager.default.fileExists(atPath: podfile.path), let content = try? String(contentsOf: podfile, encoding: .utf8) {
            let podLines = content.components(separatedBy: .newlines).filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("pod ") }
            report += "#### Declared Pods in Podfile (\(podLines.count)):\n"
            for line in podLines { report += "- `\(line.trimmingCharacters(in: .whitespaces))`\n" }
            report += "\n"
        }
        if FileManager.default.fileExists(atPath: podfileLock.path), let lockContent = try? String(contentsOf: podfileLock, encoding: .utf8) {
            let lines = lockContent.components(separatedBy: .newlines)
            var podsSection = false
            var lockedPods: [String] = []
            for line in lines {
                if line.hasPrefix("PODS:") {
                    podsSection = true
                    continue
                } else if podsSection && (!line.hasPrefix("  - ") && !line.hasPrefix("    - ") && !line.trimmingCharacters(in: .whitespaces).isEmpty && !line.hasPrefix(" ")) {
                    break
                }
                if podsSection && line.hasPrefix("  - ") {
                    lockedPods.append(line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "- ", with: ""))
                }
            }
            report += "#### Locked Pod Versions (\(lockedPods.count)):\n"
            for pod in lockedPods.prefix(20) { report += "- `\(pod)`\n" }
        }
        return .text(report)
    }

    func spmDocsDoccBuild(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let scheme = call.arguments["scheme"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !scheme.isEmpty else {
            throw MCPToolError("Missing required parameter: scheme")
        }
        guard !scheme.contains("\n") && !scheme.contains("\r") else {
            throw MCPToolError("Invalid scheme: scheme must not contain newlines.")
        }
        let destination = (call.arguments["destination"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "platform=macOS"
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let derivedDataURL: URL
        if let rawOutput = call.arguments["outputPath"]?.string, !rawOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                derivedDataURL = try resolveFileReadingPath(rawOutput, in: s)
            } catch {
                throw MCPToolError("Invalid outputPath: '\(rawOutput)' must be a workspace-relative path without '..' and must stay inside the workspace.")
            }
        } else {
            derivedDataURL = root.appendingPathComponent(".docc-derived")
        }
        guard FileManager.default.fileExists(atPath: "/usr/bin/xcodebuild") else {
            throw MCPToolError("xcodebuild not found at /usr/bin/xcodebuild. Install Xcode command line tools first.")
        }
        let arguments = ["docbuild", "-scheme", scheme, "-destination", destination,
                         "-derivedDataPath", derivedDataURL.path]
        guard let run = (await Task.detached {
            Self.terminalRunFixed("/usr/bin/xcodebuild", arguments, workingDirectory: root, timeout: 600)
        }.value) else {
            throw MCPToolError("Failed to start xcodebuild docbuild: could not start /usr/bin/xcodebuild.")
        }
        if run.timedOut {
            throw MCPToolError("xcodebuild docbuild timed out after 600 seconds.")
        }
        guard run.exitCode == 0 else {
            throw MCPToolError("xcodebuild docbuild failed (exit \(run.exitCode), scheme: \(scheme)): \(String(run.stderr.trimmingCharacters(in: .whitespacesAndNewlines).suffix(2000)))")
        }
        let archives = Self.spmDocsFindDoccArchives(under: derivedDataURL)
        guard let archive = archives.sorted(by: { $0.path < $1.path }).first else {
            throw MCPToolError("xcodebuild docbuild succeeded but no .doccarchive was found under \(derivedDataURL.path).")
        }
        let relativeArchive = fileReadingRelativePath(of: archive, in: s)
        return .structured(["scheme": .string(scheme), "destination": .string(destination),
                            "archive_path": .string(archive.path), "archive_relative": .string(relativeArchive)],
                           summary: "DocC build succeeded for scheme \(scheme). Archive: \(relativeArchive)")
    }

    func spmDocsDocsGenerate(_ call: MCPToolCall) async throws -> MCPToolResult {
        let rawOutput = call.arguments["outputPath"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        let outputRelative = (rawOutput?.isEmpty == false) ? rawOutput! : "DOCS_GENERATED.md"
        let s = try session(for: call)
        let outputURL: URL
        do {
            outputURL = try resolveFileReadingPath(outputRelative, in: s)
        } catch {
            throw MCPToolError("Invalid outputPath: '\(outputRelative)' must be a workspace-relative path without '..' and must stay inside the workspace.")
        }
        let overwrite = (call.arguments["overwrite"]?.string ?? "").lowercased() == "true"
        if FileManager.default.fileExists(atPath: outputURL.path) && !overwrite {
            throw MCPToolError("Refusing to overwrite existing file at '\(outputRelative)'. Pass overwrite=true to replace it.")
        }
        let title = call.arguments["title"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTitle = (title?.isEmpty == false) ? title! : "Generated API Documentation"
        let root = Self.folder(of: s.model)
        let swiftFiles = Self.spmDocsListSwiftFiles(under: root)
        var sections: [String] = []
        var totalDeclarations = 0
        for fileURL in swiftFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let relative = fileReadingRelativePath(of: fileURL, in: s)
            let header = Self.spmDocsFileHeader(from: content)
            let declarations = Self.spmDocsPublicDeclarations(from: content)
            totalDeclarations += declarations.count
            var section = "## \(relative)\n\n"
            if !header.isEmpty { section += header + "\n\n" }
            if declarations.isEmpty {
                section += "_No public declarations found._\n"
            } else {
                for declaration in declarations { section += "- `\(declaration)`\n" }
            }
            sections.append(section)
        }
        let formatter = ISO8601DateFormatter()
        var markdown = "# \(effectiveTitle)\n\n"
        markdown += "- Generated: \(formatter.string(from: Date()))\n"
        markdown += "- Workspace: \(root.path)\n"
        markdown += "- Swift files: \(swiftFiles.count)\n"
        markdown += "- Public declarations: \(totalDeclarations)\n\n"
        if sections.isEmpty {
            markdown += "_No Swift files found in the workspace._\n"
        } else {
            markdown += sections.joined(separator: "\n")
        }
        let original = try? String(contentsOf: outputURL, encoding: .utf8)
        let rel = fileReadingRelativePath(of: outputURL, in: s)
        do {
            try await commit(MCPChange(tool: call.name, path: outputURL.path, relativePath: rel,
                                       original: original, proposed: markdown,
                                       summary: "Generate docs at \(outputRelative)"),
                             call: call, session: s)
        } catch let error as MCPToolError {
            throw error
        } catch {
            throw MCPToolError("Failed to write docs to '\(outputRelative)': \(error.localizedDescription)")
        }
        return .structured(["output_path": .string(outputURL.path), "output_relative": .string(outputRelative),
                            "file_count": .int(swiftFiles.count), "declaration_count": .int(totalDeclarations)],
                           summary: "Generated docs for \(swiftFiles.count) Swift file(s), \(totalDeclarations) public declaration(s), at \(outputRelative)")
    }

    func spmDocsDocsIndex(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let docs = Self.spmDocsListMarkdownFiles(under: root)
        if docs.isEmpty {
            return .structured(["count": .int(0)], summary: "No Markdown files found in the workspace.")
        }
        var rows: [String] = []
        for url in docs.sorted(by: { $0.path < $1.path }) {
            let rel = fileReadingRelativePath(of: url, in: s)
            let title = (try? String(contentsOf: url, encoding: .utf8))?
                .components(separatedBy: .newlines)
                .first(where: { $0.hasPrefix("# ") })?
                .replacingOccurrences(of: "# ", with: "")
                .prefix(80).description ?? "(no title)"
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
            rows.append("| \(rel) | \(title) | \(size?.intValue ?? 0) |")
        }
        let table = "| Path | Title | Bytes |\n| --- | --- | --- |\n" + rows.joined(separator: "\n")
        return .structured(["count": .int(docs.count)],
                           summary: "Markdown index (\(docs.count) files):\n\(table)")
    }

    func spmDocsChangelog(_ call: MCPToolCall) throws -> MCPToolResult {
        let snapshots = (try? AssistSnapshotFunctions.listSnapshots()) ?? []
        let log = snapshots.map { "[\($0.timestamp)] \($0.message) (ID: \($0.id))" }.joined(separator: "\n")
        return .structured(["log": .string(log.isEmpty ? "No snapshot history found." : log)],
                           summary: "Changelog retrieved successfully.")
    }
}

extension SwiftCodeMCPHost {

    nonisolated static func spmDocsFirstQuotedString(in text: String) -> String? {
        guard let open = text.firstIndex(of: "\"") else { return nil }
        let afterOpen = text.index(after: open)
        guard let close = text[afterOpen...].firstIndex(of: "\"") else { return nil }
        return String(text[afterOpen..<close])
    }

    nonisolated static func spmDocsExtractPackageName(from content: String) -> String? {
        guard let range = content.range(of: "name:") else { return nil }
        return spmDocsFirstQuotedString(in: String(content[range.upperBound...]))
    }

    nonisolated static func spmDocsExtractPlatforms(from content: String) -> [String] {
        var found: [String] = []
        for platform in ["iOS", "macOS", "watchOS", "tvOS", "visionOS", "linux"] where content.contains(".\(platform)(") {
            found.append(platform)
        }
        return found
    }

    nonisolated static func spmDocsExtractNames(after marker: String, in content: String, cap: Int) -> [String] {
        guard let markerRange = content.range(of: marker) else { return [] }
        let after = String(content[markerRange.upperBound...])
        var names: [String] = []
        var searchFrom = after.startIndex
        while let nameRange = after.range(of: "name:", range: searchFrom..<after.endIndex) {
            if let quoted = spmDocsFirstQuotedString(in: String(after[nameRange.upperBound...])) {
                names.append(quoted)
            }
            searchFrom = nameRange.upperBound
            if names.count >= cap { break }
        }
        return names
    }

    nonisolated static func spmDocsExtractTargetNames(from content: String) -> [String] {
        guard let markerRange = content.range(of: "targets:") else { return [] }
        let after = String(content[markerRange.upperBound...])
        var names: [String] = []
        var searchFrom = after.startIndex
        while let nameRange = after.range(of: "name:", range: searchFrom..<after.endIndex) {
            if let quoted = spmDocsFirstQuotedString(in: String(after[nameRange.upperBound...])) {
                names.append(quoted)
            }
            searchFrom = nameRange.upperBound
            if names.count >= 500 { break }
        }
        return names
    }

    nonisolated static func spmDocsExtractDependencyURLs(from content: String) -> [String] {
        var urls: [String] = []
        var searchFrom = content.startIndex
        while let pkgRange = content.range(of: ".package(", range: searchFrom..<content.endIndex) {
            let rest = String(content[pkgRange.upperBound...])
            if let urlRange = rest.range(of: "url:"),
               let quoted = spmDocsFirstQuotedString(in: String(rest[urlRange.upperBound...])) {
                urls.append(quoted)
            }
            searchFrom = pkgRange.upperBound
            if urls.count >= 200 { break }
        }
        return urls
    }

    nonisolated static func spmDocsCountOccurrences(of needles: [String], in content: String) -> Int {
        var total = 0
        for needle in needles {
            total += content.components(separatedBy: needle).count - 1
        }
        return total
    }

    struct SpmDocsDeclaredDependency: Sendable {
        let url: String
        let name: String
        let requirement: String
        let isExact: Bool
    }

    nonisolated static func spmDocsExtractDeclaredDependencies(from content: String) -> [SpmDocsDeclaredDependency] {
        var results: [SpmDocsDeclaredDependency] = []
        var searchFrom = content.startIndex
        while let pkgRange = content.range(of: ".package(", range: searchFrom..<content.endIndex) {
            let rest = String(content[pkgRange.upperBound...])
            let segment = String(rest.prefix(600))
            var url = ""
            if let urlRange = segment.range(of: "url:") {
                url = spmDocsFirstQuotedString(in: String(segment[urlRange.upperBound...])) ?? ""
            }
            var requirement = "unknown"
            var isExact = false
            if segment.contains("exact:") {
                requirement = "exact"
                isExact = true
            } else if segment.contains("from:") {
                requirement = "from"
            } else if segment.contains("upToNextMajor") {
                requirement = "upToNextMajor"
            } else if segment.contains("upToNextMinor") {
                requirement = "upToNextMinor"
            } else if segment.contains("branch:") {
                requirement = "branch"
            } else if segment.contains("revision:") {
                requirement = "revision"
            } else if segment.contains("range:") {
                requirement = "range"
            }
            let name = url.split(separator: "/").last.map { String($0).replacingOccurrences(of: ".git", with: "") } ?? ""
            if !url.isEmpty {
                results.append(SpmDocsDeclaredDependency(url: url, name: name, requirement: requirement, isExact: isExact))
            }
            searchFrom = pkgRange.upperBound
            if results.count >= 200 { break }
        }
        return results
    }

    struct SpmDocsPin: Sendable {
        let identity: String
        let location: String
        let version: String
        let revision: String
    }

    nonisolated static func spmDocsPins(from json: [String: Any]) -> [SpmDocsPin] {
        var rawPins: [[String: Any]] = []
        if let direct = json["pins"] as? [[String: Any]] {
            rawPins = direct
        } else if let object = json["object"] as? [String: Any], let nested = object["pins"] as? [[String: Any]] {
            rawPins = nested
        }
        return rawPins.map { pin in
            let identity = pin["identity"] as? String ?? (pin["package"] as? String ?? "unknown")
            let location = pin["location"] as? String ?? (pin["repositoryURL"] as? String ?? "")
            let state = pin["state"] as? [String: Any] ?? [:]
            let version = state["version"] as? String ?? "unversioned"
            let revision = String((state["revision"] as? String ?? "").prefix(8))
            return SpmDocsPin(identity: identity, location: location, version: version, revision: revision)
        }
    }

    nonisolated static func spmDocsNormalizedRequirement(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "from: \"1.0.0\"" }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("from:") || lower.hasPrefix("exact:") || lower.hasPrefix("branch:")
            || lower.hasPrefix("revision:") || lower.hasPrefix("upToNextMajor")
            || lower.hasPrefix("upToNextMinor") || lower.hasPrefix("range:") {
            return trimmed
        }
        let version = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return "from: \"\(version)\""
    }

    nonisolated static func spmDocsDependenciesArrayRange(in content: String) -> Range<String.Index>? {
        guard let depsMarker = content.range(of: "dependencies:") else { return nil }
        guard let openBracket = content.range(of: "[", range: depsMarker.upperBound..<content.endIndex) else { return nil }
        guard let closeBracket = content.range(of: "]", range: openBracket.upperBound..<content.endIndex) else { return nil }
        return openBracket.lowerBound..<closeBracket.upperBound
    }

    nonisolated static func spmDocsInsertEntry(_ entry: String, into content: inout String, range: Range<String.Index>) -> Bool {
        let arrayText = String(content[range])
        guard arrayText.hasPrefix("[") && arrayText.hasSuffix("]") else { return false }
        let inner = String(arrayText.dropFirst().dropLast())
        let innerTrimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement: String
        if innerTrimmed.isEmpty {
            replacement = "[\n        \(entry)\n    ]"
        } else if !innerTrimmed.hasSuffix(",") {
            replacement = "[\n" + inner + ",\n        \(entry)\n    ]"
        } else {
            replacement = "[\n" + inner + "\n        \(entry)\n    ]"
        }
        content.replaceSubrange(range, with: replacement)
        return true
    }

    nonisolated static func spmDocsInsertProductIntoTarget(product: String, target: String, content: inout String) -> Bool {
        let needle = "name: \"\(target)\""
        guard let nameRange = content.range(of: needle) else { return false }
        let afterName = content[nameRange.upperBound...]
        guard let depsMarker = afterName.range(of: "dependencies:") else { return false }
        let absoluteDepsStart = depsMarker.lowerBound
        guard let openBracket = content.range(of: "[", range: absoluteDepsStart..<content.endIndex) else { return false }
        guard let closeBracket = content.range(of: "]", range: openBracket.upperBound..<content.endIndex) else { return false }
        if String(content[openBracket.upperBound..<closeBracket.lowerBound]).contains("\"\(product)\"") {
            return true
        }
        let inner = String(content[openBracket.upperBound..<closeBracket.lowerBound])
        let innerTrimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement: String
        if innerTrimmed.isEmpty {
            replacement = "\"\(product)\""
        } else if innerTrimmed.hasSuffix(",") {
            replacement = inner + " \"\(product)\""
        } else {
            replacement = inner + ", \"\(product)\""
        }
        content.replaceSubrange(openBracket.upperBound..<closeBracket.lowerBound, with: replacement)
        return true
    }

    nonisolated static func spmDocsListSwiftFiles(under root: URL) -> [URL] {
        var found: [URL] = []
        let skipped = Set([".git", "DerivedData", ".build", "Pods", "node_modules", ".swiftpm", "Carthage", "vendor"])
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return found
        }
        for case let url as URL in enumerator {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                if skipped.contains(url.lastPathComponent) { enumerator.skipDescendants() }
                continue
            }
            if url.pathExtension == "swift" { found.append(url) }
        }
        return found.sorted(by: { $0.path < $1.path })
    }

    nonisolated static func spmDocsListMarkdownFiles(under root: URL) -> [URL] {
        var found: [URL] = []
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return found
        }
        for case let url as URL in enumerator where ["md", "markdown"].contains(url.pathExtension.lowercased()) {
            found.append(url)
        }
        return found
    }

    nonisolated static func spmDocsFileHeader(from content: String) -> String {
        var headerLines: [String] = []
        for line in content.components(separatedBy: .newlines).prefix(5) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") {
                headerLines.append(trimmed)
            } else if trimmed.isEmpty {
                continue
            } else {
                break
            }
        }
        return headerLines.joined(separator: "\n")
    }

    nonisolated static func spmDocsPublicDeclarations(from content: String) -> [String] {
        let markers = ["struct ", "class ", "enum ", "protocol ", "actor ", "func ", "var ", "let ", "extension "]
        var results: [String] = []
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("public ") else { continue }
            guard markers.contains(where: { line.contains($0) }) else { continue }
            var cleaned = line
            if let brace = cleaned.firstIndex(of: "{") {
                cleaned = String(cleaned[..<brace]).trimmingCharacters(in: .whitespaces)
            }
            if cleaned.count > 200 { cleaned = String(cleaned.prefix(200)) }
            if !cleaned.isEmpty { results.append(cleaned) }
        }
        return results
    }

    nonisolated static func spmDocsFindDoccArchives(under root: URL) -> [URL] {
        var found: [URL] = []
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return found
        }
        for case let url as URL in enumerator where url.pathExtension == "doccarchive" {
            found.append(url)
            enumerator.skipDescendants()
        }
        return found
    }
}
