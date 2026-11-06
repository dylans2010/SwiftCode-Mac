// An in-memory accessory server for tests (@@SWIFTCODE_ORIGINAL@@; open-design.md §3
// describes the networked `swiftcode-hap-sim` of R6, this is its in-process
// cousin). It answers like a HAP accessory: an attribute database with
// aid/iid numbering, HAP status codes for refused operations, events only
// for changes the controller did not write itself, and a control API for
// tests (press the device, force errors, cut the connection).

import Foundation

public final class SwiftCodeTestAccessory: SwiftCodeAccessoryEndpoint, @unchecked Sendable {
    /// A service of a test accessory.
    public struct Service: Sendable {
        public var type: String
        public var isPrimary: Bool
        public var isHidden: Bool
        public var characteristics: [SwiftCodeCharacteristicTemplate]

        public init(type: String, isPrimary: Bool = false, isHidden: Bool = false,
                    characteristics: [SwiftCodeCharacteristicTemplate]) {
            self.type = type
            self.isPrimary = isPrimary
            self.isHidden = isHidden
            self.characteristics = characteristics
        }

        /// A service whose characteristics come from `SwiftCodeCharacteristicDefaults`.
        public init(type: String, isPrimary: Bool = false, characteristicTypes: [String]) {
            self.init(type: type, isPrimary: isPrimary, characteristics: characteristicTypes.map {
                SwiftCodeCharacteristicDefaults.template($0)
                    ?? SwiftCodeCharacteristicTemplate(type: $0, permissions: [.pairedRead, .pairedWrite, .events],
                                                   metadata: SwiftCodeCharacteristicMetadata(), initialValue: nil)
            })
        }
    }

    /// One accessory (aid) of the server.
    public struct Accessory: Sendable {
        public var name: String
        public var manufacturer: String
        public var model: String
        public var serialNumber: String
        public var firmwareVersion: String
        public var services: [Service]

        public init(name: String, manufacturer: String = "SwiftCode", model: String = "Test Accessory",
                    serialNumber: String = "0001", firmwareVersion: String = "1.0.0", services: [Service]) {
            self.name = name
            self.manufacturer = manufacturer
            self.model = model
            self.serialNumber = serialNumber
            self.firmwareVersion = firmwareVersion
            self.services = services
        }
    }

    public let endpointID: String
    public let categoryNumber: Int
    public let name: String
    /// HAP setup code (unused until R5/R7 pairing).
    public let setupCode: String
    public weak var delegate: SwiftCodeAccessoryEndpointDelegate?

    private let lock = NSLock()
    private let queue: DispatchQueue
    private var database: SwiftCodeAccessoryDatabase
    private var reachable = true
    private var subscriptions: Set<SwiftCodeCharacteristicAddress> = []
    private var forced: [SwiftCodeCharacteristicAddress: SwiftCodeHAPStatus] = [:]
    private var writeLog: [(SwiftCodeCharacteristicAddress, SwiftCodeHomeValue)] = []
    private var identifies = 0
    private var authData: [SwiftCodeCharacteristicAddress: Data] = [:]
    /// Simulated response time of every request.
    public var responseDelay: TimeInterval = 0

    public init(endpointID: String? = nil, category: Int, setupCode: String = "031-45-154", accessories: [Accessory]) {
        precondition(!accessories.isEmpty, "a test accessory needs at least one accessory")
        self.endpointID = endpointID ?? SwiftCodeTestAccessory.randomDeviceID()
        self.categoryNumber = category
        self.name = accessories[0].name
        self.setupCode = setupCode
        self.queue = DispatchQueue(label: "swiftcode.homekit.test-accessory.\(self.endpointID)")
        var list: [SwiftCodeAccessoryDatabase.Accessory] = []
        for (index, acc) in accessories.enumerated() {
            var iid = 0
            func next() -> Int { iid += 1; return iid }
            func make(_ s: Service) -> SwiftCodeAccessoryDatabase.Service {
                let sid = next()
                let chars = s.characteristics.map { t in
                    SwiftCodeAccessoryDatabase.Characteristic(iid: next(), type: t.type, permissions: t.permissions,
                                                          metadata: t.metadata, value: t.initialValue)
                }
                return .init(iid: sid, type: s.type, isPrimary: s.isPrimary, isHidden: s.isHidden, characteristics: chars)
            }
            func info(_ type: String, _ value: String) -> SwiftCodeCharacteristicTemplate {
                var t = SwiftCodeCharacteristicDefaults.template(type)!
                t.initialValue = .string(value)
                return t
            }
            let infoService = Service(type: HMServiceTypeAccessoryInformation, characteristics: [
                SwiftCodeCharacteristicDefaults.template(HMCharacteristicTypeIdentify)!,
                info(HMCharacteristicTypeManufacturer, acc.manufacturer),
                info(HMCharacteristicTypeModel, acc.model),
                info(HMCharacteristicTypeName, acc.name),
                info(HMCharacteristicTypeSerialNumber, acc.serialNumber),
                info(HMCharacteristicTypeFirmwareVersion, acc.firmwareVersion),
            ])
            var services = [make(infoService)]
            services += acc.services.map(make)
            list.append(.init(aid: index + 1, services: services))
        }
        database = SwiftCodeAccessoryDatabase(accessories: list)
    }

    static func randomDeviceID() -> String {
        let u = UUID().uuid
        return [u.0, u.1, u.2, u.3, u.4, u.5].map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    // MARK: Control API (tests)

    /// Whether the server answers. Changing it tells the paired store.
    public var isReachable: Bool {
        get { lock.lock(); defer { lock.unlock() }; return reachable }
        set {
            lock.lock()
            let changed = reachable != newValue
            reachable = newValue
            lock.unlock()
            if changed { let id = endpointID; queue.async { self.delegate?.endpoint(id, didChangeReachability: newValue) } }
        }
    }

    /// Address of the first characteristic of `type` on accessory `aid`
    /// (optionally inside a service of `serviceType`).
    public func address(of type: String, aid: Int = 1, serviceType: String? = nil) -> SwiftCodeCharacteristicAddress? {
        let t = SwiftCodeHomeCatalog.normalizedTypeUUID(type) ?? type
        let st = serviceType.map { SwiftCodeHomeCatalog.normalizedTypeUUID($0) ?? $0 }
        lock.lock(); defer { lock.unlock() }
        guard let acc = database.accessories.first(where: { $0.aid == aid }) else { return nil }
        for s in acc.services where st == nil || s.type == st {
            if let c = s.characteristics.first(where: { $0.type == t }) { return .init(aid: aid, iid: c.iid) }
        }
        return nil
    }

    /// The device's current value.
    public func value(of type: String, aid: Int = 1) -> SwiftCodeHomeValue? {
        guard let a = address(of: type, aid: aid) else { return nil }
        lock.lock(); defer { lock.unlock() }
        return characteristic(a)?.value
    }

    /// A change made on the device itself (button press, sensor reading):
    /// stored, and sent as an event if the controller subscribed.
    public func simulateChange(_ type: String, to value: SwiftCodeHomeValue, aid: Int = 1) {
        guard let a = address(of: type, aid: aid) else { preconditionFailure("no characteristic \(type) on aid \(aid)") }
        lock.lock()
        setValue(value, at: a)
        let notify = subscriptions.contains(a)
        lock.unlock()
        if notify {
            let id = endpointID
            queue.async { self.delegate?.endpoint(id, didUpdateValues: [a: value]) }
        }
    }

    /// Makes every request for this characteristic fail with `status` (nil clears).
    public func forceStatus(_ status: SwiftCodeHAPStatus?, for type: String, aid: Int = 1) {
        guard let a = address(of: type, aid: aid) else { return }
        lock.lock(); forced[a] = status; lock.unlock()
    }

    /// Values written by the controller, in order.
    public var writes: [(address: SwiftCodeCharacteristicAddress, value: SwiftCodeHomeValue)] {
        lock.lock(); defer { lock.unlock() }
        return writeLog.map { (address: $0.0, value: $0.1) }
    }

    public var subscribedAddresses: Set<SwiftCodeCharacteristicAddress> {
        lock.lock(); defer { lock.unlock() }
        return subscriptions
    }

    public var identifyCount: Int { lock.lock(); defer { lock.unlock() }; return identifies }

    public func authorizationData(for type: String, aid: Int = 1) -> Data? {
        guard let a = address(of: type, aid: aid) else { return nil }
        lock.lock(); defer { lock.unlock() }
        return authData[a]
    }

    // MARK: SwiftCodeAccessoryEndpoint

    public func fetchDatabase(completion: @escaping @Sendable (Result<SwiftCodeAccessoryDatabase, SwiftCodeAccessoryFailure>) -> Void) {
        respond {
            self.lock.lock(); defer { self.lock.unlock() }
            return self.reachable ? .success(self.database) : .failure(.unreachable)
        } then: { completion($0) }
    }

    public func read(_ address: SwiftCodeCharacteristicAddress,
                     completion: @escaping @Sendable (Result<SwiftCodeHomeValue?, SwiftCodeAccessoryFailure>) -> Void) {
        respond { () -> Result<SwiftCodeHomeValue?, SwiftCodeAccessoryFailure> in
            self.lock.lock(); defer { self.lock.unlock() }
            if let f = self.check(address) { return .failure(f) }
            let c = self.characteristic(address)!
            guard c.permissions.contains(.pairedRead) else { return .failure(.status(.readFromWriteOnly)) }
            return .success(c.value)
        } then: { completion($0) }
    }

    public func write(_ address: SwiftCodeCharacteristicAddress, value: SwiftCodeHomeValue, authorizationData: Data?,
                      completion: @escaping @Sendable (Result<Void, SwiftCodeAccessoryFailure>) -> Void) {
        respond { () -> Result<Void, SwiftCodeAccessoryFailure> in
            self.lock.lock(); defer { self.lock.unlock() }
            if let f = self.check(address) { return .failure(f) }
            let c = self.characteristic(address)!
            guard c.permissions.contains(.pairedWrite) else { return .failure(.status(.writeToReadOnly)) }
            if c.permissions.contains(.additionalAuthorization), authorizationData == nil {
                return .failure(.status(.insufficientAuthorization))
            }
            if case .failure = SwiftCodeValueValidation.validate(value.apiValue, metadata: c.metadata) {
                return .failure(.status(.invalidValue))
            }
            if let authorizationData { self.authData[address] = authorizationData }
            self.writeLog.append((address, value))
            // Write-only control points keep no readable value.
            if c.permissions.contains(.pairedRead) { self.setValue(value, at: address) }
            return .success(())
        } then: { completion($0) }
    }

    public func setEventsEnabled(_ enabled: Bool, for address: SwiftCodeCharacteristicAddress,
                                 completion: @escaping @Sendable (Result<Void, SwiftCodeAccessoryFailure>) -> Void) {
        respond { () -> Result<Void, SwiftCodeAccessoryFailure> in
            self.lock.lock(); defer { self.lock.unlock() }
            if let f = self.check(address) { return .failure(f) }
            guard self.characteristic(address)!.permissions.contains(.events) else {
                return .failure(.status(.notificationNotSupported))
            }
            if enabled { self.subscriptions.insert(address) } else { self.subscriptions.remove(address) }
            return .success(())
        } then: { completion($0) }
    }

    public func identify(completion: @escaping @Sendable (Result<Void, SwiftCodeAccessoryFailure>) -> Void) {
        respond { () -> Result<Void, SwiftCodeAccessoryFailure> in
            self.lock.lock(); defer { self.lock.unlock() }
            guard self.reachable else { return .failure(.unreachable) }
            self.identifies += 1
            return .success(())
        } then: { completion($0) }
    }

    // MARK: Internals (lock held)

    private func respond<T>(_ work: @escaping @Sendable () -> T, then: @escaping @Sendable (T) -> Void) {
        let delay = responseDelay
        let run: @Sendable () -> Void = { then(work()) }
        if delay > 0 { queue.asyncAfter(deadline: .now() + delay, execute: run) } else { queue.async(execute: run) }
    }

    private func check(_ a: SwiftCodeCharacteristicAddress) -> SwiftCodeAccessoryFailure? {
        guard reachable else { return .unreachable }
        guard characteristic(a) != nil else { return .status(.resourceDoesNotExist) }
        if let s = forced[a] { return .status(s) }
        return nil
    }

    private func characteristic(_ a: SwiftCodeCharacteristicAddress) -> SwiftCodeAccessoryDatabase.Characteristic? {
        guard let acc = database.accessories.first(where: { $0.aid == a.aid }) else { return nil }
        for s in acc.services {
            if let c = s.characteristics.first(where: { $0.iid == a.iid }) { return c }
        }
        return nil
    }

    private func setValue(_ v: SwiftCodeHomeValue, at a: SwiftCodeCharacteristicAddress) {
        guard let ai = database.accessories.firstIndex(where: { $0.aid == a.aid }) else { return }
        for si in database.accessories[ai].services.indices {
            if let ci = database.accessories[ai].services[si].characteristics.firstIndex(where: { $0.iid == a.iid }) {
                database.accessories[ai].services[si].characteristics[ci].value = v
                return
            }
        }
    }
}

// MARK: - Presets

extension SwiftCodeTestAccessory {
    /// A dimmable color lightbulb (HAP category 5).
    public static func lightbulb(name: String = "Test Lightbulb") -> SwiftCodeTestAccessory {
        SwiftCodeTestAccessory(category: 5, accessories: [lightbulbAccessory(name: name)])
    }

    public static func lightbulbAccessory(name: String) -> Accessory {
        Accessory(name: name, model: "Test Lightbulb", services: [
            Service(type: HMServiceTypeLightbulb, isPrimary: true, characteristicTypes: [
                HMCharacteristicTypePowerState, HMCharacteristicTypeBrightness, HMCharacteristicTypeHue,
                HMCharacteristicTypeSaturation, HMCharacteristicTypeColorTemperature,
            ]),
        ])
    }

    /// An outlet (category 7).
    public static func outlet(name: String = "Test Outlet") -> SwiftCodeTestAccessory {
        SwiftCodeTestAccessory(category: 7, accessories: [Accessory(name: name, model: "Test Outlet", services: [
            Service(type: HMServiceTypeOutlet, isPrimary: true,
                    characteristicTypes: [HMCharacteristicTypePowerState, HMCharacteristicTypeOutletInUse]),
        ])])
    }

    /// A switch (category 8).
    public static func `switch`(name: String = "Test Switch") -> SwiftCodeTestAccessory {
        SwiftCodeTestAccessory(category: 8, accessories: [switchAccessory(name: name)])
    }

    public static func switchAccessory(name: String) -> Accessory {
        Accessory(name: name, model: "Test Switch", services: [
            Service(type: HMServiceTypeSwitch, isPrimary: true, characteristicTypes: [HMCharacteristicTypePowerState]),
        ])
    }

    /// A thermostat (category 9).
    public static func thermostat(name: String = "Test Thermostat") -> SwiftCodeTestAccessory {
        SwiftCodeTestAccessory(category: 9, accessories: [Accessory(name: name, model: "Test Thermostat", services: [
            Service(type: HMServiceTypeThermostat, isPrimary: true, characteristicTypes: [
                HMCharacteristicTypeCurrentHeatingCooling, HMCharacteristicTypeTargetHeatingCooling,
                HMCharacteristicTypeCurrentTemperature, HMCharacteristicTypeTargetTemperature,
                HMCharacteristicTypeTemperatureUnits, HMCharacteristicTypeCurrentRelativeHumidity,
            ]),
        ])])
    }

    /// A door lock with a lock-management service (category 6); its control
    /// point is write-only, its version read-only without notifications.
    public static func lock(name: String = "Test Lock") -> SwiftCodeTestAccessory {
        SwiftCodeTestAccessory(category: 6, accessories: [Accessory(name: name, model: "Test Lock", services: [
            Service(type: HMServiceTypeLockMechanism, isPrimary: true, characteristicTypes: [
                HMCharacteristicTypeCurrentLockMechanismState, HMCharacteristicTypeTargetLockMechanismState,
            ]),
            Service(type: HMServiceTypeLockManagement, characteristicTypes: [
                HMCharacteristicTypeLockManagementControlPoint, HMCharacteristicTypeVersion,
            ]),
        ])])
    }

    /// A temperature sensor with a battery (category 10).
    public static func temperatureSensor(name: String = "Test Sensor") -> SwiftCodeTestAccessory {
        SwiftCodeTestAccessory(category: 10, accessories: [Accessory(name: name, model: "Test Sensor", services: [
            Service(type: HMServiceTypeTemperatureSensor, isPrimary: true,
                    characteristicTypes: [HMCharacteristicTypeCurrentTemperature]),
            Service(type: HMServiceTypeBattery, characteristicTypes: [
                HMCharacteristicTypeBatteryLevel, HMCharacteristicTypeChargingState, HMCharacteristicTypeStatusLowBattery,
            ]),
        ])])
    }

    /// A garage door opener (category 4).
    public static func garageDoor(name: String = "Test Garage Door") -> SwiftCodeTestAccessory {
        SwiftCodeTestAccessory(category: 4, accessories: [Accessory(name: name, model: "Test Garage Door", services: [
            Service(type: HMServiceTypeGarageDoorOpener, isPrimary: true, characteristicTypes: [
                HMCharacteristicTypeCurrentDoorState, HMCharacteristicTypeTargetDoorState,
                HMCharacteristicTypeObstructionDetected,
            ]),
        ])])
    }

    /// A bridge (category 2, aid 1, no services of its own beyond accessory
    /// information) hosting `children` as aid 2, 3, ….
    public static func bridge(name: String = "Test Bridge", children: [Accessory]) -> SwiftCodeTestAccessory {
        SwiftCodeTestAccessory(category: 2, accessories: [Accessory(name: name, model: "Test Bridge", services: [])] + children)
    }
}
