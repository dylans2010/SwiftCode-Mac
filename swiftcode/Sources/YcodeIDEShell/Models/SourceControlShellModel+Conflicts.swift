import Foundation
import YcodeIDECore

extension SourceControlShellModel {
    public var isMergeSheetShown: Bool { conflictEditor != nil }

    @discardableResult
    public func showConflictEditor(path: String? = nil, fresh: Bool = false) -> ConflictEditorShellModel? {
        guard let repo = repository else { return nil }
        mergeAlert = nil
        isMerging = false
        if let e = conflictEditor, !fresh {
            if let path { e.showFile(path) } else { e.reload() }
            return e
        }
        saveEditors?()
        let editor = ConflictEditorShellModel(repository: repo, focus: path)
        editor.onResolved = { [weak self] in self?.refresh() }
        conflictEditor = editor
        editor.reload()
        return editor
    }

    public func closeConflictEditor() {
        conflictEditor = nil
        isMerging = false
    }

    public func resolveConflicts() {
        let selected = selectedFile.flatMap { f in snapshot.changes.contains { $0.path == f && $0.status == .conflicted } ? f : nil }
        showConflictEditor(path: selected)
    }

    public func askAbort() {
        let verb = snapshot.integration.verb.lowercased()
        let name = verb.isEmpty ? "operation" : verb
        confirmation = SourceControlConfirmation(
            title: "Abort the \(name)?", message: "Returns the branch to where it was before the \(name).",
            choices: [.init(title: "Abort", isDestructive: true, action: .abortIntegration)])
    }

    public func completeMerge() async {
        guard let e = conflictEditor, e.state.canMerge else { return }
        if !e.state.files.isEmpty {
            guard await e.writeResolutions() == nil else { return }
        }
        if snapshot.integration.isInProgress || e.state.integration.isInProgress {
            perform(.continueIntegration)
        } else {
            closeConflictEditor()
            refresh()
        }
    }

    public func cancelMerge() {
        let integration = conflictEditor?.state.integration ?? snapshot.integration
        guard snapshot.integration.isInProgress || integration.isInProgress else {
            closeConflictEditor()
            return
        }
        let verb = integration.isInProgress ? integration.verb : snapshot.integration.verb
        confirmation = SourceControlConfirmation(title: MergeSheetText.cancelTitle(verb: verb), message: MergeSheetText.cancelMessage(verb: verb),
                                                 choices: [.init(title: "Abort", isDestructive: true, action: .abortIntegration)])
    }

    func integrated(_ op: Operation, _ result: GitRepository.IntegrationResult?, succeeded: Bool) {
        isMerging = false
        if case .conflicts(let files)? = result {
            showConflictEditor(path: files.first, fresh: true)
        } else if result != nil || (op == .abortIntegration && succeeded) {
            closeConflictEditor()
        }
    }
}

final class IntegrationOutcome: @unchecked Sendable {
    var value: GitRepository.IntegrationResult?
}
