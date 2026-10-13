import Foundation
import DiagnosticsKit
import WorkspaceKit

public final class ProjectInspector: Sendable {
    public init() {}

    public func inspect(at path: String) throws -> ProjectMetadata {
        let ws = Workspace(path: path)
        let root = ws.root.normalizedPath

        // Check for swiftcode.json (Extension)
        if ws.fileAccess.exists(at: "swiftcode.json") {
            let jsonString = try ws.fileAccess.readString(at: "swiftcode.json")
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw WorkspaceError.readFailed("swiftcode.json", "Malformed JSON")
            }
            let id = json["id"] as? String ?? "unknown"
            let name = json["name"] as? String ?? ws.root.fileName
            let version = json["version"] as? String ?? "1.0.0"
            let typeStr = json["type"] as? String ?? "swiftcode-extension"
            let type = ProjectType(rawValue: typeStr) ?? .swiftcodeExtension

            return ProjectMetadata(
                id: id,
                name: name,
                type: type,
                version: version,
                rootPath: root,
                targets: [ProjectTarget(name: name, type: "extension")],
                configurations: ["Default"],
                customProperties: ["entrypoint": (json["runtime"] as? [String: Any])?["entrypoint"] as? String ?? "dist/index.js"]
            )
        }

        // Check for Package.swift (Swift Package)
        if ws.fileAccess.exists(at: "Package.swift") {
            let pkgString = try ws.fileAccess.readString(at: "Package.swift")
            let name = extractPackageName(from: pkgString) ?? ws.root.fileName
            return ProjectMetadata(
                id: "package.\(name.lowercased())",
                name: name,
                type: .swiftPackage,
                version: "1.0.0",
                rootPath: root,
                targets: [ProjectTarget(name: name, type: "package")],
                configurations: ["Debug", "Release"],
                customProperties: [:]
            )
        }

        // Check for .xcodeproj
        let files = try ws.fileAccess.listFiles(recursively: false)
        if let xcodeproj = files.first(where: { $0.fileName.hasSuffix(".xcodeproj") }) {
            let name = String(xcodeproj.fileName.dropLast(".xcodeproj".count))
            return ProjectMetadata(
                id: "xcode.\(name.lowercased())",
                name: name,
                type: .xcodeProject,
                version: "1.0.0",
                rootPath: root,
                targets: [ProjectTarget(name: name, type: "xcodeApp")],
                configurations: ["Debug", "Release"],
                customProperties: ["projectFile": xcodeproj.relativePath]
            )
        }

        throw WorkspaceError.pathNotFound("No supported project found at \(path) (missing Package.swift, swiftcode.json, or .xcodeproj)")
    }

    private func extractPackageName(from content: String) -> String? {
        let pattern = "name:\\s*\"([^\"]+)\""
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
           match.numberOfRanges > 1,
           let r = Range(match.range(at: 1), in: content) {
            return String(content[r])
        }
        return nil
    }
}
