import Foundation

public struct AssistAPIResponse: Codable {
    public let success: Bool
    public let data: [String: String]?
    public let error: String?
    public let markdown: String?

    public init(success: Bool, data: [String: String]? = nil, error: String? = nil, markdown: String? = nil) {
        self.success = success
        self.data = data
        self.error = error
        self.markdown = markdown
    }

    public static func successful(data: [String: String]? = nil, markdown: String? = nil) -> AssistAPIResponse {
        return AssistAPIResponse(success: true, data: data, markdown: markdown)
    }

    public static func failure(error: String) -> AssistAPIResponse {
        return AssistAPIResponse(success: false, error: error)
    }
}
