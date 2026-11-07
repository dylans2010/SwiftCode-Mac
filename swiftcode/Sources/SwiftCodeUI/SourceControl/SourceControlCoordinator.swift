import AppKit
import SwiftCodeIDECore

@MainActor
public final class SourceControlCoordinator {
    unowned let owner: WorkspaceWindowController
    public private(set) var mode: SourceControlNavigatorModel.Mode = .changes
    public private(set) var editorOverlay: NSViewController?
    public var commitEditor: CommitEditorController? { editorOverlay as? CommitEditorController }
    public var history: BranchHistoryController? { editorOverlay as? BranchHistoryController }
    public private(set) var selectedChange: String?
    private var installedInspector = false
    public internal(set) var hasRemote = false
    public internal(set) var lastStatus: [String: GitRepository.FileStatus] = [:]
    public private(set) var snapshot = SourceControlSnapshot()
    private var refreshTask: Task<Void, Never>?
    private var refreshAgain = false
    private var operation: Task<Void, Never>?
    var integrationResult: GitRepository.IntegrationResult?
    private var operationID = 0

    private var watcher: FileSystemWatcher?
    private var observers: [NSObjectProtocol] = []
    let watchesForChanges: Bool

    init(owner: WorkspaceWindowController) {
        self.owner = owner
        watchesForChanges = !WorkspaceWindowController.isTestProcess
        owner.navigator.onSourceControlRow = { [weak self] key in self?.handleRow(key) }
        owner.navigator.onSourceControlMode = { [weak self] m in self?.setMode(m) }
        owner.navigator.sourceControlRowMenu = { [weak self] key in self?.rowMenuItems(forKey: key) ?? [] }
        guard watchesForChanges else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        })
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: owner.window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.watcher?.stop()
                self?.watcher = nil
            }
        })
    }

    isolated deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
    }

    private func watch(_ repo: GitRepository) {
        guard watchesForChanges, watcher == nil else { return }
        let w = FileSystemWatcher { [weak self] paths in
            guard paths.contains(where: FileSystemWatcher.affectsSourceControl) else { return }
            self?.scheduleRefresh()
        }
        w.start(path: repo.root.path)
        watcher = w
    }

    var repository: GitRepository? { Preferences.shared.sourceControlEnabled ? owner.repository : nil }

    public func setMode(_ m: SourceControlNavigatorModel.Mode) {
        mode = m
        owner.navigator.sourceControlMode.selectedSegment = m.rawValue
        refresh()
    }

    public func refresh() {
        guard Preferences.shared.sourceControlEnabled, let repo = snapshot.repository else { owner.navigator.setSourceControlRoots([]); return }
        let name = repo.root.lastPathComponent, branch = snapshot.currentBranch
        switch mode {
        case .changes:
            owner.navigator.setSourceControlRoots(SourceControlNavigatorModel.changesTree(
                repository: name, branch: branch, changes: snapshot.changes, root: repo.root, integration: snapshot.integration))
        case .repositories:
            owner.navigator.setSourceControlRoots(SourceControlNavigatorModel.repositoriesTree(
                repository: name, branch: branch, branches: snapshot.branches, recents: snapshot.recentBranches,
                tags: snapshot.tags, stashes: snapshot.stashes, remotes: snapshot.remotes,
                remoteBranches: snapshot.remoteBranches))
        }
        if let c = commitEditor, c.isViewLoaded { c.reload() }
        if let c = mergeSheet, c.isViewLoaded { c.update(integration: snapshot.integration, conflicted: snapshot.changes.filter { $0.status == .conflicted }.map(\.path)) }
    }

    public func scheduleRefresh() {
        guard refreshTask == nil else { refreshAgain = true; return }
        refreshTask = Task { [weak self] in
            while true {
                guard let (enabled, known, url, folder) = self?.refreshInputs() else { return }
                let read = await Task.detached { SourceControlSnapshot.read(workspace: url, known: known, branchFolder: folder) }.value
                guard let self else { return }
                self.apply(read, enabled: enabled)
                if !self.refreshAgain { self.refreshTask = nil; return }
            }
        }
    }

    private func refreshInputs() -> (Bool, GitRepository??, URL, String) {
        refreshAgain = false
        let enabled = Preferences.shared.sourceControlEnabled
        return (enabled, enabled ? owner.knownRepository : .some(nil), owner.session.model.url, owner.sourceControlRoot)
    }

    func apply(_ read: SourceControlSnapshot, enabled: Bool) {
        owner.debugArea.setBranch(read.debugBarBranch)
        guard enabled else {
            owner.navigator.setFileStatus([:])
            refresh()
            return
        }
        owner.knownRepository = .some(read.repository)
        let previous = snapshot
        snapshot = read
        if read.baselinesMayDiffer(from: previous) {
            for e in owner.editorArea.allEditors where e.fileURL != nil && e.changeBaselines != nil { e.refreshSourceChanges() }
        }
        guard let repo = read.repository else { return }
        watch(repo)
        lastStatus = read.status
        hasRemote = !read.remotes.isEmpty
        owner.navigator.setFileStatus(read.status)
        owner.navigator.setRepository(name: repo.root.lastPathComponent, branches: read.branches,
                                      tags: read.tags, remotes: read.remotes, remoteBranches: read.remoteBranches)
        refresh()
    }

    public func idle() async {
        while true {
            if let t = operation { await t.value; continue }
            if let t = refreshTask { await t.value; continue }
            if let c = commitEditor, c.loading != nil || c.working != nil { await c.idle(); continue }
            if let h = history, h.loading != nil || h.inspectorLoading != nil { await h.idle(); continue }
            if let c = mergeSheet, c.loading != nil { await c.idle(); continue }
            return
        }
    }

    public func handleRow(_ key: String) {
        guard repository != nil else { return }
        if key.hasPrefix("change:") {
            selectedChange = String(key.dropFirst(7))
            if let p = selectedChange, snapshot.changes.contains(where: { $0.path == p && $0.status == .conflicted }) {
                showConflictEditor(path: p)
            } else {
                showCommitEditor(focus: selectedChange)
            }
        } else if key == "repository" {
            selectedChange = nil
            if mode == .changes { showCommitEditor(focus: nil) } else if let b = snapshot.currentBranch { showHistory(ref: b, branch: b) }
        } else if key.hasPrefix("branch:") {
            let b = String(key.dropFirst(7))
            showHistory(ref: "refs/heads/" + b, branch: b)
        } else if key.hasPrefix("tag:") {
            showHistory(ref: "refs/tags/" + key.dropFirst(4), branch: nil)
        } else if key.hasPrefix("remoteBranch:") {
            showHistory(ref: "refs/remotes/" + key.dropFirst(13), branch: nil)
        } else if key.hasPrefix("stash:") {
            showHistory(ref: String(key.dropFirst(6)), branch: nil)
        }
    }

    @discardableResult
    public func showCommitEditor(focus: String?) -> CommitEditorController? {
        guard let repo = repository else { return nil }
        try? owner.editor.save()
        let c = CommitEditorController(repository: repo)
        c.focusPath = focus
        c.onChanged = { [weak self] in self?.owner.refreshFileStatus(nil) }
        install(c)
        setInspector(nil)
        return c
    }

    @discardableResult
    public func showHistory(ref: String, branch: String?) -> BranchHistoryController? {
        guard let repo = repository else { return nil }
        let h = BranchHistoryController(repository: repo, ref: ref)
        var selection = 0
        h.onSelectCommit = { [weak self] commit in
            selection += 1
            let mine = selection
            let task = Task { [weak self] in
                let sections = await Task.detached { () -> [(String, [(String, String)])] in
                    var sections: [(String, [(String, String)])] = []
                    if let branch { sections.append(("Branch", SourceControlInspector.branchRows(repository: repo, branch: branch))) }
                    if let commit { sections.append(("Commit", SourceControlInspector.commitRows(repository: repo, commit: commit))) }
                    return sections
                }.value
                guard mine == selection else { return }
                self?.setInspector(sections)
            }
            h.inspectorLoading = task
        }
        install(h)
        h.onSelectCommit?(nil)
        return h
    }

    public private(set) var inspectorSections: [(String, [(String, String)])]?

    func setInspector(_ sections: [(String, [(String, String)])]?) {
        inspectorSections = sections
        if let sections, !sections.isEmpty {
            installedInspector = true
            owner.inspector.setExtraInspectors([("Source Control", "arrow.triangle.branch")],
                                               provider: { _ in SourceControlInspector.view(sections: sections) },
                                               select: CommandTable.inspectors.count)
        } else if installedInspector {
            installedInspector = false
            owner.inspector.setExtraInspectors([], provider: nil)
        }
    }

    func install(_ vc: NSViewController) {
        hideEditor()
        editorOverlay = vc
        let host = owner.editorArea
        host.addChild(vc)
        let v = vc.view
        v.translatesAutoresizingMaskIntoConstraints = false
        host.view.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.topAnchor), v.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),
            v.leadingAnchor.constraint(equalTo: host.view.leadingAnchor), v.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
        ])
    }

    public func hideEditor() {
        guard let vc = editorOverlay else { return }
        vc.view.removeFromSuperview()
        vc.removeFromParent()
        editorOverlay = nil
        setInspector(nil)
    }

    var selectedFile: String? {
        if owner.navigator.selectedIndex == 1 { return selectedChange }
        return owner.navigator.selectedPath ?? owner.editor.fileURL?.path
    }

    public func menuState() -> IntegrateMenuState {
        var s = IntegrateMenuState()
        guard Preferences.shared.sourceControlEnabled, snapshot.repository != nil else {
            s.selectedFileExists = selectedFile.map { FileManager.default.fileExists(atPath: $0) } ?? false
            return s
        }
        s.hasRepository = true
        s.hasRemote = !snapshot.remotes.isEmpty
        s.otherBranchCount = snapshot.branches.filter { $0.name != snapshot.currentBranch }.count
        let changes = snapshot.changes
        s.hasStaged = changes.contains(where: \.isStaged)
        s.hasUnstaged = changes.contains(where: \.isUnstaged)
        if let f = selectedFile {
            s.selectedFileExists = FileManager.default.fileExists(atPath: f)
            if let c = changes.first(where: { $0.path == f }) { s.selectedStatus = c.status; s.selectedIsStaged = c.isStaged }
        }
        s.selectedCommit = history?.selectedCommit?.hash
        s.integration = snapshot.integration
        s.conflictCount = changes.filter { $0.status == .conflicted }.count
        return s
    }

    func perform(_ body: @escaping @Sendable (GitRepository) throws -> Void) {
        guard let repo = repository else { NSSound.beep(); return }
        runInBackground(body: { try body(repo) })
    }

    func runInBackground(body: @escaping @Sendable () throws -> Void, then: (@MainActor () -> Void)? = nil,
                         failure handle: (@MainActor (any Error) -> Bool)? = nil) {
        let previous = operation
        operationID += 1
        let id = operationID
        operation = Task { [weak self] in
            await previous?.value
            let failure = await Task.detached { () -> GitFailure? in
                do { try body(); return nil } catch { return GitFailure(error: error) }
            }.value
            guard let self else { return }
            if let failure, handle?(failure.error) != true, self.owner.window?.isVisible == true { self.owner.presentError(failure.error) }
            then?()
            self.owner.refreshFileStatus(nil)
            if let h = self.history { h.reload() }
            if self.operationID == id { self.operation = nil }
        }
    }

    struct GitFailure: @unchecked Sendable { let error: any Error }

    func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = operation
        operationID += 1
        let id = operationID
        operation = Task { [weak self] in
            await previous?.value
            await work()
            if let self, self.operationID == id { self.operation = nil }
        }
    }

    func prompt(_ title: String, _ info: String, placeholder: String) -> String? {
        guard owner.window?.isVisible == true else { return nil }
        let a = NSAlert()
        a.messageText = title
        a.informativeText = info
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 22))
        f.placeholderString = placeholder
        a.accessoryView = f
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn ? f.stringValue : nil
    }

    func confirm(_ title: String, _ info: String, _ button: String) -> Bool {
        guard owner.window?.isVisible == true else { return true }
        let a = NSAlert()
        a.messageText = title
        a.informativeText = info
        a.addButton(withTitle: button)
        a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn
    }
}

extension WorkspaceWindowController {
    @objc public func scmPush(_ sender: Any?) { sourceControl.perform { try $0.push() } }
    @objc public func scmPull(_ sender: Any?) { sourceControl.perform { try $0.pull() } }
    @objc public func scmFetch(_ sender: Any?) { sourceControl.perform { try $0.fetch() } }
    @objc public func scmStageAll(_ sender: Any?) { sourceControl.perform { try $0.stageAll() } }
    @objc public func scmUnstageAll(_ sender: Any?) { sourceControl.perform { try $0.unstageAll() } }
    @objc public func scmStageSelected(_ sender: Any?) {
        guard let f = sourceControl.selectedFile else { return }
        sourceControl.perform { try $0.stage([f]) }
    }
    @objc public func scmUnstageSelected(_ sender: Any?) {
        guard let f = sourceControl.selectedFile else { return }
        sourceControl.perform { try $0.unstage([f]) }
    }
    @objc public func scmMarkResolved(_ sender: Any?) {
        guard let f = sourceControl.selectedFile else { return }
        sourceControl.perform { try $0.markResolved([f]) }
    }
    @objc public func scmAddSelected(_ sender: Any?) {
        guard let f = sourceControl.selectedFile else { return }
        sourceControl.perform { try $0.stage([f]) }
    }
    @objc public func scmCherryPick(_ sender: Any?) {
        guard let c = sourceControl.history?.selectedCommit else { return }
        guard sourceControl.confirm("Cherry-pick \"\(c.subject)\"?", "Applies commit \(c.shortHash) on top of the current branch.", "Cherry-Pick") else { return }
        sourceControl.cherryPick(c.hash)
    }
    @objc public func scmStash(_ sender: Any?) {
        let message = window?.isVisible == true ? sourceControl.prompt("Stash Changes", "Saves uncommitted changes and untracked files to a stash.", placeholder: "Description") : ""
        guard let message else { return }
        sourceControl.perform { try $0.stash(message: message) }
    }
    @objc public func scmDiscardAll(_ sender: Any?) {
        guard sourceControl.confirm("Discard all changes?", "Tracked files return to their last commit; new files move to the Trash.", "Discard All") else { return }
        sourceControl.perform { repo in for c in try repo.changes() { try repo.discard(c.path) } }
    }
    @objc public func scmTrashSelected(_ sender: Any?) {
        guard let f = sourceControl.selectedFile else { return }
        guard sourceControl.confirm("Move \"\(URL(fileURLWithPath: f).lastPathComponent)\" to the Trash?", "", "Move to Trash") else { return }
        do { try FileManager.default.trashItem(at: URL(fileURLWithPath: f), resultingItemURL: nil) } catch { presentError(error) }
        refreshFileStatus(nil)
    }
    @objc public func scmClone(_ sender: Any?) {
        guard let url = sourceControl.prompt("Clone", "Enter a repository URL.", placeholder: "https://…"), !url.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Clone"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        let target = dir.appendingPathComponent(GitRepository.cloneFolderName(for: url))
        let progress = CloneProgressSheet.begin(name: target.lastPathComponent, on: window)
        sourceControl.runInBackground(body: { try GitRepository.clone(url, into: target) }, then: {
            progress?.end()
            if let ws = WelcomeWindowController.workspace(in: target), FileManager.default.fileExists(atPath: target.path) {
                NSDocumentController.shared.openDocument(withContentsOf: ws, display: true) { _, _, error in
                    if let error { NSApp.presentError(error) }
                }
            }
        })
    }
    @objc public func scmNewRepository(_ sender: Any?) {
        let u = session.model.url
        let dir = ["xcodeproj", "xcworkspace", "swift"].contains(u.pathExtension) || !u.hasDirectoryPath ? u.deletingLastPathComponent() : u
        sourceControl.runInBackground(body: { _ = try GitRepository.initialize(at: dir) }, then: { [weak self] in self?.resetRepository() })
    }
}
