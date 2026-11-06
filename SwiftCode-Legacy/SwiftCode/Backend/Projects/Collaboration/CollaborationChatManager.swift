import Foundation
import Combine

public struct CollaborationChatMessage: Identifiable, Codable, Equatable {
    public let id: UUID
    public let channelID: String
    public let authorID: String
    public let text: String
    public let timestamp: Date
    public let attachment: ChatAttachment?

    public init(channelID: String, authorID: String, text: String, attachment: ChatAttachment? = nil) {
        self.id = UUID()
        self.channelID = channelID
        self.authorID = authorID
        self.text = text
        self.timestamp = Date()
        self.attachment = attachment
    }
}

public enum ChatAttachment: Codable, Equatable {
    case codeSnippet(path: String, code: String)
    case fileReference(path: String)
}

@MainActor
public final class CollaborationChatManager: ObservableObject {
    @Published public private(set) var messagesByChannel: [String: [CollaborationChatMessage]] = [:]
    @Published public private(set) var activeChannelID: String = "general"

    public func sendMessage(text: String, authorID: String, channelID: String? = nil, attachment: ChatAttachment? = nil) {
        let cid = channelID ?? activeChannelID
        let message = CollaborationChatMessage(channelID: cid, authorID: authorID, text: text, attachment: attachment)
        messagesByChannel[cid, default: []].append(message)

        // Broadcast via PeerSessionManager if in a live session
        if let data = try? JSONEncoder().encode(message) {
            PeerSessionManager.shared.sendDataToAll(data)
        }
    }

    public func receiveMessage(_ message: CollaborationChatMessage) {
        messagesByChannel[message.channelID, default: []].append(message)
    }

    public func setChannel(_ channelID: String) {
        activeChannelID = channelID
    }

    public func messages(for channelID: String) -> [CollaborationChatMessage] {
        messagesByChannel[channelID] ?? []
    }
}
