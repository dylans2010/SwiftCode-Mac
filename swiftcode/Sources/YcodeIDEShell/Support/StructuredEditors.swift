import Foundation
import YcodeIDECore
import YcodeAssistant

@MainActor
public enum StructuredEditor {
    case propertyList(PlistEditorModel)
    case assetCatalog(AssetCatalogEditorModel)
    case stringCatalog(StringCatalogEditorModel)
    case interfaceBuilder(InterfaceBuilderShellModel)
    case xcodeProject(XcodeProjModel)

    public var path: String {
        switch self {
        case .propertyList(let m): m.path
        case .assetCatalog(let m): m.path
        case .stringCatalog(let m): m.path
        case .interfaceBuilder(let m): m.path
        case .xcodeProject(let m): m.projectURL.path
        }
    }

    public var editorKind: EditorKind {
        switch self {
        case .propertyList: .propertyList
        case .assetCatalog: .assetCatalog
        case .stringCatalog: .other
        case .interfaceBuilder: .interfaceBuilder
        case .xcodeProject: .other
        }
    }

    public var title: String {
        switch self {
        case .propertyList: "Property List"
        case .assetCatalog: "Asset Catalog"
        case .stringCatalog: "String Catalog"
        case .interfaceBuilder: "Interface Builder"
        case .xcodeProject: "Xcode Project"
        }
    }

    public static func handles(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ["plist", "entitlements", "xcassets", "xcstrings", "storyboard", "xib", "xcodeproj"].contains(ext)
    }

    public static func hasSourceView(_ path: String) -> Bool {
        handles(path) && !["xcassets", "xcodeproj"].contains((path as NSString).pathExtension.lowercased())
    }

    public static func open(_ path: String) -> StructuredEditor? {
        switch (path as NSString).pathExtension.lowercased() {
        case "xcassets":
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
            return .assetCatalog(AssetCatalogEditorModel(path: path))
        case "xcstrings": return (try? StringCatalogEditorModel(path: path)).map(StructuredEditor.stringCatalog)
        case "plist", "entitlements": return (try? PlistEditorModel(path: path)).map(StructuredEditor.propertyList)
        case "storyboard", "xib": return (try? InterfaceBuilderShellModel(path: path)).map(StructuredEditor.interfaceBuilder)
        case "xcodeproj":
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
            return (try? XcodeProjParse.shared.parse(projectURL: URL(fileURLWithPath: path))).map(StructuredEditor.xcodeProject)
        default: return nil
        }
    }
}

extension WorkspaceShellModel {
    func showStructured(_ path: String) -> Bool {
        guard !sourceViewPaths.contains(path), let s = StructuredEditor.open(path) else {
            structuredEditor = nil
            return false
        }
        if case .stringCatalog(let m) = s {
            m.onAddLanguage = { [weak self] code in self?.addKnownRegion(code, forFileAt: path) }
            m.sourceFiles = { [weak self] in self?.stringCatalogSourceFiles(forCatalogAt: path) ?? [] }
        }
        structuredEditor = s
        editor = nil
        document = SourceDocument(path: path, language: SyntaxLanguage(fileName: (path as NSString).lastPathComponent), lines: [])
        findBar.documentChanged(to: nil)
        syncEditorIssues()
        return true
    }

    public var editorKind: EditorKind { structuredEditor?.editorKind ?? .source }

    public var isShowingSourceView: Bool { document.map { sourceViewPaths.contains($0.path) } ?? false }

    public func setShowsSourceView(_ on: Bool) {
        guard let path = document?.path, StructuredEditor.hasSourceView(path), on != sourceViewPaths.contains(path) else { return }
        if on {
            sourceViewPaths.insert(path)
            if let d = openDocuments[path], !d.isDirty { openDocuments[path] = nil }
        } else {
            if editor?.path == path, editor?.isDirty == true {
                guard saveCurrent() else { return }
            }
            openDocuments[path] = nil
            sourceViewPaths.remove(path)
        }
        structuredEditor = nil
        document = nil
        showFile(path)
    }

    @discardableResult
    public func performEditorAction(_ action: String, tag: Int = 0) -> Bool {
        switch (structuredEditor, action) {
        case (.propertyList(let m), "addPlistItem:"): m.addItem()
        case (.propertyList(let m), "setPlistValueType:"):
            guard PlistTree.types.indices.contains(tag) else { return false }
            return m.setTypeOfSelection(PlistTree.types[tag])
        case (.propertyList(let m), "toggleRawKeysAndValues:"): m.showsRawKeys.toggle()
        case (.assetCatalog(let m), "addNewAsset:"): return m.add(tag: tag)
        case (.assetCatalog(let m), "deleteSelectedAssets:"): return m.removeSelected()
        case (.interfaceBuilder(let m), _): return m.perform(action, tag: tag)
        default: return false
        }
        return true
    }

    public func editorActionState(_ action: String, tag: Int = 0) -> (enabled: Bool, checked: Bool)? {
        switch (structuredEditor, action) {
        case (.propertyList, "addPlistItem:"): return (true, false)
        case (.propertyList(let m), "setPlistValueType:"):
            let type = PlistTree.types.indices.contains(tag) ? PlistTree.types[tag] : ""
            return (m.selection != nil, m.selectedTypeName == type)
        case (.propertyList(let m), "toggleRawKeysAndValues:"): return (true, m.showsRawKeys)
        case (.assetCatalog(let m), "addNewAsset:"): return (m.canAdd(tag: tag) && tag != AssetCatalog.AddMenuTags.importFiles
                                                               && tag != AssetCatalog.AddMenuTags.stickerFrame, false)
        case (.assetCatalog(let m), "deleteSelectedAssets:"): return (m.selectedRow != nil, false)
        case (.interfaceBuilder(let m), _): return m.actionState(action, tag: tag)
        default: return nil
        }
    }

    func addKnownRegion(_ code: String, forFileAt file: String) {
        let paths = session.model.projects.keys.sorted()
        guard let path = paths.first(where: { file.hasPrefix(URL(fileURLWithPath: $0).deletingLastPathComponent().path + "/") }) ?? paths.first,
              var proj = session.model.projects[path] else { return }
        let before = proj.objects
        proj.addKnownRegion(code)
        guard proj.objects != before else { return }
        session.model.projects[path] = proj
        try? session.model.saveProjects()
    }

    func stringCatalogSourceFiles(forCatalogAt path: String) -> [String] {
        let paths = session.model.projects.keys.sorted()
        guard let project = paths.first(where: { path.hasPrefix(URL(fileURLWithPath: $0).deletingLastPathComponent().path + "/") }),
              let proj = session.model.projects[project] else { return [] }
        return proj.localizableSourceFiles(forResourceAt: path, projectDirectory: proj.projectDirectory(xcodeprojURL: URL(fileURLWithPath: project)))
    }
}
