import Foundation

actor SyncEngine {
    private var provider: (any CloudProvider)?
    private var isSyncing = false

    private var pendingUploads: [String: Data] = [:]

    init(provider: (any CloudProvider)? = nil) {
        self.provider = provider
    }

    // MARK: - Provider Configuration

    func setProvider(_ provider: any CloudProvider) {
        self.provider = provider
    }

    func clearProvider() {
        provider = nil
    }

    var hasProvider: Bool {
        provider != nil
    }

    // MARK: - Upload Queue

    func enqueueUpload(id: String, data: Data) {
        pendingUploads[id] = data
    }

    func removePendingUpload(id: String) {
        pendingUploads.removeValue(forKey: id)
    }

    func pendingUploadIDs() -> [String] {
        Array(pendingUploads.keys)
    }

    // MARK: - Synchronization

    func synchronize() async {
        guard !isSyncing else {
            return
        }

        guard provider != nil else {
            return
        }

        isSyncing = true
        defer {
            isSyncing = false
        }

        // CloudProvider does not expose saveRecord or fetchRecords.
        // Do not attempt remote persistence or retrieval through
        // methods that are not defined by the protocol.
        //
        // Pending uploads remain queued until a supported provider
        // synchronization interface is implemented.
    }

    // MARK: - State

    var isSynchronizationInProgress: Bool {
        isSyncing
    }

    var pendingUploadCount: Int {
        pendingUploads.count
    }
}
