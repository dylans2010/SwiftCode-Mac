//
//  AssistDiskSpaceAnalyzerTool.swift
//  SwiftCode
//

import Foundation

public struct AssistDiskSpaceAnalyzerTool: AssistTool {
    public let id = "disk_space_analyzer"
    public let name = "Disk Space Analyzer"
    public let description = "Calculates disk consumption across DerivedData, project build outputs, and caches."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Inspects file and directory disk sizes for the workspace and Xcode caches.",
            properties: [
                "path": JSONSchema(type: "string", description: "Optional specific directory path to inspect. Defaults to workspace root and DerivedData.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot
        let pathArg = input["path"] as? String

        let targetDir: URL
        if let p = pathArg, !p.isEmpty {
            targetDir = p.hasPrefix("/") ? URL(fileURLWithPath: p) : root.appendingPathComponent(p)
        } else {
            targetDir = root
        }

        func directorySize(url: URL) -> Int64 {
            var size: Int64 = 0
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
            while let item = enumerator?.nextObject() as? URL {
                if let s = (try? item.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                    size += Int64(s)
                }
            }
            return size
        }

        let fm = ByteCountFormatter()
        fm.countStyle = .file

        let workspaceSize = directorySize(url: targetDir)

        let derivedData = URL(fileURLWithPath: ("~/Library/Developer/Xcode/DerivedData" as NSString).expandingTildeInPath)
        let derivedDataSize = directorySize(url: derivedData)

        // Subdirectories size in workspace
        var subDirReports: [(name: String, sizeStr: String, size: Int64)] = []
        if let subitems = try? FileManager.default.contentsOfDirectory(at: targetDir, includingPropertiesForKeys: [.isDirectoryKey]) {
            for sub in subitems {
                var isD: ObjCBool = false
                if FileManager.default.fileExists(atPath: sub.path, isDirectory: &isD), isD.boolValue {
                    let s = directorySize(url: sub)
                    subDirReports.append((sub.lastPathComponent, fm.string(fromByteCount: s), s))
                }
            }
        }

        var report = "### Disk Space Analysis:\n\n"
        report += "- **Target Scope** (`\(targetDir.lastPathComponent)`): **\(fm.string(fromByteCount: workspaceSize))**\n"
        report += "- **Xcode DerivedData Cache**: **\(fm.string(fromByteCount: derivedDataSize))**\n\n"

        if !subDirReports.isEmpty {
            report += "#### Major Directory Breakdown:\n"
            for sub in subDirReports.sorted(by: { $0.size > $1.size }).prefix(10) {
                report += "- `\(sub.name)`: \(sub.sizeStr)\n"
            }
        }

        return .success(report)
    }
}
