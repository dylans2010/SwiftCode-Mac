import AppKit
import SwiftCodeIDECore

extension SourceControlCoordinator {
    public var mergeOverlay: MergeOverlayView? {
        owner.window?.contentView?.superview?.subviews.lazy.compactMap { $0 as? MergeOverlayView }.first
    }

    public var mergeSheet: MergeSheetController? { mergeOverlay?.sheet }

    @discardableResult
    public func presentMergeAlert(branch: String, choices: [String]? = nil) -> MergeAlertView? {
        guard let w = owner.window, let overlay = MergeOverlayView.install(in: w) else { return nil }
        let alert = MergeAlertView(branch: branch, current: snapshot.currentBranch ?? "HEAD", choices: choices)
        alert.onMerge = { [weak self, weak overlay] b in
            overlay?.dismissAlert()
            self?.merge(b)
        }
        alert.onCancel = { [weak overlay] in overlay?.close() }
        overlay.showAlert(alert)
        return alert
    }

    @discardableResult
    public func showConflictEditor(path: String? = nil) -> MergeSheetController? {
        guard let repo = repository, let w = owner.window else { return nil }
        try? owner.editor.save()
        if let s = mergeSheet {
            if let path { Task { await s.show(file: path) } } else { s.reloadFiles() }
            return s
        }
        guard let overlay = MergeOverlayView.install(in: w) else { return nil }
        let sheet = MergeSheetController(repository: repo, focus: path)
        sheet.onMerge = { [weak self, weak sheet] in
            guard let self, let sheet else { return }
            Task { await self.completeMerge(sheet) }
        }
        sheet.onCancel = { [weak self] in self?.cancelMerge() }
        sheet.onResolved = { [weak self] in self?.owner.refreshFileStatus(nil) }
        if overlay.alert != nil { overlay.dismissAlert() }
        overlay.showSheet(sheet)
        return sheet
    }

    func closeConflictEditor() {
        mergeOverlay?.close(animated: owner.window?.isVisible == true)
    }

    public func completeMerge(_ sheet: MergeSheetController) async {
        guard sheet.state.canMerge else { NSSound.beep(); return }
        if !sheet.state.files.isEmpty {
            guard await sheet.writeResolutions() == nil else { return }
        }
        owner.refreshFileStatus(nil)
        if snapshot.integration.isInProgress || sheet.state.integration.isInProgress {
            continueIntegration()
        } else {
            closeConflictEditor()
        }
    }

    public func cancelMerge() {
        let verb = (mergeSheet?.state.integration ?? snapshot.integration).verb
        guard snapshot.integration.isInProgress || mergeSheet?.state.integration.isInProgress == true else {
            closeConflictEditor()
            return
        }
        guard confirm(MergeSheetText.cancelTitle(verb: verb), MergeSheetText.cancelMessage(verb: verb), "Abort") else { return }
        abortIntegration()
    }

    func exportStash(_ ref: String) {
        guard let repo = repository else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(repo.root.lastPathComponent) stash.patch"
        panel.directoryURL = repo.root.deletingLastPathComponent()
        guard owner.window?.isVisible == true, panel.runModal() == .OK, let url = panel.url else { return }
        runInBackground(body: { try repo.exportStash(ref, to: url) })
    }

    var mergeableBranches: [String] { snapshot.branches.map(\.name).filter { $0 != snapshot.currentBranch } }
}

extension WorkspaceWindowController {
    @objc public func scmMerge(_ sender: Any?) {
        let scm = sourceControl
        let branches = scm.mergeableBranches
        guard !branches.isEmpty else { NSSound.beep(); return }
        let selected = navigator.selectedSourceControlKey.flatMap { $0.hasPrefix("branch:") ? String($0.dropFirst(7)) : nil }
        let branch = selected.flatMap { branches.contains($0) ? $0 : nil } ?? branches[0]
        scm.presentMergeAlert(branch: branch, choices: branches)
    }

    @objc public func scmResolveConflicts(_ sender: Any?) {
        let selected = sourceControl.selectedFile.flatMap { f in sourceControl.snapshot.changes.contains { $0.path == f && $0.status == .conflicted } ? f : nil }
        sourceControl.showConflictEditor(path: selected)
    }
    @objc public func scmContinueIntegration(_ sender: Any?) { sourceControl.continueIntegration() }
    @objc public func scmAbortIntegration(_ sender: Any?) {
        let verb = sourceControl.snapshot.integration.verb.lowercased()
        guard sourceControl.confirm("Abort the \(verb)?", "Returns the branch to where it was before the \(verb).", "Abort") else { return }
        sourceControl.abortIntegration()
    }
}
