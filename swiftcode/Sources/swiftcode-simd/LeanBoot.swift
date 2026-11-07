import Foundation

struct LeanBootProfile: Equatable {
    var disabledLabels: [String]
    var loggingOff: Bool

    var isEmpty: Bool { disabledLabels.isEmpty && !loggingOff }

    static let defaultDisabledLabels: [String] = [
        "com.apple.suggestd",
        "com.apple.parsecd",
        "com.apple.parsec-fbf",
        "com.apple.searchd",
        "com.apple.spotlightknowledged",
        "com.apple.spotlightknowledged.updater",
        "com.apple.accessibility.axassetsd",
        "com.apple.proactiveeventtrackerd",
        "com.apple.mlhostd",
        "com.apple.intelligencetasksd",
        "com.apple.intelligenceplatformd",
        "com.apple.knowledgeconstructiond",
        "com.apple.textunderstandingd",
        "com.apple.siriactionsd",
        "com.apple.siriinferenced",
        "com.apple.siriknowledged",
        "com.apple.mediaanalysisd",
        "com.apple.photoanalysisd",
        "com.apple.sensorkitd",
        "com.apple.nanoregistrylaunchd",
        "com.apple.pairedsyncd",
        "com.apple.facetimemessagestored",
        "com.apple.homed",
    ]

    static let pairingLabels: Set<String> = ["com.apple.nanoregistrylaunchd", "com.apple.pairedsyncd"]

    static let watchOSDisabledLabels: [String] = defaultDisabledLabels.filter { !pairingLabels.contains($0) }

    static func defaultDisabledLabels(for platform: RuntimePlatform) -> [String] {
        platform == .watchOS ? watchOSDisabledLabels : defaultDisabledLabels
    }

    static let loggingOffSubsystems: [String] = [
        "com.apple.containermanager", "com.apple.network", "com.apple.runningboard", "com.apple.xpc",
        "com.apple.Foundation", "com.apple.defaults", "com.apple.SpringBoard", "com.apple.launchservices",
        "com.apple.appinstallation", "com.apple.iconservices", "com.apple.securityd", "com.apple.CFNetwork",
        "com.apple.IDS", "com.apple.appintents", "com.apple.contacts", "com.apple.apsd",
        "com.apple.intelligenceplatform", "com.apple.chrono", "com.apple.migration", "com.apple.Biome",
        "com.apple.xpc.activity", "com.apple.locationd.Core", "com.apple.mobileassetd", "com.apple.coredata",
        "com.apple.StreamingExtractor", "com.apple.FrontBoard", "com.apple.MobileAsset", "com.apple.reminderkit.store",
        "com.apple.AppleMediaServices", "com.apple.UIKit", "com.apple.xpc.transaction", "com.apple.PlugInKit",
        "com.apple.TCC", "com.apple.contacts.contactsd", "com.apple.GeoServices", "com.apple.BackBoard",
        "com.apple.UnifiedAssetFramework", "com.apple.CoreRoutine", "com.apple.HomeKit", "com.apple.Accessibility",
    ]

    static var levelOffPreference: [String: Any] { ["DEFAULT-OPTIONS": ["Level": ["Enable": "off", "Persist": "off"]]] }

    static func from(environment env: [String: String], platform: RuntimePlatform = .iOS) -> LeanBootProfile? {
        let mode = (env["SWIFTCODE_LEAN_BOOT"] ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        let daemons: Bool, logging: Bool
        switch mode {
        case "", "0", "off", "no": return nil
        case "1", "daemons", "on", "yes": (daemons, logging) = (true, false)
        case "logging": (daemons, logging) = (false, true)
        case "all": (daemons, logging) = (true, true)
        default: return nil
        }
        func list(_ key: String) -> [String] {
            (env[key] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        let keep = Set(list("SWIFTCODE_LEAN_BOOT_KEEP"))
        var labels = daemons ? defaultDisabledLabels(for: platform) : []
        for extra in list("SWIFTCODE_LEAN_BOOT_DISABLE") where !labels.contains(extra) { labels.append(extra) }
        labels.removeAll { keep.contains($0) }
        let profile = LeanBootProfile(disabledLabels: labels, loggingOff: logging)
        return profile.isEmpty ? nil : profile
    }

    static var fromProcessEnvironment: LeanBootProfile? { from(environment: ProcessInfo.processInfo.environment) }

    static func fromProcessEnvironment(platform: RuntimePlatform) -> LeanBootProfile? {
        from(environment: ProcessInfo.processInfo.environment, platform: platform)
    }

    func disabledOverrides(existing: [String: Bool] = [:]) -> [String: Bool] {
        var result = existing
        for label in disabledLabels where result[label] == nil { result[label] = true }
        return result
    }

    var summary: String {
        var parts: [String] = []
        if !disabledLabels.isEmpty { parts.append("\(disabledLabels.count) jobs disabled") }
        if loggingOff { parts.append("\(Self.loggingOffSubsystems.count) log subsystems off") }
        return "lean boot: " + parts.joined(separator: ", ")
    }
}
