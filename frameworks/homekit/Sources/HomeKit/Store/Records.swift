import Foundation

public struct SwiftCodeCharacteristicRecord: Codable, Hashable, Sendable {
    public var id: UUID
    public var iid: Int
    public var type: String
    public var properties: [String]
    public var metadata: SwiftCodeCharacteristicMetadata?
    public var value: SwiftCodeHomeValue?

    public init(id: UUID = UUID(), iid: Int, type: String, properties: [String],
                metadata: SwiftCodeCharacteristicMetadata?, value: SwiftCodeHomeValue?) {
        self.id = id
        self.iid = iid
        self.type = type
        self.properties = properties
        self.metadata = metadata
        self.value = value
    }
}

public struct SwiftCodeServiceRecord: Codable, Hashable, Sendable {
    public var id: UUID
    public var iid: Int
    public var type: String
    public var name: String
    public var associatedType: String?
    public var isPrimary: Bool
    public var isUserInteractive: Bool
    public var linkedServiceIDs: [UUID]
    public var characteristics: [SwiftCodeCharacteristicRecord]
}

public struct SwiftCodeAccessoryRecord: Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var categoryType: String
    public var manufacturer: String?
    public var model: String?
    public var firmwareVersion: String?
    public var roomID: UUID
    public var services: [SwiftCodeServiceRecord]
    public var isReachable: Bool
    public var isBlocked: Bool
    public var isBridged: Bool
    public var bridgedAccessoryIDs: [UUID]
    public var supportsIdentify: Bool
    public var endpointID: String
    public var aid: Int
    public var matterNodeID: UInt64?
}

public struct SwiftCodeRoomRecord: Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
}

public struct SwiftCodeZoneRecord: Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var roomIDs: [UUID]
}

public struct SwiftCodeServiceGroupRecord: Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var serviceIDs: [UUID]
}

public struct SwiftCodeActionRecord: Codable, Hashable, Sendable {
    public var id: UUID
    public var characteristicID: UUID
    public var targetValue: SwiftCodeHomeValue
}

public struct SwiftCodeActionSetRecord: Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var type: String
    public var actions: [SwiftCodeActionRecord]
    public var lastExecutionDate: Date?
    public var isExecuting: Bool
}

public struct SwiftCodeRegionRecord: Codable, Hashable, Sendable {
    public var identifier: String
    public var latitude: Double
    public var longitude: Double
    public var radius: Double
    public var notifyOnEntry: Bool
    public var notifyOnExit: Bool
}

public struct SwiftCodeEventRecord: Codable, Hashable, Sendable {
    public enum Kind: Codable, Hashable, Sendable {
        case characteristic(characteristicID: UUID, triggerValue: SwiftCodeHomeValue?)
        case thresholdRange(characteristicID: UUID, minimum: Double?, maximum: Double?)
        case location(SwiftCodeRegionRecord?)
        case presence(type: Int, userType: Int)
        case calendar(DateComponents)
        case significantTime(event: String, offset: DateComponents?)
        case duration(TimeInterval)
    }

    public var id: UUID
    public var kind: Kind
}

public struct SwiftCodeTriggerRecord: Codable, Hashable, Sendable {
    public enum Kind: Codable, Hashable, Sendable {
        case timer(fireDate: Date, recurrence: DateComponents?)
        case event(events: [SwiftCodeEventRecord], endEvents: [SwiftCodeEventRecord],
                   recurrences: [DateComponents]?, executeOnce: Bool)
    }

    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var actionSetIDs: [UUID]
    public var kind: Kind
    public var activationState: Int
}

public struct SwiftCodeUserRecord: Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var isAdministrator: Bool
}

public struct SwiftCodeHomeRecord: Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var isPrimary: Bool
    public var defaultRoom: SwiftCodeRoomRecord
    public var rooms: [SwiftCodeRoomRecord]
    public var zones: [SwiftCodeZoneRecord]
    public var serviceGroups: [SwiftCodeServiceGroupRecord]
    public var accessories: [SwiftCodeAccessoryRecord]
    public var actionSets: [SwiftCodeActionSetRecord]
    public var triggers: [SwiftCodeTriggerRecord]
    public var users: [SwiftCodeUserRecord]
    public var currentUserID: UUID
    public var hubState: Int

    func accessoryIndex(_ id: UUID) -> Int? { accessories.firstIndex { $0.id == id } }

    func characteristicPath(_ id: UUID) -> (Int, Int, Int)? {
        for (a, acc) in accessories.enumerated() {
            for (s, svc) in acc.services.enumerated() {
                if let c = svc.characteristics.firstIndex(where: { $0.id == id }) { return (a, s, c) }
            }
        }
        return nil
    }

    func servicePath(_ id: UUID) -> (Int, Int)? {
        for (a, acc) in accessories.enumerated() {
            if let s = acc.services.firstIndex(where: { $0.id == id }) { return (a, s) }
        }
        return nil
    }
}

public struct SwiftCodeDiscoveredAccessoryRecord: Codable, Hashable, Sendable {
    public var id: UUID
    public var endpointID: String
    public var name: String
    public var categoryType: String
}
