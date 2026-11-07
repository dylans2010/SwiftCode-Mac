import Foundation

public struct AssistAPIRequest: Codable {
    public let route: AssistAPIRoute
    public let payload: [String: String]
    public let sessionId: String?

    public init(route: AssistAPIRoute, payload: [String: String], sessionId: String? = nil) {
        self.route = route
        self.payload = payload
        self.sessionId = sessionId
    }
}

public enum AssistAPIRoute: String, Codable {
    case plan
    case execute
    case analyze
    case createFile
    case modifyFile
    case enhancePrompt
}
