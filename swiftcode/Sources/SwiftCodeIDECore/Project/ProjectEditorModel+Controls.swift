import Foundation
import SwiftCodePlist
import SwiftCodeProject

extension ProjectEditorModel {

    public var resourceTags: [String] {
        proj.project?["attributes"]?.dictionary?["KnownAssetTags"]?.array?.compactMap(\.string) ?? []
    }

    mutating func setResourceTags(_ tags: [String]) {
        guard var p = proj.project else { return }
        let had = p["attributes"] != nil
        var attrs = p["attributes"]?.dictionary ?? PlistDictionary()
        attrs["KnownAssetTags"] = tags.isEmpty ? nil : .array(tags.map(PlistValue.string))
        p["attributes"] = attrs.isEmpty && !had ? nil : .dictionary(attrs)
        proj[p.id] = p
    }

    @discardableResult
    public mutating func addResourceTag() -> String {
        let tags = resourceTags
        var name = "New Tag", n = 1
        while tags.contains(name) { n += 1; name = "New Tag \(n)" }
        setResourceTags(tags + [name])
        return name
    }

    public mutating func renameResourceTag(_ old: String, to new: String) {
        let n = new.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, old != n, !resourceTags.contains(n) else { return }
        setResourceTags(resourceTags.map { $0 == old ? n : $0 })
        rewriteTagUses { $0 == old ? n : $0 }
    }

    public mutating func removeResourceTag(_ tag: String) {
        setResourceTags(resourceTags.filter { $0 != tag })
        rewriteTagUses { $0 == tag ? nil : $0 }
    }

    static let onDemandSettings = ["ON_DEMAND_RESOURCES_INITIAL_INSTALL_TAGS", "ON_DEMAND_RESOURCES_PREFETCH_ORDER"]

    private mutating func rewriteTagUses(_ map: (String) -> String?) {
        for (id, var o) in proj.objects where o.isa == "PBXBuildFile" {
            guard var settings = o["settings"]?.dictionary, let tags = settings["ASSET_TAGS"]?.array?.compactMap(\.string) else { continue }
            let mapped = tags.compactMap(map)
            guard mapped != tags else { continue }
            settings["ASSET_TAGS"] = mapped.isEmpty ? nil : .array(mapped.map(PlistValue.string))
            o["settings"] = settings.isEmpty ? nil : .dictionary(settings)
            proj[id] = o
        }
        for c in proj.objects.values where c.isa == "XCBuildConfiguration" {
            for s in Self.onDemandSettings {
                guard let v = c["buildSettings"]?.dictionary?[s]?.string else { continue }
                let mapped = v.split(separator: " ").map(String.init).compactMap(map).joined(separator: " ")
                if mapped != v { proj.setBuildSetting(s, mapped.isEmpty ? nil : .string(mapped), configuration: c.id) }
            }
        }
    }

    public var resourceTagUses: [String: Int] {
        var out: [String: Int] = [:]
        for o in proj.objects.values where o.isa == "PBXBuildFile" {
            for t in o["settings"]?.dictionary?["ASSET_TAGS"]?.array?.compactMap(\.string) ?? [] { out[t, default: 0] += 1 }
        }
        return out
    }

    public func prefetchGroups(target: String, configuration: String) -> [(title: String, tags: [String])] {
        let s = resolve(target: target, configuration: configuration)?.settings
        let initial = (s?["ON_DEMAND_RESOURCES_INITIAL_INSTALL_TAGS"] ?? "").split(separator: " ").map(String.init)
        let order = (s?["ON_DEMAND_RESOURCES_PREFETCH_ORDER"] ?? "").split(separator: " ").map(String.init)
        let rest = resourceTags.filter { !initial.contains($0) && !order.contains($0) }
        return [("Initial Install Tags", initial), ("Prefetched Tag Order", order), ("Download Only On Demand", rest)]
    }

    @discardableResult
    public mutating func addBuildRule(target name: String) -> String? {
        guard var t = target(named: name), t.isa == "PBXNativeTarget" else { return nil }
        let id = proj.makeObjectID()
        proj[id] = PBXObject(id: id, attributes: PlistDictionary([
            ("isa", "PBXBuildRule"), ("compilerSpec", "com.apple.compilers.proxy.script"), ("filePatterns", ""),
            ("fileType", "pattern.proxy"), ("inputFiles", .array([])), ("isEditable", "1"), ("outputFiles", .array([])),
            ("script", ""),
        ]))
        t["buildRules"] = .array((t.references("buildRules") + [id]).map(PlistValue.string))
        proj[t.id] = t
        return id
    }

    public mutating func removeBuildRule(_ id: String) {
        for var t in proj.targets where t.references("buildRules").contains(id) {
            t["buildRules"] = .array(t.references("buildRules").filter { $0 != id }.map(PlistValue.string))
            proj[t.id] = t
        }
        proj[id] = nil
    }

    @discardableResult
    public mutating func copyBuildRule(_ id: String, toTarget name: String) -> String? {
        guard let rule = proj[id], var t = target(named: name), t.isa == "PBXNativeTarget" else { return nil }
        let copy = proj.makeObjectID()
        proj[copy] = PBXObject(id: copy, attributes: rule.attributes)
        t["buildRules"] = .array((t.references("buildRules") + [copy]).map(PlistValue.string))
        proj[t.id] = t
        return copy
    }

    public func ruleSectionIDs(target name: String) -> [(id: String, section: RuleSection)] {
        guard let t = target(named: name) else { return [] }
        return t.references("buildRules").compactMap { id in proj[id].map { (id, $0) } }.map { id, r in
            let input = r.string("fileType") == "pattern.proxy" ? (r.string("filePatterns") ?? "*") : (r.string("fileType") ?? r.string("filePatterns") ?? "?")
            let tool = r.string("compilerSpec") ?? "com.apple.compilers.proxy.script"
            let title = r.string("name") ?? "Files \(input.isEmpty ? "*" : input) using \(tool == "com.apple.compilers.proxy.script" ? "Script" : tool)"
            return (id, RuleSection(title: title, process: "Process: \(input)", using: "Using: \(tool)"))
        }.sorted { $0.1.title.localizedStandardCompare($1.1.title) == .orderedAscending }
    }

    @discardableResult
    public mutating func duplicateConfiguration(_ name: String) -> String? {
        let owners = [proj.rootObject] + proj.targets.map(\.id)
        let existing = Set(configurations(of: nil).names)
        guard existing.contains(name) else { return nil }
        var new = "\(name) copy", n = 1
        while existing.contains(new) { n += 1; new = "\(name) copy \(n)" }
        for owner in owners {
            guard let listID = proj[owner]?.string("buildConfigurationList"), var list = proj[listID] else { continue }
            guard let source = proj.buildConfigurations(listID: listID).first(where: { $0.string("name") == name }) else { continue }
            let id = proj.makeObjectID()
            var attrs = source.attributes
            attrs["name"] = .string(new)
            proj[id] = PBXObject(id: id, attributes: attrs)
            list["buildConfigurations"] = .array((list.references("buildConfigurations") + [id]).map(PlistValue.string))
            proj[listID] = list
        }
        return new
    }

    public mutating func removeConfiguration(_ name: String) {
        guard configurations(of: nil).names.count > 1 else { return }
        for owner in [proj.rootObject] + proj.targets.map(\.id) {
            guard let listID = proj[owner]?.string("buildConfigurationList"), var list = proj[listID] else { continue }
            let configs = proj.buildConfigurations(listID: listID)
            guard configs.count > 1, let gone = configs.first(where: { $0.string("name") == name }) else { continue }
            list["buildConfigurations"] = .array(list.references("buildConfigurations").filter { $0 != gone.id }.map(PlistValue.string))
            if list.string("defaultConfigurationName") == name {
                list["defaultConfigurationName"] = configs.first { $0.id != gone.id }?.string("name").map(PlistValue.string)
            }
            proj[listID] = list
            proj[gone.id] = nil
        }
    }

    public mutating func setCommandLineConfiguration(_ name: String) {
        guard let listID = proj.project?.string("buildConfigurationList"), var list = proj[listID],
              configurations(of: nil).names.contains(name) else { return }
        list["defaultConfigurationName"] = .string(name)
        proj[listID] = list
    }

    public mutating func setParallelizeCommandLine(_ on: Bool) {
        guard var p = proj.project else { return }
        var attrs = p["attributes"]?.dictionary ?? PlistDictionary()
        attrs["BuildIndependentTargetsInParallel"] = .string(on ? "1" : "0")
        p["attributes"] = .dictionary(attrs)
        proj[p.id] = p
    }

    var knownRegions: [String] { proj.project?["knownRegions"]?.array?.compactMap(\.string) ?? [] }

    mutating func setKnownRegions(_ regions: [String]) {
        guard var p = proj.project else { return }
        p["knownRegions"] = .array(regions.map(PlistValue.string))
        proj[p.id] = p
    }

    public var localizationRows: [(code: String, name: String, isDefault: Bool, files: Int)] {
        let dev = proj.project?.string("developmentRegion") ?? "en"
        let names = Locale(identifier: "en")
        var counts: [String: Int] = [:]
        for g in proj.objects.values where g.isa == "PBXVariantGroup" {
            for c in g.references("children") { if let n = proj[c]?.string("name") { counts[n, default: 0] += 1 } }
        }
        return knownRegions.filter { $0 != "Base" }.map { r in
            (r, (names.localizedString(forIdentifier: r) ?? r) + (r == dev ? " (Development Language)" : ""), r == dev, counts[r] ?? 0)
        }
    }

    public static func filesLocalizedText(_ n: Int) -> String { "\(n) File\(n == 1 ? "" : "s") Localized" }

    public static let addableLocalizations = ["ar", "ca", "zh-Hans", "zh-Hant", "hr", "cs", "da", "nl", "en-GB", "fi", "fr", "de", "el",
                                              "he", "hi", "hu", "id", "it", "ja", "ko", "ms", "nb", "pl", "pt-BR", "pt-PT", "ro", "ru",
                                              "sk", "es", "es-419", "sv", "th", "tr", "uk", "vi"]

    public mutating func addLocalization(_ code: String) {
        guard !knownRegions.contains(code) else { return }
        setKnownRegions(knownRegions + [code])
    }

    public mutating func removeLocalization(_ code: String) {
        guard code != (proj.project?.string("developmentRegion") ?? "en") else { return }
        setKnownRegions(knownRegions.filter { $0 != code })
    }

    public mutating func setDevelopmentRegion(_ code: String) {
        guard var p = proj.project, knownRegions.contains(code) else { return }
        p["developmentRegion"] = .string(code)
        proj[p.id] = p
    }

    public mutating func setUsesBaseInternationalization(_ on: Bool) {
        let r = knownRegions.filter { $0 != "Base" }
        setKnownRegions(on ? r + ["Base"] : r)
    }

    public func configurationFiles(_ name: String) -> [(owner: String, file: String)] {
        ([(projectName, proj.rootObject)] + proj.targets.map { ($0.string("name") ?? "", $0.id) }).map { owner, id in
            let c = proj.buildConfigurations(listID: proj[id]?.string("buildConfigurationList")).first { $0.string("name") == name }
            let f = c?.string("baseConfigurationReference").flatMap { proj[$0] }
                .flatMap { $0.string("name") ?? $0.string("path").map { ($0 as NSString).lastPathComponent } }
            return (owner, f ?? "None")
        }
    }
}
extension ProjectEditorModel {
    public static func resourceCountText(_ n: Int) -> String { "\(n) Resource\(n == 1 ? "" : "s")" }
}
