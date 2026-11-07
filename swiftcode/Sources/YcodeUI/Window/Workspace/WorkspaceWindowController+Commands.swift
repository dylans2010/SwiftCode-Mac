import AppKit
import YcodeBuild
import YcodeIDECore

extension WorkspaceWindowController {
    func navigatorAddMenu(_ index: Int) -> [NSMenuItem] {
        func item(_ t: String, _ a: Selector?) -> NSMenuItem {
            let i = NSMenuItem(title: t, action: a, keyEquivalent: "")
            i.target = a == nil ? nil : self
            return i
        }
        switch index {
        case 0: return [item("New File…", #selector(newFile(_:))), item("New Folder", #selector(newFolder(_:))), item("Add Files…", #selector(addFiles(_:)))]
        case 1: return [item("Commit…", #selector(showCommitSheet(_:))), item("Refresh File Status", #selector(refreshFileStatus(_:)))]
        case 2: return [item("Bookmark File", #selector(bookmarkFile(_:))), item("Bookmark Line", #selector(bookmarkLine(_:)))]
        case 5: return [item("New Unit Test Target…", nil), item("New UI Test Target…", nil), item("New Unit Test Class…", #selector(newFile(_:)))]
        case 8: return [item("Show Build Folder in Finder", #selector(showBuildFolderInFinder(_:)))]
        default: return []
        }
    }

    @discardableResult
    public func renameFromInspector(_ url: URL, to name: String) -> URL? {
        guard session.model.kind == .package, !name.contains("/") else { NSSound.beep(); inspector.refresh(); return nil }
        let dest = url.deletingLastPathComponent().appendingPathComponent(name)
        do { try FileManager.default.moveItem(at: url, to: dest) } catch { NSSound.beep(); inspector.refresh(); return nil }
        session.model.root = NavigatorTree.package(at: session.model.url)
        navigator.setProjectTree(session.model.root, packages: packageSection())
        open(path: dest.path, line: nil)
        return dest
    }

    @objc public func showInFinder(_ sender: Any?) {
        guard window?.isVisible == true, let url = editor.fileURL ?? Optional(session.model.url) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc public func hideFindBar(_ sender: Any?) { editor.hideFindBar() }

    @objc public func chooseTheme(_ sender: Any?) { SettingsWindowController.shared.show(pane: "Appearance") }
    @objc public func showBehaviorsSettings(_ sender: Any?) { SettingsWindowController.shared.show(pane: "Behaviors") }

    @objc public func showCodingAssistant(_ sender: Any?) { setLeftPane(codingAssistant: true) }

    @objc public func showDatabaseExplorer(_ sender: Any?) { SQLiteExplorerWindowManager.shared.showWindow() }

    @objc public func filterInNavigator(_ sender: Any?) {
        navigatorItem.isCollapsed = false
        window?.makeFirstResponder(navigator.filter)
    }

    @objc public func clearAllIssues(_ sender: Any?) { session.clearIssues() }

    func buildFolder() async -> URL? {
        let request = session.model.buildRequest(scheme: session.scheme, destination: session.destination, action: .build)
        let engine = session.engine
        guard let exe = await Task.detached(operation: { engine.executablePath(for: request) }).value,
              let r = exe.range(of: "/Products/") else { return nil }
        return URL(fileURLWithPath: String(exe[..<r.lowerBound]))
    }

    @objc public func showBuildFolderInFinder(_ sender: Any?) {
        Task {
            guard window?.isVisible == true, let f = await buildFolder() else { return }
            NSWorkspace.shared.activateFileViewerSelecting([f])
        }
    }

    @objc public func copyBuildFolderPath(_ sender: Any?) {
        Task {
            guard let f = await buildFolder() else { NSSound.beep(); return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(f.path, forType: .string)
        }
    }

    @objc public func stepOverInstruction(_ sender: Any?) {
        Task { if let c = session.debugClient, let t = session.stoppedThread { try? await c.stepInstruction(threadID: t, into: false) } }
    }

    @objc public func stepIntoInstruction(_ sender: Any?) {
        Task { if let c = session.debugClient, let t = session.stoppedThread { try? await c.stepInstruction(threadID: t, into: true) } }
    }

    @objc public func clearConsole(_ sender: Any?) { session.clearConsole() }

    @objc public func detachDebugger(_ sender: Any?) {
        guard let c = session.debugClient else { return }
        Task { try? await c.disconnect(terminate: false); c.close() }
    }

    @objc public func jumpToProgramCounter(_ sender: Any?) {
        if let loc = session.currentLocation { open(path: loc.file, line: loc.line) } else { NSSound.beep() }
    }
}
