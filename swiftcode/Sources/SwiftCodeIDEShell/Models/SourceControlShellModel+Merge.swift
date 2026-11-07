import Foundation
import SwiftCodeIDECore

public struct MergeAlertState: Equatable, Sendable {
    public var branch: String
    public var current: String
    public var choices: [String]?

    public init(branch: String, current: String, choices: [String]? = nil) {
        self.branch = branch
        self.current = current
        self.choices = choices
    }

    public var title: String { MergeSheetText.alertTitle(branch: branch) }
    public var message: String { MergeSheetText.alertMessage(branch: branch, current: current) }
    public var hasChooser: Bool { !(choices?.isEmpty ?? true) }

    public func frame(window size: (width: Double, height: Double)) -> MergeSheetMetrics.Rect {
        MergeSheetMetrics.alertFrame(window: size, chooser: hasChooser)
    }
}

extension SourceControlShellModel {
    public var mergeableBranches: [String] { snapshot.branches.map(\.name).filter { $0 != snapshot.currentBranch } }

    public func presentMergeAlert(branch: String, choices: [String]? = nil) {
        mergeAlert = MergeAlertState(branch: branch, current: snapshot.currentBranch ?? "HEAD", choices: choices)
    }

    public func showMergeFromMenu() {
        let branches = mergeableBranches
        guard !branches.isEmpty else { return }
        let selected = selection.flatMap { s -> String? in
            if s.hasPrefix("branch:") { return String(s.dropFirst(7)) }
            if s.hasPrefix("recent:") { return String(s.dropFirst(7)) }
            return nil
        }
        presentMergeAlert(branch: selected.flatMap { branches.contains($0) ? $0 : nil } ?? branches[0], choices: branches)
    }

    public func chooseMergeBranch(_ branch: String) {
        guard var a = mergeAlert, a.choices?.contains(branch) ?? false else { return }
        a.branch = branch
        mergeAlert = a
    }

    public func confirmMergeAlert() {
        guard let a = mergeAlert else { return }
        mergeAlert = nil
        isMerging = true
        perform(.merge(a.branch))
    }

    public func cancelMergeAlert() {
        mergeAlert = nil
    }

    func chooseMore(_ action: SourceControlRowMenu.Action) {
        switch action {
        case .viewOnHost(let branch):
            if let url = SourceControlRowMenu.hostURL(branch: branch, remoteURLs: snapshot.remotes.map(\.url)) { openExternally(url) }
        case .exportStash(let ref):
            let name = repository?.root.lastPathComponent ?? "Repository"
            let folder = repository?.root.deletingLastPathComponent().path ?? folder.path
            prompt = SourceControlPrompt(purpose: .exportStash(ref), title: "Export Stashed Changes as Patch File",
                                         message: "Write the changes of \u{201C}\(ref)\u{201D} as a patch file.",
                                         fields: [.init(label: "File", placeholder: "Path of the patch file",
                                                        text: (folder as NSString).appendingPathComponent("\(name) stash.patch"))],
                                         button: "Export")
        default: break
        }
    }

    func exportStash(_ ref: String, to path: String) {
        guard let repo = repository else { return }
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded.hasPrefix("/") ? expanded : (folder.path as NSString).appendingPathComponent(expanded))
        Task { [weak self] in
            let error = await Task.detached { () -> String? in
                do { try repo.exportStash(ref, to: url); return nil } catch let e as GitRepository.GitError {
                    return e.errorDescription ?? e.description
                } catch { return error.localizedDescription }
            }.value
            if let error { self?.errorMessage = error }
        }
    }
}
