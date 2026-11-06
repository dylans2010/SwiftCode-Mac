import Foundation
import Observation
import SwiftCodePreviews
import SwiftCodeIDECore

/// Per-artboard preview runtime sessions, artboard synchronisation,
/// and the build-log store (Legacy
/// `SwiftCode/Core/Preview/PreviewManager.swift`, Dylan's own code,
/// ported under MIT).
///
/// `PreviewManager` itself is not ported whole: it depended on
/// `DocumentCoordinator`, `XcodeBuildAPI`, `PreviewCommunicationService`,
/// `PreviewBlockParser`, `SwiftViewDetector`, `FullAppRunManager`,
/// and `ProcessRunnerTool`, none of which exist in the destination,
/// and its session orchestration (`startFreshLivePreviewSession`,
/// `loadPreviews`, `stopActiveSession`, the dark-mode/device
/// toggles) already lives in the destination's
/// `WorkspaceWindowController+LivePreviews` /
/// `PreviewCanvasController` flow. What was genuinely missing — and
/// is ported here — is the per-artboard `RuntimeSession` registry,
/// the build-log store, artboard synchronisation for `#Preview`
/// declarations, and `validatePreviewBuildPipeline`.
///
/// Wiring: the editor creates one `PreviewArtboardRuntime` per
/// workspace and passes its `VisualUIScene` to
/// `synchronizeArtboardsForPreviews`; the preview canvas drives
/// `getOrCreateRuntimeSession(for:)` per artboard id.
@Observable
@MainActor
public final class PreviewArtboardRuntime {
    public static let shared = PreviewArtboardRuntime()

    /// Per-artboard live runtime sessions, keyed by artboard id.
    public var runtimeSessions: [UUID: RuntimeSession] = [:]

    /// The build log lines the preview UI shows.
    public var buildLogs: [String] = []

    public init() {}

    /// The runtime session for `artboardID`, creating it on first use.
    public func getOrCreateRuntimeSession(for artboardID: UUID) -> RuntimeSession {
        if let session = runtimeSessions[artboardID] {
            return session
        }
        let session = RuntimeSession(artboardID: artboardID)
        runtimeSessions[artboardID] = session
        return session
    }

    public func appendBuildLog(_ line: String) {
        buildLogs.append(line)
    }

    public func clearLogs() {
        buildLogs.removeAll()
    }

    /// Synchronises `scene`'s artboards with the `#Preview`
    /// declarations in `sourceCode` (Legacy's
    /// `synchronizeArtboardsForPreviews`): artboards named
    /// `"Default"` are kept, a `"Default"` artboard is created when
    /// none exists, and each preview title gets an artboard (an
    /// existing artboard of that name is kept). The active artboard
    /// is set to the first artboard when it is missing or stale.
    public func synchronizeArtboardsForPreviews(scene: VisualUIScene, sourceCode: String, deviceFrame: String = "iPhone 16 Pro") {
        let previews = PreviewDiscovery.previews(in: sourceCode)

        var newArtboards = scene.artboards.filter { $0.name == "Default" }
        if newArtboards.isEmpty {
            let rootNode = VisualComponentNode(type: .vStack)
            let defaultArtboard = VisualUIArtboard(name: "Default", deviceFrame: deviceFrame, rootNode: rootNode)
            newArtboards.append(defaultArtboard)
        }

        for preview in previews {
            let name = preview.name
            if name == "Default" { continue }
            if let existing = scene.artboards.first(where: { $0.name == name }) {
                newArtboards.append(existing)
            } else {
                let rootNode = VisualComponentNode(type: .vStack)
                let artboard = VisualUIArtboard(name: name, deviceFrame: deviceFrame, rootNode: rootNode)
                newArtboards.append(artboard)
            }
        }

        scene.artboards = newArtboards
        if scene.activeArtboardID == nil || !scene.artboards.contains(where: { $0.id == scene.activeArtboardID }) {
            scene.activeArtboardID = scene.artboards.first?.id
        }
    }

    public enum BuildPipelineError: Error, LocalizedError {
        case noProject(code: Int)
        case missingSwiftToolchain(code: Int)
        case missingPackageManifest(code: Int)

        public var errorDescription: String? {
            switch self {
            case .noProject(let code):
                return "No active workspace or project resolved. (PreviewBuild \(code))"
            case .missingSwiftToolchain(let code):
                return "Swift compiler tools (swiftc) are missing in the current system. (PreviewBuild \(code))"
            case .missingPackageManifest(let code):
                return "Package.swift is missing in active package dependencies. (PreviewBuild \(code))"
            }
        }
    }

    /// Validates the build pipeline constraints for the project at
    /// `projectURL` (Legacy's `validatePreviewBuildPipeline`, error
    /// codes kept: 401 no project, 405 no swiftc, 407 missing
    /// Package.swift). The checks that need `XcodeBuildAPI` —
    /// active project (402), scheme (403), bundle identifier (404),
    /// SDK environment (406), and Xcode project generation (408) —
    /// are not reproduced here: `XcodeBuildAPI` is not on main (it
    /// exists only in the dropped batch-2 commit). The destination
    /// equivalent for a full build is the `PreviewCompiler` payload
    /// pipeline driven by `RuntimeSession.startBuildPipeline`.
    public func validatePreviewBuildPipeline(projectURL: URL) throws {
        // 1. Workspace / Project Resolver validation
        let metadata: ResolvedProjectMetadata
        do {
            metadata = try ProjectResolver.resolveActiveProject(from: projectURL)
        } catch {
            throw BuildPipelineError.noProject(code: 401)
        }

        // 5. Swift Version Check (checks swiftc executable)
        let fm = FileManager.default
        let hasSwiftc = fm.fileExists(atPath: "/usr/bin/swiftc") || fm.fileExists(atPath: "/usr/bin/swift")
        if !hasSwiftc {
            throw BuildPipelineError.missingSwiftToolchain(code: 405)
        }

        // 7. Dependencies check
        if metadata.kind == .package {
            guard fm.fileExists(atPath: metadata.url.appendingPathComponent("Package.swift").path) else {
                throw BuildPipelineError.missingPackageManifest(code: 407)
            }
        }
    }
}
