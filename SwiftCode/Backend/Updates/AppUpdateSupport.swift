import Foundation

/// Single source of truth for SwiftCode's update configuration.
///
/// This file deliberately imports neither Sparkle nor AppKit, so the pure
/// logic here (feed URL, release-notes parsing, reminder gating) can be
/// reasoned about and self-tested without the update framework.
///
/// The appcast is hosted as an asset named `appcast.xml` on GitHub Releases.
/// The `releases/latest/download/` path always resolves to the newest
/// release's asset, so installed copies never need a feed URL change when a
/// new version ships. The release workflow (`.github/workflows/release.yml`)
/// is responsible for uploading a fresh `appcast.xml` with every release.
enum AppUpdateConfiguration {
    /// The one and only update feed. There is no second feed, no beta feed,
    /// and no legacy GitHub API check alongside it.
    static let feedURLString = "https://github.com/dylans2010/SwiftCode-Mac/releases/latest/download/appcast.xml"

    static var feedURL: URL? { URL(string: feedURLString) }

    /// Default automatic-check interval, in seconds (24 hours). This mirrors
    /// the `SUScheduledCheckInterval` value in Info.plist; Sparkle owns the
    /// actual schedule, this constant exists so Settings and docs agree.
    static let checkInterval: TimeInterval = 86_400

    /// How long "Remind Me Later" defers an offer for the same version.
    /// The deferral is persistent (UserDefaults) and is ignored for
    /// user-initiated checks, so a manual check always re-offers.
    static let remindLaterInterval: TimeInterval = 7 * 86_400

    /// UserDefaults key holding `[versionString: remindUntilTimestamp]`.
    /// Skip decisions are NOT stored here: Sparkle persists skipped
    /// versions itself, and this file must not duplicate that state.
    static let remindUntilDefaultsKey = "com.swiftcode.updates.remindUntil"

    /// Current marketing version, from the bundle (never hardcoded).
    static var currentDisplayVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    /// Current build number, from the bundle (never hardcoded).
    static var currentBuildVersion: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    /// Whether an EdDSA public key is embedded in the bundle. Sparkle
    /// verifies every download against `SUPublicEDKey` and fails closed
    /// when it is absent, so this is a real production blocker, not a
    /// cosmetic flag. See Docs/Updates.md for how to generate the key.
    static var isPublicKeyConfigured: Bool {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else {
            return false
        }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Version-agnostic description of an available update, built from a
/// Sparkle appcast item by `AppUpdateService`. Views never touch Sparkle
/// types directly; they render this struct.
struct AppUpdateInfo: Equatable {
    /// The appcast item's `versionString` (CFBundleVersion of the update).
    let versionString: String
    /// The appcast item's `displayVersionString` (marketing version).
    let displayVersionString: String
    /// The appcast item's title, if the feed provides one.
    let title: String?
    /// Download URL for the update artifact, if the item is installable.
    let fileURL: URL?
    /// Informational link for information-only updates.
    let infoURL: URL?
    /// Release-notes link from the feed, if the notes are not embedded.
    let releaseNotesURL: URL?
    /// Embedded release notes from the feed, if present.
    let embeddedReleaseNotes: String?
    /// True when the item has no downloadable artifact.
    let isInformationOnly: Bool
    /// Declared download size in bytes, if the feed provides one.
    let contentLength: UInt64

    /// The version string shown to the user. Falls back to the build
    /// version when no display version is available.
    var displayVersion: String {
        displayVersionString.isEmpty ? versionString : displayVersionString
    }
}

/// Lifecycle phase of an update, as presented to the user. Sparkle owns
/// download/installation; this enum only describes what the UI should show.
enum AppUpdatePhase: Equatable {
    case idle
    case offer
    case downloading
    case extracting
    case readyToInstall
    case installing
    case error
}

/// One rendered block of release notes.
enum ReleaseNoteBlock: Equatable {
    case heading(String)
    case bullet(String)
    case body(String)
}

/// Pure release-notes handling. Notes come from the appcast item's embedded
/// description or from its release-notes link — never from a hardcoded
/// changelog in the app.
enum ReleaseNotesFormatter {
    /// Convert embedded HTML release notes to plain text, preserving
    /// headings, paragraphs and list items. Unknown tags are stripped;
    /// nothing is invented when the input is empty.
    static func plainText(from htmlOrText: String) -> String {
        var text = htmlOrText
        // List items first, so their content survives tag stripping.
        text = text.replacingOccurrences(of: "(?i)<li[^>]*>", with: "\n• ", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</li>", with: "", options: .regularExpression)
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
        // Collapse runs of blank lines, keep single newlines for structure.
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

    /// Split plain release-notes text into renderable blocks.
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

    /// Full pipeline: HTML/text from the feed to renderable blocks.
    static func blocks(fromFeedText feedText: String?) -> [ReleaseNoteBlock] {
        guard let feedText, !feedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        return blocks(from: plainText(from: feedText))
    }
}

/// Pure "Remind Me Later" gating. Sparkle itself persists skipped
/// versions; this gate only covers the deferral window, so the two
/// mechanisms can never disagree about a skip.
enum RemindLaterGate {
    /// Whether an offer for `version` should be suppressed right now.
    /// Manual (user-initiated) checks bypass the gate entirely.
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

    /// The deferral timestamp to persist for a "Remind Me Later" choice.
    static func remindUntil(from now: Date = Date()) -> TimeInterval {
        now.timeIntervalSince1970 + AppUpdateConfiguration.remindLaterInterval
    }

    /// Read persisted deferrals from UserDefaults.
    static func loadFromDefaults(_ defaults: UserDefaults = .standard) -> [String: TimeInterval] {
        defaults.dictionary(forKey: AppUpdateConfiguration.remindUntilDefaultsKey) as? [String: TimeInterval] ?? [:]
    }

    /// Persist deferrals to UserDefaults.
    static func saveToDefaults(_ values: [String: TimeInterval], defaults: UserDefaults = .standard) {
        defaults.set(values, forKey: AppUpdateConfiguration.remindUntilDefaultsKey)
    }
}
