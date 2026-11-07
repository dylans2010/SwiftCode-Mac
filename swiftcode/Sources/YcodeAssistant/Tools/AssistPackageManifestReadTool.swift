import Foundation

public struct AssistPackageManifestReadTool: AssistTool {
    public let id = "package_manifest_read"
    public let name = "Read Package Manifest"
    public let description = "Reads Package.swift and summarizes the package name, platforms, products, targets, and dependencies."

    public init() {}

    public var capability: ToolCapability { .compilation }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Reads Package.swift and summarizes its contents.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to Package.swift. Default: \"Package.swift\".")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let rawPath = (input["path"] as? String) ?? "Package.swift"
        guard let url = resolvePath(rawPath, workspaceRoot: context.workspaceRoot) else {
            return .failure("Invalid path '\(rawPath)': must be inside the workspace and must not contain '..'.")
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure("Package manifest not found at '\(rawPath)'.")
        }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return .failure("Failed to read Package.swift at '\(rawPath)'.")
        }

        let packageName = extractPackageName(from: content) ?? "unknown"
        let platforms = extractPlatforms(from: content)
        let products = extractNames(after: "products:", in: content)
        let targets = extractTargetNames(from: content)
        let dependencies = extractDependencyURLs(from: content)

        let targetCount = countOccurrences(of: [".target(", ".testTarget(", ".executableTarget(", ".binaryTarget(", ".macro("], in: content)
        let productCount = countOccurrences(of: [".library(", ".executable("], in: content)

        var lines: [String] = []
        lines.append("Package: \(packageName)")
        lines.append("Manifest: \(rawPath)")
        lines.append("Platforms: \(platforms.isEmpty ? "none declared" : platforms.joined(separator: ", "))")
        lines.append("Products (\(productCount)): \(products.isEmpty ? "none" : products.joined(separator: ", "))")
        lines.append("Targets (\(targetCount)): \(targets.isEmpty ? "none" : targets.joined(separator: ", "))")
        lines.append("Dependencies (\(dependencies.count)): \(dependencies.isEmpty ? "none" : dependencies.joined(separator: ", "))")

        return .success(lines.joined(separator: "\n"), data: [
            "packageName": packageName,
            "platforms": platforms.joined(separator: ","),
            "products": products.joined(separator: ","),
            "targets": targets.joined(separator: ","),
            "dependencies": dependencies.joined(separator: ","),
            "productCount": "\(productCount)",
            "targetCount": "\(targetCount)",
            "dependencyCount": "\(dependencies.count)"
        ])
    }

    private func resolvePath(_ rawPath: String, workspaceRoot: URL) -> URL? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.contains("..") { return nil }
        let root = workspaceRoot.standardizedFileURL
        if trimmed.hasPrefix("/") {
            let candidate = URL(fileURLWithPath: trimmed).standardizedFileURL
            guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else { return nil }
            return candidate
        }
        let candidate = root.appendingPathComponent(trimmed).standardizedFileURL
        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else { return nil }
        return candidate
    }

    private func extractPackageName(from content: String) -> String? {
        guard let range = content.range(of: "name:") else { return nil }
        let rest = String(content[range.upperBound...])
        return firstQuotedString(in: rest)
    }

    private func extractPlatforms(from content: String) -> [String] {
        var found: [String] = []
        let known = ["iOS", "macOS", "watchOS", "tvOS", "visionOS", "linux"]
        for platform in known {
            if content.contains(".\(platform)(") {
                found.append(platform)
            }
        }
        return found
    }

    private func extractNames(after marker: String, in content: String) -> [String] {
        guard let markerRange = content.range(of: marker) else { return [] }
        let after = String(content[markerRange.upperBound...])
        var names: [String] = []
        var searchFrom = after.startIndex
        while let nameRange = after.range(of: "name:", range: searchFrom..<after.endIndex) {
            let rest = String(after[nameRange.upperBound...])
            if let quoted = firstQuotedString(in: rest) {
                names.append(quoted)
            }
            searchFrom = nameRange.upperBound
            if names.count >= 200 { break }
        }
        return names
    }

    private func extractTargetNames(from content: String) -> [String] {
        guard let markerRange = content.range(of: "targets:") else { return [] }
        let after = String(content[markerRange.upperBound...])
        var names: [String] = []
        var searchFrom = after.startIndex
        while let nameRange = after.range(of: "name:", range: searchFrom..<after.endIndex) {
            let rest = String(after[nameRange.upperBound...])
            if let quoted = firstQuotedString(in: rest) {
                names.append(quoted)
            }
            searchFrom = nameRange.upperBound
            if names.count >= 500 { break }
        }
        return names
    }

    private func extractDependencyURLs(from content: String) -> [String] {
        var urls: [String] = []
        var searchFrom = content.startIndex
        while let pkgRange = content.range(of: ".package(", range: searchFrom..<content.endIndex) {
            let rest = String(content[pkgRange.upperBound...])
            if let urlRange = rest.range(of: "url:") {
                let afterUrl = String(rest[urlRange.upperBound...])
                if let quoted = firstQuotedString(in: afterUrl) {
                    urls.append(quoted)
                }
            }
            searchFrom = pkgRange.upperBound
            if urls.count >= 200 { break }
        }
        return urls
    }

    private func countOccurrences(of needles: [String], in content: String) -> Int {
        var total = 0
        for needle in needles {
            total += content.components(separatedBy: needle).count - 1
        }
        return total
    }

    private func firstQuotedString(in text: String) -> String? {
        guard let open = text.firstIndex(of: "\"") else { return nil }
        let afterOpen = text.index(after: open)
        guard let close = text[afterOpen...].firstIndex(of: "\"") else { return nil }
        return String(text[afterOpen..<close])
    }
}
