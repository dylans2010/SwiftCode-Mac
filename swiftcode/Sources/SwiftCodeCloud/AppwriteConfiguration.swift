import Foundation

public struct AppwriteConfiguration: Sendable, Equatable {
    public static let defaultEndpoint = URL(string: "https://sfo.cloud.appwrite.io/v1")!
    public static let defaultProjectID = "6a670d0b0022e5f964b4"

    public var endpoint: URL
    public var projectID: String

    public init(endpoint: URL = Self.defaultEndpoint, projectID: String = Self.defaultProjectID) {
        self.endpoint = endpoint
        self.projectID = projectID
    }

    public var callbackScheme: String {
        "appwrite-callback-\(projectID)"
    }

    public var sessionCookieName: String {
        "a_session_\(projectID)"
    }
}
