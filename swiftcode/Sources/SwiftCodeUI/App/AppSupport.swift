import AppKit
import SwiftCodeAssistant
import SwiftCodeCloud
import SwiftCodeIDECore
import SwiftCodeLanguage

@MainActor
public final class WorkspaceDocument: NSDocument {
    nonisolated(unsafe) public private(set) var model: WorkspaceModel?
    public static let typeName = "org.swiftcode.workspace"

    public override class var autosavesInPlace: Bool { false }

    nonisolated public override func read(from url: URL, ofType typeName: String) throws {
        model = try WorkspaceModel(url: url)
    }

    public override func makeWindowControllers() {
        guard let model else { return }
        RecentProjects.shared.note(model.url)
        let wc = WorkspaceWindowController(session: WorkspaceSession(model: model))
        addWindowController(wc)
        wc.window?.center()
        wc.applyDefaultLayout()
        DeviceHubLaunch.openIfAsked(wc)
    }

    public override func save(_ sender: Any?) {
        (windowControllers.first as? WorkspaceWindowController)?.saveDocument(sender)
    }
}

@MainActor
public final class SwiftCodeDocumentController: NSDocumentController {
    public override func typeForContents(of url: URL) throws -> String {
        Self.isWorkspaceContainer(url) ? WorkspaceDocument.typeName : SourceFileDocument.typeName
    }
    public override func documentClass(forType typeName: String) -> AnyClass? {
        typeName == SourceFileDocument.typeName ? SourceFileDocument.self : WorkspaceDocument.self
    }
    public override var defaultType: String? { WorkspaceDocument.typeName }

    public static func isWorkspaceContainer(_ url: URL) -> Bool {
        if ["xcodeproj", "xcworkspace"].contains(url.pathExtension) || url.lastPathComponent == "Package.swift" { return true }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    public static func workspaceWindow(containing file: URL, among windows: [WorkspaceWindowController]) -> WorkspaceWindowController? {
        windows.first { $0.session.model.root.containsForOpening(file) }
    }

    var workspaceWindows: [WorkspaceWindowController] {
        let byOrder = NSApp.orderedWindows.compactMap { $0.windowController as? WorkspaceWindowController }
        let all = documents.flatMap(\.windowControllers).compactMap { $0 as? WorkspaceWindowController }
        return byOrder + all.filter { wc in !byOrder.contains { $0 === wc } }
    }

    public override func openDocument(withContentsOf url: URL, display displayDocument: Bool,
                                      completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void) {
        if url.pathExtension == "xcresult", let wc = workspaceWindows.first {
            if displayDocument { wc.showWindow(nil) }
            wc.openResultBundle(url)
            completionHandler(wc.document as? NSDocument, true, nil)
            return
        }
        if !Self.isWorkspaceContainer(url), let wc = Self.workspaceWindow(containing: url, among: workspaceWindows) {
            if displayDocument { wc.showWindow(nil) }
            wc.handleOpenRequest(url)
            completionHandler(wc.document as? NSDocument, true, nil)
            return
        }
        if !Self.isWorkspaceContainer(url), !pendingOpens.isEmpty {
            deferredFileOpens.append((url, displayDocument, completionHandler))
            return
        }
        openOnce(url, display: displayDocument, completionHandler: completionHandler) { done in
            super.openDocument(withContentsOf: url, display: displayDocument, completionHandler: done)
        }
    }

    public override func reopenDocument(for urlOrNil: URL?, withContentsOf contentsURL: URL, display displayDocument: Bool,
                                        completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void) {
        openOnce(urlOrNil ?? contentsURL, display: displayDocument, completionHandler: completionHandler) { done in
            super.reopenDocument(for: urlOrNil, withContentsOf: contentsURL, display: displayDocument, completionHandler: done)
        }
    }

    private var deferredFileOpens: [(URL, Bool, (NSDocument?, Bool, (any Error)?) -> Void)] = []

    private func openDeferredFiles() {
        guard pendingOpens.isEmpty, !deferredFileOpens.isEmpty else { return }
        let files = deferredFileOpens
        deferredFileOpens = []
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                for (url, display, done) in files { self.openDocument(withContentsOf: url, display: display, completionHandler: done) }
            }
        }
    }

    private var pendingOpens: [String: [(NSDocument?, Bool, (any Error)?) -> Void]] = [:]

    private func openOnce(_ url: URL, display: Bool, completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void,
                          open: (@escaping (NSDocument?, Bool, (any Error)?) -> Void) -> Void) {
        let key = OpenRequestKey.path(url)
        if let existing = documents.first(where: { $0.fileURL.map(OpenRequestKey.path) == key }) {
            if display { existing.showWindows() }
            completionHandler(existing, true, nil)
            return
        }
        if pendingOpens[key] != nil {
            pendingOpens[key]?.append(completionHandler)
            return
        }
        pendingOpens[key] = [completionHandler]
        Self.launchGate.openRequested()
        open { [weak self] doc, wasOpen, error in
            MainActor.assumeIsolated {
                let waiting = self?.pendingOpens.removeValue(forKey: key) ?? []
                for (i, done) in waiting.enumerated() { done(doc, wasOpen || i > 0, error) }
                self?.openDeferredFiles()
                if Self.launchGate.openFinished(openDocuments: self?.documents.count ?? 0) { Self.showWelcome?() }
            }
        }
    }

    public static var launchGate = WelcomeLaunchGate()
    public static var showWelcome: (() -> Void)?

    public override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        item.action == #selector(openDocument(_:)) ? true : super.validateUserInterfaceItem(item)
    }

    public override func runModalOpenPanel(_ openPanel: NSOpenPanel, forTypes types: [String]?) -> Int {
        openPanel.canChooseDirectories = true
        openPanel.treatsFilePackagesAsDirectories = false
        openPanel.allowedContentTypes = []
        return super.runModalOpenPanel(openPanel, forTypes: nil)
    }

    public nonisolated override var maximumRecentDocumentCount: Int { 0 }

    public override func noteNewRecentDocumentURL(_ url: URL) {
        RecentProjects.shared.note(url)
        super.noteNewRecentDocumentURL(url)
    }

    public override func clearRecentDocuments(_ sender: Any?) {
        RecentProjects.shared.clear()
        super.clearRecentDocuments(sender)
    }
}

@MainActor
public final class CommandMenuItem: NSMenuItem {
    public var spec: MenuCommand?
}

@MainActor
public final class CommandMenu: NSMenu {
    public var path = ""
    public var editorKind: EditorKind = .source
}

@MainActor
public enum MainMenu {
    static let foreignMenus: Set<String> = ["SwiftCode ▸ Services", "File ▸ Open Recent", "Editor ▸ Refactor"]

    public static func make() -> NSMenu {
        UserDefaults.standard.register(defaults: ["NSFullScreenMenuItemEverywhere": false])
        let bar = NSMenu()
        for (title, items) in CommandTable.menus {
            let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            top.submenu = menu(title, items, path: title)
            bar.addItem(top)
            if title == "Window" { NSApp?.windowsMenu = top.submenu }
            if title == "Editor", let m = top.submenu { markCheckedDisabled(in: m, kind: .source) }
            if title == "Help" { NSApp?.helpMenu = top.submenu }
        }
        return bar
    }

    static func menu(_ title: String, _ items: [MenuItemSpec], path: String? = nil) -> NSMenu {
        let path = path ?? title
        let m = CommandMenu(title: title)
        m.path = path
        if !foreignMenus.contains(path) { m.delegate = MenuBarDelegate.shared }
        var base: MenuCommand?
        for item in items {
            switch item {
            case .separator: m.addItem(.separator())
            case .label(let t): m.addItem(.sectionHeader(title: t))
            case .submenu(let t, let sub):
                let i = NSMenuItem(title: t, action: nil, keyEquivalent: "")
                i.submenu = menu(t, sub, path: path + " ▸ " + t)
                if t == "Refactor" { i.submenu?.delegate = RefactorMenuDelegate.shared }
                if path == "SwiftCode", t == "Services" { NSApp?.servicesMenu = i.submenu }
                if t == "Open Recent" { i.submenu?.delegate = RecentProjectsMenuDelegate.shared }
                m.addItem(i)
            case .command(let original):
                let c = KeyBindings.effective(original)
                m.addItem(MainMenu.item(for: c, base: c.isAlternate ? base : nil))
                if !c.isAlternate { base = c }
            }
        }
        return m
    }

    static func item(for c: MenuCommand, base: MenuCommand?) -> CommandMenuItem {
        var key = c.key, mods = c.modifiers
        if let base, !key.isEmpty, key != base.key, Key.shiftedBase[key] == base.key {
            key = base.key
            mods.insert(.shift)
        }
        let i = CommandMenuItem(title: c.title, action: Selector(c.action), keyEquivalent: key)
        i.spec = c
        i.keyEquivalentModifierMask = modifierFlags(mods, key: key)
        i.tag = c.tag
        i.isAlternate = c.isAlternate
        if AppCommands.handles(c.action) { i.target = AppCommands.shared }
        if !MenuConditions.isShown(c.condition, in: nil) { i.isHidden = true }
        return i
    }

    static func markCheckedDisabled(in menu: NSMenu, kind: EditorKind) {
        let titles = EditorMenu.checkedDisabled[kind] ?? []
        guard !titles.isEmpty else { return }
        for i in menu.items {
            if let s = i.submenu { markCheckedDisabled(in: s, kind: kind) }
            if titles.contains(i.title), let c = (i as? CommandMenuItem)?.spec, !c.isAvailable { i.state = .on }
        }
    }

    static func restoreShortcut(_ i: CommandMenuItem) {
        guard let c = i.spec, !c.isAlternate, !c.key.isEmpty else { return }
        let mask = modifierFlags(c.modifiers, key: c.key)
        if i.keyEquivalent != c.key || i.keyEquivalentModifierMask != mask {
            i.keyEquivalent = c.key
            i.keyEquivalentModifierMask = mask
        }
    }

    static func modifierFlags(_ m: MenuCommand.Modifiers, key: String) -> NSEvent.ModifierFlags {
        var mask: NSEvent.ModifierFlags = []
        if m.contains(.command) { mask.insert(.command) }
        if m.contains(.shift) { mask.insert(.shift) }
        if m.contains(.option) { mask.insert(.option) }
        if m.contains(.control) { mask.insert(.control) }
        return mask
    }

    static func canonicalShortcut(_ i: NSMenuItem) -> String {
        guard !i.keyEquivalent.isEmpty else { return "" }
        let f = i.keyEquivalentModifierMask
        var m: MenuCommand.Modifiers = []
        if f.contains(.command) { m.insert(.command) }
        if f.contains(.shift) { m.insert(.shift) }
        if f.contains(.option) { m.insert(.option) }
        if f.contains(.control) { m.insert(.control) }
        return Shortcut.canonical(key: i.keyEquivalent, modifiers: m)
    }

    static let tableShortcuts: Set<String> = Set(CommandTable.allCommands.map(\.canonicalShortcut).filter { !$0.isEmpty })
    static let systemDuplicateActions: Set<String> = [
        "toggleFullScreen:", "toggleTabBar:", "toggleTabOverview:", "selectNextTab:", "selectPreviousTab:",
    ]

    static func removeSystemConflicts(in menu: NSMenu) {
        for i in menu.items.reversed() where !(i is CommandMenuItem) && !i.isSeparatorItem && !i.isSectionHeader && i.submenu == nil {
            let action = i.action.map(NSStringFromSelector) ?? ""
            if tableShortcuts.contains(canonicalShortcut(i)) || systemDuplicateActions.contains(action) { menu.removeItem(i) }
        }
    }

    static func removeSystemRecentMenus(in menu: NSMenu) {
        let clear = NSSelectorFromString("clearRecentDocuments:")
        for i in menu.items.reversed() where !(i is CommandMenuItem) {
            guard let sub = i.submenu, !(sub is CommandMenu) else { continue }
            if i.title == "Open Recent" || sub.items.contains(where: { $0.action == clear }) { menu.removeItem(i) }
        }
    }

    static func isSystemFeedbackItem(_ i: NSMenuItem) -> Bool {
        guard !(i is CommandMenuItem), !i.isSeparatorItem else { return false }
        let action = i.action.map(NSStringFromSelector) ?? ""
        return action.localizedCaseInsensitiveContains("feedback") || (i.title.hasPrefix("Send ") && i.title.hasSuffix(" Feedback to Apple"))
    }

    static func removeSystemFeedbackItem(in menu: NSMenu) {
        guard menu.items.contains(where: isSystemFeedbackItem) else { return }
        for i in menu.items.reversed() where isSystemFeedbackItem(i) { menu.removeItem(i) }
        while let first = menu.items.first, first.isSeparatorItem, !(first is CommandMenuItem) { menu.removeItem(first) }
    }

    static func collapseSeparators(in menu: NSMenu) {
        let items = menu.items
        let shown = MenuConditions.visibleSeparators(isSeparator: items.map(\.isSeparatorItem),
                                                     isVisible: items.map { !$0.isHidden && !$0.isAlternate })
        for (i, item) in items.enumerated() where item.isSeparatorItem { item.isHidden = !shown[i] }
    }
}

@MainActor
final class RefactorMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = RefactorMenuDelegate()
    static let dynamicTag = 9_917

    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items where item.tag == Self.dynamicTag { menu.removeItem(item) }
        guard let wc = NSApp.keyWindow?.windowController as? WorkspaceWindowController else { return }
        Self.fill(menu, with: wc.cachedCodeActions, target: wc)
        Task { await wc.codeActionsAtCaret() }
    }

    static func fill(_ menu: NSMenu, with actions: [CodeAction], target: AnyObject) {
        let refactors = RefactorCatalog.unmatched(actions).map { ($0, actions[$0]) }
        guard !refactors.isEmpty else { return }
        let sep = NSMenuItem.separator()
        sep.tag = dynamicTag
        menu.addItem(sep)
        for (i, a) in refactors {
            let item = NSMenuItem(title: a.title, action: #selector(WorkspaceWindowController.performCachedCodeAction(_:)), keyEquivalent: "")
            item.tag = dynamicTag
            item.representedObject = i
            item.target = target
            menu.addItem(item)
        }
    }
}

@MainActor
final class RecentProjectsMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = RecentProjectsMenuDelegate()
    static let clearTitle = "Clear Menu"

    func menuNeedsUpdate(_ menu: NSMenu) { Self.fill(menu, with: RecentProjects.shared.urls) }

    static func fill(_ menu: NSMenu, with urls: [URL]) {
        menu.removeAllItems()
        for (url, title) in zip(urls, RecentProjects.menuTitles(urls)) {
            let item = NSMenuItem(title: title, action: #selector(AppDelegate.openRecentProject(_:)), keyEquivalent: "")
            item.representedObject = url
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        if !urls.isEmpty { menu.addItem(.separator()) }
        menu.addItem(NSMenuItem(title: clearTitle, action: #selector(AppDelegate.clearRecentProjects(_:)), keyEquivalent: ""))
    }
}

public extension Notification.Name {
    static let appwriteRecoveryLinkReceived = Notification.Name("AppwriteRecoveryLinkReceived")
}

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    public private(set) var welcome: WelcomeWindowController?

    public override init() {
        _ = SwiftCodeDocumentController()
        super.init()
    }

    public func applicationWillFinishLaunching(_ n: Notification) {
        LayoutProbe.prepareIfRequested()
        MainThreadWatchdog.startIfRequested()
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") == nil { NSApp.applicationIconImage = ProductIcon.image }
        DeveloperTools.prefetch()
        NSApp.mainMenu = MainMenu.make()
        NotificationCenter.default.addObserver(forName: Preferences.didChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                NSApp.mainMenu = MainMenu.make()
                NSApp.appearance = Preferences.shared.nsAppearance
            }
        }
        NSApp.appearance = Preferences.shared.nsAppearance
    }

    public func applicationDidFinishLaunching(_ n: Notification) {
        if LayoutProbe.startIfRequested() { return }
        AlertSoundPlayer.installBuildSoundHook()
        Task { await SwiftCodeSDKInstaller.installIfNeeded() }
        PasswordResetWindowController.installIfNeeded()
        SwiftCodeDocumentController.showWelcome = { [weak self] in self?.showWelcomeWindow(nil) }
        if case .open(let all) = LaunchAction.decide(arguments: Array(CommandLine.arguments.dropFirst()), openDocumentCount: 0) {
            let (traces, paths) = GaugeSettings.tracePaths(all)
            for t in traces {
                do { try GaugeWindowController.show(traceAt: URL(fileURLWithPath: t)) } catch { NSApp.presentError(error) }
            }
            for a in paths {
                NSDocumentController.shared.openDocument(withContentsOf: URL(fileURLWithPath: a), display: true) { _, _, error in
                    if let error { NSApp.presentError(error) }
                }
            }
        }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if SwiftCodeDocumentController.launchGate.launchCheck(openDocuments: NSDocumentController.shared.documents.count) {
                    self.showWelcomeWindow(nil)
                }
                RuntimeSetupWindowController.offerAtFirstLaunch()
                SCSetupOnboardWindowController.offerIfNeeded()
            }
        }
    }

    @discardableResult
    @objc public func showWelcomeWindow(_ sender: Any?) -> WelcomeWindowController {
        let w = welcome ?? WelcomeWindowController()
        welcome = w
        w.present()
        return w
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWelcomeWindow(nil) }
        return true
    }

    public func application(_ sender: NSApplication, open urls: [URL]) {
        for url in urls { Self.handleOpenedURL(url) }
    }

    @discardableResult
    public static func handleOpenedURL(_ url: URL) -> Bool {
        if let callback = CloudAuthManager.shared.handleOAuthCallback(url) {
            switch callback {
            case .verification(let userId, let secret):
                Task { @MainActor in
                    try? await CloudAuthManager.shared.verifyEmail(userId: userId, secret: secret)
                }
            case .recovery(let userId, let secret):
                NotificationCenter.default.post(
                    name: .appwriteRecoveryLinkReceived, object: nil,
                    userInfo: ["userId": userId, "secret": secret])
            case .success, .failure:
                break
            }
            return true
        }
        if url.scheme == CloudAuthManager.shared.client.configuration.callbackScheme {
            return true
        }
        if GitHubOAuth.shared.handleOpenURL(url) {
            return true
        }
        return GoogleAccountAuthService.shared.handleOpenURL(url)
    }

    @objc public func openRecentProject(_ sender: Any?) {
        guard let url = (sender as? NSMenuItem)?.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }

    @objc public func clearRecentProjects(_ sender: Any?) {
        RecentProjects.shared.clear()
        NSDocumentController.shared.clearRecentDocuments(nil)
    }

    public func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(clearRecentProjects(_:)) { return !RecentProjects.shared.urls.isEmpty }
        return true
    }

    @objc public func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.showWindow(sender)
    }

    public func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
}
