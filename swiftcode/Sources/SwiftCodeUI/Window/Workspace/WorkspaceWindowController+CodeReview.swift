import AppKit
import SwiftCodeIDECore

extension WorkspaceWindowController {
    @discardableResult
    func startCodeReview() -> Bool {
        guard let url = editor.fileURL, let repo = repository else { NSSound.beep(); return false }
        let source = editor.review.rightSource
        let baseline = source == .uncommittedChanges ? editor.textView.string : (source.baseline(of: url.path, in: repo) ?? "")
        editor.review.host = { [weak self] bar in self?.debugArea.setReviewControls(bar) }
        let left = editor.review.leftSource
        editor.review.leftText = left == .uncommittedChanges ? nil : (left.leftContents(of: url.path, in: repo) ?? "")
        if editor.comparisonStyle == .inline && editor.review.leftText == nil {
            editor.showInlineComparison(baseline: baseline, source: source)
        } else {
            editor.showSideBySideComparison(baseline: baseline, source: source)
        }
        let bar = editor.reviewBar
        bar.onSwap = { [weak self] in
            guard let self else { return }
            self.editor.swapReviewSources()
            self.endCodeReview(); self.startCodeReview()
        }
        bar.onPick = { [weak self] left, anchor in self?.showReviewSourcePicker(left: left, anchor: anchor) }
        return true
    }

    func endCodeReview() { endCodeReview(in: editor) }

    func endCodeReview(in e: SourceEditorController) {
        e.hideInlineComparison()
        e.hideComparison()
    }

    @objc public func showInlineComparison(_ sender: Any?) { setComparisonStyle(.inline) }
    @objc public func showSideBySideComparison(_ sender: Any?) { setComparisonStyle(.sideBySide) }

    func setComparisonStyle(_ s: ComparisonStyle) {
        let active = editor.isShowingComparison || editor.isShowingInlineComparison
        editor.comparisonStyle = s
        if active { endCodeReview(); startCodeReview() }
    }

    @discardableResult
    public func reviewSourcePicker(left: Bool) -> ReviewSourcePicker? {
        guard let repo = repository else { return nil }
        let branches = (try? repo.branches()) ?? []
        let tags = (try? repo.tags()) ?? []
        let commits = repo.recentCommits(limit: 50, path: editor.fileURL?.path)
        let recents = [editor.review.leftSource, editor.review.rightSource].compactMap { s -> String? in
            if case .branch(let b) = s { return b } else { return nil }
        }
        let columns = CodeReviewModel.pickerColumns(branches: branches + tags, recents: recents, commits: commits)
        var branchSources: [String: ReviewSource] = [:]
        for b in branches + tags { branchSources[b.name] = .branch(b.name) }
        let commitSources: [ReviewSource] = [.uncommittedChanges, .unstagedChanges, .stagedChanges]
            + commits.map { .commit(hash: $0.hash, title: "\($0.shortHash) \($0.subject)") }
        let picker = ReviewSourcePicker(columns: columns, commitSources: commitSources, branchSources: branchSources)
        picker.onChoose = { [weak self] s in
            guard let self else { return }
            self.editor.setReviewSource(s, left: left)
            self.endCodeReview(); self.startCodeReview()
        }
        return picker
    }

    func showReviewSourcePicker(left: Bool, anchor: NSView) {
        guard let picker = reviewSourcePicker(left: left), window?.isVisible == true else { return }
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentViewController = picker
        pop.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }
}
