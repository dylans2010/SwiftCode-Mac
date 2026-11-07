import Foundation
import Observation
import YcodeIDECore

@MainActor
@Observable
public final class ConflictEditorShellModel {
    @ObservationIgnored public let repository: GitRepository
    public internal(set) var state = ConflictEditorState(source: .repository)
    public var isFlat = false
    public var filterText = ""
    public private(set) var revealCount = 0
    @ObservationIgnored public let isPackage: Bool
    public var editedText: String {
        get { editorText }
        set {
            editorText = newValue
            state.setEditedText(newValue)
        }
    }
    private var editorText = ""

    @ObservationIgnored public var onResolved: (() -> Void)?

    @ObservationIgnored private var pending: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var nextPending = 0
    @ObservationIgnored private var showGeneration = 0
    @ObservationIgnored private let focus: String?

    public init(repository: GitRepository, focus: String? = nil) {
        self.repository = repository
        self.focus = focus
        isPackage = FileManager.default.fileExists(atPath: repository.root.appendingPathComponent("Package.swift").path)
    }

    public var isLoading: Bool { !pending.isEmpty }

    public var fileRows: [ConflictEditorState.FileRow] {
        state.fileRows(root: repository.root.path, flat: isFlat, filter: filterText)
    }

    public var jumpPath: [String] { state.jumpPath(root: repository.root.path) }

    public func reload() {
        let repo = repository, wanted = state.currentFile ?? focus
        let known = Set(state.files.filter { state.sheetDocument($0) != nil })
        track { [weak self] in
            let read = await Task.detached { () -> ([String], GitRepository.IntegrationState, (MergeSheetFooter?, MergeSheetFooter?), [String: MergeDocument]) in
                let files = repo.conflictedFiles(), integration = repo.integrationState()
                let labels = repo.conflictLabels(integration)
                let footers = MergeSheetFooter.read(repo, integration: integration, oursLabel: labels.ours, theirsLabel: labels.theirs)
                var docs: [String: MergeDocument] = [:]
                for f in files where !known.contains(f) { docs[f] = repo.mergeDocument(forConflictedFile: f) }
                return (files, integration, footers, docs)
            }.value
            guard let self else { return }
            _ = self.state.update(integration: read.1, conflicted: read.0)
            self.state.files = read.0
            self.state.leftFooter = read.2.0
            self.state.rightFooter = read.2.1
            for (f, d) in read.3 { self.state.prefetch(file: f, document: d) }
            let target = ConflictEditorState.target(wanted: wanted, in: read.0)
            if target != self.state.currentFile || self.state.document == nil {
                self.state.show(file: target, document: target.flatMap { read.3[$0] })
                self.editorText = self.state.editedText
            }
        }
    }

    public func update(integration: GitRepository.IntegrationState, conflicted: [String]) {
        guard pending.isEmpty else { return }
        if conflicted != state.files {
            reload()
        } else {
            state.integration = integration
        }
    }

    public func show(file: String?) async {
        let repo = repository
        guard let file else {
            state.show(file: nil, document: nil)
            editorText = ""
            return
        }
        if file == state.currentFile, state.document != nil { return }
        if state.sheetDocument(file) != nil {
            state.show(file: file, document: nil)
            editorText = state.editedText
            return
        }
        showGeneration += 1
        let generation = showGeneration
        await track { [weak self] in
            let doc = await Task.detached { repo.mergeDocument(forConflictedFile: file) }.value
            guard let self, generation == self.showGeneration else { return }
            self.state.show(file: file, document: doc)
            self.editorText = self.state.editedText
        }.value
    }

    public func showFile(_ path: String) {
        track { [weak self] in await self?.show(file: path) }
    }

    @discardableResult
    func track(_ body: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        nextPending += 1
        let id = nextPending
        let t = Task { @MainActor [weak self] in
            await body()
            self?.pending[id] = nil
        }
        pending[id] = t
        return t
    }

    public func idle() async {
        while let t = pending.values.first { await t.value }
    }

    public func selectHunk(_ h: Int?) { state.selectHunk(h); editorText = state.editedText }
    public func nextHunk() { state.nextHunk(); editorText = state.editedText; revealCount += 1 }
    public func previousHunk() { state.previousHunk(); editorText = state.editedText; revealCount += 1 }

    public func choose(_ choice: MergeDocument.Choice, forHunk h: Int) {
        state.choose(choice, forHunk: h)
        editorText = state.editedText
    }

    public func choose(_ choice: MergeDocument.Choice) {
        state.chooseKeepingSelection(choice)
        editorText = state.editedText
    }

    public func beginEditing() {
        state.beginEditing()
        editorText = state.editedText
    }

    @discardableResult
    public func markResolved() async -> Bool {
        guard state.canMarkResolved, let file = state.currentFile, let doc = state.document else { return false }
        let repo = repository, text = doc.result
        await track { [weak self] in
            let error = await Task.detached { () -> String? in
                do { try repo.resolveConflict(file, text: text); return nil } catch let e as GitRepository.GitError {
                    return e.errorDescription ?? e.description
                } catch { return "\(error)" }
            }.value
            self?.state.lastError = error
        }.value
        guard state.lastError == nil else { return false }
        onResolved?()
        reload()
        await idle()
        return true
    }

    public func writeResolutions() async -> String? {
        let repo = repository, items = state.resolutions
        var error: String?
        await track {
            error = await Task.detached { () -> String? in
                for r in items {
                    do { try repo.resolveConflict(r.file, text: r.text) } catch let e as GitRepository.GitError {
                        return e.errorDescription ?? e.description
                    } catch { return "\(error)" }
                }
                return nil
            }.value
        }.value
        state.lastError = error
        return error
    }
}
