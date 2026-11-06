import Foundation
import Observation
import SwiftCodeSigning

/// The entitlements editor's document model: a `.entitlements` file as an
/// `Entitlements` dictionary (SwiftCodeSigning's `EntitlementValue`), edited
/// through the capability catalog and written back as a sorted XML plist.
///
/// Ported from Legacy's `EntitlementsEditorManager`
/// (`Core/Editor/EntitlementsEditorManager.swift`) + `EntitlementsEditorView`
/// (`Views/Editor/EntitlementsEditorView.swift`): the same read/write,
/// capability toggles, four presets, base + cross-entitlement validation,
/// change history, and raw-XML round trip. The 17-entry manager catalog is
/// subsumed by `EntitlementCapabilityCatalog` (123 definitions); the
/// manager's `EntitlementMetadata` display data (minimum OS, SF symbol,
/// colour) that the view catalog does not carry is not reproduced — the
/// view catalog's symbol is the one the editor shows.
///
/// A file that is only looked at is never written. Saving writes the whole
/// dictionary as XML with keys sorted, as Legacy did.

public struct EntitlementIssue: Identifiable, Equatable, Sendable {
    public var id: String { rawKey + "|" + message }
    public enum Severity: String, Sendable { case error, warning }
    public let severity: Severity
    public let rawKey: String
    public let message: String

    public init(severity: Severity, rawKey: String, message: String) {
        self.severity = severity
        self.rawKey = rawKey
        self.message = message
    }
}

public struct EntitlementChange: Identifiable, Sendable {
    public var id: UUID
    public let rawKey: String
    public let oldValue: String
    public let newValue: String
    public let timestamp: Date

    public init(rawKey: String, oldValue: String, newValue: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.rawKey = rawKey
        self.oldValue = oldValue
        self.newValue = newValue
        self.timestamp = timestamp
    }
}

public enum EntitlementsPreset: String, CaseIterable, Sendable {
    case appStoreSandbox = "App Store Sandbox (macOS)"
    case hardenedRuntimeDeveloperTool = "Developer Tool Hardened Runtime"
    case mediaHardware = "Media & Hardware Access"
    case iCloudKeyValueContainers = "iCloud Key-Value & Containers"

    /// The keys the preset sets, exactly as Legacy's
    /// `EntitlementsEditorView` preset menu.
    public var keys: Entitlements {
        switch self {
        case .appStoreSandbox:
            return [
                "com.apple.security.app-sandbox": .bool(true),
                "com.apple.security.files.user-selected.read-write": .bool(true),
                "com.apple.security.network.client": .bool(true),
            ]
        case .hardenedRuntimeDeveloperTool:
            return [
                "com.apple.security.cs.allow-jit": .bool(true),
                "com.apple.security.cs.allow-unsigned-executable-memory": .bool(true),
                "com.apple.security.cs.disable-library-validation": .bool(true),
            ]
        case .mediaHardware:
            return [
                "com.apple.security.device.camera": .bool(true),
                "com.apple.security.device.audio-input": .bool(true),
                "com.apple.security.personal-information.photos-library": .bool(true),
            ]
        case .iCloudKeyValueContainers:
            return [
                EntitlementCapabilityCatalog.iCloudContainersKey: .array([.string("iCloud.$(CFBundleIdentifier)")]),
                EntitlementCapabilityCatalog.iCloudKVStoreKey: .string("$(TeamIdentifierPrefix)$(CFBundleIdentifier)"),
            ]
        }
    }
}

/// A short readable summary of an entitlement value, for search, history
/// and the raw view. Mirrors what Legacy showed via `String(describing:)`.
public func entitlementSummary(_ value: EntitlementValue) -> String {
    switch value {
    case .string(let s): return s
    case .bool(let b): return b ? "true" : "false"
    case .integer(let i): return String(i)
    case .real(let d): return String(d)
    case .date(let d): return ISO8601DateFormatter().string(from: d)
    case .data(let d): return "<\(d.count) bytes>"
    case .array(let a): return "[" + a.map(entitlementSummary).joined(separator: ", ") + "]"
    case .dictionary(let d):
        return "{" + d.keys.sorted().map { "\($0): \(entitlementSummary(d[$0]!))" }.joined(separator: ", ") + "}"
    }
}

@MainActor
@Observable
public final class EntitlementsEditorModel {
    /// The file on disk, if the editor was opened on one.
    public let url: URL?
    /// The live dictionary. Every edit goes through `set(_:forKey:)` /
    /// `setCapability(_:on:)` so history and the dirty flag stay correct.
    public private(set) var entitlements: Entitlements
    /// Whether the in-memory dictionary differs from disk.
    public private(set) var isDirty = false
    /// Why the last load, save or raw-XML parse failed.
    public private(set) var problem: String?

    /// Sets the problem message.
    public func setProblem(_ message: String) { problem = message }

    /// Clears the problem banner.
    public func clearProblem() { problem = nil }
    /// The last modification date seen on disk.
    public private(set) var lastModified: Date?
    /// The search text filtering capabilities and uncovered keys.
    public var searchText = ""
    /// The section filter (`.all` shows every catalog section).
    public var selectedSection: EntitlementCapabilitySection = .all
    /// The selected capability key, for the inspector.
    public var selectedKey: String?
    /// The edit history, newest first (Legacy's `EntitlementChange`).
    public private(set) var history: [EntitlementChange] = []

    /// Opens `url`; a missing file starts empty (Legacy's
    /// `readEntitlements` returned `[:]` for a missing file).
    public init(url: URL?) throws {
        self.url = url
        if let url, FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            entitlements = try Entitlements.fromPropertyList(data)
            lastModified = Self.modifiedDate(of: url)
        } else {
            entitlements = [:]
        }
    }

    /// An in-memory document with no file (used by tests and new files).
    public init(entitlements: Entitlements = [:]) {
        self.url = nil
        self.entitlements = entitlements
    }

    private static func modifiedDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    // MARK: - Persistence

    /// Writes the dictionary back as a sorted XML plist. A directory at
    /// the target path is refused, as Legacy refused it.
    public func save() throws {
        guard let url else { throw EntitlementsEditorError.noFile }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            throw EntitlementsEditorError.isDirectory(url.lastPathComponent)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try xmlData().write(to: url, options: .atomic)
        isDirty = false
        lastModified = Self.modifiedDate(of: url)
    }

    /// Writes to a different file (the editor keeps pointing at the
    /// file it was opened on).
    public func save(to newURL: URL) throws {
        let data = try xmlData()
        try data.write(to: newURL, options: .atomic)
        isDirty = false
        lastModified = Self.modifiedDate(of: newURL)
    }

    /// Re-reads the file, dropping unsaved changes.
    public func revert() throws {
        guard let url else { throw EntitlementsEditorError.noFile }
        let data = try Data(contentsOf: url)
        entitlements = try Entitlements.fromPropertyList(data)
        history.removeAll()
        isDirty = false
        lastModified = Self.modifiedDate(of: url)
    }

    /// The dictionary as XML plist data (keys sorted, as Foundation writes
    /// them — the same bytes Legacy's sorted writer produced).
    public func xmlData() throws -> Data { try entitlements.xmlPropertyList() }

    /// The dictionary as XML text, for the raw view and Copy Raw XML.
    public func xmlText() -> String {
        guard let data = try? xmlData(), let text = String(data: data, encoding: .utf8) else {
            return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\">\n<dict>\n</dict>\n</plist>"
        }
        return text
    }

    /// Replaces the dictionary from raw XML text; throws when it is not a
    /// dictionary plist (Legacy's `parseRawXML`).
    public func setXMLText(_ xml: String) throws {
        guard let data = xml.data(using: .utf8) else { throw EntitlementsEditorError.invalidXML }
        let parsed = try Entitlements.fromPropertyList(data)
        recordChanges(from: entitlements, to: parsed)
        entitlements = parsed
        isDirty = true
    }

    // MARK: - Editing

    /// Sets or removes one key, recording the change.
    public func set(_ value: EntitlementValue?, forKey key: String) {
        let old = entitlements[key].map(entitlementSummary) ?? "(absent)"
        if let value {
            entitlements[key] = value
            history.insert(EntitlementChange(rawKey: key, oldValue: old, newValue: entitlementSummary(value)), at: 0)
        } else {
            entitlements.removeValue(forKey: key)
            history.insert(EntitlementChange(rawKey: key, oldValue: old, newValue: "(removed)"), at: 0)
        }
        isDirty = true
    }

    /// Whether the capability's key is present — for iCloud, whether any of
    /// its composite keys is present (Legacy's `isCapabilityOn`).
    public func isCapabilityOn(_ def: CapabilityDefinition) -> Bool {
        if def.rawKey == EntitlementCapabilityCatalog.iCloudContainersKey {
            return entitlements[EntitlementCapabilityCatalog.iCloudContainersKey] != nil
                || entitlements[EntitlementCapabilityCatalog.iCloudKVStoreKey] != nil
                || entitlements[EntitlementCapabilityCatalog.ubiquitousContainersKey] != nil
        }
        return entitlements[def.rawKey] != nil
    }

    /// Turns a capability on (writes its default value) or off (removes
    /// the key). iCloud writes the containers key plus the key-value store
    /// identifier, and off removes all three composite keys
    /// (Legacy's `setCapability(_:on:)`).
    public func setCapability(_ def: CapabilityDefinition, on: Bool) {
        if def.rawKey == EntitlementCapabilityCatalog.iCloudContainersKey {
            if on {
                if entitlements[EntitlementCapabilityCatalog.iCloudContainersKey] == nil {
                    set(.array([]), forKey: EntitlementCapabilityCatalog.iCloudContainersKey)
                }
                if entitlements[EntitlementCapabilityCatalog.iCloudKVStoreKey] == nil {
                    set(.string("$(TeamIdentifierPrefix)$(CFBundleIdentifier)"), forKey: EntitlementCapabilityCatalog.iCloudKVStoreKey)
                }
            } else {
                set(nil, forKey: EntitlementCapabilityCatalog.iCloudContainersKey)
                set(nil, forKey: EntitlementCapabilityCatalog.iCloudKVStoreKey)
                set(nil, forKey: EntitlementCapabilityCatalog.ubiquitousContainersKey)
            }
            return
        }
        set(on ? def.defaultValue : nil, forKey: def.rawKey)
    }

    /// Applies one of Legacy's four capability presets.
    public func applyPreset(_ preset: EntitlementsPreset) {
        for (key, value) in preset.keys { set(value, forKey: key) }
    }

    /// The string array of a key (an id-list payload), or [].
    public func stringArray(forKey key: String) -> [String] {
        entitlements[key]?.strings ?? []
    }

    public func setStringArray(_ values: [String], forKey key: String) {
        set(.array(values.map(EntitlementValue.string)), forKey: key)
    }

    /// The string of a key (a choice / string payload), or `fallback`.
    public func string(forKey key: String, fallback: String) -> String {
        entitlements[key]?.stringValue ?? fallback
    }

    public func setString(_ value: String, forKey key: String) {
        set(.string(value), forKey: key)
    }

    /// Sets a boolean key (a plain toggle payload).
    public func setBool(_ value: Bool, forKey key: String) {
        set(.bool(value), forKey: key)
    }

    // MARK: - iCloud composite payload

    /// The iCloud container identifiers.
    public func iCloudContainers() -> [String] {
        entitlements[EntitlementCapabilityCatalog.iCloudContainersKey]?.strings ?? []
    }

    public func setICloudContainers(_ values: [String]) {
        set(.array(values.map(EntitlementValue.string)), forKey: EntitlementCapabilityCatalog.iCloudContainersKey)
    }

    /// The ubiquity key-value store identifier.
    public func iCloudKVStore() -> String {
        entitlements[EntitlementCapabilityCatalog.iCloudKVStoreKey]?.stringValue ?? ""
    }

    public func setICloudKVStore(_ value: String) {
        set(.string(value), forKey: EntitlementCapabilityCatalog.iCloudKVStoreKey)
    }

    /// One ubiquitous container: id, display name, whether its documents
    /// are public, and its supported folder levels.
    public func ubiquitousContainers() -> [(id: String, name: String, isPublic: Bool, folderLevels: String)] {
        guard let dict = entitlements[EntitlementCapabilityCatalog.ubiquitousContainersKey]?.dictionaryValue else { return [] }
        return dict.keys.sorted().map { id in
            let entry = dict[id]?.dictionaryValue ?? [:]
            return (id: id,
                    name: entry["NSUbiquitousContainerName"]?.stringValue ?? id,
                    isPublic: entry["NSUbiquitousContainerIsDocumentScopePublic"]?.boolValue ?? false,
                    folderLevels: entry["NSUbiquitousContainerSupportedFolderLevels"]?.stringValue ?? "")
        }
    }

    public func setUbiquitousContainer(id: String, name: String, isPublic: Bool, folderLevels: String) {
        var dict = entitlements[EntitlementCapabilityCatalog.ubiquitousContainersKey]?.dictionaryValue ?? [:]
        var entry: [String: EntitlementValue] = [:]
        entry["NSUbiquitousContainerName"] = .string(name)
        entry["NSUbiquitousContainerIsDocumentScopePublic"] = .bool(isPublic)
        if !folderLevels.isEmpty { entry["NSUbiquitousContainerSupportedFolderLevels"] = .string(folderLevels) }
        dict[id] = .dictionary(entry)
        set(.dictionary(dict), forKey: EntitlementCapabilityCatalog.ubiquitousContainersKey)
    }

    public func removeUbiquitousContainer(id: String) {
        var dict = entitlements[EntitlementCapabilityCatalog.ubiquitousContainersKey]?.dictionaryValue ?? [:]
        dict.removeValue(forKey: id)
        if dict.isEmpty {
            set(nil, forKey: EntitlementCapabilityCatalog.ubiquitousContainersKey)
        } else {
            set(.dictionary(dict), forKey: EntitlementCapabilityCatalog.ubiquitousContainersKey)
        }
    }

    /// Whether App Sandbox is on.
    public var sandboxIsOn: Bool { entitlements["com.apple.security.app-sandbox"]?.boolValue ?? false }

    /// Entitlement keys present in the file that no capability toggle
    /// manages (Legacy's `uncoveredKeys`), filtered by the search text.
    public var uncoveredKeys: [String] {
        let known = EntitlementCapabilityCatalog.allRawKeys
        return entitlements.keys.filter { !known.contains($0) }.sorted().filter { key in
            guard !searchText.isEmpty else { return true }
            let q = searchText.lowercased()
            return key.lowercased().contains(q)
                || entitlementSummary(entitlements[key]!).lowercased().contains(q)
        }
    }

    /// Whether a capability matches the search text (Legacy's
    /// `capabilityMatchesSearch`).
    public func capabilityMatchesSearch(_ def: CapabilityDefinition) -> Bool {
        guard !searchText.isEmpty else { return true }
        let q = searchText.lowercased()
        if def.name.lowercased().contains(q) || def.rawKey.lowercased().contains(q)
            || def.explanation.lowercased().contains(q) { return true }
        for key in [def.rawKey] + def.compositeKeys {
            if let v = entitlements[key], entitlementSummary(v).lowercased().contains(q) { return true }
        }
        return false
    }

    /// The sections the filter shows (Legacy's `visibleSections`).
    public var visibleSections: [EntitlementCapabilitySection] {
        switch selectedSection {
        case .all: return [.sandbox, .hardenedRuntime, .cloud, .sharing, .personal, .services, .systemExtensions]
        case .other: return []
        default: return [selectedSection]
        }
    }

    private func recordChanges(from old: Entitlements, to new: Entitlements) {
        for key in Set(old.keys).union(new.keys).sorted() {
            let o = old[key].map(entitlementSummary) ?? "(absent)"
            let n = new[key].map(entitlementSummary) ?? "(removed)"
            if o != n { history.insert(EntitlementChange(rawKey: key, oldValue: o, newValue: n), at: 0) }
        }
    }

    // MARK: - Validation

    /// Base validation plus cross-entitlement checks, deduplicated by
    /// message (Legacy's `combinedIssues` = `validate` + `crossEntitlementIssues`).
    public func validate() -> [EntitlementIssue] {
        var seen: Set<String> = []
        var out: [EntitlementIssue] = []
        for issue in baseValidation() + crossEntitlementIssues() where seen.insert(issue.message).inserted {
            out.append(issue)
        }
        return out
    }

    public var errors: [EntitlementIssue] { validate().filter { $0.severity == .error } }
    public var warnings: [EntitlementIssue] { validate().filter { $0.severity == .warning } }
    public var isValid: Bool { errors.isEmpty }

    /// Legacy's `validate(_:)`: sandbox presence, network-without-sandbox,
    /// App Groups format.
    func baseValidation() -> [EntitlementIssue] {
        var issues: [EntitlementIssue] = []
        let sandbox = entitlements["com.apple.security.app-sandbox"]
        if let sandbox {
            if sandbox == .bool(false) {
                issues.append(.init(severity: .warning, rawKey: "com.apple.security.app-sandbox",
                                    message: "App Sandbox is disabled. This will prevent App Store distribution."))
            }
        } else {
            issues.append(.init(severity: .warning, rawKey: "com.apple.security.app-sandbox",
                                message: "App Sandbox entitlement is missing entirely."))
        }
        let hasNetwork = entitlements["com.apple.security.network.client"]?.boolValue ?? false
        let sandboxOn = entitlements["com.apple.security.app-sandbox"]?.boolValue ?? false
        if hasNetwork && !sandboxOn {
            issues.append(.init(severity: .warning, rawKey: "com.apple.security.network.client",
                                message: "Network Client outgoing connections are enabled, but App Sandbox is inactive."))
        }
        if let groups = entitlements["com.apple.security.application-groups"] {
            if groups.arrayValue == nil || groups.arrayValue!.contains(where: { $0.stringValue == nil }) {
                issues.append(.init(severity: .error, rawKey: "com.apple.security.application-groups",
                                    message: "App Groups entitlement must be an array of strings."))
            }
        }
        return issues
    }

    /// Legacy's `crossEntitlementIssues(_:)`, ported to `EntitlementValue`.
    /// Pure: inspects the dictionary, performs no I/O.
    func crossEntitlementIssues() -> [EntitlementIssue] {
        var warnings: [EntitlementIssue] = []
        var errors: [EntitlementIssue] = []
        let sandbox = entitlements["com.apple.security.app-sandbox"]?.boolValue ?? false

        if let aps = entitlements["aps-environment"] {
            if aps.stringValue != "development" && aps.stringValue != "production" {
                errors.append(.init(severity: .error, rawKey: "aps-environment",
                                    message: "aps-environment must be \"development\" or \"production\"."))
            }
        }
        if !sandbox {
            for key in ["com.apple.security.network.client", "com.apple.security.network.server"] where entitlements[key] != nil {
                warnings.append(.init(severity: .warning, rawKey: key,
                                      message: "This entitlement is set but App Sandbox is off; sandbox resource entitlements have no effect without it."))
            }
            for key in [
                "com.apple.security.device.camera",
                "com.apple.security.device.audio-input",
                "com.apple.security.personal-information.photos-library",
                "com.apple.security.personal-information.location",
            ] where entitlements[key] != nil {
                warnings.append(.init(severity: .warning, rawKey: key,
                                      message: "This entitlement only takes effect in a sandboxed app, but App Sandbox is off."))
            }
        }
        let folderPairs = [
            ("com.apple.security.files.user-selected.read-only", "com.apple.security.files.user-selected.read-write"),
            ("com.apple.security.assets.downloads.read-only", "com.apple.security.assets.downloads.read-write"),
            ("com.apple.security.assets.pictures.read-only", "com.apple.security.assets.pictures.read-write"),
            ("com.apple.security.assets.music.read-only", "com.apple.security.assets.music.read-write"),
            ("com.apple.security.assets.movies.read-only", "com.apple.security.assets.movies.read-write"),
        ]
        for (readOnly, readWrite) in folderPairs where entitlements[readOnly] != nil && entitlements[readWrite] != nil {
            warnings.append(.init(severity: .warning, rawKey: readOnly,
                                  message: "Read-write access already includes read access; the read-only key for this folder is redundant."))
        }
        let csKeys = [
            "com.apple.security.cs.allow-jit",
            "com.apple.security.cs.allow-unsigned-executable-memory",
            "com.apple.security.cs.disable-library-validation",
            "com.apple.security.cs.allow-dyld-environment-variables",
            "com.apple.security.cs.debugger",
        ]
        if sandbox, csKeys.contains(where: { entitlements[$0] != nil }) {
            warnings.append(.init(severity: .warning, rawKey: "com.apple.security.cs.*",
                                  message: "Hardened Runtime entitlements apply to Developer ID / notarized distribution; Mac App Store builds enforce their own runtime policy."))
        }
        let containers = entitlements[EntitlementCapabilityCatalog.iCloudContainersKey]
        let services = entitlements[EntitlementCapabilityCatalog.iCloudServicesKey]?.strings
        if containers != nil && (services?.isEmpty ?? true) {
            warnings.append(.init(severity: .warning, rawKey: EntitlementCapabilityCatalog.iCloudContainersKey,
                                  message: "iCloud container identifiers are set but no iCloud services (CloudDocuments / CloudKit) are enabled."))
        }
        if let services, !services.isEmpty, containers == nil {
            warnings.append(.init(severity: .warning, rawKey: EntitlementCapabilityCatalog.iCloudServicesKey,
                                  message: "iCloud services are enabled but no container identifiers are set."))
        }
        if entitlements[EntitlementCapabilityCatalog.ubiquitousContainersKey] != nil && containers == nil {
            warnings.append(.init(severity: .warning, rawKey: EntitlementCapabilityCatalog.ubiquitousContainersKey,
                                  message: "Ubiquitous containers are declared but no iCloud container identifiers are set."))
        }
        if let groups = entitlements["com.apple.security.application-groups"] {
            if let arr = groups.arrayValue {
                let strings = arr.compactMap(\.stringValue)
                if arr.isEmpty {
                    warnings.append(.init(severity: .warning, rawKey: "com.apple.security.application-groups",
                                          message: "App Groups is enabled with an empty identifier list."))
                } else if strings.count != arr.count || strings.contains(where: { !$0.hasPrefix("group.") }) {
                    warnings.append(.init(severity: .warning, rawKey: "com.apple.security.application-groups",
                                          message: "App Group identifiers should begin with \"group.\"."))
                }
            } else {
                errors.append(.init(severity: .error, rawKey: "com.apple.security.application-groups",
                                    message: "App Groups must be an array of strings."))
            }
        }
        if let keychain = entitlements["keychain-access-groups"] {
            if let arr = keychain.arrayValue {
                if arr.isEmpty {
                    warnings.append(.init(severity: .warning, rawKey: "keychain-access-groups",
                                          message: "Keychain Access Groups is enabled with an empty identifier list."))
                }
            } else {
                errors.append(.init(severity: .error, rawKey: "keychain-access-groups",
                                    message: "Keychain Access Groups must be an array of strings."))
            }
        }
        let knownPrefixes = ["applinks:", "webcredentials:", "activitycontinuation:", "appclips:"]
        if let domains = entitlements["com.apple.developer.associated-domains"]?.arrayValue {
            let strings = domains.compactMap(\.stringValue)
            if strings.contains(where: { d in !knownPrefixes.contains(where: d.hasPrefix) }) {
                warnings.append(.init(severity: .warning, rawKey: "com.apple.developer.associated-domains",
                                      message: "Entries should begin with one of applinks:, webcredentials:, activitycontinuation:, appclips:."))
            }
        }
        let validDDP = [
            "NSFileProtectionComplete",
            "NSFileProtectionCompleteUnlessOpen",
            "NSFileProtectionCompleteUntilFirstUserAuthentication",
            "NSFileProtectionNone",
        ]
        if let ddp = entitlements["com.apple.developer.default-data-protection"]?.stringValue, !validDDP.contains(ddp) {
            errors.append(.init(severity: .error, rawKey: "com.apple.developer.default-data-protection",
                                message: "Unknown data protection class. Use one of the NSFileProtection values."))
        }
        if entitlements["com.apple.security.network.server"]?.boolValue == true {
            warnings.append(.init(severity: .warning, rawKey: "com.apple.security.network.server",
                                  message: "Incoming network connections may draw extra App Review scrutiny; be ready to explain why the app listens."))
        }
        for key in [
            "com.apple.developer.driverkit",
            "com.apple.developer.endpoint-security.client",
            "com.apple.developer.networking.networkextension",
            "com.apple.developer.system-extension.install",
        ] where entitlements[key] != nil {
            warnings.append(.init(severity: .warning, rawKey: key,
                                  message: "Requires a special entitlement request to Apple — the key alone does not grant access."))
        }
        return errors + warnings
    }

    /// The restricted entitlements a provisioning profile does not allow
    /// (SwiftCodeSigning's `EntitlementPolicy.mismatches`). The editor itself
    /// has no profile; callers pass the target's resolved profile.
    public func profileMismatches(profile: ProvisioningProfile, platform: SigningPlatform) -> [EntitlementPolicy.Mismatch] {
        EntitlementPolicy.mismatches(entitlements, profile: profile, platform: platform)
    }
}

public enum EntitlementsEditorError: Error, CustomStringConvertible {
    case noFile
    case isDirectory(String)
    case invalidXML

    public var description: String {
        switch self {
        case .noFile: return "The entitlements editor has no file to save to."
        case .isDirectory(let name): return "The target path is a directory, not an entitlements file: \(name)"
        case .invalidXML: return "Invalid UTF-8 encoding"
        }
    }
}
