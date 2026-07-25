import Foundation

public actor DownloadQueue {
    public static let shared = DownloadQueue()

    private var pendingChanges: [SyncPayload] = []

    private init() {}

    public func enqueue(_ payloads: [SyncPayload]) {
        for payload in payloads {
            pendingChanges.removeAll { $0.resourceID == payload.resourceID }
            pendingChanges.append(payload)
        }
    }

    public func getPending() -> [SyncPayload] {
        return pendingChanges
    }

    public func clear() {
        pendingChanges.removeAll()
    }

    public func remove(_ resourceID: String) {
        pendingChanges.removeAll { $0.resourceID == resourceID }
    }
}
