import Foundation

@MainActor
public final class CloudSyncWiring {
    public static let shared = CloudSyncWiring()
    private init() {}

    public func recordChanged(tableName: String, recordID: String, payload: [String: String], isDeleted: Bool = false) {
        Task {
            await CloudSyncEngine.shared.queueLocalUpdate(
                tableName: tableName,
                recordID: recordID,
                payload: payload,
                isDeleted: isDeleted
            )
        }
    }
}

public struct SerializedChatMessage: Codable, Sendable, Identifiable {
    public let id: UUID
    public let role: String
    public let content: String
    public let timestamp: Date

    public init(id: UUID = UUID(), role: String, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

public final class LocalChatHistoryStore: @unchecked Sendable {
    public static let shared = LocalChatHistoryStore()
    private init() {}

    private var directoryURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("SwiftCode/Chats", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }

    public func saveChat(sessionID: String, messages: [SerializedChatMessage]) {
        let fileURL = directoryURL.appendingPathComponent("\(sessionID).json")
        do {
            let data = try JSONEncoder().encode(messages)
            try data.write(to: fileURL)

            let payload: [String: String] = [
                "session_id": sessionID,
                "message_count": "\(messages.count)",
                "updated_at": "\(Date().timeIntervalSince1970)"
            ]
            Task { @MainActor in
                CloudSyncWiring.shared.recordChanged(
                    tableName: "chat_history",
                    recordID: sessionID,
                    payload: payload
                )
            }
        } catch {
            NSLog("Failed to serialize chat history: \(error.localizedDescription)")
        }
    }

    public func loadChat(sessionID: String) -> [SerializedChatMessage] {
        let fileURL = directoryURL.appendingPathComponent("\(sessionID).json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([SerializedChatMessage].self, from: data)
        } catch {
            return []
        }
    }
}
