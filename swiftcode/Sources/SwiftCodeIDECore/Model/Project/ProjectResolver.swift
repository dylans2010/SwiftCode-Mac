import Foundation

/// Resolved project metadata (Legacy
/// `SwiftCode/Backend/Project/ProjectResolver.swift`, Dylan's own
/// code, ported under MIT).
///
/// Legacy resolved against its singletons (`ProjectSessionStore`,
/// `DocumentCoordinator`, `XcodeBuildManager`); the destination has
/// none of those, so resolution is adapted to the destination's
/// `WorkspaceModel`. (Callers in `SwiftCodeMCP` can combine this
/// with `SwiftCodeMCPHost.discoverWorkspace(in:)`; this target does
/// not depend on `SwiftCodeMCP`.)
/// The ancestor walk-up rule is Legacy's: starting at the given URL,
/// walk up until a directory containing a `Package.swift`,
/// `.xcodeproj`, or `.xcworkspace` is found.
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

/// Resolves the project that owns a file or directory, walking up
/// ancestors until a project container is found.
public enum ProjectResolver {
    /// The project that owns `url` (the URL itself or an ancestor),
    /// or nil when no container exists above it.
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

    /// Metadata for the project at `url` itself, or nil when `url`
    /// is not a project container.
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