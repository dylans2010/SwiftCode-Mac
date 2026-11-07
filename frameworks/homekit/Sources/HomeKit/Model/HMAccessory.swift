import Foundation

public protocol HMAccessoryDelegate: AnyObject {
    func accessoryDidUpdateName(_ accessory: HMAccessory)
    func accessory(_ accessory: HMAccessory, didUpdateNameFor service: HMService)
    func accessory(_ accessory: HMAccessory, didUpdateAssociatedServiceTypeFor service: HMService)
    func accessoryDidUpdateServices(_ accessory: HMAccessory)
    func accessory(_ accessory: HMAccessory, didAdd profile: HMAccessoryProfile)
    func accessory(_ accessory: HMAccessory, didRemove profile: HMAccessoryProfile)
    func accessoryDidUpdateReachability(_ accessory: HMAccessory)
    func accessory(_ accessory: HMAccessory, service: HMService, didUpdateValueFor characteristic: HMCharacteristic)
    func accessory(_ accessory: HMAccessory, didUpdateFirmwareVersion firmwareVersion: String)
}

public extension HMAccessoryDelegate {
    func accessoryDidUpdateName(_ accessory: HMAccessory) {}
    func accessory(_ accessory: HMAccessory, didUpdateNameFor service: HMService) {}
    func accessory(_ accessory: HMAccessory, didUpdateAssociatedServiceTypeFor service: HMService) {}
    func accessoryDidUpdateServices(_ accessory: HMAccessory) {}
    func accessory(_ accessory: HMAccessory, didAdd profile: HMAccessoryProfile) {}
    func accessory(_ accessory: HMAccessory, didRemove profile: HMAccessoryProfile) {}
    func accessoryDidUpdateReachability(_ accessory: HMAccessory) {}
    func accessory(_ accessory: HMAccessory, service: HMService, didUpdateValueFor characteristic: HMCharacteristic) {}
    func accessory(_ accessory: HMAccessory, didUpdateFirmwareVersion firmwareVersion: String) {}
}

open class HMAccessoryCategory: NSObject, @unchecked Sendable {
    public let categoryType: String
    public let localizedDescription: String

    init(categoryType: String) {
        self.categoryType = categoryType
        localizedDescription = SwiftCodeHomeCatalog.localizedDescription(forCategory: categoryType)
    }

    open override func isEqual(_ object: Any?) -> Bool { (object as? HMAccessoryCategory)?.categoryType == categoryType }
    open override var hash: Int { categoryType.hashValue }
}

open class HMAccessoryProfile: NSObject, @unchecked Sendable {
    public let uniqueIdentifier: UUID
    public let services: [HMService]
    public internal(set) weak var accessory: HMAccessory?

    init(id: UUID, services: [HMService]) {
        uniqueIdentifier = id
        self.services = services
    }
}

open class HMAccessory: NSObject, @unchecked Sendable {
    public let uniqueIdentifier: UUID
    public weak var delegate: HMAccessoryDelegate?
    public internal(set) weak var home: HMHome?
    public private(set) var name = ""
    public private(set) var category = HMAccessoryCategory(categoryType: HMAccessoryCategoryTypeOther)
    public private(set) var services: [HMService] = []
    public var profiles: [HMAccessoryProfile] { [] }
    public private(set) var isReachable = false
    public private(set) var isBridged = false
    public private(set) var isBlocked = false
    public private(set) var model: String?
    public private(set) var manufacturer: String?
    public private(set) var firmwareVersion: String?
    public private(set) var supportsIdentify = false
    public private(set) var matterNodeID: UInt64?
    public internal(set) var bridgedAccessories: [HMAccessory]?
    public var isVendorAccessory: Bool { false }
    public var hapInstanceID: Int? { discoveredID == nil ? record.aid : nil }

    var record: SwiftCodeAccessoryRecord
    var discoveredID: UUID?

    init(id: UUID) {
        uniqueIdentifier = id
        record = SwiftCodeAccessoryRecord(id: id, name: "", categoryType: HMAccessoryCategoryTypeOther, manufacturer: nil,
                                      model: nil, firmwareVersion: nil, roomID: id, services: [], isReachable: false,
                                      isBlocked: false, isBridged: false, bridgedAccessoryIDs: [], supportsIdentify: false,
                                      endpointID: "", aid: 1, matterNodeID: nil)
    }

    convenience init(discovered d: SwiftCodeDiscoveredAccessoryRecord) {
        self.init(id: d.id)
        discoveredID = d.id
        name = d.name
        category = HMAccessoryCategory(categoryType: d.categoryType)
        isReachable = true
    }

    open override func isEqual(_ object: Any?) -> Bool { (object as? HMAccessory)?.uniqueIdentifier == uniqueIdentifier }
    open override var hash: Int { uniqueIdentifier.hashValue }

    public var room: HMRoom? { home?.room(record.roomID) }

    public var uniqueIdentifiersForBridgedAccessories: [UUID]? {
        record.bridgedAccessoryIDs.isEmpty ? nil : record.bridgedAccessoryIDs
    }

    func apply(_ r: SwiftCodeAccessoryRecord) {
        record = r
        discoveredID = nil
        name = r.name
        if category.categoryType != r.categoryType { category = HMAccessoryCategory(categoryType: r.categoryType) }
        isReachable = r.isReachable
        isBridged = r.isBridged
        isBlocked = r.isBlocked
        model = r.model
        manufacturer = r.manufacturer
        firmwareVersion = r.firmwareVersion
        supportsIdentify = r.supportsIdentify
        matterNodeID = r.matterNodeID
        let old = Dictionary(services.map { ($0.uniqueIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        services = r.services.map { sr in
            let s = old[sr.id] ?? HMService(id: sr.id)
            s.accessory = self
            s.apply(sr)
            return s
        }
        for (s, sr) in zip(services, r.services) {
            s.linkedServices = sr.linkedServiceIDs.isEmpty ? nil
                : sr.linkedServiceIDs.compactMap { id in services.first { $0.uniqueIdentifier == id } }
        }
    }

    public func updateName(_ name: String, completionHandler completion: @escaping (Error?) -> Void) {
        guard let home else { fail(completion, .objectNotAssociatedToAnyHome); return }
        home.connection.simple(.renameAccessory(home: home.uniqueIdentifier, accessory: uniqueIdentifier, name: name), completion)
    }

    public func identify(completionHandler completion: @escaping (Error?) -> Void) {
        guard let home else { fail(completion, .objectNotAssociatedToAnyHome); return }
        home.connection.simple(.identifyAccessory(home: home.uniqueIdentifier, accessory: uniqueIdentifier), completion)
    }

    public func updateName(_ name: String) async throws { try await asyncCall { updateName(name, completionHandler: $0) } }
    public func identify() async throws { try await asyncCall { identify(completionHandler: $0) } }
}

open class HMService: NSObject, @unchecked Sendable {
    public let uniqueIdentifier: UUID
    public internal(set) weak var accessory: HMAccessory?
    public private(set) var serviceType = ""
    public private(set) var localizedDescription = ""
    public private(set) var name = ""
    public private(set) var associatedServiceType: String?
    public private(set) var characteristics: [HMCharacteristic] = []
    public private(set) var isUserInteractive = true
    public private(set) var isPrimaryService = false
    public internal(set) var linkedServices: [HMService]?
    public var matterEndpointID: Int? { nil }

    init(id: UUID) { uniqueIdentifier = id }

    open override func isEqual(_ object: Any?) -> Bool { (object as? HMService)?.uniqueIdentifier == uniqueIdentifier }
    open override var hash: Int { uniqueIdentifier.hashValue }

    func apply(_ r: SwiftCodeServiceRecord) {
        serviceType = r.type
        localizedDescription = SwiftCodeHomeCatalog.localizedDescription(forType: r.type) ?? "Custom"
        name = r.name
        associatedServiceType = r.associatedType
        isUserInteractive = r.isUserInteractive
        isPrimaryService = r.isPrimary
        let old = Dictionary(characteristics.map { ($0.uniqueIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        characteristics = r.characteristics.map { cr in
            let c = old[cr.id] ?? HMCharacteristic(id: cr.id)
            c.service = self
            c.apply(cr)
            return c
        }
    }

    var home: HMHome? { accessory?.home }

    public func updateName(_ name: String, completionHandler completion: @escaping (Error?) -> Void) {
        guard let home else { fail(completion, .objectNotAssociatedToAnyHome); return }
        home.connection.simple(.renameService(home: home.uniqueIdentifier, service: uniqueIdentifier, name: name), completion)
    }

    public func updateAssociatedServiceType(_ serviceType: String?, completionHandler completion: @escaping (Error?) -> Void) {
        guard let home else { fail(completion, .objectNotAssociatedToAnyHome); return }
        home.connection.simple(.updateAssociatedServiceType(home: home.uniqueIdentifier, service: uniqueIdentifier,
                                                            type: serviceType), completion)
    }

    public func updateName(_ name: String) async throws { try await asyncCall { updateName(name, completionHandler: $0) } }
    public func updateAssociatedServiceType(_ serviceType: String?) async throws {
        try await asyncCall { updateAssociatedServiceType(serviceType, completionHandler: $0) }
    }
}

open class HMCharacteristicMetadata: NSObject, @unchecked Sendable {
    public let minimumValue: NSNumber?
    public let maximumValue: NSNumber?
    public let stepValue: NSNumber?
    public let maxLength: NSNumber?
    public let format: String?
    public let units: String?
    public let manufacturerDescription: String?
    public let validValues: [NSNumber]?

    let record: SwiftCodeCharacteristicMetadata

    init(_ m: SwiftCodeCharacteristicMetadata) {
        record = m
        minimumValue = m.minimumValue.map { NSNumber(value: $0) }
        maximumValue = m.maximumValue.map { NSNumber(value: $0) }
        stepValue = m.stepValue.map { NSNumber(value: $0) }
        maxLength = m.maxLength.map { NSNumber(value: $0) }
        format = m.format
        units = m.units
        manufacturerDescription = m.manufacturerDescription
        validValues = m.validValues.map { $0.map { NSNumber(value: $0) } }
    }

    open override func isEqual(_ object: Any?) -> Bool { (object as? HMCharacteristicMetadata)?.record == record }
    open override var hash: Int { record.hashValue }
}

open class HMCharacteristic: NSObject, @unchecked Sendable {
    public let uniqueIdentifier: UUID
    public internal(set) weak var service: HMService?
    public private(set) var characteristicType = ""
    public private(set) var localizedDescription = ""
    public private(set) var properties: [String] = []
    public private(set) var metadata: HMCharacteristicMetadata?
    public private(set) var isNotificationEnabled = false

    var cachedValue: SwiftCodeHomeValue?
    var record: SwiftCodeCharacteristicRecord?

    public var value: Any? { cachedValue?.apiValue }

    init(id: UUID) { uniqueIdentifier = id }

    open override func isEqual(_ object: Any?) -> Bool { (object as? HMCharacteristic)?.uniqueIdentifier == uniqueIdentifier }
    open override var hash: Int { uniqueIdentifier.hashValue }

    func apply(_ r: SwiftCodeCharacteristicRecord) {
        record = r
        characteristicType = r.type
        localizedDescription = SwiftCodeHomeCatalog.localizedDescription(forType: r.type) ?? "Custom"
        properties = r.properties
        if metadata?.record != r.metadata { metadata = r.metadata.map(HMCharacteristicMetadata.init) }
    }

    var home: HMHome? { service?.accessory?.home }

    public func readValue(completionHandler completion: @escaping (Error?) -> Void) {
        guard let home else { fail(completion, .objectNotAssociatedToAnyHome); return }
        guard properties.contains(HMCharacteristicPropertyReadable) else { fail(completion, .writeOnlyCharacteristic); return }
        home.connection.request(.readCharacteristic(home: home.uniqueIdentifier, characteristic: uniqueIdentifier)) { result in
            switch result {
            case .success(.value(let v)):
                self.cachedValue = v
                completion(nil)
            case .success: completion(nil)
            case .failure(let e): completion(e)
            }
        }
    }

    public func writeValue(_ value: Any?, completionHandler completion: @escaping (Error?) -> Void) {
        guard let home else { fail(completion, .objectNotAssociatedToAnyHome); return }
        guard properties.contains(HMCharacteristicPropertyWritable) else { fail(completion, .readOnlyCharacteristic); return }
        let checked: SwiftCodeHomeValue
        switch SwiftCodeValueValidation.validate(value, metadata: metadata?.record) {
        case .success(let v): checked = v
        case .failure(let e): onMain { completion(e) }; return
        }
        home.connection.simple(.writeCharacteristic(home: home.uniqueIdentifier, characteristic: uniqueIdentifier,
                                                    value: checked)) { error in
            if error == nil, self.properties.contains(HMCharacteristicPropertyReadable) { self.cachedValue = checked }
            completion(error)
        }
    }

    public func enableNotification(_ enable: Bool, completionHandler completion: @escaping (Error?) -> Void) {
        guard let home else { fail(completion, .objectNotAssociatedToAnyHome); return }
        guard properties.contains(HMCharacteristicPropertySupportsEventNotification) else {
            fail(completion, .notificationNotSupported); return
        }
        home.connection.simple(.enableNotification(home: home.uniqueIdentifier, characteristic: uniqueIdentifier,
                                                   enabled: enable)) { error in
            if error == nil { self.isNotificationEnabled = enable }
            completion(error)
        }
    }

    public func updateAuthorizationData(_ data: Data?, completionHandler completion: @escaping (Error?) -> Void) {
        guard let home else { fail(completion, .objectNotAssociatedToAnyHome); return }
        home.connection.simple(.updateAuthorizationData(home: home.uniqueIdentifier, characteristic: uniqueIdentifier,
                                                        data: data), completion)
    }

    public func readValue() async throws { try await asyncCall { readValue(completionHandler: $0) } }
    public func writeValue(_ value: Any?) async throws { try await asyncCall { writeValue(value, completionHandler: $0) } }
    public func enableNotification(_ enable: Bool) async throws {
        try await asyncCall { enableNotification(enable, completionHandler: $0) }
    }
    public func updateAuthorizationData(_ data: Data?) async throws {
        try await asyncCall { updateAuthorizationData(data, completionHandler: $0) }
    }
}

public protocol HMAccessoryBrowserDelegate: AnyObject {
    func accessoryBrowser(_ browser: HMAccessoryBrowser, didFindNewAccessory accessory: HMAccessory)
    func accessoryBrowser(_ browser: HMAccessoryBrowser, didRemoveNewAccessory accessory: HMAccessory)
}

public extension HMAccessoryBrowserDelegate {
    func accessoryBrowser(_ browser: HMAccessoryBrowser, didFindNewAccessory accessory: HMAccessory) {}
    func accessoryBrowser(_ browser: HMAccessoryBrowser, didRemoveNewAccessory accessory: HMAccessory) {}
}

open class HMAccessoryBrowser: NSObject, @unchecked Sendable {
    public weak var delegate: HMAccessoryBrowserDelegate?
    public private(set) var discoveredAccessories: [HMAccessory] = []
    let connection: SwiftCodeConnection
    private var searching = false

    public override convenience init() {
        self.init(swiftcodeStore: SwiftCodeLocalHomeStore.shared, client: .processDefault)
    }

    public init(swiftcodeStore store: SwiftCodeHomeStore, client: SwiftCodeHomeClient) {
        connection = SwiftCodeConnection(store: store)
        super.init()
        let session = store.connect(client: client) { [weak self] event in
            onMain { self?.handle(event) }
        }
        connection.sessionID = session.id
    }

    deinit { connection.store.disconnect(connection.sessionID) }

    public func startSearchingForNewAccessories() {
        searching = true
        connection.request(.setBrowsing(true)) { [weak self] result in
            guard let self, self.searching, case .success(.discovered(let list)) = result else { return }
            for d in list { self.found(d) }
        }
    }

    public func stopSearchingForNewAccessories() {
        searching = false
        connection.request(.setBrowsing(false)) { _ in }
    }

    private func found(_ d: SwiftCodeDiscoveredAccessoryRecord) {
        guard !discoveredAccessories.contains(where: { $0.uniqueIdentifier == d.id }) else { return }
        let a = HMAccessory(discovered: d)
        discoveredAccessories.append(a)
        delegate?.accessoryBrowser(self, didFindNewAccessory: a)
    }

    func handle(_ event: SwiftCodeHomeEvent) {
        guard searching else { return }
        switch event {
        case .accessoryDiscovered(let d): found(d)
        case .accessoryDiscoveryRemoved(let id):
            guard let i = discoveredAccessories.firstIndex(where: { $0.uniqueIdentifier == id }) else { return }
            let a = discoveredAccessories.remove(at: i)
            delegate?.accessoryBrowser(self, didRemoveNewAccessory: a)
        default: break
        }
    }
}
