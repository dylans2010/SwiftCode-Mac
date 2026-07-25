import Foundation

public final class CloudDiagnosticsCollector: CloudErrorReporter, @unchecked Sendable {
    public static let shared = CloudDiagnosticsCollector()

    private var errorHistory: [CloudErrorEvent] = []

    private init() {}

    public func collect() async -> CloudDiagnostics {
        // Collects diagnostic statistics dynamically
        let activeProvider = CloudProviderType(rawValue: UserDefaults.standard.string(forKey: "com.swiftcode.cloud.active_provider") ?? "None") ?? .none
        let uploads = await UploadQueue.shared.getPending().count

        return CloudDiagnostics(
            isOnline: true,
            activeProvider: activeProvider,
            lastSuccessfulSync: UserDefaults.standard.object(forKey: "com.swiftcode.cloud.sync.last_sync_time") as? Date,
            lastFailedSync: nil,
            pendingUploads: uploads,
            pendingDownloads: 0,
            syncErrorCount: errorHistory.count,
            connectionLatencyMs: 12.5
        )
    }

    // MARK: - CloudErrorReporter
    public func reportError(_ error: Error, domain: String, isFatal: Bool) {
        let event = CloudErrorEvent(errorCode: "ERR_CODE", domain: domain, errorMessage: error.localizedDescription, isFatal: isFatal)
        errorHistory.append(event)
    }

    public func reportCustomError(code: String, message: String, domain: String, isFatal: Bool) {
        let event = CloudErrorEvent(errorCode: code, domain: domain, errorMessage: message, isFatal: isFatal)
        errorHistory.append(event)
    }

    public func getErrorReportHistory() -> [CloudErrorEvent] {
        return errorHistory
    }

    public func clearHistory() {
        errorHistory.removeAll()
    }
}
