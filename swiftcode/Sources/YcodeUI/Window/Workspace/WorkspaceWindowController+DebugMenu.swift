import AppKit
import Darwin
import YcodeDebug
import YcodeIDECore

extension WorkspaceWindowController {

    var debugCaret: (file: String, line: Int, column: Int)? {
        guard editor.auxiliary == nil, let path = editor.fileURL?.path else { return nil }
        let tv = editor.textView
        let loc = tv.selectedRange().location
        let line = tv.lineIndex.line(at: loc)
        let start = tv.lineIndex.range(ofLine: line)?.location ?? loc
        return (path, line, loc - start + 1)
    }

    @objc public func continueToCurrentLine(_ sender: Any?) {
        guard let c = debugCaret else { return NSSound.beep() }
        Task { await session.continueToLine(file: c.file, line: c.line) }
    }

    @objc public func stepOverThread(_ sender: Any?) { Task { await session.step("over", instruction: false, singleThread: true) } }
    @objc public func stepIntoThread(_ sender: Any?) { Task { await session.step("in", instruction: false, singleThread: true) } }

    @objc public func toggleBreakpointsEnabledAtCurrentLine(_ sender: Any?) {
        guard let c = debugCaret else { return }
        session.breakpoints.toggleEnabled(file: c.file, line: c.line)
    }

    @objc public func createColumnBreakpoint(_ sender: Any?) {
        guard let c = debugCaret else { return }
        session.breakpoints.addColumn(file: c.file, line: c.line, column: c.column)
    }

    @objc public func deleteColumnBreakpointsAtCurrentLine(_ sender: Any?) {
        guard let c = debugCaret else { return }
        session.breakpoints.removeColumns(file: c.file, line: c.line)
    }

    @objc public func createSwiftErrorBreakpoint(_ sender: Any?) { addExceptionBreakpoint(swift: true) }
    @objc public func createExceptionBreakpoint(_ sender: Any?) { addExceptionBreakpoint(swift: false) }
    @objc public func createSymbolicBreakpoint(_ sender: Any?) {
        if window?.isVisible == true { askSymbolicBreakpoint() }
    }

    @objc public func createTestFailureBreakpoint(_ sender: Any?) {
        guard let f = session.testFailureFilter, !session.breakpoints.exceptionFilters.contains(f) else { return }
        session.breakpoints.exceptionFilters.append(f)
    }

    public func deleteAllBreakpointsAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Are you sure you want to delete all breakpoints?"
        alert.informativeText = "You can’t undo this action."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        return alert
    }

    @objc public func deleteAllBreakpoints(_ sender: Any?) {
        guard let window, window.isVisible else { return }
        deleteAllBreakpointsAlert().beginSheetModal(for: window) { [weak self] r in
            if r == .alertFirstButtonReturn { self?.session.breakpoints.removeAll() }
        }
    }

    var consoleRows: [ConsoleRow] {
        ConsoleRows.rows(session.consoleEntries.filter { debugArea.consoleFilter.includes($0.kind) })
    }

    var selectedConsoleRow: ConsoleRow? {
        guard let i = debugArea.selectedConsoleRow else { return nil }
        let rows = consoleRows
        return rows.indices.contains(i) ? rows[i] : nil
    }

    private func copyConsoleRow(_ metadata: ConsoleMetadata?) {
        guard let row = selectedConsoleRow else { return NSSound.beep() }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ConsoleRows.copyText(row, metadata: metadata), forType: .string)
    }

    @objc public func copyConsoleRowWithVisibleMetadata(_ sender: Any?) {
        copyConsoleRow(debugArea.metadata.enabled ? debugArea.metadata : nil)
    }
    @objc public func copyConsoleRowWithAllMetadata(_ sender: Any?) { copyConsoleRow(ConsoleRows.allMetadata) }
    @objc public func copyConsoleRowWithoutMetadata(_ sender: Any?) { copyConsoleRow(nil) }

    var selectedConsoleSource: (file: String, line: Int)? {
        guard let row = selectedConsoleRow, let loc = ConsoleRows.sourceLocation(in: row.text),
              let file = ConsoleRows.resolve(loc.path, files: workspaceFiles) else { return nil }
        return (file, loc.line)
    }

    @objc public func jumpToConsoleSource(_ sender: Any?) {
        guard let s = selectedConsoleSource else { return NSSound.beep() }
        open(path: s.file, line: s.line)
    }

    @objc public func reloadConsole(_ sender: Any?) {
        debugArea.setConsole(session.consoleText(debugArea.consoleFilter, metadata: debugArea.metadata))
    }

    @objc public func selectLastConsoleOutput(_ sender: Any?) {
        showDebugArea(true)
        if debugArea.selectLastOutput() == nil { NSSound.beep() }
    }

    @objc public func toggleNavigateToSourceOnPause(_ sender: Any?) { navigatesToSourceOnPause.toggle() }
    @objc public func toggleSynchronizeInsertionPoint(_ sender: Any?) { synchronizesInsertionPoint.toggle() }

    func showDebugLocation(_ loc: (file: String, line: Int)) {
        let key = "\(session.stopCount)|\(loc.file):\(loc.line)|\(session.selectedFrameID ?? -1)"
        guard key != lastShownLocation else { return }
        lastShownLocation = key
        let topFrame = session.selectedFrameID == nil || session.selectedFrameID == session.frames.first?.id
        if topFrame && !navigatesToSourceOnPause { return }
        let same = editor.fileURL.map { $0.standardizedFileURL.path == URL(fileURLWithPath: loc.file).standardizedFileURL.path } ?? false
        if same && !synchronizesInsertionPoint && topFrame {
            editor.scrollTo(line: loc.line)
        } else {
            open(path: loc.file, line: loc.line)
        }
    }

    @objc public func debugExecutable(_ sender: Any?) {
        guard let window, window.isVisible else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = true
        panel.message = "Choose an executable to debug"
        panel.beginSheetModal(for: window) { [weak self] r in
            guard r == .OK, let url = panel.url else { return }
            Task { await self?.session.debug(program: url.path) }
        }
    }

    @objc public func attachToListedProcess(_ sender: NSMenuItem) {
        guard let pid = sender.representedObject as? Int else { return }
        Task { await session.attach(to: String(pid)) }
    }

    func validateDebugMenuItem(_ item: NSMenuItem) -> Bool? {
        let caret = debugCaret
        let paused = session.stoppedThread != nil
        switch item.action {
        case #selector(continueToCurrentLine(_:)): return paused && caret != nil
        case #selector(stepOverThread(_:)), #selector(stepIntoThread(_:)): return paused
        case #selector(toggleBreakpointsEnabledAtCurrentLine(_:)):
            return caret.map { session.breakpoints.lineIsEnabled(file: $0.file, line: $0.line) != nil } ?? false
        case #selector(createColumnBreakpoint(_:)): return caret != nil
        case #selector(deleteColumnBreakpointsAtCurrentLine(_:)):
            return caret.map { session.breakpoints.hasColumnBreakpoints(file: $0.file, line: $0.line) } ?? false
        case #selector(createSwiftErrorBreakpoint(_:)): return !session.breakpoints.exceptionFilters.contains("swift_throw")
        case #selector(createExceptionBreakpoint(_:)), #selector(createSymbolicBreakpoint(_:)): return true
        case #selector(createTestFailureBreakpoint(_:)): return session.testFailureFilter != nil
        case #selector(deleteAllBreakpoints(_:)): return !session.breakpoints.isEmpty
        case #selector(copyConsoleRowWithVisibleMetadata(_:)), #selector(copyConsoleRowWithAllMetadata(_:)),
             #selector(copyConsoleRowWithoutMetadata(_:)):
            return selectedConsoleRow != nil
        case #selector(jumpToConsoleSource(_:)): return selectedConsoleSource != nil
        case #selector(reloadConsole(_:)), #selector(selectLastConsoleOutput(_:)): return !session.consoleEntries.isEmpty
        case #selector(toggleNavigateToSourceOnPause(_:)):
            item.state = navigatesToSourceOnPause ? .on : .off
            return true
        case #selector(toggleSynchronizeInsertionPoint(_:)):
            item.state = synchronizesInsertionPoint ? .on : .off
            return true
        case #selector(toggleAlwaysShowDisassembly(_:)):
            item.state = session.alwaysShowDisassembly ? .on : .off
            return true
        case #selector(debugExecutable(_:)): return !session.isBusy
        case #selector(attachToListedProcess(_:)): return session.debugClient == nil
        default: return nil
        }
    }
}

extension SourceEditorController {
    func scrollTo(line: Int) {
        guard let r = textView.lineIndex.range(ofLine: line) else { return }
        textView.scrollRangeToVisible(r)
    }
}

public enum RunningProcesses {
    public struct Entry: Equatable, Sendable {
        public var pid: Int
        public var name: String
    }

    public static func list(uid: uid_t = getuid(), excluding: Int32 = getpid()) -> [Entry] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard n > 0 else { return [] }
        var out: [Entry] = []
        for pid in pids.prefix(Int(n)) where pid > 0 && pid != excluding {
            var info = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0,
                  info.pbi_uid == uid, info.pbi_status != UInt32(SZOMB) else { continue }
            var buf = [CChar](repeating: 0, count: 256)
            guard proc_name(pid, &buf, UInt32(buf.count)) > 0 else { continue }
            out.append(Entry(pid: Int(pid), name: String(cString: buf)))
        }
        return out.sorted { ($0.name.lowercased(), $0.pid) < ($1.name.lowercased(), $1.pid) }
    }

    @MainActor
    static func recent(now: Date = Date()) -> [Entry] {
        if let c = cache, now.timeIntervalSince(c.date) < 2 { return c.list }
        let list = list()
        cache = (now, list)
        return list
    }
    @MainActor private static var cache: (date: Date, list: [Entry])?

    @MainActor
    static func fill(_ menu: NSMenu, target: AnyObject?, entries: [Entry]?) {
        menu.removeAllItems()
        guard let entries else {
            menu.addItem(NSMenuItem(title: "Getting Process List…", action: nil, keyEquivalent: ""))
            return
        }
        for e in entries {
            let i = NSMenuItem(title: "\(e.name) (\(e.pid))", action: #selector(WorkspaceWindowController.attachToListedProcess(_:)), keyEquivalent: "")
            i.target = target
            i.representedObject = e.pid
            menu.addItem(i)
        }
    }
}
