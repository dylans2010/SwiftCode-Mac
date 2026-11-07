import Foundation
import SwiftCodeIDECore

extension WorkspaceShellModel {
    func connectSourceControl() {
        let scm = sourceControl
        scm.currentText = { [weak self] path in self?.openDocuments[path]?.buffer.text }
        scm.saveEditors = { [weak self] in _ = self?.saveAll() }
        scm.openFile = { [weak self] path in self?.open(path) }
        scm.refresh()
    }

    public var currentBranch: String? { sourceControl.snapshot.currentBranch }
}
