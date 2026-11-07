import Foundation

actor SyncEngine {
    private var provider: (any CloudProvider)?
    private var isSyncing = false

    private var pendingUploads: [String: Data] = [:]

    init(provider: (any CloudProvider)? = nil) {
        self.provider = provider
    }

    func setProvider(_ provider: any CloudProvider) {
        self.provider = provider
    }

    func clearProvider() {
        provider = nil
    }

    var hasProvider: Bool {
        provider != nil
    }

    func enqueueUpload(id: String, data: Data) {
        pendingUploads[id] = data
    }

    func removePendingUpload(id: String) {
        pendingUploads.removeValue(forKey: id)
    }

    func pendingUploadIDs() -> [String] {
        Array(pendingUploads.keys)
    }

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

    }

    var isSynchronizationInProgress: Bool {
        isSyncing
    }

    var pendingUploadCount: Int {
        pendingUploads.count
    }
}
