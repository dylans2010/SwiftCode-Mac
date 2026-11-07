import AppKit
import SwiftCodeDebug

extension WorkspaceWindowController {
    func wireDebuggerUI() {
        wireSimulatorDebugBar()
        navigator.testRowMenu = { [weak self] in self?.testRowMenuItems() ?? [] }
        navigator.onToggleBreakpointEnabled = { [weak self] file, line in
            self?.session.breakpoints.edit(file: file, line: line) { $0.isEnabled.toggle() }
        }
        debugArea.branchesProvider = { [weak self] in
            guard let self, self.sourceControl.snapshot.repository != nil else { return [] }
            return self.sourceControl.snapshot.branches.map { ($0.name, $0.isCurrent) }
        }
        debugArea.onSwitchBranch = { [weak self] name in
            guard let self else { return }
            self.sourceControl.enqueue { [weak self] in _ = await self?.switchBranch(name) }
        }
    }

    @discardableResult
    public func switchBranch(_ name: String) async -> Bool {
        guard let repo = repository else { NSSound.beep(); return false }
        for e in editorArea.allEditors { try? e.save() }
        let failure = await Task.detached { () -> String? in
            do { try repo.switchBranch(name); return nil } catch { return "\(error)" }
        }.value
        if let failure {
            let alert = NSAlert()
            alert.messageText = "Couldn’t switch to “\(name)”"
            alert.informativeText = failure
            if let window, window.isVisible { alert.beginSheetModal(for: window, completionHandler: nil) }
            return false
        }
        refreshFileStatus(nil)
        for e in editorArea.allEditors {
            guard let url = e.fileURL, e.auxiliary == nil, FileManager.default.fileExists(atPath: url.path) else { continue }
            let line = e.currentLine
            if (try? e.open(url)) != nil { e.reveal(line: line) }
        }
        return true
    }

    var sourceControlRoot: String {
        let url = session.model.url
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        let dir = isDir.boolValue && !["xcodeproj", "xcworkspace"].contains(url.pathExtension) ? url : url.deletingLastPathComponent()
        return dir.path
    }

    func refreshBranch() { sourceControl.scheduleRefresh() }

    func refreshDebugChrome() {
        if session.stoppedThread != nil, session.stopCount > session.autoSelectedStop {
            session.autoSelectedStop = session.stopCount
            if navigator.selectedIndex != 6 { navigator.select(6) }
        }
        navigator.setDebugProcess(session.debugProcessInfo)
        debugArea.setPath(session.debugBarPath)
        debugArea.setVariableBadges(session.variableBadges)
        debugArea.setLoadingVariables(session.isLoadingVariables)
        applyStopAnnotation(path: editor.fileURL?.standardizedFileURL.path)
        if case .finished = session.activity { refreshBranch() }
    }

    func applyStopAnnotation(path: String?) {
        let a = session.stopAnnotation
        let topSelected = session.selectedFrameID == nil || session.selectedFrameID == session.frames.first?.id
        editor.setStopAnnotation(a != nil && a.map { URL(fileURLWithPath: $0.file).standardizedFileURL.path } == path.map { URL(fileURLWithPath: $0).standardizedFileURL.path } && topSelected && session.stoppedThread != nil ? a?.text : nil)
    }

    func addSpecialBreakpoint(_ kind: NavigatorAreaController.NewBreakpointKind) {
        let names: [String]
        switch kind {
        case .runtimeIssue: names = ["__asan_on_error", "__tsan_on_report", "__ubsan_on_report", "__main_thread_checker_on_report"]
        case .constraintError: names = ["UIViewAlertForUnsatisfiableConstraints"]
        case .testFailure: names = ["XCTFail"]
        default: return
        }
        for n in names { addSymbolicBreakpoint(name: n) }
    }
}
