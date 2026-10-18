import Foundation

public struct AssistPackageDependencyAuditTool: AssistTool {
    public let id = "package_dependency_audit"
    public let name = "Audit Package Dependencies"
    public let description = "Audits Swift package dependencies from Package.swift and Package.resolved, flagging missing pins and unpinned requirements."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Audits Swift package dependencies. Takes no parameters.",
            properties: [:],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot.standardizedFileURL
        let manifestURL = root.appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return .failure("Package.swift not found in the workspace root.")
        }
        guard let content = try? String(contentsOf: manifestURL, encoding: .utf8) else {
            return .failure("Failed to read Package.swift.")
        }
        let declared = extractDeclaredDependencies(from: content)
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
                    if !identity.isEmpty {
                        pinned[identity.lowercased()] = version
                    }
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
            let key = dep.name.lowercased()
            if dep.isExact {
                pinnedList.append(dep.url)
            } else {
                unpinned.append(dep.url)
            }
            if hasResolved && pinned[key] == nil && !dep.url.isEmpty {
                flags.append("Declared dependency not in Package.resolved: \(dep.url)")
            }
        }
        var dependencyLines: [String] = []
        for dep in declared {
            let pin = pinned[dep.name.lowercased()] ?? "unpinned"
            dependencyLines.append("- \(dep.url) (requirement: \(dep.requirement), resolved: \(pin))")
        }
        let showDeps = runShowDependencies(workspaceRoot: context.workspaceRoot)
        var lines: [String] = []
        lines.append("Package dependencies: \(declared.count) declared, \(pinned.count) pinned in Package.resolved")
        lines.append("Package.resolved present: \(hasResolved ? "yes" : "no")")
        lines.append("Exact requirements: \(pinnedList.count); non-exact requirements: \(unpinned.count)")
        if !dependencyLines.isEmpty {
            lines.append("Dependencies:")
            lines.append(contentsOf: dependencyLines)
        }
        if !flags.isEmpty {
            lines.append("Flags:")
            for flag in flags {
                lines.append("- \(flag)")
            }
        }
        if !showDeps.isEmpty {
            lines.append("swift package show-dependencies:")
            lines.append(showDeps)
        }
        return .success(lines.joined(separator: "\n"), data: [
            "declaredCount": "\(declared.count)",
            "pinnedCount": "\(pinned.count)",
            "hasResolved": hasResolved ? "true" : "false",
            "unpinnedCount": "\(unpinned.count)",
            "unpinned": unpinned.joined(separator: ","),
            "flags": flags.joined(separator: "; ")
        ])
    }

    private struct DeclaredDependency {
        let url: String
        let name: String
        let requirement: String
        let isExact: Bool
    }

    private func extractDeclaredDependencies(from content: String) -> [DeclaredDependency] {
        var results: [DeclaredDependency] = []
        var searchFrom = content.startIndex
        while let pkgRange = content.range(of: ".package(", range: searchFrom..<content.endIndex) {
            let afterStart = pkgRange.upperBound
            let rest = String(content[afterStart...])
            let segment = String(rest.prefix(600))
            var url = ""
            if let urlRange = segment.range(of: "url:") {
                let afterUrl = String(segment[urlRange.upperBound...])
                url = firstQuotedString(in: afterUrl) ?? ""
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
                results.append(DeclaredDependency(url: url, name: name, requirement: requirement, isExact: isExact))
            }
            searchFrom = pkgRange.upperBound
            if results.count >= 200 { break }
        }
        return results
    }

    private func firstQuotedString(in text: String) -> String? {
        guard let open = text.firstIndex(of: "\"") else { return nil }
        let afterOpen = text.index(after: open)
        guard let close = text[afterOpen...].firstIndex(of: "\"") else { return nil }
        return String(text[afterOpen..<close])
    }

    private func runShowDependencies(workspaceRoot: URL) -> String {
        let swiftPath = "/usr/bin/swift"
        guard FileManager.default.fileExists(atPath: swiftPath) else { return "" }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: swiftPath)
        process.arguments = ["package", "show-dependencies"]
        process.currentDirectoryURL = workspaceRoot
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
        } catch {
            return ""
        }
        process.waitUntilExit()
        if process.terminationStatus != 0 { return "" }
        let output = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return String(output.suffix(2000))
    }
}
