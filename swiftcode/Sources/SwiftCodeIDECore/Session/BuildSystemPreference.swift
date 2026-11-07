import Foundation
import SwiftCodeBuild
import SwiftCodeXcodebuild

public enum BuildSystemPreference: String, CaseIterable, Sendable {
    case xcodebuild
    case swiftBuild = "swift-build"

    public static let defaultsKey = "SwiftCodeBuildSystem"
    public static let defaultValue: BuildSystemPreference = .swiftBuild

    public var title: String {
        switch self {
        case .xcodebuild: "xcodebuild"
        case .swiftBuild: "swift-build"
        }
    }

    public static func current(_ defaults: UserDefaults = .standard) -> BuildSystemPreference {
        defaults.string(forKey: defaultsKey).flatMap(BuildSystemPreference.init(rawValue:)) ?? defaultValue
    }

    public func save(_ defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.defaultsKey) }

    static func xcodebuildEngine() -> XcodebuildEngine {
        var e = XcodebuildEngine()
        if let helper = SwiftBuildSettingsSource.locate() { e.settingsSource = SwiftBuildSettingsSource(helper: helper) }
        return e
    }

    public func makeEngine(locateSwiftBuild: () -> String? = { SwiftBuildEngine.locate() }) -> BuildEngine {
        switch self {
        case .xcodebuild: return Self.xcodebuildEngine()
        case .swiftBuild:
            guard let tool = locateSwiftBuild() else { return Self.xcodebuildEngine() }
            var engine = SwiftBuildEngine(swbuild: tool)
            engine.pifSource = XcodePIFSource()
            return FallbackEngine(primary: engine, fallback: Self.xcodebuildEngine(), supports: XcodePIFSource.supports)
        }
    }
}
