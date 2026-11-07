import Foundation

public actor SDKViewOpener {

    public static let shared = SDKViewOpener()

    public typealias ViewOpener = @MainActor @Sendable () throws -> Void

    private var openers: [SDKCapabilityID: ViewOpener] = [:]

    public func register(viewID: SDKCapabilityID, opener: @escaping ViewOpener) {
        openers[viewID] = opener
    }

    public func isRegistered(viewID: SDKCapabilityID) -> Bool {
        openers[viewID] != nil
    }

    public func open(viewID: SDKCapabilityID) async throws {
        guard let opener = openers[viewID] else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "The host has no opener for view \"\(viewID.rawValue)\".",
                suggestion: "The capability is known, but no view opener is registered for it in this build.",
                diagnostics: ["viewId": viewID.rawValue]
            )
        }
        try await MainActor.run {
            try opener()
        }
    }
}
