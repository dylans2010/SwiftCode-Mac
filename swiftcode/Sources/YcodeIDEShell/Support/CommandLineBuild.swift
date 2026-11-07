import Foundation
import YcodeBuild
import YcodeIDECore
import YcodeXcodebuild

public enum CommandLineBuild {
    public enum Engine: String, Equatable, Sendable, CaseIterable {
        case xcodebuild
        case swiftBuild = "swift-build"
        case swiftPM = "swiftpm"
    }

    public static func engine(named name: String?, container: BuildRequest.Container, isLinux: Bool,
                              environment: [String: String] = ProcessInfo.processInfo.environment,
                              isPackageFolder: (String) -> Bool = CommandLineBuild.isPackageFolder) -> Engine? {
        if let name { return Engine(rawValue: name) }
        guard isLinux else { return .xcodebuild }
        if environment["SWIFTCODE_IDE_ENGINE"] == "swiftcodebuild" { return .xcodebuild }
        if case .package(let dir) = container, isPackageFolder(dir) { return .swiftPM }
        return .xcodebuild
    }

    public static func isPackageFolder(_ dir: String) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: (dir as NSString).appendingPathComponent("Package.swift")) else { return false }
        let entries = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
        return !entries.contains { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }
    }

    public struct Failure: Error, Equatable, CustomStringConvertible {
        public var description: String
    }

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
            guard let tool = locateSwbuild() else {
                throw Failure(description: "swift-build not found (set SWIFTCODE_SWB to SwiftCode's swiftcode-swb, or SWIFTCODE_SWBUILD to swbuild). Swift packages build with --engine swiftpm"
                    + (isLinux ? ", the default here." : "."))
            }
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
