import Foundation

public struct AssistImageAssetSizeReportTool: AssistTool {
    public let id = "image_asset_size_report"
    public let name = "Image Asset Size Report"
    public let description = "Reports oversized image files inside .xcassets catalogs — candidates for compression or vectorization."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Reports oversized asset-catalog images.",
            properties: [
                "thresholdKB": JSONSchema(type: "integer", description: "Size threshold in KB. Default 500.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let threshold = Int64(max(1, (input["thresholdKB"] as? Int) ?? 500)) * 1024
        let root = context.workspaceRoot
        let exts: Set<String> = ["png", "jpg", "jpeg", "heic", "webp", "tiff", "pdf"]
        var oversized: [(String, Int64)] = []
        var total = 0
        var totalBytes: Int64 = 0
        for url in AssistWorkspaceScan.files(under: root, extensions: exts) {
            guard url.path.contains(".xcassets/") else { continue }
            total += 1
            let size = AssistWorkspaceScan.fileSize(of: url)
            totalBytes += size
            if size >= threshold {
                oversized.append((AssistWorkspacePaths.relative(url, workspaceRoot: root), size))
            }
        }
        if total == 0 {
            return .success("No image files found inside .xcassets catalogs.", data: ["imageCount": "0"])
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
        return .success(lines.joined(separator: "\n"), data: [
            "imageCount": "\(total)", "oversizedCount": "\(oversized.count)", "totalBytes": "\(totalBytes)"
        ])
    }
}
