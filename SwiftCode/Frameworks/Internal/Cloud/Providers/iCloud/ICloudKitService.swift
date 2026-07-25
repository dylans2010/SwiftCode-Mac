import Foundation

public enum ICloudAccountStatus: String, Codable, Sendable {
    case available
    case noAccount
    case restricted
    case couldNotDetermine
}

public final class ICloudKitService: @unchecked Sendable {
    public static let shared = ICloudKitService()

    public var accountStatus: ICloudAccountStatus = .couldNotDetermine
    public var currentAppleAccount: String? = nil

    private init() {
        Task {
            await checkAccountStatus()
        }
    }

    public func checkAccountStatus() async {
        // Simulate checking CloudKit account status
        try? await Task.sleep(nanoseconds: 200_000_000)
        self.accountStatus = .available
        self.currentAppleAccount = "developer@apple.com"
    }

    public func getAccountStatus() async -> ICloudAccountStatus {
        await checkAccountStatus()
        return accountStatus
    }
}
