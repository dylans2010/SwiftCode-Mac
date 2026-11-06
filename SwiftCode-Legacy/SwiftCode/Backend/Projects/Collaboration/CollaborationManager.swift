import Foundation
import Combine
import MultipeerConnectivity

public struct CollaborationActivity: Identifiable, Codable, Equatable {
    public enum Kind: String, Codable {
        case branch
        case commit
        case review
        case pullRequest
        case sync
        case invite
        case permissions
        case conflict
        case fileLock
        case chat
    }

    public let id: UUID
    public let timestamp: Date
    public let actorID: String
    public let title: String
    public let detail: String
    public let kind: Kind

    public init(actorID: String, title: String, detail: String, kind: Kind, timestamp: Date = Date()) {
        self.id = UUID()
        self.timestamp = timestamp
        self.actorID = actorID
        self.title = title
        self.detail = detail
        self.kind = kind
    }
}

public struct CollaborationNotificationItem: Identifiable, Codable, Equatable {
    public let id: UUID
    public let title: String
    public let detail: String
    public let timestamp: Date
    public var isRead: Bool

    public init(title: String, detail: String, timestamp: Date = Date(), isRead: Bool = false) {
        self.id = UUID()
        self.title = title
        self.detail = detail
        self.timestamp = timestamp
        self.isRead = isRead
    }
}

public struct UserPresence: Identifiable, Codable, Equatable {
    public let id: String
    public var lastSeen: Date
    public var currentFile: String?
    public var cursorPosition: Int?
    public var selectionRange: NSRange?

    public init(id: String, lastSeen: Date = Date(), currentFile: String? = nil, cursorPosition: Int? = nil, selectionRange: NSRange? = nil) {
        self.id = id
        self.lastSeen = lastSeen
        self.currentFile = currentFile
        self.cursorPosition = cursorPosition
        self.selectionRange = selectionRange
    }
}

@MainActor
public final class CollaborationManager: ObservableObject {
    public let project: Project
    public var projectID: UUID { project.id }
    public let creatorID: String
    public let permissions: PermissionsManager
    public let branches: BranchManager
    public let commits: CommitManager
    public let pushes: PushManager
    public let reviews: CollaborationCodeReviewManager
    public let invites: InviteManager
    public let pullRequests: PullRequestManager
    public let workspaces: BranchWorkspaceManager

    @Published public private(set) var activityLog: [CollaborationActivity] = []
    @Published public private(set) var notifications: [CollaborationNotificationItem] = []
    @Published public private(set) var pendingConflicts: [BranchConflict] = []
    @Published public private(set) var fileLocks: [FileLock] = []
    @Published public private(set) var activeUsers: [UserPresence] = []

    private var cancellables = Set<AnyCancellable>()

    public init(project: Project, creatorID: String) {
        self.project = project
        self.creatorID = creatorID
        self.permissions = PermissionsManager(creatorID: creatorID)
        self.branches = BranchManager()
        self.commits = CommitManager()
        self.pushes = PushManager()
        self.reviews = CollaborationCodeReviewManager()
        self.invites = InviteManager()
        self.pullRequests = PullRequestManager()
        self.workspaces = BranchWorkspaceManager(branchManager: branches, commitManager: commits, pullRequestManager: pullRequests)

        setupBindings()
        workspaces.setProject(project)
        loadState()

        PeerSessionManager.shared.onData = { [weak self] data, peerID in
            self?.handleIncomingData(data, from: peerID)
        }

        addActivity(actorID: creatorID, title: "Collaboration Enabled", detail: "Project collaboration workspace is ready.", kind: .permissions, notify: true)
        commits.setActiveBranch(branches.currentBranch.id)
        _ = workspaces.loadWorkspace(for: branches.currentBranch.id, actorID: creatorID)

        startPresenceHeartbeat()
    }

    private func handleIncomingData(_ data: Data, from peerID: MCPeerID) {
        if let state = try? JSONDecoder().decode(ProjectState.self, from: data) {
            if state.activityLog.count > self.activityLog.count {
                self.restoreStateFromObject(state)
                saveState()
                addActivity(actorID: peerID.displayName, title: "Synced From Peer", detail: "Project state updated to match \(peerID.displayName).", kind: .sync, notify: true)
            }
        } else if let presence = try? JSONDecoder().decode(UserPresence.self, from: data) {
            updateUserPresence(presence)
        }
    }

    private func restoreStateFromObject(_ state: ProjectState) {
        self.activityLog = state.activityLog
        self.notifications = state.notifications
        branches.restoreState(branches: state.branches, currentBranchID: state.currentBranchID, merges: state.merges)
        commits.restoreState(commits: state.commits)
        commits.setActiveBranch(state.currentBranchID)
        pullRequests.restoreState(pullRequests: state.pullRequests)
        reviews.restoreState(reviews: state.reviews)
        permissions.restoreState(memberRoles: state.memberRoles)
        commits.setActiveBranch(branches.currentBranch.id)
        commits.seedWorkingChangesIfNeeded(authorID: creatorID, branchID: branches.currentBranch.id)
        _ = workspaces.loadWorkspace(for: branches.currentBranch.id, actorID: creatorID)
        invites.restoreState(invites: state.invites)
    }

    private func setupBindings() {
        branches.$currentBranch
            .sink { [weak self] branch in
                self?.commits.setActiveBranch(branch.id)
                _ = self?.workspaces.loadWorkspace(for: branch.id)
            }
            .store(in: &cancellables)

        branches.$lastEvent
            .compactMap { $0 }
            .sink { [weak self] event in
                self?.addActivity(actorID: event.actorID, title: event.title, detail: event.detail, kind: .branch, notify: event.notifies)
            }
            .store(in: &cancellables)

        commits.$lastEvent
            .compactMap { $0 }
            .sink { [weak self] event in
                self?.addActivity(actorID: event.actorID, title: event.title, detail: event.detail, kind: .commit, notify: event.notifies)
            }
            .store(in: &cancellables)

        pushes.$lastEvent
            .compactMap { $0 }
            .sink { [weak self] event in
                self?.addActivity(actorID: event.actorID, title: event.title, detail: event.detail, kind: .sync, notify: event.notifies)
            }
            .store(in: &cancellables)

        reviews.$lastEvent
            .compactMap { $0 }
            .sink { [weak self] event in
                self?.addActivity(actorID: event.actorID, title: event.title, detail: event.detail, kind: .review, notify: event.notifies)
            }
            .store(in: &cancellables)

        permissions.$lastEvent
            .compactMap { $0 }
            .sink { [weak self] event in
                self?.addActivity(actorID: event.actorID, title: event.title, detail: event.detail, kind: .permissions, notify: event.notifies)
            }
            .store(in: &cancellables)

        invites.$lastEvent
            .compactMap { $0 }
            .sink { [weak self] event in
                self?.addActivity(actorID: event.actorID, title: event.title, detail: event.detail, kind: .invite, notify: event.notifies)
            }
            .store(in: &cancellables)

        pullRequests.$lastEvent
            .compactMap { $0 }
            .sink { [weak self] event in
                self?.addActivity(actorID: event.actorID, title: event.title, detail: event.detail, kind: .pullRequest, notify: event.notifies)
            }
            .store(in: &cancellables)
    }

    public func commit(message: String, authorID: String, changes: [String: String]) {
        guard permissions.hasPermission(.commit, for: authorID, projectPermission: .owner) else { return }
        let commit = commits.recordCommit(branchID: branches.currentBranch.id, authorID: authorID, message: message, changes: changes)
        workspaces.syncWorkspaceStateFromCommitManager()
        branches.updateLastCommit(for: branches.currentBranch.id, commitID: commit.id)
        reviews.initiateReview(for: commit.id)
    }

    public func merge(branch sourceID: UUID, into targetID: UUID, actorID: String, pullRequestID: UUID? = nil) {
        guard permissions.hasPermission(.merge, for: actorID, projectPermission: .owner) else { return }
        if let mergedCommit = commits.merge(branchID: sourceID, into: targetID, authorID: actorID) {
            branches.registerMerge(from: sourceID, into: targetID, commitID: mergedCommit.id, actorID: actorID)
            workspaces.reset(branchID: targetID, toMatch: sourceID)
            workspaces.syncWorkspaceStateFromCommitManager()
            reviews.initiateReview(for: mergedCommit.id)
            if let pullRequestID {
                pullRequests.markMerged(prID: pullRequestID, mergeCommitID: mergedCommit.id, actorID: actorID)
            }
        }
    }

    public func createPullRequest(sourceID: UUID, targetID: UUID, title: String, description: String, actorID: String, status: PullRequestStatus = .open, linkedCommitIDs: [UUID] = [], conflictSummary: String? = nil) {
        guard permissions.hasPermission(.branchCreateDelete, for: actorID, projectPermission: .owner) else { return }
        _ = pullRequests.createPullRequest(sourceBranchID: sourceID, targetBranchID: targetID, title: title, description: description, actorID: actorID, status: status, linkedCommitIDs: linkedCommitIDs, conflictSummary: conflictSummary)
    }

    public func syncCurrentBranch(actorID: String) async {
        guard permissions.hasPermission(.push, for: actorID, projectPermission: .owner) else { return }
        let branchName = branches.currentBranch.name
        let localCommits = commits.commits(for: branches.currentBranch.id).count
        let remoteCommits = max(0, localCommits - 1)
        let conflict = pushes.prepareSync(branchName: branchName, actorID: actorID, localCommitCount: localCommits, remoteCommitCount: remoteCommits)
        if let conflict {
            pendingConflicts.removeAll { $0.id == conflict.id }
            pendingConflicts.append(conflict)
            addActivity(actorID: actorID, title: "Conflict Detected", detail: "\(conflict.filePath) requires resolution on \(branchName).", kind: .conflict, notify: true)
        }

        let state = ProjectState(
            projectID: project.id,
            creatorID: creatorID,
            activityLog: activityLog,
            notifications: notifications,
            branches: branches.branches,
            currentBranchID: branches.currentBranch.id,
            merges: branches.merges,
            commits: commits.commits,
            pullRequests: pullRequests.pullRequests,
            reviews: reviews.reviews,
            memberRoles: permissions.memberRoles,
            invites: invites.invites
        )
        let data = try? JSONEncoder().encode(state)

        await pushes.push(branchName: branchName, actorID: actorID, data: data)
        await pushes.pull(branchName: branchName, actorID: actorID)
    }

    public func resolveConflict(_ conflictID: UUID, using resolution: ConflictResolutionChoice, actorID: String) {
        guard let index = pendingConflicts.firstIndex(where: { $0.id == conflictID }) else { return }
        let conflict = pendingConflicts.remove(at: index)
        pushes.resolveConflict(conflictID, using: resolution, actorID: actorID)
        addActivity(actorID: actorID, title: "Conflict Resolved", detail: "Resolved \(conflict.filePath) using \(resolution.displayName).", kind: .conflict, notify: true)
    }

    public func lockFile(path: String, actorID: String) {
        guard permissions.hasPermission(.editFiles, for: actorID, projectPermission: .owner) else { return }
        guard fileLocks.contains(where: { $0.path == path }) == false else { return }
        let lock = FileLock(path: path, lockedBy: actorID)
        fileLocks.append(lock)
        addActivity(actorID: actorID, title: "File Locked", detail: "\(path) is now locked for editing.", kind: .fileLock, notify: true)
    }

    public func unlockFile(path: String, actorID: String) {
        guard let index = fileLocks.firstIndex(where: { $0.path == path }) else { return }
        let lock = fileLocks[index]
        guard lock.lockedBy == actorID || permissions.memberRoles[actorID] == .owner || permissions.memberRoles[actorID] == .admin else { return }
        fileLocks.remove(at: index)
        addActivity(actorID: actorID, title: "File Unlocked", detail: "\(path) is available for collaborators again.", kind: .fileLock, notify: false)
    }

    public func invite(memberID: String, role: CollaborationRole, actorID: String) {
        guard permissions.canManageMembers(actorID: actorID) else { return }
        invites.createInvite(memberID: memberID, role: role, actorID: actorID)
        permissions.assignRole(role, to: memberID, by: actorID)
    }

    public func markNotificationRead(_ notificationID: UUID) {
        guard let index = notifications.firstIndex(where: { $0.id == notificationID }) else { return }
        notifications[index].isRead = true
    }

    public func addActivity(actorID: String, title: String, detail: String, kind: CollaborationActivity.Kind, notify: Bool) {
        let activity = CollaborationActivity(actorID: actorID, title: title, detail: detail, kind: kind)
        activityLog.insert(activity, at: 0)
        if notify {
            notifications.insert(CollaborationNotificationItem(title: title, detail: detail), at: 0)
        }
        saveState()
    }

    // MARK: - Presence Management

    public func broadcastPresence(currentFile: String? = nil, cursorPosition: Int? = nil, selectionRange: NSRange? = nil) {
        let presence = UserPresence(id: creatorID, currentFile: currentFile, cursorPosition: cursorPosition, selectionRange: selectionRange)
        updateUserPresence(presence)
        if let data = try? JSONEncoder().encode(presence) {
            PeerSessionManager.shared.sendDataToAll(data)
        }
    }

    private func updateUserPresence(_ presence: UserPresence) {
        if let index = activeUsers.firstIndex(where: { $0.id == presence.id }) {
            activeUsers[index] = presence
        } else {
            activeUsers.append(presence)
        }
    }

    private func startPresenceHeartbeat() {
        Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.broadcastPresence()
                self?.cleanupInactiveUsers()
            }
            .store(in: &cancellables)
    }

    private func cleanupInactiveUsers() {
        let timeout: TimeInterval = 15.0
        activeUsers.removeAll { Date().timeIntervalSince($0.lastSeen) > timeout && $0.id != creatorID }
    }

    // MARK: - Persistence

    public struct ProjectState: Codable {
        public let projectID: UUID
        public let creatorID: String
        public let activityLog: [CollaborationActivity]
        public let notifications: [CollaborationNotificationItem]
        public let branches: [Branch]
        public let currentBranchID: UUID
        public let merges: [BranchMerge]
        public let commits: [Commit]
        public let pullRequests: [PullRequest]
        public let reviews: [UUID: CodeReview]
        public let memberRoles: [String: CollaborationRole]
        public let invites: [CollaborationInvite]
    }

    public func saveState() {
        let state = ProjectState(
            projectID: project.id,
            creatorID: creatorID,
            activityLog: activityLog,
            notifications: notifications,
            branches: branches.branches,
            currentBranchID: branches.currentBranch.id,
            merges: branches.merges,
            commits: commits.commits,
            pullRequests: pullRequests.pullRequests,
            reviews: reviews.reviews,
            memberRoles: permissions.memberRoles,
            invites: invites.invites
        )
        if let data = try? JSONEncoder().encode(state) {
            let url = getPersistenceURL()
            try? data.write(to: url, options: .atomic)
        }
    }

    public func loadState() {
        let url = getPersistenceURL()
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(ProjectState.self, from: data) else { return }

        restoreStateFromObject(state)
    }

    private func getPersistenceURL() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("collaboration_\(project.id).json")
    }
}
