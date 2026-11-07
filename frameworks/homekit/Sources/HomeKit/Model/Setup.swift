import Foundation

open class HMAccessoryOwnershipToken: NSObject, @unchecked Sendable {
    let data: Data
    public init(data: Data) { self.data = data }
}

open class HMAccessorySetupPayload: NSObject, @unchecked Sendable {
    public let swiftcodeURL: URL
    public let swiftcodeOwnershipToken: HMAccessoryOwnershipToken?

    public init?(url setupPayloadURL: URL?) {
        guard let url = setupPayloadURL, HMAccessorySetupPayload.isValid(url.absoluteString) else { return nil }
        swiftcodeURL = url
        swiftcodeOwnershipToken = nil
    }

    public init?(url setupPayloadURL: URL?, ownershipToken: HMAccessoryOwnershipToken?) {
        guard let url = setupPayloadURL, HMAccessorySetupPayload.isValid(url.absoluteString) else { return nil }
        swiftcodeURL = url
        swiftcodeOwnershipToken = ownershipToken
    }

    static func isValid(_ text: String) -> Bool {
        let scheme = "X-HM://"
        guard text.count == scheme.count + 13, text.uppercased().hasPrefix(scheme) else { return false }
        return text.dropFirst(scheme.count).allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}

open class HMAccessorySetupRequest: NSObject, NSCopying, @unchecked Sendable {
    public var payload: HMAccessorySetupPayload?
    public var homeUniqueIdentifier: UUID?
    public var suggestedRoomUniqueIdentifier: UUID?
    public var suggestedAccessoryName: String?

    public override init() { super.init() }

    public func copy(with zone: NSZone? = nil) -> Any {
        let c = HMAccessorySetupRequest()
        c.payload = payload
        c.homeUniqueIdentifier = homeUniqueIdentifier
        c.suggestedRoomUniqueIdentifier = suggestedRoomUniqueIdentifier
        c.suggestedAccessoryName = suggestedAccessoryName
        return c
    }

    open override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? HMAccessorySetupRequest else { return false }
        return o.payload === payload && o.homeUniqueIdentifier == homeUniqueIdentifier
            && o.suggestedRoomUniqueIdentifier == suggestedRoomUniqueIdentifier
            && o.suggestedAccessoryName == suggestedAccessoryName
    }

    open override var hash: Int {
        var h = Hasher()
        h.combine(homeUniqueIdentifier)
        h.combine(suggestedRoomUniqueIdentifier)
        h.combine(suggestedAccessoryName)
        return h.finalize()
    }
}

open class HMAccessorySetupResult: NSObject, @unchecked Sendable {
    public let homeUniqueIdentifier: UUID
    public let accessoryUniqueIdentifiers: [UUID]
    init(homeUniqueIdentifier: UUID, accessoryUniqueIdentifiers: [UUID]) {
        self.homeUniqueIdentifier = homeUniqueIdentifier
        self.accessoryUniqueIdentifiers = accessoryUniqueIdentifiers
    }
}

open class HMAccessorySetupManager: NSObject, @unchecked Sendable {
    public class var isSupported: Bool { true }

    public override init() { super.init() }

    public func performAccessorySetup(using request: HMAccessorySetupRequest,
                                      completionHandler completion: @escaping (HMAccessorySetupResult?, Error?) -> Void) {
        onMain { completion(nil, HMError.cancelledWithoutInfo) }
    }

    public func performAccessorySetup(using request: HMAccessorySetupRequest) async throws -> HMAccessorySetupResult {
        try await asyncCall { performAccessorySetup(using: request, completionHandler: $0) }
    }
}
