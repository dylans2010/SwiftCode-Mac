import Foundation
import Observation
import SwiftCodeSigning

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
    public let url: URL?
    public private(set) var entitlements: Entitlements
    public private(set) var isDirty = false
    public private(set) var problem: String?

    public func setProblem(_ message: String) { problem = message }

    public func clearProblem() { problem = nil }
    public private(set) var lastModified: Date?
    public var searchText = ""
    public var selectedSection: EntitlementCapabilitySection = .all
    public var selectedKey: String?
    public private(set) var history: [EntitlementChange] = []

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

    public init(entitlements: Entitlements = [:]) {
        self.url = nil
        self.entitlements = entitlements
    }

    private static func modifiedDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

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

    public func save(to newURL: URL) throws {
        let data = try xmlData()
        try data.write(to: newURL, options: .atomic)
        isDirty = false
        lastModified = Self.modifiedDate(of: newURL)
    }

    public func revert() throws {
        guard let url else { throw EntitlementsEditorError.noFile }
        let data = try Data(contentsOf: url)
        entitlements = try Entitlements.fromPropertyList(data)
        history.removeAll()
        isDirty = false
        lastModified = Self.modifiedDate(of: url)
    }

    public func xmlData() throws -> Data { try entitlements.xmlPropertyList() }

    public func xmlText() -> String {
        guard let data = try? xmlData(), let text = String(data: data, encoding: .utf8) else {
            return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\">\n<dict>\n</dict>\n</plist>"
        }
        return text
    }

    public func setXMLText(_ xml: String) throws {
        guard let data = xml.data(using: .utf8) else { throw EntitlementsEditorError.invalidXML }
        let parsed = try Entitlements.fromPropertyList(data)
        recordChanges(from: entitlements, to: parsed)
        entitlements = parsed
        isDirty = true
    }

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

    public func isCapabilityOn(_ def: CapabilityDefinition) -> Bool {
        if def.rawKey == EntitlementCapabilityCatalog.iCloudContainersKey {
            return entitlements[EntitlementCapabilityCatalog.iCloudContainersKey] != nil
                || entitlements[EntitlementCapabilityCatalog.iCloudKVStoreKey] != nil
                || entitlements[EntitlementCapabilityCatalog.ubiquitousContainersKey] != nil
        }
        return entitlements[def.rawKey] != nil
    }

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

    public func applyPreset(_ preset: EntitlementsPreset) {
        for (key, value) in preset.keys { set(value, forKey: key) }
    }

    public func stringArray(forKey key: String) -> [String] {
        entitlements[key]?.strings ?? []
    }

    public func setStringArray(_ values: [String], forKey key: String) {
        set(.array(values.map(EntitlementValue.string)), forKey: key)
    }

    public func string(forKey key: String, fallback: String) -> String {
        entitlements[key]?.stringValue ?? fallback
    }

    public func setString(_ value: String, forKey key: String) {
        set(.string(value), forKey: key)
    }

    public func setBool(_ value: Bool, forKey key: String) {
        set(.bool(value), forKey: key)
    }

    public func iCloudContainers() -> [String] {
        entitlements[EntitlementCapabilityCatalog.iCloudContainersKey]?.strings ?? []
    }

    public func setICloudContainers(_ values: [String]) {
        set(.array(values.map(EntitlementValue.string)), forKey: EntitlementCapabilityCatalog.iCloudContainersKey)
    }

    public func iCloudKVStore() -> String {
        entitlements[EntitlementCapabilityCatalog.iCloudKVStoreKey]?.stringValue ?? ""
    }

    public func setICloudKVStore(_ value: String) {
        set(.string(value), forKey: EntitlementCapabilityCatalog.iCloudKVStoreKey)
    }

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

    public var sandboxIsOn: Bool { entitlements["com.apple.security.app-sandbox"]?.boolValue ?? false }

    public var uncoveredKeys: [String] {
        let known = EntitlementCapabilityCatalog.allRawKeys
        return entitlements.keys.filter { !known.contains($0) }.sorted().filter { key in
            guard !searchText.isEmpty else { return true }
            let q = searchText.lowercased()
            return key.lowercased().contains(q)
                || entitlementSummary(entitlements[key]!).lowercased().contains(q)
        }
    }

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
