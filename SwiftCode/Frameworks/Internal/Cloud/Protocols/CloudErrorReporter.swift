import Foundation

public struct CloudErrorEvent: Codable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let errorCode: String
    public let domain: String
    public let errorMessage: String
    public let isFatal: Bool

    public init(id: UUID = UUID(), timestamp: Date = Date(), errorCode: String, domain: String, errorMessage: String, isFatal: Bool = false) {
        self.id = id
        self.timestamp = timestamp
        self.errorCode = errorCode
        self.domain = domain
        self.errorMessage = errorMessage
        self.isFatal = isFatal
    }
}

public protocol CloudErrorReporter: AnyObject, Sendable {
    func reportError(_ error: Error, domain: String, isFatal: Bool)
    func reportCustomError(code: String, message: String, domain: String, isFatal: Bool)
    func getErrorReportHistory() -> [CloudErrorEvent]
    func clearHistory()
}
