import AppKit
import YcodeIDECore
import YcodeSubprocess

@MainActor
public final class MenuBarDelegate: NSObject, NSMenuDelegate {
    public static let shared = MenuBarDelegate()
    static let dynamicTag = 9_918

    static var controller: WorkspaceWindowController? {
        (NSApp?.mainWindow?.windowController ?? NSApp?.keyWindow?.windowController) as? WorkspaceWindowController
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        update(menu, controller: Self.controller)
    }

    public func menuWillOpen(_ menu: NSMenu) {
        removeSystemAdditions(menu)
        if menu.supermenu === NSApp?.mainMenu {
            MainMenu.removeSystemConflicts(in: menu)
            MainMenu.collapseSeparators(in: menu)
        }
    }

    public func update(_ menu: NSMenu, controller wc: WorkspaceWindowController?) {
        let ctx = wc?.menuContext
        removeSystemAdditions(menu)
        if let m = menu as? CommandMenu { DynamicMenus.fill(m, controller: wc) }
        for item in menu.items {
            guard let c = item as? CommandMenuItem, let spec = c.spec else { continue }
            c.title = MenuTitles.title(for: spec, in: ctx)
            c.isHidden = !MenuConditions.isShown(spec.condition, in: ctx)
            MainMenu.restoreShortcut(c)
        }
        if menu.supermenu === NSApp?.mainMenu, NSApp?.mainMenu != nil { MainMenu.removeSystemConflicts(in: menu) }
        MainMenu.collapseSeparators(in: menu)
    }
}

extension MenuBarDelegate {
    func removeSystemAdditions(_ menu: NSMenu) {
        switch (menu as? CommandMenu)?.path {
        case "File": MainMenu.removeSystemRecentMenus(in: menu)
        case "Help": MainMenu.removeSystemFeedbackItem(in: menu)
        default: break
        }
    }
}

@MainActor
enum DynamicMenus {
    static func fill(_ m: CommandMenu, controller wc: WorkspaceWindowController?) {
        switch m.path {
        case "SwiftCode ▸ Open Developer Tool": fillDeveloperTools(m, tools: DeveloperTools.installed)
        case "View ▸ Inspectors": fillInspectors(m, names: wc?.inspector.tabNames ?? CommandTable.inspectors)
        case "Product ▸ Scheme": fillSchemes(m, names: wc?.session.model.schemeNames ?? [], active: wc?.session.scheme, target: wc)
        case "Product ▸ Destination":
            guard let wc else { removeDynamic(m); break }
            fillDestinations(m, model: wc.destinationMenuModel(), current: wc.session.destination, target: wc)
        case "Product ▸ Test Plan":
            guard let wc else { removeDynamic(m); break }
            fillTestPlans(m, rows: wc.session.testPlanRows, plans: wc.session.testPlanNames, active: wc.session.effectiveTestPlan, target: wc)
        case "Editor": fillEditor(m, kind: wc?.menuContext.editorKind ?? .source)
        case "Debug ▸ Simulate Location": fillSimulateLocation(m, controller: wc)
        case "Debug ▸ Attach to Process": RunningProcesses.fill(m, target: wc, entries: RunningProcesses.recent())
        default: break
        }
    }

    static func fillEditor(_ m: CommandMenu, kind: EditorKind) {
        guard m.editorKind != kind else { return }
        let fresh = MainMenu.menu("Editor", EditorMenu.items(for: kind), path: "Editor")
        m.removeAllItems()
        for i in fresh.items {
            fresh.removeItem(i)
            m.addItem(i)
        }
        m.editorKind = kind
        MainMenu.markCheckedDisabled(in: m, kind: kind)
    }

    static func removeDynamic(_ m: NSMenu) {
        for i in m.items.reversed() where i.tag == MenuBarDelegate.dynamicTag { m.removeItem(i) }
    }

    static func fillDeveloperTools(_ m: NSMenu, tools: [DeveloperTools.Tool]) {
        removeDynamic(m)
        for (n, t) in tools.enumerated() {
            let i = NSMenuItem(title: t.name, action: #selector(AppCommands.openDeveloperTool(_:)), keyEquivalent: "")
            i.target = AppCommands.shared
            i.representedObject = t.url
            i.tag = MenuBarDelegate.dynamicTag
            m.insertItem(i, at: n)
        }
    }

    static func fillInspectors(_ m: NSMenu, names: [String]) {
        let end = m.items.firstIndex(where: \.isSeparatorItem) ?? 0
        guard m.items[..<end].map(\.title) != names else { return }
        for _ in 0..<end { m.removeItem(at: 0) }
        for (i, n) in names.enumerated() {
            let key = i < 9 ? "⌥⌘\(i + 1)" : ""
            let c = MenuCommand(n, shortcut: key, "showInspector:", tag: i)
            m.insertItem(MainMenu.item(for: KeyBindings.effective(c), base: nil), at: i)
        }
    }

    static func fillSchemes(_ m: NSMenu, names: [String], active: String?, target: AnyObject?) {
        removeDynamic(m)
        guard !names.isEmpty else { return }
        let sep = NSMenuItem.separator()
        sep.tag = MenuBarDelegate.dynamicTag
        m.addItem(sep)
        for (n, name) in names.enumerated() {
            let i = NSMenuItem(title: name, action: #selector(WorkspaceWindowController.selectSchemeRow(_:)), keyEquivalent: "")
            i.target = target
            i.representedObject = n
            i.tag = MenuBarDelegate.dynamicTag
            i.state = name == active ? .on : .off
            m.addItem(i)
        }
    }
}
