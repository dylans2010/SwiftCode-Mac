import Foundation
import Observation
import SwiftCodePreviews
import SwiftCodeIDECore

@Observable
@MainActor
public final class PreviewArtboardRuntime {
    public static let shared = PreviewArtboardRuntime()

    public var runtimeSessions: [UUID: RuntimeSession] = [:]

    public var buildLogs: [String] = []

    public init() {}

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

    public func validatePreviewBuildPipeline(projectURL: URL) throws {
        let metadata: ResolvedProjectMetadata
        do {
            metadata = try ProjectResolver.resolveActiveProject(from: projectURL)
        } catch {
            throw BuildPipelineError.noProject(code: 401)
        }

        let fm = FileManager.default
        let hasSwiftc = fm.fileExists(atPath: "/usr/bin/swiftc") || fm.fileExists(atPath: "/usr/bin/swift")
        if !hasSwiftc {
            throw BuildPipelineError.missingSwiftToolchain(code: 405)
        }

        if metadata.kind == .package {
            guard fm.fileExists(atPath: metadata.url.appendingPathComponent("Package.swift").path) else {
                throw BuildPipelineError.missingPackageManifest(code: 407)
            }
        }
    }
}
