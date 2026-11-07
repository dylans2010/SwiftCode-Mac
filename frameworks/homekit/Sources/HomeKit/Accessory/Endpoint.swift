import Foundation

public struct SwiftCodeCharacteristicAddress: Hashable, Codable, Sendable, CustomStringConvertible {
    public var aid: Int
    public var iid: Int
    public init(aid: Int, iid: Int) { self.aid = aid; self.iid = iid }
    public var description: String { "\(aid).\(iid)" }
}

public enum SwiftCodeHAPPermission: String, Codable, Hashable, Sendable, CaseIterable {
    case pairedRead = "pr"
    case pairedWrite = "pw"
    case events = "ev"
    case additionalAuthorization = "aa"
    case timedWrite = "tw"
    case hidden = "hd"
    case writeResponse = "wr"

    public var property: String? {
        switch self {
        case .pairedRead: return HMCharacteristicPropertyReadable
        case .pairedWrite: return HMCharacteristicPropertyWritable
        case .events: return HMCharacteristicPropertySupportsEventNotification
        case .additionalAuthorization: return HMCharacteristicPropertyRequiresAuthorizationData
        case .hidden: return HMCharacteristicPropertyHidden
        case .timedWrite, .writeResponse: return nil
        }
    }

    public static func properties(_ perms: [SwiftCodeHAPPermission]) -> [String] {
        let order: [SwiftCodeHAPPermission] = [.pairedRead, .pairedWrite, .events, .hidden, .additionalAuthorization]
        return order.filter(perms.contains).compactMap(\.property)
    }
}

public struct SwiftCodeAccessoryDatabase: Codable, Hashable, Sendable {
    public struct Characteristic: Codable, Hashable, Sendable {
        public var iid: Int
        public var type: String
        public var permissions: [SwiftCodeHAPPermission]
        public var metadata: SwiftCodeCharacteristicMetadata
        public var value: SwiftCodeHomeValue?

        public init(iid: Int, type: String, permissions: [SwiftCodeHAPPermission],
                    metadata: SwiftCodeCharacteristicMetadata, value: SwiftCodeHomeValue?) {
            self.iid = iid
            self.type = SwiftCodeHomeCatalog.normalizedTypeUUID(type) ?? type
            self.permissions = permissions
            self.metadata = metadata
            self.value = value
        }
    }

    public struct Service: Codable, Hashable, Sendable {
        public var iid: Int
        public var type: String
        public var isPrimary: Bool
        public var isHidden: Bool
        public var linkedIIDs: [Int]
        public var characteristics: [Characteristic]

        public init(iid: Int, type: String, isPrimary: Bool = false, isHidden: Bool = false,
                    linkedIIDs: [Int] = [], characteristics: [Characteristic]) {
            self.iid = iid
            self.type = SwiftCodeHomeCatalog.normalizedTypeUUID(type) ?? type
            self.isPrimary = isPrimary
            self.isHidden = isHidden
            self.linkedIIDs = linkedIIDs
            self.characteristics = characteristics
        }
    }

    public struct Accessory: Codable, Hashable, Sendable {
        public var aid: Int
        public var services: [Service]
        public init(aid: Int, services: [Service]) { self.aid = aid; self.services = services }
    }

    public var accessories: [Accessory]
    public init(accessories: [Accessory]) { self.accessories = accessories }
}

public protocol SwiftCodeAccessoryEndpointDelegate: AnyObject, Sendable {
    func endpoint(_ endpointID: String, didUpdateValues values: [SwiftCodeCharacteristicAddress: SwiftCodeHomeValue])
    func endpoint(_ endpointID: String, didChangeReachability reachable: Bool)
}

public protocol SwiftCodeAccessoryEndpoint: AnyObject, Sendable {
    var endpointID: String { get }
    var name: String { get }
    var categoryNumber: Int { get }
    var isReachable: Bool { get }
    var delegate: SwiftCodeAccessoryEndpointDelegate? { get set }

    func fetchDatabase(completion: @escaping @Sendable (Result<SwiftCodeAccessoryDatabase, SwiftCodeAccessoryFailure>) -> Void)
    func read(_ address: SwiftCodeCharacteristicAddress,
              completion: @escaping @Sendable (Result<SwiftCodeHomeValue?, SwiftCodeAccessoryFailure>) -> Void)
    func write(_ address: SwiftCodeCharacteristicAddress, value: SwiftCodeHomeValue, authorizationData: Data?,
               completion: @escaping @Sendable (Result<Void, SwiftCodeAccessoryFailure>) -> Void)
    func setEventsEnabled(_ enabled: Bool, for address: SwiftCodeCharacteristicAddress,
                          completion: @escaping @Sendable (Result<Void, SwiftCodeAccessoryFailure>) -> Void)
    func identify(completion: @escaping @Sendable (Result<Void, SwiftCodeAccessoryFailure>) -> Void)
}
