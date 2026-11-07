import Foundation
import Observation
import SwiftCodeIDECore

@MainActor
@Observable
public final class SourceControlShellModel {
    public enum Mode: Int, CaseIterable, Sendable { case changes, repositories }

    public enum Pane: Equatable, Sendable {
        case commit(focus: String?)
        case history(ref: String, title: String, branch: String?)
        case conflicts

        public var isHistory: Bool { if case .history = self { true } else { false } }
    }

    public enum Operation: Equatable, Sendable {
        case checkout(String, GitRepository.ChangeHandling)
        case createBranch(String, from: String?)
        case createTag(String, at: String?, message: String?)
        case renameBranch(String, to: String)
        case deleteBranch(String, force: Bool)
        case merge(String)
        case rebase(String)
        case push(branch: String?)
        case pull(branch: String?)
        case fetch(remote: String?)
        case deleteRemoteBranch(remote: String, branch: String)
        case pushTag(String)
        case deleteTag(String)
        case applyStash(String, pop: Bool)
        case dropStash(String)
        case stash(message: String)
        case addRemote(name: String, url: String)
        case removeRemote(String)
        case stage([String])
        case unstage([String])
        case stageAll
        case unstageAll
        case markResolved([String])
        case discard([String])
        case cherryPick(String)
        case continueIntegration
        case abortIntegration
        case newRepository
    }

    @ObservationIgnored public let folder: URL
    public private(set) var snapshot = SourceControlSnapshot()
    public private(set) var hasRead = false
    public var mode: Mode = .changes
    public var collapsed: Set<String> = RepositoriesViewStyle.initiallyCollapsed
    public private(set) var selection: String?
    public internal(set) var pane: Pane?
    public internal(set) var conflictEditor: ConflictEditorShellModel?
    public internal(set) var mergeAlert: MergeAlertState?
    public internal(set) var isMerging = false
    @ObservationIgnored public var openExternally: (URL) -> Void = { _ in }
    public private(set) var busy: String?
    public var errorMessage: String?
    public var notice: String?
    public var prompt: SourceControlPrompt?
    public var confirmation: SourceControlConfirmation?
    public var commitSheet: CommitSheet?

    public var message = ""
    public var amend = false {
        didSet {
            if amend, !oldValue, message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let m = headMessage { message = m }
        }
    }
    public var scope: GitRepository.DiffScope = .all {
        didSet { if scope != oldValue { loadCards() } }
    }
    public private(set) var cards: [ChangeCard] = []
    public var collapsedCards: Set<String> = []
    public private(set) var author: GitRepository.Author?
    public private(set) var headMessage: String?

    public private(set) var history: [GitRepository.Commit] = []
    public var historyScope: HistoryScope = .all
    public var historyFilter = ""
    public var selectedCommit: String? {
        didSet { if selectedCommit != oldValue { loadCommitDetail() } }
    }
    public private(set) var commitDetail: CommitDetail?
    public private(set) var branchInfo: [(key: String, value: String)] = []

    public private(set) var fileHistoryPath: String?
    public private(set) var fileHistory: [GitRepository.Commit] = []

    public private(set) var changeRegionsPath: String?
    public private(set) var changeRegions: [SourceChangeRegion] = []
    @ObservationIgnored private var baselines: [String: (index: String?, head: String?)] = [:]

    @ObservationIgnored private var known: GitRepository??
    @ObservationIgnored private var reading: Task<Void, Never>?
    @ObservationIgnored private var readAgain = false
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private var loads: [Task<Void, Never>] = []
    @ObservationIgnored private var regionTask: Task<Void, Never>?
    @ObservationIgnored private var watcher: FileSystemWatcher?
    @ObservationIgnored public var currentText: ((String) -> String?)?
    @ObservationIgnored public var saveEditors: (() -> Void)?
    @ObservationIgnored public var openFile: ((String) -> Void)?

    public init(folder: URL) {
        self.folder = folder
        folderReal = Self.realPath(folder.path)
    }

    @ObservationIgnored private let folderReal: String

    nonisolated static func realPath(_ p: String) -> String {
        if let r = realpath(p, nil) {
            defer { free(r) }
            return String(cString: r)
        }
        let parent = (p as NSString).deletingLastPathComponent
        guard parent != p, !parent.isEmpty else { return p }
        return (realPath(parent) as NSString).appendingPathComponent((p as NSString).lastPathComponent)
    }

    public func repoPath(_ p: String) -> String {
        let f = folder.path
        guard f != folderReal, p == f || p.hasPrefix(f + "/") else { return p }
        return folderReal + p.dropFirst(f.count)
    }

    public func workspacePath(_ p: String) -> String {
        let f = folder.path
        guard f != folderReal, p == folderReal || p.hasPrefix(folderReal + "/") else { return p }
        return f + p.dropFirst(folderReal.count)
    }

    public static func folder(for url: URL) -> URL {
        let ext = url.pathExtension
        if ext == "xcodeproj" || ext == "xcworkspace" || url.lastPathComponent == "Package.swift" { return url.deletingLastPathComponent() }
        return url
    }

    public var repository: GitRepository? { snapshot.repository }
    public var repositoryName: String { SourceControlRows.repositoryName(snapshot) }

    public var rows: [OutlineRow] {
        mode == .changes ? SourceControlRows.changes(snapshot, collapsed: collapsed) : SourceControlRows.repositories(snapshot, collapsed: collapsed)
    }

    public var badges: [String: String] {
        Dictionary(snapshot.status.map { (workspacePath($0.key), $0.value.rawValue) }, uniquingKeysWith: { a, _ in a })
    }

    public static func shown(_ changes: [GitRepository.Change], scope: GitRepository.DiffScope) -> [GitRepository.Change] {
        switch scope {
        case .all: changes
        case .unstaged: changes.filter(\.isUnstaged)
        case .staged: changes.filter(\.isStaged)
        }
    }

    public var hasStagedChanges: Bool { snapshot.changes.contains(where: \.isStaged) }
    public var hasRemote: Bool { !snapshot.remotes.isEmpty }
    public var canCommit: Bool {
        busy == nil && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (!snapshot.changes.isEmpty || amend)
    }

    public var shownHistory: [GitRepository.Commit] { historyScope.apply(history, filter: historyFilter) }

    public func refresh() {
        if reading != nil { readAgain = true; return }
        let folder = folder, known = known
        reading = Task { [weak self] in
            let read = await Task.detached { SourceControlSnapshot.read(workspace: folder, known: known, branchFolder: nil) }.value
            guard let self else { return }
            self.apply(read)
            self.reading = nil
            if self.readAgain {
                self.readAgain = false
                self.refresh()
            }
        }
    }

    public func idle() async {
        while true {
            if let r = reading { await r.value; continue }
            if let q = queue { await q.value; if queue == q { queue = nil }; continue }
            if let l = loads.first { await l.value; loads.removeAll { $0 == l }; continue }
            if let t = regionTask { await t.value; if regionTask == t { regionTask = nil }; continue }
            if let c = conflictEditor, c.isLoading { await c.idle(); continue }
            return
        }
    }

    private func apply(_ read: SourceControlSnapshot) {
        let before = snapshot
        known = .some(read.repository)
        snapshot = read
        hasRead = true
        if let repo = read.repository, watcher == nil, !IDEProcess.isTestProcess { watch(repo) }
        if let s = selection, !rows.contains(where: { $0.id == s }), !s.hasPrefix("folder:") {
            if s.hasPrefix("change:") || s.hasPrefix("stash:") { selection = nil }
        }
        if before.baselinesMayDiffer(from: read) || !hasRead {
            baselines = [:]
            if let p = changeRegionsPath { loadRegions(for: p) }
        }
        switch pane {
        case .commit?: if before.changes != read.changes || before.head != read.head || cards.isEmpty { loadCards() }
        case .history?: if before.head != read.head || before.branches != read.branches || before.tags != read.tags { loadHistory() }
        case .conflicts?, nil: break
        }
        conflictEditor?.update(integration: read.integration, conflicted: read.changes.filter { $0.status == .conflicted }.map(\.path))
        if let p = fileHistoryPath, before.head != read.head { loadFileHistory(p) }
    }

    private func watch(_ repo: GitRepository) {
        let w = FileSystemWatcher { [weak self] paths in
            guard let self, paths.contains(where: FileSystemWatcher.affectsSourceControl) else { return }
            self.refresh()
        }
        w.start(path: repo.root.path, latency: 0.5)
        watcher = w
    }

    public func select(_ id: String) {
        selection = id
        guard repository != nil else { return }
        if id.hasPrefix("change:") {
            let p = String(id.dropFirst(7))
            if snapshot.changes.contains(where: { $0.path == p && $0.status == .conflicted }) { showConflictEditor(path: p); return }
            showCommitEditor(focus: p)
        } else if id == "repository" {
            if mode == .changes { showCommitEditor(focus: nil) } else if let b = snapshot.currentBranch { showHistory(ref: "refs/heads/" + b, title: b, branch: b) }
        } else if id.hasPrefix("branch:") {
            let b = String(id.dropFirst(7))
            showHistory(ref: "refs/heads/" + b, title: b, branch: b)
        } else if id.hasPrefix("recent:") {
            let b = String(id.dropFirst(7))
            showHistory(ref: "refs/heads/" + b, title: b, branch: b)
        } else if id.hasPrefix("tag:") {
            showHistory(ref: "refs/tags/" + id.dropFirst(4), title: String(id.dropFirst(4)), branch: nil)
        } else if id.hasPrefix("remoteBranch:") {
            showHistory(ref: "refs/remotes/" + id.dropFirst(13), title: String(id.dropFirst(13)), branch: nil)
        } else if id.hasPrefix("stash:") {
            showHistory(ref: String(id.dropFirst(6)), title: String(id.dropFirst(6)), branch: nil)
        }
    }

    public func setExpanded(_ id: String, _ on: Bool) {
        if on { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    public func menu(for id: String) -> [SourceControlRowMenu.Item] {
        let key = id.hasPrefix("recent:") ? "branch:" + id.dropFirst(7) : id
        return SourceControlRowMenu.items(forKey: key, in: SourceControlRowMenu.Context(snapshot))
    }

    public func choose(_ action: SourceControlRowMenu.Action) {
        let q = { (s: String) in "\u{201C}\(s)\u{201D}" }
        let current = snapshot.currentBranch ?? "HEAD"
        switch action {
        case .checkout(let b):
            let changed = snapshot.changes.contains { $0.status != .untracked }
            let short = b.split(separator: "/", maxSplits: 1).count == 2 && snapshot.remoteBranches.contains { $0.name == b } ? String(b.split(separator: "/", maxSplits: 1)[1]) : b
            confirmation = SourceControlConfirmation(
                title: "Check out \(q(short))?",
                message: changed ? "The working copy has uncommitted changes. They can be stashed first, or carried to \(q(short)) when they do not conflict."
                    : "The working copy will switch to \(q(short)).",
                choices: changed ? [.init(title: "Stash and Check Out", isDestructive: false, action: .checkout(b, .stash)),
                                    .init(title: "Check Out", isDestructive: false, action: .checkout(b, .carry))]
                    : [.init(title: "Check Out", isDestructive: false, action: .checkout(b, .carry))])
        case .newBranch(let from):
            prompt = SourceControlPrompt(purpose: .newBranch(from: from), title: "New Branch",
                                         message: "Create a branch from \(q(from ?? current)) and check it out.",
                                         fields: [.init(label: "Name", placeholder: "Branch name", text: "")], button: "Create")
        case .newTag(let at):
            prompt = SourceControlPrompt(purpose: .newTag(at: at), title: "New Tag", message: "Tag \(q(at ?? current)).",
                                         fields: [.init(label: "Name", placeholder: "Tag name", text: ""),
                                                  .init(label: "Message", placeholder: "Message (optional)", text: "")], button: "Create")
        case .renameBranch(let b):
            prompt = SourceControlPrompt(purpose: .renameBranch(b), title: "Rename Branch", message: "Rename \(q(b)).",
                                         fields: [.init(label: "Name", placeholder: "Branch name", text: b)], button: "Rename")
        case .deleteBranch(let b):
            confirmation = SourceControlConfirmation(title: "Delete \(q(b))?", message: "The branch is deleted from this repository. Its commits stay reachable from other branches that contain them.",
                                                     choices: [.init(title: "Delete", isDestructive: true, action: .deleteBranch(b, force: false))])
        case .merge(let r): presentMergeAlert(branch: r)
        case .rebaseOnto(let r):
            confirmation = SourceControlConfirmation(title: "Rebase \(q(current)) onto \(q(r))?", message: "The commits of \(q(current)) are replayed on top of \(q(r)).",
                                                     choices: [.init(title: "Rebase", isDestructive: false, action: .rebase(r))])
        case .push(let b): perform(.push(branch: b))
        case .pull(let b): perform(.pull(branch: b))
        case .deleteRemoteBranch(let r, let b):
            confirmation = SourceControlConfirmation(title: "Delete \(q(b)) from \(q(r))?", message: "The branch is deleted on the remote.",
                                                     choices: [.init(title: "Delete", isDestructive: true, action: .deleteRemoteBranch(remote: r, branch: b))])
        case .pushTag(let t): perform(.pushTag(t))
        case .deleteTag(let t):
            confirmation = SourceControlConfirmation(title: "Delete the tag \(q(t))?", message: "The tag is deleted from this repository.",
                                                     choices: [.init(title: "Delete", isDestructive: true, action: .deleteTag(t))])
        case .applyStash(let s): perform(.applyStash(s, pop: false))
        case .popStash(let s): perform(.applyStash(s, pop: true))
        case .dropStash(let s):
            confirmation = SourceControlConfirmation(title: "Delete the stash?", message: "Its changes are lost.",
                                                     choices: [.init(title: "Delete", isDestructive: true, action: .dropStash(s))])
        case .fetch(let r): perform(.fetch(remote: r))
        case .addRemote:
            prompt = SourceControlPrompt(purpose: .addRemote, title: "Add Remote", message: "Add a remote to this repository.",
                                         fields: [.init(label: "Name", placeholder: "origin", text: snapshot.remotes.isEmpty ? "origin" : ""),
                                                  .init(label: "Address", placeholder: "https://example.com/repository.git", text: "")], button: "Add")
        case .removeRemote(let r):
            confirmation = SourceControlConfirmation(title: "Remove \(q(r))?", message: "The remote and its remote branches are removed from this repository.",
                                                     choices: [.init(title: "Remove", isDestructive: true, action: .removeRemote(r))])
        case .resolveConflicts(let p): showConflictEditor(path: p)
        case .markResolved(let p): perform(.markResolved([p]))
        case .mergeInto, .newHostedRemote, .viewOnHost, .exportStash: chooseMore(action)
        }
    }

    public func confirmPrompt() {
        guard let p = prompt, p.canConfirm else { return }
        prompt = nil
        let first = p.fields.first?.text.trimmingCharacters(in: .whitespaces) ?? ""
        let second = p.fields.count > 1 ? p.fields[1].text.trimmingCharacters(in: .whitespaces) : ""
        switch p.purpose {
        case .newBranch(let from): perform(.createBranch(first, from: from))
        case .newTag(let at): perform(.createTag(first, at: at, message: second.isEmpty ? nil : second))
        case .renameBranch(let b): perform(.renameBranch(b, to: first))
        case .addRemote: perform(.addRemote(name: first, url: second))
        case .stash: perform(.stash(message: first))
        case .exportStash(let ref): exportStash(ref, to: first)
        }
    }

    public func confirm(_ choice: SourceControlConfirmation.Choice) {
        confirmation = nil
        perform(choice.action)
    }

    static func busyTitle(_ op: Operation) -> String {
        switch op {
        case .push, .pushTag, .deleteRemoteBranch: "Pushing…"
        case .pull: "Pulling…"
        case .fetch: "Fetching…"
        case .merge: "Merging…"
        case .rebase: "Rebasing…"
        case .checkout: "Checking out…"
        case .cherryPick: "Cherry-picking…"
        default: "Working…"
        }
    }

    public func perform(_ op: Operation) {
        let folder = folder
        let current = snapshot.currentBranch
        let remotes = snapshot.remotes.map(\.name)
        let title = Self.busyTitle(op)
        let outcome = IntegrationOutcome()
        enqueue(title, { repo in
            if case .newRepository = op {
                _ = try GitRepository.initialize(at: folder)
                return nil
            }
            guard let repo else { throw GitRepository.GitError(description: "The workspace is not in a git repository.") }
            func result(_ r: GitRepository.IntegrationResult) -> String? {
                outcome.value = r
                return nil
            }
            func remote(for branch: String) -> String? {
                repo.remote(of: branch) ?? (remotes.contains("origin") ? "origin" : remotes.first)
            }
            switch op {
            case .checkout(let b, let h): try repo.checkout(b, changes: h)
            case .createBranch(let n, let from): try repo.createBranch(n, from: from, checkout: true)
            case .createTag(let n, let at, let m): try repo.createTag(n, at: at, message: m)
            case .renameBranch(let a, let b): try repo.renameBranch(a, to: b)
            case .deleteBranch(let b, let force): try repo.deleteBranch(b, force: force)
            case .merge(let r): return result(try repo.merge(r))
            case .rebase(let r): return result(try repo.rebase(onto: r))
            case .push(let branch):
                guard let b = branch ?? current else { throw GitRepository.GitError(description: "Check out a branch to push it.") }
                if repo.upstream(of: b) != nil, branch == nil || branch == current {
                    try repo.push()
                } else {
                    guard let r = remote(for: b) else { throw GitRepository.GitError(description: "The repository has no remote. Add one first.") }
                    try repo.push(remote: r, branch: b, setUpstream: repo.upstream(of: b) == nil)
                }
            case .pull(let branch):
                guard let b = branch ?? current else { throw GitRepository.GitError(description: "Check out a branch to pull into it.") }
                if repo.upstream(of: b) != nil {
                    try repo.pull()
                } else {
                    guard let r = remote(for: b) else { throw GitRepository.GitError(description: "The repository has no remote. Add one first.") }
                    return result(try repo.pull(remote: r, branch: b, style: .fastForwardOnly))
                }
            case .fetch(let r): if let r { try repo.fetch(remote: r) } else { try repo.fetch() }
            case .deleteRemoteBranch(let r, let b): try repo.deleteRemoteBranch(remote: r, branch: b)
            case .pushTag(let t):
                guard let r = remotes.contains("origin") ? "origin" : remotes.first else { throw GitRepository.GitError(description: "The repository has no remote.") }
                try repo.push(remote: r, tag: t)
            case .deleteTag(let t): try repo.deleteTag(t)
            case .applyStash(let s, let pop): return result(try repo.applyStash(s, pop: pop))
            case .dropStash(let s): try repo.dropStash(s)
            case .stash(let m): try repo.stash(message: m)
            case .addRemote(let n, let u): try repo.addRemote(n, url: u)
            case .removeRemote(let r): try repo.removeRemote(r)
            case .stage(let p): try repo.stage(p)
            case .unstage(let p): try repo.unstage(p)
            case .stageAll: try repo.stageAll()
            case .unstageAll: try repo.unstageAll()
            case .markResolved(let p): try repo.markResolved(p)
            case .discard(let paths): for p in paths { try repo.discard(p) }
            case .cherryPick(let c): return result(try repo.cherryPickCommit(c))
            case .continueIntegration: return result(try repo.continueIntegration())
            case .abortIntegration: try repo.abortIntegration()
            case .newRepository: break
            }
            return nil
        }, then: { [weak self] ok in self?.integrated(op, outcome.value, succeeded: ok) })
        if case .newRepository = op { known = nil }
    }

    private func enqueue(_ title: String, _ body: @escaping @Sendable (GitRepository?) throws -> String?,
                         then: (@MainActor (Bool) -> Void)? = nil) {
        let previous = queue
        queue = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            self.busy = title
            let repo = self.repository
            let outcome = await Task.detached { () -> Result<String?, GitRepository.GitError> in
                do { return .success(try body(repo)) } catch let e as GitRepository.GitError { return .failure(e) } catch {
                    return .failure(GitRepository.GitError(description: "\(error)"))
                }
            }.value
            self.busy = nil
            switch outcome {
            case .success(let n): if let n { self.notice = n }
            case .failure(let e): self.errorMessage = e.errorDescription ?? e.description
            }
            if case .success = outcome { then?(true) } else { then?(false) }
            self.refresh()
            if let r = self.reading { await r.value }
        }
    }

    public var selectedFile: String? {
        if let f = conflictEditor?.state.currentFile { return f }
        if let s = selection, s.hasPrefix("change:"), pane != nil { return String(s.dropFirst(7)) }
        return openPath.map(repoPath)
    }

    public var openPath: String?

    public var menuState: IntegrateMenuState {
        var m = IntegrateMenuState()
        let s = snapshot
        m.hasRepository = s.repository != nil
        m.hasRemote = !s.remotes.isEmpty
        m.hasUnstaged = s.changes.contains(where: \.isUnstaged)
        m.hasStaged = s.changes.contains(where: \.isStaged)
        if let p = selectedFile {
            let change = s.changes.first { $0.path == p }
            m.selectedStatus = change?.status
            m.selectedIsStaged = change?.isStaged ?? false
            m.selectedFileExists = FileManager.default.fileExists(atPath: p)
        }
        if case .history? = pane { m.selectedCommit = selectedCommit }
        m.integration = s.integration
        m.conflictCount = s.changes.filter { $0.status == .conflicted }.count
        m.otherBranchCount = mergeableBranches.count
        return m
    }

    public func isEnabled(_ selector: String) -> Bool {
        if busy != nil, selector != "refreshFileStatus:" { return false }
        if selector == "scmDiscardSelected:" { return menuState.selectedStatus != nil }
        return menuState.isEnabled(selector)
    }

    public func performIntegrate(_ selector: String) {
        let q = { (s: String) in "\u{201C}\(s)\u{201D}" }
        switch selector {
        case "showCommitSheet:": showCommitSheet()
        case "scmPush:": perform(.push(branch: nil))
        case "scmPull:": perform(.pull(branch: nil))
        case "scmFetch:": perform(.fetch(remote: nil))
        case "refreshFileStatus:": refresh()
        case "scmStageAll:": perform(.stageAll)
        case "scmUnstageAll:": perform(.unstageAll)
        case "scmMarkResolved:" where conflictEditor?.state.canMarkResolved == true: Task { await conflictEditor?.markResolved() }
        case "scmStageSelected:", "scmAddSelected:", "scmMarkResolved:": if let p = selectedFile { perform(.stage([p])) }
        case "scmUnstageSelected:": if let p = selectedFile { perform(.unstage([p])) }
        case "scmCherryPick:": if let c = selectedCommit { perform(.cherryPick(c)) }
        case "scmStash:":
            prompt = SourceControlPrompt(purpose: .stash, title: "Stash Changes", message: "Stash every change, untracked files included.",
                                         fields: [.init(label: "Message", placeholder: "Message (optional)", text: "")], button: "Stash")
        case "scmDiscardAll:":
            confirmation = SourceControlConfirmation(
                title: "Discard all changes?", message: "Tracked files return to their last commit; new files move to the Trash.",
                choices: [.init(title: "Discard All", isDestructive: true, action: .discard(snapshot.changes.map(\.path)))])
        case "scmDiscardSelected:":
            if let p = selectedFile {
                confirmation = SourceControlConfirmation(
                    title: "Discard changes in \(q((p as NSString).lastPathComponent))?", message: "The file returns to its last commit; a new file moves to the Trash.",
                    choices: [.init(title: "Discard", isDestructive: true, action: .discard([p]))])
            }
        case "scmResolveConflicts:": resolveConflicts()
        case "scmMerge:": showMergeFromMenu()
        case "scmContinueIntegration:": perform(.continueIntegration)
        case "scmAbortIntegration:": askAbort()
        case "scmNewRepository:": perform(.newRepository)
        default: break
        }
    }

    public func showCommitSheet() {
        saveEditors?()
        guard let root = repository?.root else { return }
        let files = snapshot.changes.map { c in
            CommitSheetFile(path: c.path, relativePath: c.path.hasPrefix(root.path + "/") ? String(c.path.dropFirst(root.path.count + 1)) : c.path,
                            status: c.status)
        }
        commitSheet = CommitSheet(files: files)
    }

    public func commitSheetFiles() {
        guard var sheet = commitSheet, sheet.canCommit, repository != nil else { return }
        let files = sheet.files.filter(\.isOn).map(\.path), message = sheet.message
        sheet.error = nil
        commitSheet = sheet
        let previous = queue
        queue = Task { [weak self] in
            await previous?.value
            guard let self, let repo = self.repository else { return }
            self.busy = "Committing…"
            let r = await Task.detached { () -> String? in
                do { try repo.commit(files: files, message: message); return nil } catch let e as GitRepository.GitError { return e.errorDescription } catch { return "\(error)" }
            }.value
            self.busy = nil
            if let r { self.commitSheet?.error = r } else { self.commitSheet = nil }
            self.refresh()
            if let t = self.reading { await t.value }
        }
    }

    public func showCommitEditor(focus: String?) {
        saveEditors?()
        pane = .commit(focus: focus)
        if let focus { collapsedCards.remove(focus) }
        loadCards()
    }

    public func hidePane() {
        pane = nil
    }

    private func track(_ t: Task<Void, Never>) {
        loads.removeAll { $0.isCancelled }
        loads.append(t)
    }

    func loadCards() {
        guard let repo = repository else { cards = []; return }
        let shown = Self.shown(snapshot.changes, scope: scope), scope = scope, root = repo.root
        let t = Task { [weak self] in
            let (cards, author, head) = await Task.detached { () -> ([ChangeCard], GitRepository.Author, String?) in
                let cards = shown.map { c in
                    ChangeCard(path: c.path, title: SourceControlRows.changeTitle(c.path, root: root), status: c.status, isStaged: c.isStaged,
                               lines: UnifiedDiffLines.parse(repo.diff(of: c.path, scope: scope)))
                }
                return (cards, repo.author(), repo.headHash().flatMap { repo.commit($0)?.message })
            }.value
            guard let self else { return }
            self.cards = cards
            self.author = author
            self.headMessage = head
        }
        track(t)
    }

    public func commit(andPush push: Bool = false) {
        guard canCommit else { return }
        saveEditors?()
        let message = message, amend = amend
        let stageFirst = !hasStagedChanges && !snapshot.changes.isEmpty
        enqueue("Committing…", { repo in
            guard let repo else { return nil }
            if stageFirst { try repo.stageAll() }
            try repo.commitStaged(message: message, amend: amend)
            return nil
        }, then: { [weak self] ok in
            guard ok, let self else { return }
            self.message = ""
            self.amend = false
            if push { self.perform(.push(branch: nil)) }
        })
    }

    public func stageAll() { perform(.stageAll) }

    public func askDiscard(_ path: String) {
        confirmation = SourceControlConfirmation(
            title: "Discard changes in \u{201C}\((path as NSString).lastPathComponent)\u{201D}?",
            message: "The file returns to its last commit; a new file moves to the Trash.",
            choices: [.init(title: "Discard", isDestructive: true, action: .discard([path]))])
    }

    public func toggleStaged(_ card: ChangeCard) {
        perform(card.isStaged ? .unstage([card.path]) : .stage([card.path]))
    }

    public func showHistory(ref: String, title: String, branch: String?) {
        pane = .history(ref: ref, title: title, branch: branch)
        history = []
        selectedCommit = nil
        commitDetail = nil
        loadHistory()
    }

    func loadHistory() {
        guard let repo = repository, case .history(let ref, _, let branch)? = pane else { return }
        let t = Task { [weak self] in
            let (log, info) = await Task.detached { () -> ([GitRepository.Commit], [(key: String, value: String)]) in
                let info: [(key: String, value: String)] = branch.map { b in
                    [("Name", b), ("Remote", repo.remote(of: b) ?? "No Remote"), ("Remote Branch", repo.upstream(of: b) ?? "No Remote Branch")]
                } ?? []
                return (repo.log(ref), info)
            }.value
            guard let self, case .history(let now, _, _)? = self.pane, now == ref else { return }
            self.history = log
            self.branchInfo = info
            if let s = self.selectedCommit, !log.contains(where: { $0.hash == s }) { self.selectedCommit = nil }
        }
        track(t)
    }

    func loadCommitDetail() {
        guard let repo = repository, let hash = selectedCommit, let c = history.first(where: { $0.hash == hash }) else { commitDetail = nil; return }
        let t = Task { [weak self] in
            let detail = await Task.detached { () -> CommitDetail in
                CommitDetail(commit: c, files: repo.files(in: c.hash).map { CommitFile(path: $0.path, status: $0.status) },
                             branches: repo.branches(containing: c.hash))
            }.value
            guard let self, self.selectedCommit == hash else { return }
            self.commitDetail = detail
        }
        track(t)
    }

    public var commitRows: [(key: String, value: String)] {
        guard let d = commitDetail else { return [] }
        let c = d.commit
        return [("Identifier", c.hash), ("Date", GitDates.detail(c.date)), ("Author", "\(c.authorName) <\(c.authorEmail)>"),
                ("Verification", c.verification), ("Branches", d.branches.joined(separator: "\n"))]
    }

    public func showFileHistory(for path: String?) {
        guard path != fileHistoryPath else { return }
        fileHistoryPath = path
        fileHistory = []
        if let path { loadFileHistory(path) }
    }

    func loadFileHistory(_ path: String) {
        guard let repo = repository else {
            if !hasRead { refresh() }
            return
        }
        let repoPath = repoPath(path)
        let t = Task { [weak self] in
            let log = await Task.detached { repo.history(ofFile: repoPath) }.value
            guard let self, self.fileHistoryPath == path else { return }
            self.fileHistory = log
        }
        track(t)
    }

    public func noteText(of path: String?) {
        openPath = path
        guard let path else {
            changeRegionsPath = nil
            changeRegions = []
            return
        }
        if path != changeRegionsPath {
            changeRegionsPath = path
            changeRegions = []
            if fileHistoryPath != nil { showFileHistory(for: path) }
        }
        loadRegions(for: path, delay: 0.25)
    }

    func loadRegions(for path: String, delay: Double = 0) {
        regionTask?.cancel()
        guard let repo = repository else { return }
        let cached = baselines[path], gitPath = repoPath(path)
        regionTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1e9)) }
            guard !Task.isCancelled, let self else { return }
            guard let text = self.currentText?(path) ?? (try? String(contentsOfFile: path, encoding: .utf8)) else { return }
            let base = await Task.detached { () -> (index: String?, head: String?) in
                if let cached { return cached }
                return (repo.contents(of: gitPath, at: nil), repo.contents(of: gitPath, at: "HEAD"))
            }.value
            guard !Task.isCancelled, self.changeRegionsPath == path else { return }
            self.baselines[path] = base
            let regions = await Task.detached { SourceChanges.regions(text: text, index: base.index, head: base.head) }.value
            guard !Task.isCancelled, self.changeRegionsPath == path else { return }
            if regions != self.changeRegions { self.changeRegions = regions }
        }
    }
}
