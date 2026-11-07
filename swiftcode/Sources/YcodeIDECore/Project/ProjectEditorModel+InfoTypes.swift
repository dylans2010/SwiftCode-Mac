import Foundation
import YcodePlist
import YcodeProject

extension ProjectEditorModel {
    public static let infoTypeKeys: [(title: String, key: String)] = [
        ("Document Types", "CFBundleDocumentTypes"), ("Exported Type Identifiers", "UTExportedTypeDeclarations"),
        ("Imported Type Identifiers", "UTImportedTypeDeclarations"), ("URL Types", "CFBundleURLTypes"),
    ]

    static let infoTypeNameKeys = [
        "CFBundleDocumentTypes": "CFBundleTypeName", "UTExportedTypeDeclarations": "UTTypeIdentifier",
        "UTImportedTypeDeclarations": "UTTypeIdentifier", "CFBundleURLTypes": "CFBundleURLName",
    ]

    static func newInfoTypeEntry(_ key: String) -> PropertyListItem {
        switch key {
        case "CFBundleDocumentTypes":
            .dictionary([.init(key: "CFBundleTypeName", value: .string("Untitled")), .init(key: "CFBundleTypeRole", value: .string("Editor")),
                         .init(key: "LSItemContentTypes", value: .array([]))])
        case "CFBundleURLTypes":
            .dictionary([.init(key: "CFBundleURLName", value: .string("")), .init(key: "CFBundleTypeRole", value: .string("Editor")),
                         .init(key: "CFBundleURLSchemes", value: .array([]))])
        default:
            .dictionary([.init(key: "UTTypeIdentifier", value: .string("")), .init(key: "UTTypeDescription", value: .string("")),
                         .init(key: "UTTypeConformsTo", value: .array([]))])
        }
    }

    func infoPlistURL(target: String, configuration: String) -> URL? {
        guard let file = resolve(target: target, configuration: configuration)?.settings["INFOPLIST_FILE"], !file.isEmpty else { return nil }
        return file.hasPrefix("/") ? URL(fileURLWithPath: file) : proj.projectDirectory(xcodeprojURL: xcodeprojURL).appendingPathComponent(file)
    }

    public func infoTypeEntries(_ key: String, target: String, configuration: String) -> [PropertyListItem] {
        if case .array(let a)? = infoDictionary(target: target, configuration: configuration).first(where: { $0.key == key })?.value { return a }
        return []
    }

    public static func infoTypeEntryName(_ entry: PropertyListItem, key: String) -> String {
        if case .dictionary(let d) = entry, let n = infoTypeNameKeys[key],
           case .string(let s)? = d.first(where: { $0.key == n })?.value, !s.isEmpty { return s }
        return "Untitled"
    }

    public enum InfoTypeError: Error { case noInfoPlistFile }

    public func generatesInfoPlist(target: String, configuration: String) -> Bool {
        resolve(target: target, configuration: configuration)?.settings["GENERATE_INFOPLIST_FILE"].uppercased() == "YES"
    }

    mutating func createInfoPlistFile(target: String) throws -> URL {
        let rel = "\(target)/Info.plist"
        let url = proj.projectDirectory(xcodeprojURL: xcodeprojURL).appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try PropertyListDocument(root: .dictionary([])).xml().write(to: url, atomically: true, encoding: .utf8)
            proj.addFileReference(path: rel, to: proj.project?.string("mainGroup") ?? "")
        }
        setSetting("INFOPLIST_FILE", rel, target: target)
        return url
    }

    public mutating func setInfoTypeEntries(_ key: String, _ entries: [PropertyListItem], target: String, configuration: String) throws {
        let url: URL
        if let u = infoPlistURL(target: target, configuration: configuration) {
            url = u
        } else if generatesInfoPlist(target: target, configuration: configuration) {
            if entries.isEmpty { return }
            url = try createInfoPlistFile(target: target)
        } else {
            throw InfoTypeError.noInfoPlistFile
        }
        var doc = (try? PropertyListDocument(data: Data(contentsOf: url))) ?? PropertyListDocument(root: .dictionary([]))
        guard case .dictionary(var d) = doc.root else { return }
        if let i = d.firstIndex(where: { $0.key == key }) {
            if entries.isEmpty { d.remove(at: i) } else { d[i].value = .array(entries) }
        } else if !entries.isEmpty {
            d.append(.init(key: key, value: .array(entries)))
        }
        doc.root = .dictionary(d)
        try doc.data().write(to: url, options: .atomic)
    }

    public mutating func addInfoTypeEntry(_ key: String, target: String, configuration: String) throws {
        try setInfoTypeEntries(key, infoTypeEntries(key, target: target, configuration: configuration) + [Self.newInfoTypeEntry(key)],
                               target: target, configuration: configuration)
    }

    public mutating func removeInfoTypeEntry(_ key: String, at index: Int, target: String, configuration: String) throws {
        var e = infoTypeEntries(key, target: target, configuration: configuration)
        guard e.indices.contains(index) else { return }
        e.remove(at: index)
        try setInfoTypeEntries(key, e, target: target, configuration: configuration)
    }
}
