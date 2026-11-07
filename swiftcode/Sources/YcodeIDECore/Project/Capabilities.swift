import Foundation
import YcodePlist
import YcodeProject

public enum Capability: String, CaseIterable, Sendable {
    case appSandbox = "App Sandbox"
    case hardenedRuntime = "Hardened Runtime"
    case outgoingNetwork = "Outgoing Connections (Client)"
    case incomingNetwork = "Incoming Connections (Server)"
    case userSelectedFilesRead = "User Selected File (Read Only)"
    case userSelectedFilesReadWrite = "User Selected File (Read/Write)"

    public var entitlements: [String] {
        switch self {
        case .appSandbox: ["com.apple.security.app-sandbox"]
        case .hardenedRuntime: []
        case .outgoingNetwork: ["com.apple.security.network.client"]
        case .incomingNetwork: ["com.apple.security.network.server"]
        case .userSelectedFilesRead: ["com.apple.security.files.user-selected.read-only"]
        case .userSelectedFilesReadWrite: ["com.apple.security.files.user-selected.read-write"]
        }
    }

    public var settings: [String] { self == .hardenedRuntime ? ["ENABLE_HARDENED_RUNTIME"] : [] }

    public var requiresSandbox: Bool { ![.appSandbox, .hardenedRuntime].contains(self) }
}

extension ProjectEditorModel {
    public var teams: [String] {
        Set(proj.objects.values.filter { $0.isa == "XCBuildConfiguration" }
            .compactMap { $0["buildSettings"]?.dictionary?["DEVELOPMENT_TEAM"]?.string }.filter { !$0.isEmpty }).sorted()
    }

    public mutating func setAutomaticSigning(_ on: Bool, target: String) {
        setSetting("CODE_SIGN_STYLE", on ? "Automatic" : "Manual", target: target)
    }

    public func entitlementsURL(target: String, configuration: String) -> URL? {
        guard let path = resolve(target: target, configuration: configuration)?.settings["CODE_SIGN_ENTITLEMENTS"], !path.isEmpty else { return nil }
        return path.hasPrefix("/") ? URL(fileURLWithPath: path) : proj.projectDirectory(xcodeprojURL: xcodeprojURL).appendingPathComponent(path)
    }

    func entitlements(target: String, configuration: String) -> [PropertyListEntry] {
        guard let url = entitlementsURL(target: target, configuration: configuration), let data = try? Data(contentsOf: url),
              let doc = try? PropertyListDocument(data: data), case .dictionary(let d) = doc.root else { return [] }
        return d
    }

    public func capabilities(target: String, configuration: String) -> [Capability] {
        let ents = entitlements(target: target, configuration: configuration)
        let settings = resolve(target: target, configuration: configuration)?.settings
        return Capability.allCases.filter { c in
            c.entitlements.allSatisfy { k in ents.contains { $0.key == k && $0.value == .bool(true) } }
                && c.settings.allSatisfy { settings?[$0] == "YES" }
        }
    }

    public mutating func addCapability(_ c: Capability, target: String, configuration: String) throws {
        if c.requiresSandbox, !capabilities(target: target, configuration: configuration).contains(.appSandbox) {
            try addCapability(.appSandbox, target: target, configuration: configuration)
        }
        for s in c.settings { setSetting(s, "YES", target: target) }
        guard !c.entitlements.isEmpty else { return }
        let url: URL
        if let existing = entitlementsURL(target: target, configuration: configuration) {
            url = existing
        } else {
            let rel = "\(target)/\(target).entitlements"
            url = proj.projectDirectory(xcodeprojURL: xcodeprojURL).appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                try PropertyListDocument(root: .dictionary([])).xml().write(to: url, atomically: true, encoding: .utf8)
            }
            proj.addFileReference(path: rel, to: proj.project?.string("mainGroup") ?? "")
            setSetting("CODE_SIGN_ENTITLEMENTS", rel, target: target)
        }
        var doc = (try? PropertyListDocument(data: Data(contentsOf: url))) ?? PropertyListDocument(root: .dictionary([]))
        guard case .dictionary(var d) = doc.root else { return }
        for k in c.entitlements {
            if let i = d.firstIndex(where: { $0.key == k }) { d[i].value = .bool(true) } else { d.append(PropertyListEntry(key: k, value: .bool(true))) }
        }
        doc.root = .dictionary(d)
        try doc.data().write(to: url, options: .atomic)
    }

    public mutating func removeCapability(_ c: Capability, target: String, configuration: String) throws {
        let dependents = c == .appSandbox ? Capability.allCases.filter(\.requiresSandbox) : []
        for s in c.settings { setSetting(s, "", target: target) }
        guard let url = entitlementsURL(target: target, configuration: configuration),
              var doc = try? PropertyListDocument(data: Data(contentsOf: url)), case .dictionary(var d) = doc.root else { return }
        let keys = Set(([c] + dependents).flatMap(\.entitlements))
        d.removeAll { keys.contains($0.key) }
        doc.root = .dictionary(d)
        try doc.data().write(to: url, options: .atomic)
    }

    public func signingCertificate(target: String, configuration: String) -> String {
        let id = resolve(target: target, configuration: configuration)?.settings["CODE_SIGN_IDENTITY"] ?? ""
        switch id {
        case "-": return "Sign to Run Locally"
        case "": return "None"
        default: return id
        }
    }
}
