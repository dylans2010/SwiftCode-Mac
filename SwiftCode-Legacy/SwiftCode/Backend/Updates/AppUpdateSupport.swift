import Foundation

enum AppUpdateConfiguration {
    static let feedURLString = "https://github.com/dylans2010/SwiftCode-Mac/releases/latest/download/appcast.xml"

    static var feedURL: URL? { URL(string: feedURLString) }

    static let checkInterval: TimeInterval = 86_400

    static let remindLaterInterval: TimeInterval = 7 * 86_400

    static let remindUntilDefaultsKey = "com.swiftcode.updates.remindUntil"

    static var currentDisplayVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    static var currentBuildVersion: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    static var isPublicKeyConfigured: Bool {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else {
            return false
        }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct AppUpdateInfo: Equatable {
    let versionString: String
    let displayVersionString: String
    let title: String?
    let fileURL: URL?
    let infoURL: URL?
    let releaseNotesURL: URL?
    let embeddedReleaseNotes: String?
    let isInformationOnly: Bool
    let contentLength: UInt64

    var displayVersion: String {
        displayVersionString.isEmpty ? versionString : displayVersionString
    }
}

enum AppUpdatePhase: Equatable {
    case idle
    case offer
    case downloading
    case extracting
    case readyToInstall
    case installing
    case error
}

enum ReleaseNoteBlock: Equatable {
    case heading(String)
    case bullet(String)
    case body(String)
}

enum ReleaseNotesFormatter {
    static func plainText(from htmlOrText: String) -> String {
        var text = htmlOrText
        text = text.replacingOccurrences(of: "(?i)<li[^>]*>", with: "\n• ", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</li>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)<p[^>]*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</p>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</h[1-6]>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)<h[1-6][^>]*>", with: "\n# ", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var collapsed: [String] = []
        for line in lines {
            if line.isEmpty, collapsed.last?.isEmpty == true { continue }
            collapsed.append(line)
        }
        while collapsed.first?.isEmpty == true { collapsed.removeFirst() }
        while collapsed.last?.isEmpty == true { collapsed.removeLast() }
        return collapsed.joined(separator: "\n")
    }

    static func blocks(from plainText: String) -> [ReleaseNoteBlock] {
        let trimmed = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var blocks: [ReleaseNoteBlock] = []
        for rawLine in trimmed.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("# ") {
                blocks.append(.heading(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("• ") {
                blocks.append(.bullet(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("- ") {
                blocks.append(.bullet(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("* ") {
                blocks.append(.bullet(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)))
            } else {
                blocks.append(.body(line))
            }
        }
        return blocks
    }

    static func blocks(fromFeedText feedText: String?) -> [ReleaseNoteBlock] {
        guard let feedText, !feedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        return blocks(from: plainText(from: feedText))
    }
}

enum RemindLaterGate {
    static func shouldSuppressOffer(
        version: String,
        remindUntil: [String: TimeInterval],
        now: Date = Date(),
        userInitiated: Bool
    ) -> Bool {
        guard !userInitiated else { return false }
        guard let until = remindUntil[version] else { return false }
        return now.timeIntervalSince1970 < until
    }

    static func remindUntil(from now: Date = Date()) -> TimeInterval {
        now.timeIntervalSince1970 + AppUpdateConfiguration.remindLaterInterval
    }

    static func loadFromDefaults(_ defaults: UserDefaults = .standard) -> [String: TimeInterval] {
        defaults.dictionary(forKey: AppUpdateConfiguration.remindUntilDefaultsKey) as? [String: TimeInterval] ?? [:]
    }

    static func saveToDefaults(_ values: [String: TimeInterval], defaults: UserDefaults = .standard) {
        defaults.set(values, forKey: AppUpdateConfiguration.remindUntilDefaultsKey)
    }
}
