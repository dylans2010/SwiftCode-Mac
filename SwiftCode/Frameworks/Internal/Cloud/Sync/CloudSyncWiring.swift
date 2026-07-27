import Foundation

/// Static utility to wire existing local persistence systems to the actor-isolated CloudSyncEngine.
@MainActor
public final class CloudSyncWiring {
    public static let shared = CloudSyncWiring()
    private init() {}

    /// Registers a change in a local table with the Sync Engine.
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

// MARK: - Local Serialization for AI Chats & Agent History

/// High-fidelity struct representing an AI Chat Message to persist locally.
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

/// High-fidelity persistent store manager for AI Chat History and Agent History.
public final class LocalChatHistoryStore: @unchecked Sendable {
    public static let shared = LocalChatHistoryStore()
    private init() {}

    private var directoryURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("SwiftCode/Chats", isDirectory: true)
        // SAFETY: Creating directories if they don't exist is safe as we handle error catch options.
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }

    public func saveChat(sessionID: String, messages: [SerializedChatMessage]) {
        let fileURL = directoryURL.appendingPathComponent("\(sessionID).json")
        do {
            let data = try JSONEncoder().encode(messages)
            try data.write(to: fileURL)

            // Submit record change to sync engine
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
