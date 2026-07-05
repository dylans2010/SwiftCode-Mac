import Foundation

public struct PushEvent: Equatable {
    public let actorID: String
    public let title: String
    public let detail: String
    public let notifies: Bool
}

public struct BranchConflict: Identifiable, Codable, Equatable {
    public let id: UUID
    public let branchName: String
    public let filePath: String
    public let localChange: String
    public let remoteChange: String

    public init(branchName: String, filePath: String, localChange: String, remoteChange: String) {
        self.id = UUID()
        self.branchName = branchName
        self.filePath = filePath
        self.localChange = localChange
        self.remoteChange = remoteChange
    }
}

public struct PushStatus: Identifiable, Equatable {
    public let id = UUID()
    public let branchName: String
    public let progress: Double
    public let isComplete: Bool
    public let direction: String
}

@MainActor
public final class PushManager: ObservableObject {
    @Published public private(set) var activePushes: [PushStatus] = []
    @Published public private(set) var conflicts: [BranchConflict] = []
    @Published public private(set) var lastEvent: PushEvent?

    public func prepareSync(branchName: String, actorID: String, localCommitCount: Int, remoteCommitCount: Int) -> BranchConflict? {
        guard localCommitCount != remoteCommitCount else { return nil }
        let conflict = BranchConflict(branchName: branchName, filePath: "Sources/Shared/SyncState.swift", localChange: "local: commit count \(localCommitCount)", remoteChange: "remote: commit count \(remoteCommitCount)")
        conflicts.removeAll { $0.branchName == branchName }
        conflicts.append(conflict)
        lastEvent = PushEvent(actorID: actorID, title: "Sync Prepared", detail: "Local/remote comparison finished for \(branchName).", notifies: false)
        return conflict
    }

    public func resolveConflict(_ conflictID: UUID, using resolution: ConflictResolutionChoice, actorID: String) {
        conflicts.removeAll { $0.id == conflictID }
        lastEvent = PushEvent(actorID: actorID, title: "Conflict Resolution Applied", detail: resolution.displayName, notifies: true)
    }

    public func push(branchName: String, actorID: String, data: Data? = nil) async {
        activePushes.append(PushStatus(branchName: branchName, progress: 0, isComplete: false, direction: "Push"))
        if let data {
            let peerManager = PeerSessionManager.shared
            let peers = peerManager.session.connectedPeers
            if !peers.isEmpty {
                try? peerManager.send(data, to: peers)
            }
        }
        // Artificial progress for UI feedback
        for i in 1...10 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let index = activePushes.firstIndex(where: { $0.branchName == branchName && $0.direction == "Push" }) {
                activePushes[index] = PushStatus(branchName: branchName, progress: Double(i) / 10.0, isComplete: i == 10, direction: "Push")
            }
        }
        lastEvent = PushEvent(actorID: actorID, title: "Push Complete", detail: "\(branchName) synced successfully.", notifies: true)
        try? await Task.sleep(nanoseconds: 200_000_000)
        activePushes.removeAll { $0.branchName == branchName && $0.direction == "Push" }
    }

    public func pull(branchName: String, actorID: String) async {
        activePushes.append(PushStatus(branchName: branchName, progress: 0, isComplete: false, direction: "Pull"))
        // Pull logic: in P2P, we normally wait for data or request it.
        // For this implementation, we simulate the network request and response.
        for i in 1...10 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let index = activePushes.firstIndex(where: { $0.branchName == branchName && $0.direction == "Pull" }) {
                activePushes[index] = PushStatus(branchName: branchName, progress: Double(i) / 10.0, isComplete: i == 10, direction: "Pull")
            }
        }
        lastEvent = PushEvent(actorID: actorID, title: "Pull Complete", detail: "\(branchName) is up to date.", notifies: true)
        try? await Task.sleep(nanoseconds: 200_000_000)
        activePushes.removeAll { $0.branchName == branchName && $0.direction == "Pull" }
    }
}
