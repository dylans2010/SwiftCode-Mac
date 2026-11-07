import Foundation
import YcodePlist
import YcodeProject
import YcodeSubprocess
import YcodeWorkspace

public struct NewProjectFlowModel: Equatable, Sendable {
    public enum Step: Equatable, Sendable { case template, options }
    public enum Chooser: String, Equatable, Sendable { case project, package }

    public static let saveFolderKey = Keys.saveFolder
    public static let gitKey = Keys.git

    public static let templateHeading = ProjectTemplateCatalog.heading
    public static let optionsHeading = ProjectOptions.heading

    enum Keys {
        static func tab(_ c: Chooser) -> String { c == .project ? "SwiftCodeNewProjectTab" : "SwiftCodeNewPackageTab" }
        static func template(_ c: Chooser, _ tab: String) -> String { "\(c == .project ? "SwiftCodeNewProjectTemplate" : "SwiftCodeNewPackageTemplate").\(tab)" }
        static let options = "SwiftCodeNewProjectOptions"
        static let saveFolder = "SwiftCodeNewProjectLocation"
        static let pickerRow = "SwiftCodeNewProjectPickerRow"
        static let git = "SwiftCodeNewProjectCreateGitRepository"
        static let legacy = "SwiftCodeLastProjectTemplate"
    }

    public let chooser: Chooser
    public private(set) var step = Step.template
    public private(set) var platform: String
    public private(set) var filter = ""
    public private(set) var selected: ProjectTemplateDescriptor?
    public private(set) var form: TemplateOptionsForm
    private var perTab: [String: String] = [:]
    public private(set) var sharedValues: [String: String]
    public var team = "None"

    var catalog: TemplateChooserCatalog { chooser == .project ? ProjectTemplates.projects : ProjectTemplates.packages }

    public init(chooser: Chooser = .project, platform: String? = nil, template: String? = nil, organization: String = "",
                sharedValues: [String: String] = [:], perTab: [String: String] = [:]) {
        self.chooser = chooser
        let catalog = chooser == .project ? ProjectTemplates.projects : ProjectTemplates.packages
        var shared = sharedValues
        if !organization.isEmpty { shared[TemplateOptionID.organizationIdentifier] = organization }
        self.sharedValues = shared
        self.perTab = perTab
        let start = template.flatMap { catalog.find($0) }
        let tab = start?.platform ?? platform ?? catalog.tabs[0]
        self.platform = catalog.tabs.contains(tab) ? tab : catalog.tabs[0]
        let first = start ?? Self.remembered(catalog, self.platform, perTab) ?? catalog.templates(platform: self.platform).first
        selected = first
        form = (first ?? catalog.templates[0]).makeForm(shared)
        if let first { self.perTab[self.platform] = first.memoryKey }
    }

    static func remembered(_ catalog: TemplateChooserCatalog, _ tab: String, _ perTab: [String: String]) -> ProjectTemplateDescriptor? {
        guard let key = perTab[tab] else { return nil }
        return catalog.templates(platform: tab).first { $0.memoryKey == key }
    }

    public init(defaults: UserDefaults, chooser: Chooser = .project) {
        let catalog = chooser == .project ? ProjectTemplates.projects : ProjectTemplates.packages
        var perTab: [String: String] = [:]
        for t in catalog.tabs { if let v = defaults.string(forKey: Keys.template(chooser, t)) { perTab[t] = v } }
        var tab = defaults.string(forKey: Keys.tab(chooser))
        var template: String?
        if chooser == .project, tab == nil, let raw = defaults.string(forKey: Keys.legacy), let d = ProjectTemplates.find(raw) {
            tab = d.platform
            template = d.id
        }
        let shared = (defaults.dictionary(forKey: Keys.options) as? [String: String]) ?? [:]
        self.init(chooser: chooser, platform: tab, template: template, sharedValues: shared, perTab: perTab)
    }

    public func remember(in defaults: UserDefaults) {
        defaults.set(platform, forKey: Keys.tab(chooser))
        for (t, v) in perTab { defaults.set(v, forKey: Keys.template(chooser, t)) }
        defaults.set(sharedValues.merging(form.persistedValues) { $1 }, forKey: Keys.options)
        if chooser == .project, let selected { defaults.set(selected.id, forKey: Keys.legacy) }
    }

    public var tabs: [String] { catalog.tabs }
    public var sections: [TemplateSection] { catalog.sections(platform: platform, filter: filter) }
    public var visibleTemplates: [ProjectTemplateDescriptor] {
        sections.flatMap(\.entries).compactMap { e in catalog.templates.first { $0.id == e.templateID } }
    }

    public mutating func setPlatform(_ p: String) {
        guard catalog.tabs.contains(p), step == .template else { return }
        platform = p
        let keep = Self.remembered(catalog, p, perTab).flatMap { d in visibleTemplates.contains(d) ? d : nil }
        choose(keep ?? visibleTemplates.first)
    }

    public mutating func setFilter(_ f: String) {
        guard step == .template else { return }
        filter = f
        if let s = selected, visibleTemplates.contains(s) { return }
        choose(visibleTemplates.first)
    }

    @discardableResult
    public mutating func select(_ key: String) -> Bool {
        guard step == .template, let d = catalog.find(key, platform: platform) ?? catalog.find(key) else { return false }
        if d.platform != platform {
            platform = d.platform
            filter = ""
        } else if !visibleTemplates.contains(d) {
            return false
        }
        choose(d)
        return true
    }

    private mutating func choose(_ d: ProjectTemplateDescriptor?) {
        sharedValues.merge(form.persistedValues) { $1 }
        if form.productName.isEmpty == false { sharedValues[TemplateOptionID.productName] = form.value(TemplateOptionID.productName) }
        selected = d
        guard let d else { return }
        perTab[d.platform] = d.memoryKey
        form = d.makeForm(sharedValues)
    }

    public mutating func setOption(_ id: String, _ value: String) {
        if id == TemplateOptionID.team { team = value; return }
        form.set(id, value)
    }

    public var isPreviousEnabled: Bool { step == .options }

    public var isNextEnabled: Bool {
        switch step {
        case .template: selected?.isAvailable == true
        case .options: form.isNextEnabled
        }
    }

    public var templateCaption: String {
        guard let s = selected else { return "No templates match “\(filter)”." }
        return s.unavailableReason ?? s.summary
    }

    @discardableResult
    public mutating func next() -> Bool {
        guard isNextEnabled else { return false }
        switch step {
        case .template:
            step = .options
            return false
        case .options:
            return true
        }
    }

    public mutating func previous() {
        guard step == .options else { return }
        sharedValues.merge(form.persistedValues) { $1 }
        step = .template
    }

    public mutating func jump(to key: String) {
        step = .template
        filter = ""
        if select(key) { _ = next() }
    }

    public var defaultSaveName: String {
        let n = form.productName
        return n.isEmpty ? (selected?.defaultSaveName ?? "") : n
    }
}

extension NewProjectPicker {
    public static let rowValues = ["app", "commandLineTool", "package", "playground", "template"]

    public static func templateID(forRow i: Int) -> String? {
        switch i {
        case 1: "macos.command-line-tool"
        case 3: "ios.app-playground"
        default: nil
        }
    }

    public static func remember(row i: Int, in defaults: UserDefaults) {
        if rowValues.indices.contains(i) { defaults.set(rowValues[i], forKey: NewProjectFlowModel.Keys.pickerRow) }
    }

    public static func lastRow(_ defaults: UserDefaults) -> Int? {
        defaults.string(forKey: NewProjectFlowModel.Keys.pickerRow).flatMap { rowValues.firstIndex(of: $0) }
    }
}

public struct NewProjectSaveOptions: Equatable, Sendable {
    public var location: URL
    public var saveAs: String?
    public var createGitRepository = true
    public var addTo: URL?
    public var group: String?
    public var newWorkspaceForProject = true
    public var team: String?

    public init(location: URL, saveAs: String? = nil, createGitRepository: Bool = true, addTo: URL? = nil, group: String? = nil) {
        self.location = location
        self.saveAs = saveAs
        self.createGitRepository = createGitRepository
        self.addTo = addTo
        self.group = group
    }
}

public struct NewProjectGroupChoice: Equatable, Sendable {
    public var title: String
    public var depth: Int
    public var key: String?
}

public enum NewProjectCreator {
    public struct Created: Equatable, Sendable {
        public var openURL: URL
        public var folder: URL
        public var entryFile: URL?
        public var gitWarning: String?
        public var addedTo: URL?
    }

    public static func groups(in container: URL) -> [NewProjectGroupChoice] {
        if container.pathExtension == "xcworkspace" {
            guard let ws = try? Workspace(contentsOf: container.path) else { return [] }
            var out = [NewProjectGroupChoice(title: container.deletingPathExtension().lastPathComponent, depth: 0, key: nil)]
            func walk(_ nodes: [YcodeWorkspace.XMLNode], _ depth: Int, _ prefix: String) {
                for n in nodes where n.name == "Group" {
                    let loc = n["location"] ?? ""
                    let key = prefix.isEmpty ? loc : prefix + "|" + loc
                    out.append(NewProjectGroupChoice(title: n["name"] ?? Workspace.Location(loc).displayPath, depth: depth, key: key))
                    walk(n.children, depth + 1, key)
                }
            }
            walk(ws.document.children, 1, "")
            return out
        }
        guard let proj = try? PBXProj(contentsOf: container.appendingPathComponent("project.pbxproj")),
              let main = proj.project?.string("mainGroup") else { return [] }
        var out: [NewProjectGroupChoice] = []
        let products = proj.project?.string("productRefGroup")
        func walk(_ id: String, _ depth: Int) {
            guard let g = proj[id], g.isa == "PBXGroup" else { return }
            let title = depth == 0 ? container.deletingPathExtension().lastPathComponent
                : g.string("name") ?? g.string("path").map { ($0 as NSString).lastPathComponent } ?? "Group"
            out.append(NewProjectGroupChoice(title: title, depth: depth, key: depth == 0 ? nil : id))
            for c in g.references("children") where c != products { walk(c, depth + 1) }
        }
        walk(main, 0)
        return out
    }

    public static func generate(_ d: ProjectTemplateDescriptor, _ form: TemplateOptionsForm, saveAs: String?, team: String? = nil) throws -> GeneratedProject {
        var g = try ProjectGenerator.generate(d, form, team: team)
        if let s = saveAs?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
            g.folderName = g.folderName.hasSuffix(".swiftpm") && !s.hasSuffix(".swiftpm") ? s + ".swiftpm" : s
        }
        return g
    }

    public static func create(_ d: ProjectTemplateDescriptor, _ form: TemplateOptionsForm, save: NewProjectSaveOptions,
                              gitEnvironment: [String: String]? = nil) throws -> Created {
        let g = try generate(d, form, saveAs: save.saveAs, team: save.team)
        let open = try g.write(in: save.location)
        let folder = save.location.appendingPathComponent(g.folderName, isDirectory: true)
        var created = Created(openURL: open, folder: folder, entryFile: g.entryFile.map { folder.appendingPathComponent($0) })
        if save.createGitRepository { created.gitWarning = initializeRepository(folder, environment: gitEnvironment) }
        if let target = save.addTo {
            created.addedTo = try add(open, to: target, group: save.group, newWorkspace: save.newWorkspaceForProject)
        }
        return created
    }

    static func initializeRepository(_ folder: URL, environment: [String: String]?) -> String? {
        let git = [HostTool.path("git"), "/usr/local/bin/git", "/opt/homebrew/bin/git"].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let git else { return "Git was not found; no repository was created." }
        let env = environment.map { ProcessInfo.processInfo.environment.merging($0) { $1 } }
        if let inside = try? Subprocess.run(git, ["rev-parse", "--is-inside-work-tree"], environment: env, currentDirectory: folder),
           inside.status == 0, inside.stdoutText.hasPrefix("true") {
            return nil
        }
        for args in [["init", "--quiet"], ["add", "--all"], ["commit", "--quiet", "--message", "Initial Commit"]] {
            guard let out = try? Subprocess.run(git, args, environment: env, currentDirectory: folder) else {
                return "git \(args[0]) could not run."
            }
            if out.status != 0 {
                let why = out.stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
                return "git \(args[0]) failed\(why.isEmpty ? "" : ": \(why)")."
            }
        }
        return nil
    }

    @discardableResult
    public static func add(_ item: URL, to container: URL, group: String?, newWorkspace: Bool = false) throws -> URL {
        if container.pathExtension == "xcodeproj", newWorkspace {
            let ws = container.deletingPathExtension().appendingPathExtension("xcworkspace")
            let base = ws.deletingLastPathComponent().standardizedFileURL.path
            let refs = [container, item].map { "   <FileRef\n      location = \"group:\(relativePath($0.standardizedFileURL.path, from: base))\">\n   </FileRef>\n" }
            let text = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Workspace\n   version = \"1.0\">\n" + refs.joined() + "</Workspace>\n"
            guard !FileManager.default.fileExists(atPath: ws.path) else { return try add(item, to: ws, group: nil) }
            try FileManager.default.createDirectory(at: ws, withIntermediateDirectories: true)
            try text.write(to: ws.appendingPathComponent("contents.xcworkspacedata"), atomically: true, encoding: .utf8)
            return ws
        }
        if container.pathExtension == "xcworkspace" {
            let dataURL = container.appendingPathComponent("contents.xcworkspacedata")
            var ws = try Workspace(contentsOf: container.path)
            let base = container.deletingLastPathComponent()
            var groupDir = base.standardizedFileURL.path
            var path: [Int] = []
            if let group {
                var nodes = ws.document.children
                for loc in group.split(separator: "|").map(String.init) {
                    guard let i = nodes.firstIndex(where: { $0.name == "Group" && $0["location"] == loc }) else { break }
                    path.append(i)
                    if case .group(let p) = Workspace.Location(loc) {
                        groupDir = p.hasPrefix("/") ? p : URL(fileURLWithPath: groupDir).appendingPathComponent(p).standardizedFileURL.path
                    }
                    nodes = nodes[i].children
                }
            }
            let ref = YcodeWorkspace.XMLNode("FileRef", attributes: [("location", "group:" + relativePath(item.standardizedFileURL.path, from: groupDir))])
            func insert(_ node: inout YcodeWorkspace.XMLNode, _ rest: ArraySlice<Int>) {
                guard let i = rest.first else { node.children.append(ref); return }
                insert(&node.children[i], rest.dropFirst())
            }
            insert(&ws.document, path[...])
            try ws.serialized().write(to: dataURL, atomically: true, encoding: .utf8)
            return container
        }
        let pbx = container.appendingPathComponent("project.pbxproj")
        var proj = try PBXProj(contentsOf: pbx)
        let projectDir = proj.projectDirectory(xcodeprojURL: container)
        let parents = proj.parentMap()
        let groupID = group.flatMap { proj[$0] != nil ? $0 : nil } ?? proj.project?.string("mainGroup") ?? ""
        let groupDir = proj.resolvedPath(of: groupID, projectDirectory: projectDir, parents: parents) ?? projectDir.path
        let id = proj.makeObjectID()
        let isProject = item.pathExtension == "xcodeproj"
        var attrs: [(String, PlistValue)] = [("isa", "PBXFileReference")]
        attrs.append(("lastKnownFileType", isProject ? "wrapper.pb-project" : "wrapper"))
        attrs += [("name", .string(item.lastPathComponent)), ("path", .string(relativePath(item.standardizedFileURL.path, from: groupDir))),
                  ("sourceTree", "<group>")]
        proj[id] = PBXObject(id: id, attributes: PlistDictionary(attrs))
        if var g = proj[groupID] {
            g["children"] = .array((g.references("children") + [id]).map(PlistValue.string))
            proj[groupID] = g
        }
        let name = container.deletingPathExtension().lastPathComponent
        try proj.serialized(projectName: name).write(to: pbx, atomically: true, encoding: .utf8)
        return container
    }

    static func relativePath(_ path: String, from base: String) -> String {
        let a = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        let b = URL(fileURLWithPath: base).standardizedFileURL.pathComponents
        var i = 0
        while i < a.count, i < b.count, a[i] == b[i] { i += 1 }
        return (Array(repeating: "..", count: b.count - i) + a[i...]).joined(separator: "/")
    }
}

extension Workspace.Location {
    var displayPath: String {
        switch self {
        case .group(let p), .container(let p), .absolute(let p), .developer(let p), .selfReference(let p): (p as NSString).lastPathComponent
        case .unknown(let s): s
        }
    }
}
