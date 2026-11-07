import Foundation

public enum SyncOperationType: String, Codable, Sendable {
    case upload
    case download
}

public struct SyncOperation: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public let type: SyncOperationType
    public let recordID: String
    public let timestamp: Date
    public var retryCount: Int
    public var errorState: String?

    public init(id: UUID = UUID(), type: SyncOperationType, recordID: String, timestamp: Date = Date(), retryCount: Int = 0, errorState: String? = nil) {
        self.id = id
        self.type = type
        self.recordID = recordID
        self.timestamp = timestamp
        self.retryCount = retryCount
        self.errorState = errorState
    }
}

public actor SyncQueue {
    public static let shared = SyncQueue()

    private var queue: [SyncOperation] = []

    private init() {}

    public func enqueue(_ operation: SyncOperation) {
        queue.append(operation)
    }

    public func dequeue() -> SyncOperation? {
        guard !queue.isEmpty else { return nil }
        return queue.removeFirst()
    }

    public func getAll() -> [SyncOperation] {
        return queue
    }

    public func getPendingUploadCount() -> Int {
        return queue.filter { $0.type == .upload && $0.errorState == nil }.count
    }

    public func clear() {
        queue.removeAll()
    }

    public func removeOperation(id: UUID) {
        queue.removeAll { $0.id == id }
    }

    public func updateOperation(_ operation: SyncOperation) {
        if let index = queue.firstIndex(where: { $0.id == operation.id }) {
            queue[index] = operation
        }
    }
}
