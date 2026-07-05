import Foundation

public struct BranchWorkspaceFile: Identifiable, Codable, Equatable {
    public let id: UUID
    public var path: String
    public var content: String
    public var lastModified: Date

    public init(path: String, content: String, lastModified: Date = Date()) {
        self.id = UUID()
        self.path = path
        self.content = content
        self.lastModified = lastModified
    }
}

public struct BranchWorkspaceSnapshot: Codable, Equatable {
    public var files: [BranchWorkspaceFile]
    public var metadata: [String: String]
    public var basedOnBranchID: UUID?
    public var lastCommitID: UUID?

    public init(files: [BranchWorkspaceFile] = [], metadata: [String: String] = [:], basedOnBranchID: UUID? = nil, lastCommitID: UUID? = nil) {
        self.files = files
        self.metadata = metadata
        self.basedOnBranchID = basedOnBranchID
        self.lastCommitID = lastCommitID
    }
}

public struct BranchWorkspace: Identifiable, Codable, Equatable {
    public let id: UUID
    public let branchID: UUID
    public var branchName: String
    public var workingDirectory: String
    public var baseBranchID: UUID?
    public var files: [BranchWorkspaceFile]
    public var metadata: [String: String]
    public var lastCommitID: UUID?
    public var pendingChanges: [CommitFileChange]
    public var updatedAt: Date

    public init(branchID: UUID, branchName: String, workingDirectory: String, baseBranchID: UUID?, files: [BranchWorkspaceFile], metadata: [String: String], lastCommitID: UUID?, pendingChanges: [CommitFileChange], updatedAt: Date = Date()) {
        self.id = branchID
        self.branchID = branchID
        self.branchName = branchName
        self.workingDirectory = workingDirectory
        self.baseBranchID = baseBranchID
        self.files = files
        self.metadata = metadata
        self.lastCommitID = lastCommitID
        self.pendingChanges = pendingChanges
        self.updatedAt = updatedAt
    }
}

public struct PullRequestDiffEntry: Equatable {
    public let path: String
    public let diff: String

    public init(path: String, diff: String) {
        self.path = path
        self.diff = diff
    }
}

public struct PullRequestDraftPayload: Equatable {
    public let sourceBranchID: UUID
    public let targetBranchID: UUID
    public let title: String
    public let description: String
    public let linkedCommitIDs: [UUID]
    public let diffEntries: [PullRequestDiffEntry]
}

@MainActor
public final class BranchWorkspaceManager: ObservableObject {
    @Published public private(set) var workspaces: [UUID: BranchWorkspace] = [:]
    @Published public private(set) var currentWorkspaceID: UUID?
    @Published public private(set) var isLoadingWorkspace = false
    @Published public private(set) var lastErrorMessage: String?
    @Published public private(set) var lastSuccessMessage: String?

    private let branchManager: BranchManager
    private let commitManager: CommitManager
    private let pullRequestManager: PullRequestManager
    private var project: Project?

    public init(branchManager: BranchManager, commitManager: CommitManager, pullRequestManager: PullRequestManager) {
        self.branchManager = branchManager
        self.commitManager = commitManager
        self.pullRequestManager = pullRequestManager
    }

    public func setProject(_ project: Project) {
        self.project = project
        seedMainWorkspaceIfNeeded()
    }

    public var currentWorkspace: BranchWorkspace? {
        guard let currentWorkspaceID else { return nil }
        return workspaces[currentWorkspaceID]
    }

    public func createWorkspace(for branch: Branch, from baseBranchID: UUID? = nil, actorID: String = "System") -> BranchWorkspace {
        let sourceBranchID = baseBranchID ?? branchManager.currentBranch.id
        let sourceWorkspace = workspaces[sourceBranchID] ?? makeWorkspace(for: branchManager.branches.first(where: { $0.id == sourceBranchID }) ?? branch)
        let workspace = BranchWorkspace(
            branchID: branch.id,
            branchName: branch.name,
            workingDirectory: "/DerivedData/Collaboration/\(branch.name.replacingOccurrences(of: " ", with: "-"))",
            baseBranchID: sourceBranchID,
            files: sourceWorkspace.files,
            metadata: sourceWorkspace.metadata.merging([
                "createdBy": actorID,
                "createdAt": Date().formatted(date: .abbreviated, time: .shortened)
            ]) { _, new in new },
            lastCommitID: branch.lastCommitID ?? sourceWorkspace.lastCommitID,
            pendingChanges: []
        )
        workspaces[branch.id] = workspace
        currentWorkspaceID = branch.id
        if branchManager.currentBranch.id != branch.id {
            branchManager.switchBranch(to: branch.id, actorID: actorID)
        }
        commitManager.replaceWorkingChanges([], stagedChanges: [:], for: branch.id)
        publishSuccess("Workspace created for \(branch.name).")
        return workspace
    }

    @discardableResult
    public func loadWorkspace(for branchID: UUID, actorID: String = "System") -> BranchWorkspace? {
        isLoadingWorkspace = true
        defer { isLoadingWorkspace = false }

        if workspaces[branchID] == nil, let branch = branchManager.branches.first(where: { $0.id == branchID }) {
            workspaces[branchID] = makeWorkspace(for: branch)
        }

        guard let workspace = workspaces[branchID] else {
            publishError("Unable to load the selected branch workspace.")
            return nil
        }

        currentWorkspaceID = branchID
        if branchManager.currentBranch.id != branchID {
            branchManager.switchBranch(to: branchID, actorID: actorID)
        }
        commitManager.replaceWorkingChanges(workspace.pendingChanges, stagedChanges: Dictionary(uniqueKeysWithValues: workspace.pendingChanges.filter(\.isStaged).map { ($0.path, $0.diff) }), for: branchID)
        publishSuccess("Loaded \(workspace.branchName) Workspace.")
        return workspace
    }

    public func updateFile(path: String, content: String, authorID: String) {
        guard var workspace = currentWorkspace else { return }
        if let index = workspace.files.firstIndex(where: { $0.path == path }) {
            workspace.files[index].content = content
            workspace.files[index].lastModified = Date()
        } else {
            workspace.files.append(BranchWorkspaceFile(path: path, content: content))
        }
        let diff = "@@ \(path) @@\n\(content)"
        commitManager.updateWorkingChange(path: path, diff: diff, kind: .modified, authorID: authorID, branchID: workspace.branchID)
        workspace.pendingChanges = commitManager.workingChanges(for: workspace.branchID)
        workspace.updatedAt = Date()
        workspaces[workspace.branchID] = workspace
        publishSuccess("Updated \(path).")
    }

    public func createFile(path: String, content: String = "", authorID: String) {
        guard var workspace = currentWorkspace else { return }
        guard workspace.files.contains(where: { $0.path == path }) == false else {
            publishError("A file already exists at \(path).")
            return
        }
        workspace.files.append(BranchWorkspaceFile(path: path, content: content))
        commitManager.updateWorkingChange(path: path, diff: "+\(content)", kind: .added, authorID: authorID, branchID: workspace.branchID)
        workspace.pendingChanges = commitManager.workingChanges(for: workspace.branchID)
        workspace.updatedAt = Date()
        workspaces[workspace.branchID] = workspace
        publishSuccess("Created \(path).")
    }

    public func deleteFile(path: String, authorID: String) {
        guard var workspace = currentWorkspace else { return }
        guard let index = workspace.files.firstIndex(where: { $0.path == path }) else {
            publishError("The selected file no longer exists.")
            return
        }
        let removed = workspace.files.remove(at: index)
        commitManager.updateWorkingChange(path: path, diff: "-\(removed.content)", kind: .deleted, authorID: authorID, branchID: workspace.branchID)
        workspace.pendingChanges = commitManager.workingChanges(for: workspace.branchID)
        workspace.updatedAt = Date()
        workspaces[workspace.branchID] = workspace
        publishSuccess("Deleted \(path).")
    }

    public func discardChanges(for branchID: UUID? = nil) {
        guard let branchID = branchID ?? currentWorkspaceID,
              var workspace = workspaces[branchID] else { return }
        let snapshot = lastCommittedSnapshot(for: branchID)
        workspace.files = snapshot.files
        workspace.metadata = snapshot.metadata
        workspace.lastCommitID = snapshot.lastCommitID
        workspace.pendingChanges = []
        workspace.updatedAt = Date()
        workspaces[branchID] = workspace
        commitManager.replaceWorkingChanges([], stagedChanges: [:], for: branchID)
        publishSuccess("Discarded uncommitted changes on \(workspace.branchName).")
    }

    public func resetToLastCommit(branchID: UUID? = nil) {
        discardChanges(for: branchID)
    }

    public func reset(branchID: UUID? = nil, toMatch sourceBranchID: UUID) {
        guard let branchID = branchID ?? currentWorkspaceID,
              var workspace = workspaces[branchID],
              let source = workspaces[sourceBranchID] ?? branchManager.branches.first(where: { $0.id == sourceBranchID }).map(makeWorkspace(for:)) else { return }
        workspace.files = source.files
        workspace.metadata = source.metadata
        workspace.lastCommitID = source.lastCommitID
        workspace.pendingChanges = []
        workspace.updatedAt = Date()
        workspaces[branchID] = workspace
        commitManager.replaceWorkingChanges([], stagedChanges: [:], for: branchID)

        // If we reset the main branch, we should potentially update the project on disk
        if workspace.branchName == "main", let project = project {
            syncMainToDisk(workspace: workspace, project: project)
        }

        publishSuccess("Reset \(workspace.branchName) to match \(source.branchName).")
    }

    private func syncMainToDisk(workspace: BranchWorkspace, project: Project) {
        let root = project.directoryURL
        for file in workspace.files {
            let fileURL = root.appendingPathComponent(file.path)
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? file.content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    public func commitCurrentWorkspace(message: String, authorID: String) -> Commit? {
        guard let workspace = currentWorkspace else { return nil }
        let changes = Dictionary(uniqueKeysWithValues: commitManager.workingChanges(for: workspace.branchID).map { ($0.path, $0.diff) })
        guard changes.isEmpty == false else {
            publishError("There are no changes to commit.")
            return nil
        }
        let commit = commitManager.recordCommit(branchID: workspace.branchID, authorID: authorID, message: message, changes: changes)
        branchManager.updateLastCommit(for: workspace.branchID, commitID: commit.id)
        var updated = workspace
        updated.lastCommitID = commit.id
        updated.pendingChanges = []
        updated.updatedAt = Date()
        workspaces[workspace.branchID] = updated
        publishSuccess("Committed changes on \(workspace.branchName).")
        return commit
    }

    public func preparePullRequestPayload(targetBranchID: UUID, actorID: String) -> PullRequestDraftPayload? {
        guard let workspace = currentWorkspace,
              let targetWorkspace = workspaces[targetBranchID] ?? branchManager.branches.first(where: { $0.id == targetBranchID }).map(makeWorkspace(for:)) else { return nil }

        let commits = commitManager.commits(for: workspace.branchID)

        var diffEntries: [PullRequestDiffEntry] = []
        let sourceFiles = workspace.files
        let targetFiles = targetWorkspace.files

        let allPaths = Set(sourceFiles.map { $0.path }).union(targetFiles.map { $0.path })

        for path in allPaths.sorted() {
            let sourceFile = sourceFiles.first(where: { $0.path == path })
            let targetFile = targetFiles.first(where: { $0.path == path })

            if sourceFile?.content != targetFile?.content {
                let diff = generateDiff(from: targetFile?.content ?? "", to: sourceFile?.content ?? "", path: path)
                diffEntries.append(PullRequestDiffEntry(path: path, diff: diff))
            }
        }

        let title = "\(workspace.branchName) → \(targetWorkspace.branchName)"
        let description = "Prepared by \(actorID) from isolated workspace \(workspace.workingDirectory).\n\nFiles changed: \(diffEntries.count)."
        return PullRequestDraftPayload(sourceBranchID: workspace.branchID, targetBranchID: targetBranchID, title: title, description: description, linkedCommitIDs: commits.map(\.id), diffEntries: diffEntries)
    }

    private func generateDiff(from oldContent: String, to newContent: String, path: String) -> String {
        if oldContent == newContent { return "No changes" }
        if oldContent.isEmpty { return "@@ \(path) @@\n+\(newContent)" }
        if newContent.isEmpty { return "@@ \(path) @@\n-\(oldContent)" }

        let oldLines = oldContent.components(separatedBy: .newlines)
        let newLines = newContent.components(separatedBy: .newlines)

        var diff = "@@ \(path) @@\n"
        let maxLines = max(oldLines.count, newLines.count)

        for i in 0..<maxLines {
            let oldLine = i < oldLines.count ? oldLines[i] : nil
            let newLine = i < newLines.count ? newLines[i] : nil

            if oldLine != newLine {
                if let old = oldLine { diff += "-\(old)\n" }
                if let new = newLine { diff += "+\(new)\n" }
            } else if let line = oldLine {
                // Show context lines only if they are near a change?
                // For simplicity, just show the line as is
                diff += " \(line)\n"
            }

            // Limit diff size to avoid massive strings
            if diff.count > 10000 {
                diff += "... diff truncated ..."
                break
            }
        }

        return diff
    }

    public func syncWorkspaceStateFromCommitManager() {
        for (branchID, var workspace) in workspaces {
            workspace.pendingChanges = commitManager.workingChanges(for: branchID)
            workspace.lastCommitID = branchManager.branches.first(where: { $0.id == branchID })?.lastCommitID
            workspaces[branchID] = workspace
        }
    }

    private func seedMainWorkspaceIfNeeded() {
        let branch = branchManager.currentBranch
        if workspaces[branch.id] == nil {
            workspaces[branch.id] = makeWorkspace(for: branch)
            currentWorkspaceID = branch.id
        }
    }

    private func makeWorkspace(for branch: Branch) -> BranchWorkspace {
        var workspace = BranchWorkspace(
            branchID: branch.id,
            branchName: branch.name,
            workingDirectory: "/DerivedData/Collaboration/\(branch.name)",
            baseBranchID: nil,
            files: [],
            metadata: [:],
            lastCommitID: branch.lastCommitID,
            pendingChanges: commitManager.workingChanges(for: branch.id)
        )

        let snapshot = lastCommittedSnapshot(for: branch.id)
        if snapshot.files.isEmpty && branch.name == "main" {
            // Initial seeding from project disk
            let realFiles = scanProjectFiles()
            workspace.files = realFiles
        } else {
            workspace.files = snapshot.files
            workspace.lastCommitID = branch.lastCommitID ?? snapshot.lastCommitID
        }

        workspace.metadata = snapshot.metadata
        return workspace
    }

    private func lastCommittedSnapshot(for branchID: UUID) -> BranchWorkspaceSnapshot {
        let commits = commitManager.commits(for: branchID)
        let latestCommit = commits.first
        let fileMap = commits.reversed().reduce(into: [String: String]()) { partialResult, commit in
            commit.changes.forEach { partialResult[$0.key] = $0.value }
        }
        let files = fileMap.keys.sorted().map { path in
            BranchWorkspaceFile(path: path, content: fileMap[path] ?? "")
        }
        return BranchWorkspaceSnapshot(files: files, metadata: ["branchID": branchID.uuidString], basedOnBranchID: branchID, lastCommitID: latestCommit?.id)
    }

    private func scanProjectFiles() -> [BranchWorkspaceFile] {
        guard let project = project else { return [] }
        var files: [BranchWorkspaceFile] = []
        let root = project.directoryURL

        func scan(at url: URL) {
            guard let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) else { return }
            for item in contents {
                if item.lastPathComponent == "project.json" { continue }
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir) {
                    if isDir.boolValue {
                        scan(at: item)
                    } else {
                        if let content = try? String(contentsOf: item, encoding: .utf8) {
                            let relativePath = item.path.replacingOccurrences(of: root.path + "/", with: "")
                            files.append(BranchWorkspaceFile(path: relativePath, content: content))
                        }
                    }
                }
            }
        }

        scan(at: root)
        return files
    }

    private func publishError(_ message: String) {
        lastErrorMessage = message
        lastSuccessMessage = nil
    }

    private func publishSuccess(_ message: String) {
        lastSuccessMessage = message
        lastErrorMessage = nil
    }
}
