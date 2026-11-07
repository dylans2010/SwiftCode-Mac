import Foundation
import Observation

@Observable
@MainActor
public final class PreviewErrorHandler {
    public static let shared = PreviewErrorHandler()

    public var activeError: String? = nil
    public var errorDetails: String? = nil

    private init() {}

    public func handleError(_ error: Error, message: String) {
        self.activeError = message
        self.errorDetails = error.localizedDescription
        PreviewDiagnostics.shared.addLog(category: "error", message: "\(message): \(error.localizedDescription)")
    }

    public func clearError() {
        self.activeError = nil
        self.errorDetails = nil
    }
}
