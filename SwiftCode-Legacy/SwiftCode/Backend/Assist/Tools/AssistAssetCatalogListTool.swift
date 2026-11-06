import Foundation

public struct AssistAssetCatalogListTool: AssistTool {
    public let id = "asset_catalog_list"
    public let name = "List Asset Catalog"
    public let description = "Lists asset catalogs under the workspace and the image, color, and app-icon sets inside each catalog."

    public init() {}

    public var capability: ToolCapability { .repositoryDiscovery }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Lists asset catalogs and their sets.",
            properties: [
                "path": JSONSchema(type: "string", description: "Optional workspace-relative path to a single .xcassets catalog or a directory to search. Default: whole workspace.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot.standardizedFileURL
        var searchRoots: [URL] = [root]
        if let rawPath = input["path"] as? String, !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let resolved = resolvePath(rawPath, workspaceRoot: context.workspaceRoot) else {
                return .failure("Invalid path '\(rawPath)': must be inside the workspace and must not contain '..'.")
            }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir), isDir.boolValue else {
                return .failure("Path '\(rawPath)' does not exist or is not a directory.")
            }
            searchRoots = [resolved]
        }
        var catalogs: [URL] = []
        for searchRoot in searchRoots {
            if searchRoot.lastPathComponent.hasSuffix(".xcassets") {
                catalogs.append(searchRoot)
                continue
            }
            guard let enumerator = FileManager.default.enumerator(at: searchRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            while let url = enumerator.nextObject() as? URL {
                if url.lastPathComponent.hasSuffix(".xcassets") {
                    catalogs.append(url)
                    enumerator.skipDescendants()
                }
            }
        }
        catalogs.sort { $0.path < $1.path }
        if catalogs.isEmpty {
            return .success("No .xcassets catalogs found.", data: ["catalogCount": "0", "totalSets": "0"])
        }
        var lines: [String] = []
        var totalSets = 0
        var catalogNames: [String] = []
        for catalog in catalogs {
            let relative = relativePath(catalog, root: root)
            catalogNames.append(relative)
            let sets = listSets(in: catalog)
            totalSets += sets.count
            lines.append("\(relative): \(sets.count) set(s)")
            for set in sets {
                lines.append("  - \(set)")
            }
        }
        lines.insert("Found \(catalogs.count) catalog(s) with \(totalSets) set(s) total.", at: 0)
        return .success(lines.joined(separator: "\n"), data: [
            "catalogCount": "\(catalogs.count)",
            "totalSets": "\(totalSets)",
            "catalogs": catalogNames.joined(separator: ",")
        ])
    }

    private func listSets(in catalog: URL) -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: catalog, includingPropertiesForKeys: nil) else { return [] }
        var sets: [String] = []
        for item in contents {
            let name = item.lastPathComponent
            if name.hasSuffix(".imageset") || name.hasSuffix(".colorset") || name.hasSuffix(".appiconset") || name.hasSuffix(".dataset") || name.hasSuffix(".symbolset") {
                sets.append(name)
            }
        }
        return sets.sorted()
    }

    private func relativePath(_ url: URL, root: URL) -> String {
        let path = url.standardizedFileURL.path
        let rootPath = root.path
        if path == rootPath { return "." }
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return url.lastPathComponent
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
}
