import Foundation

public struct AssistDerivedDataLocateTool: AssistTool {
    public let id = "derived_data_locate"
    public let name = "DerivedData Locate"
    public let description = "Locates the project's DerivedData directories under ~/Library/Developer/Xcode/DerivedData with sizes."

    public init() {}

    public var capability: ToolCapability { .compilation }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Locates DerivedData directories.",
            properties: [
                "nameFilter": JSONSchema(type: "string", description: "Optional substring filter on the DerivedData folder name.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let filter = (input["nameFilter"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let dd = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: dd, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return .failure("DerivedData directory not found at \(dd.path).")
        }
        var rows: [(String, Int64)] = []
        for entry in entries {
            if let filter, !filter.isEmpty, !entry.lastPathComponent.localizedCaseInsensitiveContains(filter) { continue }
            var size: Int64 = 0
            if let enumerator = FileManager.default.enumerator(at: entry, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) {
                while let child = enumerator.nextObject() as? URL {
                    let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    if !isDir { size += AssistWorkspaceScan.fileSize(of: child) }
                    if size > 20_000_000_000 { break }
                }
            }
            rows.append((entry.lastPathComponent, size))
        }
        rows.sort { $0.1 > $1.1 }
        if rows.isEmpty {
            return .success("No DerivedData directories matched.", data: ["count": "0"])
        }
        var lines = ["DerivedData directories (\(rows.count)):"]
        for (name, size) in rows.prefix(30) {
            lines.append(String(format: "- %@ — %.2f GB", name, Double(size) / 1_073_741_824.0))
        }
        return .success(lines.joined(separator: "\n"), data: ["count": "\(rows.count)"])
    }
}
