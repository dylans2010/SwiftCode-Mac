import Foundation
import SwiftCodeBuild
import SwiftCodeIDECore
import SwiftCodeXcodebuild

/// The engine `swiftcode build` uses (`specs/ide/build.md`, "The command
/// line"). On Linux, also inside the Flatpak, it picks what the Linux IDE
/// picks: SwiftPM for a package folder, swiftcodebuild for projects and
/// workspaces. On macOS the default stays xcodebuild.
public enum CommandLineBuild {
    public enum Engine: String, Equatable, Sendable, CaseIterable {
        /// Apple's `xcrun xcodebuild` on macOS; swiftcodebuild on Linux.
        case xcodebuild
        /// swift-build's `swbuild` client from SwiftCode's PIF.
        case swiftBuild = "swift-build"
        /// The toolchain's own SwiftPM (`swift build`, `swift test`), as the
        /// Linux IDE builds packages.
        case swiftPM = "swiftpm"
    }

    /// `--engine <name>`, or nil for the default. Nil for an unknown name.
    public static func engine(named name: String?, container: BuildRequest.Container, isLinux: Bool,
                              environment: [String: String] = ProcessInfo.processInfo.environment,
                              isPackageFolder: (String) -> Bool = CommandLineBuild.isPackageFolder) -> Engine? {
        if let name { return Engine(rawValue: name) }
        guard isLinux else { return .xcodebuild }
        // `SWIFTCODE_IDE_ENGINE=swiftcodebuild` sends packages to swiftcodebuild, as in the IDE.
        if environment["SWIFTCODE_IDE_ENGINE"] == "swiftcodebuild" { return .xcodebuild }
        if case .package(let dir) = container, isPackageFolder(dir) { return .swiftPM }
        return .xcodebuild
    }

    /// A folder with a `Package.swift` and no project or workspace (one
    /// with both builds the project, as swiftcodebuild does).
    public static func isPackageFolder(_ dir: String) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: (dir as NSString).appendingPathComponent("Package.swift")) else { return false }
        let entries = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
        return !entries.contains { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }
    }

    public struct Failure: Error, Equatable, CustomStringConvertible {
        public var description: String
    }

    /// The engine for a choice on this host. A missing tool is an error that
    /// says what to install or set; a missing Swift toolchain is the SwiftPM
    /// engine's own first issue (in the Flatpak, the host-tool wrapper's).
    public static func make(_ engine: Engine, isLinux: Bool,
                            environment: [String: String] = ProcessInfo.processInfo.environment,
                            locateSwiftCodebuild: () -> String? = { TestRunnerSelection.locateSwiftCodebuild() },
                            locateSwbuild: () -> String? = { SwiftBuildEngine.locate() ?? SwiftBuildEngine.locateHelper(swbuild: nil) }) throws -> BuildEngine {
        switch engine {
        case .swiftPM:
            return PackageBuildEngine()
        case .xcodebuild where isLinux:
            guard let tool = locateSwiftCodebuild() else { throw Failure(description: ShellToolchain.noBuildTool) }
            return XcodebuildEngine(command: [tool])
        case .xcodebuild:
            return XcodebuildEngine()
        case .swiftBuild:
            // SwiftCode's swiftcode-swb helper alone is enough (the release ships no swbuild).
            guard let tool = locateSwbuild() else {
                throw Failure(description: "swift-build not found (set SWIFTCODE_SWB to SwiftCode's swiftcode-swb, or SWIFTCODE_SWBUILD to swbuild). Swift packages build with --engine swiftpm"
                    + (isLinux ? ", the default here." : "."))
            }
            // The PIF of projects and workspaces is XcodePIF's, with the
            // container's Swift packages (the IDE's PIF source).
            var e = SwiftBuildEngine(swbuild: tool)
            e.pifSource = XcodePIFSource()
            return e
        }
    }

    public static var isLinuxHost: Bool {
        #if os(Linux)
        true
        #else
        false
        #endif
    }
}
