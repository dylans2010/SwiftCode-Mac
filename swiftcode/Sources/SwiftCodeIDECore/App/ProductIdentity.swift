import Foundation
import SwiftCodeRelease

public enum ProductIdentity {
    public static let name = "SwiftCode"
    public static let version = SwiftCodeRelease.version
    public static let marketingVersion = SwiftCodeRelease.marketingVersion

    public static var versionText: String { "Version \(marketingVersion)" }
    public static var fullVersionText: String { "Version \(marketingVersion) (\(version))" }

    public static let copyright = "Copyright © 2026 MarcoDotIO and the SwiftCode contributors"
    public static let license = "MIT License"
    public static let notAffiliated = "SwiftCode is an independent project. It is not affiliated with or endorsed by Apple Inc."

    public static let repositoryURL = URL(string: "https://github.com/dylans2010/SwiftCode-Mac")!
    public static let licenseURL = URL(string: "https://github.com/dylans2010/SwiftCode-Mac/blob/main/LICENSE")!
    public static let noticesURL = URL(string: "https://github.com/dylans2010/SwiftCode-Mac/blob/main/THIRD_PARTY_NOTICES.md")!
    public static let releasesURL = URL(string: "https://github.com/dylans2010/SwiftCode-Mac/releases")!
    public static let helpURL = URL(string: "https://github.com/dylans2010/SwiftCode-Mac#readme")!

    public static var platformOption: String {
        #if os(macOS)
        #if arch(arm64)
        return "macOS (arm64)"
        #else
        return "macOS (x86_64)"
        #endif
        #else
        #if arch(arm64)
        return "Linux arm64"
        #else
        return "Linux x86-64"
        #endif
        #endif
    }

    public static var systemVersion: String {
        #if os(macOS)
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion)"
        #else
        let release = (try? String(contentsOfFile: "/etc/os-release", encoding: .utf8)) ?? ""
        for line in release.split(separator: "\n") where line.hasPrefix("PRETTY_NAME=") {
            return line.dropFirst("PRETTY_NAME=".count).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return "Linux"
        #endif
    }

    public static func bugReportURL(version: String = version, platform: String = platformOption, system: String = systemVersion) -> URL {
        var c = URLComponents(url: repositoryURL.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false)
        c?.queryItems = [URLQueryItem(name: "template", value: "bug_report.yml"), URLQueryItem(name: "version", value: version),
                         URLQueryItem(name: "platform", value: platform), URLQueryItem(name: "os", value: system)]
        return c?.url ?? repositoryURL
    }
}

public enum ExperimentalNotice {
    public static let label = "Experimental"
    public static let simulator = "The SwiftCode simulator is experimental. It needs a Linux arm64 host with KVM and a simulator runtime you obtain yourself; "
        + "SwiftCode does not include one."
    public static let simulatorSetup = "Add a host in Settings ▸ Simulators, or pair one with `swiftcode sim remote pair`."
    public static let runtimes = "Simulator runtimes are Apple software. SwiftCode includes none and shares none; it gets one from Apple for you only when you ask, or uses one you have."
    public static let headset = "Viewing a device in a headset is experimental. It needs a Linux PC running the viewer and an OpenXR headset."
    public static let profiler = "Gauge, the profiler, is experimental. It records CPU samples and a few other tracks, and only apps on the SwiftCode simulator."
    public static let interfaceBuilder = "This editor is experimental: it shows and edits common properties, and may not show every object in the file."
}

public enum ProductIconGeometry {
    public static let side = 1024.0
    public static let fieldTop = "#3A2157", fieldBottom = "#1F1033", chevronColor = "#FFF3DC", caretColor = "#FF7A59"
    public static let fieldMin = 100.0, fieldMax = 924.0, cornerStart = 219.0, cornerControl = 92.0
    public static let strokeWidth = 98.0
    public static let chevron = [(322.0, 290.0), (512.0, 486.0), (702.0, 290.0)]
    public static let caret = [(512.0, 616.0), (512.0, 752.0)]
}
