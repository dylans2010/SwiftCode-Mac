import Foundation

public typealias ViewOpener = @MainActor @Sendable () async throws -> Void

public actor SDKViewOpener {
    public static let shared = SDKViewOpener()

    private var openers: [String: ViewOpener] = [:]

    private init() {}

    public func register(viewID: String, opener: @escaping ViewOpener) {
        openers[viewID] = opener
    }

    public func isRegistered(viewID: String) -> Bool {
        openers[viewID] != nil
    }

    public func open(viewID: String) async throws {
        guard let opener = openers[viewID] else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "The view “\(viewID)” is not available.",
                suggestion: "The host has not registered an opener for this view."
            )
        }
        try await opener()
    }
}

public protocol SDKViewHost: Sendable {
    func open(viewID: String) async throws
}

public final class SDKViewHostRegistry: @unchecked Sendable {
    public static let shared = SDKViewHostRegistry()

    public var host: (any SDKViewHost)?

    private init() {}

    public func open(viewID: String) async throws {
        guard let host else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "The view “\(viewID)” is not available.",
                suggestion: "The host UI has not installed a view host for this view yet."
            )
        }
        try await host.open(viewID: viewID)
    }

    public func openAssistMainView() async throws {
        try await open(viewID: SDKAssistUIOpener.assistMainViewID)
    }
}
