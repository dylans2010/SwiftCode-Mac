import Foundation
import SwiftCodePlist
import SwiftCodeProject
import SwiftCodeSettings

public struct ProjectEditorModel {
    public var proj: PBXProj
    public let xcodeprojURL: URL
    public var defaultsProvider: ((String?, String) -> [String: String]?)?

    public init(proj: PBXProj, xcodeprojURL: URL) {
        self.proj = proj
        self.xcodeprojURL = xcodeprojURL
    }

    public var projectName: String { xcodeprojURL.deletingPathExtension().lastPathComponent }
    public var targets: [PBXObject] { proj.targets }

    public func target(named name: String) -> PBXObject? { proj.targets.first { $0.string("name") == name } }

    public func configurations(of owner: String?) -> (names: [String], defaultName: String?) {
        let id = owner.flatMap { target(named: $0)?.id } ?? proj.rootObject
        let listID = proj[id]?.string("buildConfigurationList")
        return (proj.buildConfigurations(listID: listID).compactMap { $0.string("name") },
                proj[listID ?? ""]?.string("defaultConfigurationName"))
    }

    public func resolve(target: String?, configuration: String) -> ProjectSettingsBuilder.Resolved? {
        try? ProjectSettingsBuilder(proj: proj, xcodeprojURL: xcodeprojURL).resolve(target: target, configuration: configuration)
    }

    public enum Filter: String, CaseIterable, Sendable { case basic = "Basic", customized = "Customized", all = "All" }

    public static let basicSettings = [
        "ARCHS", "SDKROOT", "SUPPORTED_PLATFORMS", "MACOSX_DEPLOYMENT_TARGET", "PRODUCT_NAME", "PRODUCT_BUNDLE_IDENTIFIER",
        "INFOPLIST_FILE", "GENERATE_INFOPLIST_FILE", "MARKETING_VERSION", "CURRENT_PROJECT_VERSION", "CODE_SIGN_IDENTITY",
        "CODE_SIGN_STYLE", "DEVELOPMENT_TEAM", "CODE_SIGN_ENTITLEMENTS", "ENABLE_HARDENED_RUNTIME", "SWIFT_VERSION",
        "SWIFT_OPTIMIZATION_LEVEL", "GCC_OPTIMIZATION_LEVEL", "DEBUG_INFORMATION_FORMAT", "OTHER_LDFLAGS",
        "OTHER_SWIFT_FLAGS", "HEADER_SEARCH_PATHS", "FRAMEWORK_SEARCH_PATHS", "LD_RUNPATH_SEARCH_PATHS",
    ]

    public struct SettingRow: Equatable, Sendable {
        public var name: String
        public var resolved: String
        public var target: String?
        public var targetXCConfig: String?
        public var project: String?
        public var projectXCConfig: String?
        public var defaults: String?

        public var providingLevel: String? {
            if target != nil { return "target" }
            if targetXCConfig != nil { return "targetXCConfig" }
            if project != nil { return "project" }
            if projectXCConfig != nil { return "projectXCConfig" }
            if defaults != nil { return "defaults" }
            return nil
        }
    }

    static let customizedLevels: Set<String> = ["target", "target-xcconfig", "project", "project-xcconfig"]

    public func settingRows(target: String?, configuration: String, filter: Filter, search: String = "") -> [SettingRow] {
        guard let r = resolve(target: target, configuration: configuration) else { return [] }
        let s = r.settings
        let defaults = defaultsProvider?(target, configuration)
        let names: [String]
        switch filter {
        case .basic: names = Self.basicSettings
        case .customized:
            let levels = target == nil ? Set(["project", "project-xcconfig"]) : Self.customizedLevels
            names = s.names.filter { s.isAssigned($0, inLevels: levels) }
        case .all: names = Array(Set(s.names).union(defaults?.keys ?? [String: String]().keys))
        }
        let q = search.lowercased()
        return rows(names.filter { q.isEmpty || $0.lowercased().contains(q) }.sorted(), resolved: r, defaults: defaults, target: target)
    }

    public func settingRows(names: [String], target: String?, configuration: String) -> [SettingRow] {
        guard let r = resolve(target: target, configuration: configuration) else { return [] }
        return rows(names, resolved: r, defaults: defaultsProvider?(target, configuration), target: target)
    }

    private func rows(_ names: [String], resolved r: ProjectSettingsBuilder.Resolved, defaults: [String: String]?, target: String?) -> [SettingRow] {
        let s = r.settings
        return names.map { n in
            let own = s.isAssigned(n, inLevels: Self.customizedLevels) || defaults == nil
            return SettingRow(name: n, resolved: own ? s[n] : (defaults?[n] ?? s[n]),
                       target: target == nil ? nil : s.assignedText(n, inLevel: "target"),
                       targetXCConfig: target == nil ? nil : s.assignedText(n, inLevel: "target-xcconfig"),
                       project: s.assignedText(n, inLevel: "project"),
                       projectXCConfig: s.assignedText(n, inLevel: "project-xcconfig"),
                       defaults: defaults.map { $0[n] } ?? s.assignedText(n, inLevel: "defaults"))
        }
    }

    public mutating func setSetting(_ name: String, _ value: String, target: String?) {
        let owner = target.flatMap { self.target(named: $0)?.id } ?? proj.rootObject
        let v = value.trimmingCharacters(in: .whitespaces)
        proj.setBuildSetting(name, v.isEmpty ? nil : .string(v), inListOf: owner)
    }

    public struct PhaseSection: Equatable, Sendable {
        public var title: String
        public var phaseID: String?
        public var items: [(id: String, name: String)]
        public var script: String?
        public var shell: String?
        public static func == (a: Self, b: Self) -> Bool {
            a.title == b.title && a.phaseID == b.phaseID && a.script == b.script && a.shell == b.shell
                && a.items.map(\.id) == b.items.map(\.id) && a.items.map(\.name) == b.items.map(\.name)
        }
    }

    public func embeddedAndSigned(target name: String) -> Set<String> {
        guard let t = target(named: name) else { return [] }
        var out = Set<String>()
        for p in proj.buildPhases(ofTarget: t.id) where p.isa == "PBXCopyFilesBuildPhase" && p.string("dstSubfolderSpec") == "10" {
            for bf in p.references("files") {
                let attrs = proj[bf]?["settings"]?.dictionary?["ATTRIBUTES"]?.array?.compactMap(\.string) ?? []
                guard attrs.contains("CodeSignOnCopy") else { continue }
                let ref = proj.fileReference(ofBuildFile: bf)
                if let n = ref?.string("name") ?? ref?.string("path").map({ ($0 as NSString).lastPathComponent })
                    ?? proj[bf]?.string("productRef").flatMap({ proj[$0]?.string("productName") }) { out.insert(n) }
            }
        }
        return out
    }

    public func phaseSections(target name: String) -> [PhaseSection] {
        guard let t = target(named: name) else { return [] }
        let deps = t.references("dependencies").compactMap { d -> (String, String)? in
            guard let tid = proj[d]?.string("target"), let n = proj[tid]?.string("name") else { return nil }
            return (d, n)
        }
        let plugins = t.references("dependencies").compactMap { d -> (String, String)? in
            guard let p = proj[d]?.string("productRef"), let n = proj[p]?.string("productName"), n.hasPrefix("plugin:") else { return nil }
            return (d, String(n.dropFirst("plugin:".count)))
        }
        var out = [PhaseSection(title: "Target Dependencies", phaseID: nil, items: deps.map { ($0.0, $0.1) }, script: nil),
                   PhaseSection(title: "Run Build Tool Plug-ins", phaseID: nil, items: plugins.map { ($0.0, $0.1) }, script: nil)]
        for p in proj.buildPhases(ofTarget: t.id) {
            let title: String = switch p.isa {
            case "PBXSourcesBuildPhase": "Compile Sources"
            case "PBXFrameworksBuildPhase": "Link Binary With Libraries"
            case "PBXResourcesBuildPhase": "Copy Bundle Resources"
            case "PBXHeadersBuildPhase": "Headers"
            case "PBXCopyFilesBuildPhase": p.string("name") ?? "Copy Files"
            case "PBXShellScriptBuildPhase": p.string("name") ?? "Run Script"
            default: p.isa
            }
            let items = p.references("files").map { bf -> (String, String) in
                let ref = proj.fileReference(ofBuildFile: bf)
                let n = ref?.string("name") ?? ref?.string("path").map { ($0 as NSString).lastPathComponent }
                    ?? proj[bf]?.string("productRef").flatMap { proj[$0]?.string("productName") } ?? bf
                return (bf, n)
            }
            var section = PhaseSection(title: title, phaseID: p.id, items: items,
                                       script: p.isa == "PBXShellScriptBuildPhase" ? p.string("shellScript") : nil)
            if p.isa == "PBXShellScriptBuildPhase" { section.shell = p.string("shellPath") ?? "/bin/sh" }
            out.append(section)
        }
        return out
    }

    @discardableResult
    public mutating func addFile(_ relativePath: String, toPhase phase: String) -> String {
        let existing = proj.objects.values.first { $0.isa == "PBXFileReference" && $0.string("path") == relativePath }?.id
        let ref = existing ?? proj.addFileReference(path: relativePath, to: proj.project?.string("mainGroup") ?? "")
        return proj.addBuildFile(fileReference: ref, to: phase)
    }

    public mutating func removeBuildFile(_ id: String) { proj.removeBuildFile(id) }

    public func buildRules(target name: String) -> [String] {
        guard let t = target(named: name) else { return [] }
        return t.references("buildRules").compactMap { proj[$0] }.map { r in
            let input = r.string("filePatterns") ?? r.string("fileType") ?? "?"
            let tool = r.string("compilerSpec") ?? "script"
            return "\(input) → \(tool == "com.apple.compilers.proxy.script" ? "script" : tool)"
        }
    }

    public struct InfoRow: Equatable, Sendable {
        public var key: String
        public var type: String
        public var value: String
    }

    public func infoRows(target name: String, configuration: String) -> [InfoRow] {
        guard let r = resolve(target: name, configuration: configuration) else { return [] }
        var rows: [InfoRow] = []
        let file = r.settings["INFOPLIST_FILE"]
        if !file.isEmpty {
            let url = file.hasPrefix("/") ? URL(fileURLWithPath: file)
                : proj.projectDirectory(xcodeprojURL: xcodeprojURL).appendingPathComponent(file)
            if let data = try? Data(contentsOf: url), let doc = try? PropertyListDocument(data: data), case .dictionary(let d) = doc.root {
                for e in d { rows.append(InfoRow(key: e.key, type: e.value.typeName, value: e.value.summary)) }
            }
        }
        for n in r.settings.names where n.hasPrefix("INFOPLIST_KEY_") {
            rows.append(InfoRow(key: String(n.dropFirst("INFOPLIST_KEY_".count)), type: "String", value: r.settings[n]))
        }
        return rows
    }

    public func entitlementKeys(target name: String, configuration: String) -> [String] {
        guard let r = resolve(target: name, configuration: configuration) else { return [] }
        let file = r.settings["CODE_SIGN_ENTITLEMENTS"]
        guard !file.isEmpty else { return [] }
        let url = file.hasPrefix("/") ? URL(fileURLWithPath: file) : proj.projectDirectory(xcodeprojURL: xcodeprojURL).appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url), let doc = try? PropertyListDocument(data: data), case .dictionary(let d) = doc.root else { return [] }
        return d.map(\.key)
    }
}
