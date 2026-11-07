import Foundation

public struct BranchEvent: Equatable {
    public let actorID: String
    public let title: String
    public let detail: String
    public let notifies: Bool
}

public struct BranchMerge: Identifiable, Codable, Equatable {
    public let id: UUID
    public let sourceBranchID: UUID
    public let targetBranchID: UUID
    public let commitID: UUID
    public let timestamp: Date

    public init(sourceBranchID: UUID, targetBranchID: UUID, commitID: UUID) {
        self.id = UUID()
        self.sourceBranchID = sourceBranchID
        self.targetBranchID = targetBranchID
        self.commitID = commitID
        self.timestamp = Date()
    }
}

public struct Branch: Identifiable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var lastCommitID: UUID?
    public let createdAt: Date

    public init(name: String, lastCommitID: UUID? = nil) {
        self.id = UUID()
        self.name = name
        self.lastCommitID = lastCommitID
        self.createdAt = Date()
    }
}

@MainActor
public final class BranchManager: ObservableObject {
    @Published public private(set) var branches: [Branch] = []
    @Published public private(set) var currentBranch: Branch
    @Published public private(set) var merges: [BranchMerge] = []
    @Published public private(set) var lastEvent: BranchEvent?

    public init(mainBranchName: String = "main") {
        let main = Branch(name: mainBranchName)
        self.branches = [main]
        self.currentBranch = main
    }

    public func createBranch(name: String, from baseBranchID: UUID? = nil, actorID: String = "System") -> Branch {
        let baseBranch = branches.first(where: { $0.id == (baseBranchID ?? currentBranch.id) })
        let newBranch = Branch(name: name, lastCommitID: baseBranch?.lastCommitID)
        branches.append(newBranch)
        let baseName = baseBranch?.name ?? currentBranch.name
        lastEvent = BranchEvent(actorID: actorID, title: "Branch Created", detail: "\(name) was created from \(baseName).", notifies: true)
        return newBranch
    }

    public func switchBranch(to branchID: UUID, actorID: String = "System") {
        if let branch = branches.first(where: { $0.id == branchID }) {
            currentBranch = branch
            lastEvent = BranchEvent(actorID: actorID, title: "Branch Switched", detail: "Now working on \(branch.name).", notifies: false)
        }
    }

    public func deleteBranch(_ branchID: UUID, actorID: String = "System") {
        guard branches.count > 1 else { return }
        guard let branch = branches.first(where: { $0.id == branchID }) else { return }
        if currentBranch.id == branchID, let fallback = branches.first(where: { $0.id != branchID }) {
            currentBranch = fallback
        }
        branches.removeAll { $0.id == branchID }
        merges.removeAll { $0.sourceBranchID == branchID || $0.targetBranchID == branchID }
        lastEvent = BranchEvent(actorID: actorID, title: "Branch Deleted", detail: "\(branch.name) was removed.", notifies: true)
    }

    public func renameBranch(_ branchID: UUID, to newName: String, actorID: String = "System") {
        if let index = branches.firstIndex(where: { $0.id == branchID }) {
            let oldName = branches[index].name
            branches[index].name = newName
            if currentBranch.id == branchID { currentBranch = branches[index] }
            lastEvent = BranchEvent(actorID: actorID, title: "Branch Renamed", detail: "\(oldName) is now \(newName).", notifies: false)
        }
    }

    public func updateLastCommit(for branchID: UUID, commitID: UUID) {
        if let index = branches.firstIndex(where: { $0.id == branchID }) {
            branches[index].lastCommitID = commitID
            if currentBranch.id == branchID { currentBranch = branches[index] }
        }
    }

    public func restoreState(branches: [Branch], currentBranchID: UUID, merges: [BranchMerge]) {
        self.branches = branches
        if let current = branches.first(where: { $0.id == currentBranchID }) {
            self.currentBranch = current
        }
        self.merges = merges
    }

    public func registerMerge(from sourceID: UUID, into targetID: UUID, commitID: UUID, actorID: String) {
        updateLastCommit(for: targetID, commitID: commitID)
        let merge = BranchMerge(sourceBranchID: sourceID, targetBranchID: targetID, commitID: commitID)
        merges.insert(merge, at: 0)
        let sourceName = branches.first(where: { $0.id == sourceID })?.name ?? "source"
        let targetName = branches.first(where: { $0.id == targetID })?.name ?? "target"
        lastEvent = BranchEvent(actorID: actorID, title: "Branches Merged", detail: "Merged \(sourceName) into \(targetName).", notifies: true)
    }
}
