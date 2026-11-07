import AppKit
import YcodeIDECore

extension WorkspaceWindowController {
    var stringCatalogConversionProject: String? { navigatorSelectionItems?.project ?? defaultNavigatorProject }

    public func legacyStringTables() -> [LegacyStringTable] {
        navigatorOperations(stringCatalogConversionProject)?.legacyStringTables() ?? []
    }

    @objc public func convertToStringCatalogs(_ sender: Any?) {
        let tables = legacyStringTables()
        let sheet = StringCatalogConversionController(tables: tables, projectDirectory: navigatorOperations(stringCatalogConversionProject)?.rootDirectory.path ?? "")
        sheet.onConvert = { [weak self] chosen in _ = self?.convertToStringCatalogs(tables: chosen) }
        pendingStringCatalogConversion = sheet
        guard let window, window.isVisible else { return }
        let panel = NSWindow(contentViewController: sheet)
        panel.title = "Convert to String Catalogs"
        sheet.onClose = { [weak window, weak panel] in if let panel { window?.endSheet(panel) } }
        window.beginSheet(panel)
    }

    @discardableResult
    public func convertToStringCatalogs(tables: [LegacyStringTable]) -> ProjectEdit? {
        pendingStringCatalogConversion = nil
        return performNavigatorEdit(stringCatalogConversionProject) { try $0.convertToStringCatalogs(tables) }
    }

    public internal(set) var pendingStringCatalogConversion: StringCatalogConversionController? {
        get { objc_getAssociatedObject(self, &StringCatalogConversionController.key) as? StringCatalogConversionController }
        set { objc_setAssociatedObject(self, &StringCatalogConversionController.key, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    func stringCatalogSourceFiles(forCatalogAt path: String) -> [String] {
        let paths = session.model.projects.keys.sorted()
        guard let project = paths.first(where: { path.hasPrefix(URL(fileURLWithPath: $0).deletingLastPathComponent().path + "/") }),
              let proj = session.model.projects[project] else { return [] }
        return proj.localizableSourceFiles(forResourceAt: path, projectDirectory: proj.projectDirectory(xcodeprojURL: URL(fileURLWithPath: project)))
    }

    func validateStringCatalogConversion(_ item: NSMenuItem) -> Bool? {
        guard item.action == #selector(convertToStringCatalogs(_:)) else { return nil }
        return session.model.kind != .package && !legacyStringTables().isEmpty
    }
}

@MainActor
public final class StringCatalogConversionController: NSViewController {
    nonisolated(unsafe) static var key: UInt8 = 0

    public let tables: [LegacyStringTable]
    let projectDirectory: String
    public var checked: Set<String>
    var onConvert: (([LegacyStringTable]) -> Void)?
    var onClose: (() -> Void)?
    public private(set) var checkboxes: [NSButton] = []
    public private(set) var convertButton: NSButton?

    init(tables: [LegacyStringTable], projectDirectory: String) {
        self.tables = tables
        self.projectDirectory = projectDirectory
        checked = Set(tables.map(\.id))
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public func title(_ t: LegacyStringTable) -> String {
        var folder = t.directory
        if folder.hasPrefix(projectDirectory + "/") { folder = String(folder.dropFirst(projectDirectory.count + 1)) } else if folder == projectDirectory { folder = "" }
        let place = folder.isEmpty ? "" : " in \(folder)"
        return "\(t.name)\(place) (\(t.languages.joined(separator: ", ")))" + (t.targetNames.isEmpty ? "" : " — \(t.targetNames.joined(separator: ", "))")
    }

    public override func loadView() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        let heading = NSTextField(labelWithString: tables.isEmpty ? "This project has no .strings or .stringsdict tables."
                                                                  : "Choose the string tables to convert to String Catalogs.")
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        stack.addArrangedSubview(heading)
        let note = NSTextField(wrappingLabelWithString: "Each table becomes one .xcstrings file in the same targets. The .strings and .stringsdict files move to the Trash.")
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 460
        stack.addArrangedSubview(note)
        checkboxes = tables.enumerated().map { i, t in
            let b = NSButton(checkboxWithTitle: title(t), target: self, action: #selector(toggled(_:)))
            b.tag = i
            b.state = checked.contains(t.id) ? .on : .off
            stack.addArrangedSubview(b)
            return b
        }
        let buttons = NSStackView()
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancel.keyEquivalent = "\u{1b}"
        let convert = NSButton(title: "Convert", target: self, action: #selector(convertClicked))
        convert.keyEquivalent = "\r"
        convertButton = convert
        buttons.addArrangedSubview(cancel)
        buttons.addArrangedSubview(convert)
        stack.addArrangedSubview(buttons)
        stack.setFrameSize(NSSize(width: 500, height: 160 + 24 * tables.count))
        view = stack
        updateButtons()
    }

    func updateButtons() { convertButton?.isEnabled = !checked.isEmpty }

    @objc func toggled(_ sender: NSButton) {
        let id = tables[sender.tag].id
        if sender.state == .on { checked.insert(id) } else { checked.remove(id) }
        updateButtons()
    }

    public func setChecked(_ on: Bool, table id: String) {
        if on { checked.insert(id) } else { checked.remove(id) }
        if let i = tables.firstIndex(where: { $0.id == id }), i < checkboxes.count { checkboxes[i].state = on ? .on : .off }
        updateButtons()
    }

    @objc func cancelClicked() { onClose?() }

    @objc public func convertClicked() {
        let chosen = tables.filter { checked.contains($0.id) }
        onClose?()
        guard !chosen.isEmpty else { return }
        onConvert?(chosen)
    }
}
