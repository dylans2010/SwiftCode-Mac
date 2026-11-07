import Foundation

public struct SwiftCodeHomeClient: Codable, Hashable, Sendable {
    public var bundleIdentifier: String
    public var usageDescription: String?
    public var hasHomeKitEntitlement: Bool
    public var enforcesRequirements: Bool

    public init(bundleIdentifier: String, usageDescription: String? = "SwiftCode test client",
                hasHomeKitEntitlement: Bool = true, enforcesRequirements: Bool = true) {
        self.bundleIdentifier = bundleIdentifier
        self.usageDescription = usageDescription
        self.hasHomeKitEntitlement = hasHomeKitEntitlement
        self.enforcesRequirements = enforcesRequirements
    }

    public static var processDefault: SwiftCodeHomeClient {
        let env = ProcessInfo.processInfo.environment
        let info = Bundle.main.infoDictionary ?? [:]
        let hasPlist = info["CFBundleIdentifier"] != nil
        let bundle = env["SWIFTCODE_HOMEKIT_BUNDLE_IDENTIFIER"] ?? Bundle.main.bundleIdentifier
            ?? "local.\(ProcessInfo.processInfo.processName)"
        let usage = env["SWIFTCODE_HOMEKIT_USAGE_DESCRIPTION"] ?? info["NSHomeKitUsageDescription"] as? String
        return SwiftCodeHomeClient(bundleIdentifier: bundle,
                               usageDescription: usage ?? (hasPlist ? nil : "SwiftCode command-line client"),
                               hasHomeKitEntitlement: env["SWIFTCODE_HOMEKIT_ENTITLED"] != "0",
                               enforcesRequirements: hasPlist)
    }
}

public struct SwiftCodeHomeSession: Codable, Hashable, Sendable {
    public var id: UUID
    public var authorizationStatus: UInt
}

public enum SwiftCodeHomeRequest: Codable, Hashable, Sendable {
    case addHome(name: String)
    case removeHome(UUID)
    case renameHome(UUID, name: String)
    case updatePrimaryHome(UUID)
    case addRoom(home: UUID, name: String)
    case removeRoom(home: UUID, room: UUID)
    case renameRoom(home: UUID, room: UUID, name: String)
    case addZone(home: UUID, name: String)
    case removeZone(home: UUID, zone: UUID)
    case renameZone(home: UUID, zone: UUID, name: String)
    case addRoomToZone(home: UUID, zone: UUID, room: UUID)
    case removeRoomFromZone(home: UUID, zone: UUID, room: UUID)
    case addServiceGroup(home: UUID, name: String)
    case removeServiceGroup(home: UUID, group: UUID)
    case renameServiceGroup(home: UUID, group: UUID, name: String)
    case addServiceToGroup(home: UUID, group: UUID, service: UUID)
    case removeServiceFromGroup(home: UUID, group: UUID, service: UUID)
    case setBrowsing(Bool)
    case addAccessory(home: UUID, discovered: UUID)
    case removeAccessory(home: UUID, accessory: UUID)
    case assignAccessory(home: UUID, accessory: UUID, room: UUID)
    case renameAccessory(home: UUID, accessory: UUID, name: String)
    case identifyAccessory(home: UUID, accessory: UUID)
    case unblockAccessory(home: UUID, accessory: UUID)
    case renameService(home: UUID, service: UUID, name: String)
    case updateAssociatedServiceType(home: UUID, service: UUID, type: String?)
    case readCharacteristic(home: UUID, characteristic: UUID)
    case writeCharacteristic(home: UUID, characteristic: UUID, value: SwiftCodeHomeValue)
    case enableNotification(home: UUID, characteristic: UUID, enabled: Bool)
    case updateAuthorizationData(home: UUID, characteristic: UUID, data: Data?)
    case addActionSet(home: UUID, name: String)
    case removeActionSet(home: UUID, actionSet: UUID)
    case renameActionSet(home: UUID, actionSet: UUID, name: String)
    case addAction(home: UUID, actionSet: UUID, action: SwiftCodeActionRecord)
    case removeAction(home: UUID, actionSet: UUID, action: UUID)
    case updateActionTarget(home: UUID, action: UUID, value: SwiftCodeHomeValue)
    case executeActionSet(home: UUID, actionSet: UUID)
    case addTrigger(home: UUID, trigger: SwiftCodeTriggerRecord)
    case removeTrigger(home: UUID, trigger: UUID)
    case renameTrigger(home: UUID, trigger: UUID, name: String)
    case enableTrigger(home: UUID, trigger: UUID, enabled: Bool)
    case addActionSetToTrigger(home: UUID, trigger: UUID, actionSet: UUID)
    case removeActionSetFromTrigger(home: UUID, trigger: UUID, actionSet: UUID)
    case updateTrigger(home: UUID, trigger: SwiftCodeTriggerRecord)
}

public enum SwiftCodeHomeResponse: Codable, Hashable, Sendable {
    case done
    case home(SwiftCodeHomeRecord)
    case object(UUID)
    case value(SwiftCodeHomeValue?)
    case discovered([SwiftCodeDiscoveredAccessoryRecord])
}

public enum SwiftCodeHomeChange: Codable, Hashable, Sendable {
    case homeName
    case accessoryAdded(UUID)
    case accessoryRemoved(UUID, bridged: [UUID])
    case accessoryRoom(accessory: UUID, room: UUID)
    case accessoryName(UUID)
    case accessoryUnblocked(UUID)
    case accessoryReachability(UUID)
    case serviceName(accessory: UUID, service: UUID)
    case associatedServiceType(accessory: UUID, service: UUID)
    case roomAdded(UUID)
    case roomRemoved(UUID)
    case roomName(UUID)
    case zoneAdded(UUID)
    case zoneRemoved(UUID)
    case zoneName(UUID)
    case roomAddedToZone(room: UUID, zone: UUID)
    case roomRemovedFromZone(room: UUID, zone: UUID)
    case serviceGroupAdded(UUID)
    case serviceGroupRemoved(UUID)
    case serviceGroupName(UUID)
    case serviceAddedToGroup(service: UUID, group: UUID)
    case serviceRemovedFromGroup(service: UUID, group: UUID)
    case actionSetAdded(UUID)
    case actionSetRemoved(UUID)
    case actionSetName(UUID)
    case actionSetActions(UUID)
    case triggerAdded(UUID)
    case triggerRemoved(UUID)
    case triggerName(UUID)
    case triggerUpdated(UUID)
    case hubState
    case state
}

public enum SwiftCodeHomeEvent: Codable, Hashable, Sendable {
    case authorizationStatus(UInt)
    case homesLoaded([SwiftCodeHomeRecord])
    case homeAdded(SwiftCodeHomeRecord, origin: UUID)
    case homeRemoved(UUID, origin: UUID)
    case homeUpdated(SwiftCodeHomeRecord, change: SwiftCodeHomeChange, origin: UUID)
    case characteristicValue(home: UUID, accessory: UUID, service: UUID, characteristic: UUID, value: SwiftCodeHomeValue?)
    case accessoryDiscovered(SwiftCodeDiscoveredAccessoryRecord)
    case accessoryDiscoveryRemoved(UUID)
    case disconnected
}

public protocol SwiftCodeHomeStore: AnyObject, Sendable {
    func connect(client: SwiftCodeHomeClient, events: @escaping @Sendable (SwiftCodeHomeEvent) -> Void) -> SwiftCodeHomeSession
    func disconnect(_ session: UUID)
    func perform(_ request: SwiftCodeHomeRequest, session: UUID,
                 completion: @escaping @Sendable (Result<SwiftCodeHomeResponse, SwiftCodeHomeStoreError>) -> Void)
}
