import Foundation

public struct ResolvedProjectMetadata: Sendable {
    public let url: URL
    public let name: String
    public let kind: WorkspaceModel.ContainerKind

    public init(url: URL, name: String, kind: WorkspaceModel.ContainerKind) {
        self.url = url
        self.name = name
        self.kind = kind
    }
}

public enum ProjectResolutionError: Error, LocalizedError {
    case noProjectFound(URL)
    case invalidProject(URL, String)

    public var errorDescription: String? {
        switch self {
        case .noProjectFound(let url):
            return "No project found at or above \(url.path)."
        case .invalidProject(let url, let reason):
            return "Project at \(url.path) is invalid: \(reason)."
        }
    }
}

public enum ProjectResolver {
    public static func resolveActiveProject(from url: URL) throws -> ResolvedProjectMetadata {
        var current = url
        if !current.hasDirectoryPath {
            current = current.deletingLastPathComponent()
        }
        while true {
            if let metadata = metadata(at: current) { return metadata }
            let parent = current.deletingLastPathComponent()
            guard parent != current else { break }
            current = parent
        }
        throw ProjectResolutionError.noProjectFound(url)
    }

    public static func metadata(at url: URL) -> ResolvedProjectMetadata? {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
            return ResolvedProjectMetadata(url: url, name: url.lastPathComponent, kind: .package)
        }
        if let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil),
           let project = contents.first(where: { $0.pathExtension == "xcodeproj" }) {
            return ResolvedProjectMetadata(url: url, name: project.deletingPathExtension().lastPathComponent, kind: .project)
        }
        if let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil),
           let workspace = contents.first(where: { $0.pathExtension == "xcworkspace" }) {
            return ResolvedProjectMetadata(url: url, name: workspace.deletingPathExtension().lastPathComponent, kind: .workspace)
        }
        return nil
    }
}
