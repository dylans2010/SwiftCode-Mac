import Foundation

public struct QueuedOperation: Codable, Identifiable, Sendable {
    public let id: UUID
    public let payload: SyncPayload
    public var retryCount: Int
    public var lastAttempted: Date?
    public var lastError: String?

    public init(id: UUID = UUID(), payload: SyncPayload, retryCount: Int = 0, lastAttempted: Date? = nil, lastError: String? = nil) {
        self.id = id
        self.payload = payload
        self.retryCount = retryCount
        self.lastAttempted = lastAttempted
        self.lastError = lastError
    }
}

public actor UploadQueue {
    public static let shared = UploadQueue()

    private var queue: [QueuedOperation] = []
    private let queueKey = "com.swiftcode.cloud.sync.upload_queue"

    private init() {
        loadQueue()
    }

    private func loadQueue() {
        if let data = UserDefaults.standard.data(forKey: queueKey),
           let decoded = try? JSONDecoder().decode([QueuedOperation].self, from: data) {
            self.queue = decoded
        }
    }

    private func saveQueue() {
        if let data = try? JSONEncoder().encode(queue) {
            UserDefaults.standard.set(data, forKey: queueKey)
        }
    }

    public func enqueue(_ payload: SyncPayload) {
        // Dedup: if same resource has a queued op, replace it
        queue.removeAll { $0.payload.resourceID == payload.resourceID }
        queue.append(QueuedOperation(payload: payload))
        saveQueue()
    }

    public func getPending() -> [QueuedOperation] {
        return queue
    }

    public func remove(_ id: UUID) {
        queue.removeAll { $0.id == id }
        saveQueue()
    }

    public func update(_ operation: QueuedOperation) {
        if let idx = queue.firstIndex(where: { $0.id == operation.id }) {
            queue[idx] = operation
            saveQueue()
        }
    }

    public func clear() {
        queue.removeAll()
        saveQueue()
    }
}
