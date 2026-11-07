import Foundation
import Testing
@testable import HomeKit

let mainKey = DispatchSpecificKey<Bool>()
private let mainKeyOnce: Void = { DispatchQueue.main.setSpecific(key: mainKey, value: true) }()

func onMainQueue() -> Bool {
    _ = mainKeyOnce
    return DispatchQueue.getSpecific(key: mainKey) == true
}

func flushMain() async {
    _ = mainKeyOnce
    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in DispatchQueue.main.async { c.resume() } }
}

func settle(_ store: SwiftCodeLocalHomeStore) async {
    for _ in 0..<3 {
        store.sync {}
        await flushMain()
    }
}

func eventually(_ store: SwiftCodeLocalHomeStore, timeout: Double = 5, _ condition: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        await settle(store)
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return condition()
}

func client(_ bundle: String = "local.swiftcode.homekit-tests", usage: String? = "Tests control made-up accessories.",
            entitled: Bool = true) -> SwiftCodeHomeClient {
    SwiftCodeHomeClient(bundleIdentifier: bundle, usageDescription: usage, hasHomeKitEntitlement: entitled)
}

func newStore(noAccount: Bool = false, hub: HMHomeHubState = .connected, url: URL? = nil,
              consent: @escaping @Sendable (SwiftCodeHomeClient) -> Bool = { _ in true }) -> SwiftCodeLocalHomeStore {
    SwiftCodeLocalHomeStore(configuration: .init(persistenceURL: url, simulateNoAccount: noAccount, hubState: hub, consent: consent))
}

func loadedManager(_ store: SwiftCodeLocalHomeStore, _ c: SwiftCodeHomeClient = client(),
                   delegate: HMHomeManagerDelegate? = nil) async -> HMHomeManager {
    let m = HMHomeManager(swiftcodeStore: store, client: c)
    m.delegate = delegate
    await settle(store)
    return m
}

private let keepLock = NSLock()
nonisolated(unsafe) private var keptManagers: [HMHomeManager] = []
private func keep(_ m: HMHomeManager) { keepLock.lock(); keptManagers.append(m); keepLock.unlock() }

func homeFixture(_ name: String = "Test Home", store: SwiftCodeLocalHomeStore = newStore()) async throws
    -> (SwiftCodeLocalHomeStore, HMHomeManager, HMHome) {
    let m = await loadedManager(store)
    keep(m)
    let h = try await m.addHome(named: name)
    return (store, m, h)
}

@discardableResult
func pair(_ endpoint: SwiftCodeAccessoryEndpoint, into home: HMHome, store: SwiftCodeLocalHomeStore) async throws -> HMAccessory {
    store.publish(endpoint)
    let browser = HMAccessoryBrowser(swiftcodeStore: store, client: client())
    browser.startSearchingForNewAccessories()
    let found = await eventually(store) { browser.discoveredAccessories.contains { $0.name == endpoint.name } }
    #expect(found)
    let candidate = browser.discoveredAccessories.first { $0.name == endpoint.name }!
    try await home.addAccessory(candidate)
    browser.stopSearchingForNewAccessories()
    return home.accessories.first { $0.uniqueIdentifier == candidate.uniqueIdentifier }!
}

func characteristic(_ accessory: HMAccessory, _ type: String) -> HMCharacteristic {
    accessory.services.flatMap(\.characteristics).first { $0.characteristicType == type }!
}

func expectCode(_ code: HMError.Code, sourceLocation: SourceLocation = #_sourceLocation, _ body: () async throws -> Void) async {
    do {
        try await body()
        Issue.record("expected HMError \(code.rawValue), got success", sourceLocation: sourceLocation)
    } catch {
        let ns = error as NSError
        #expect(ns.domain == "HMErrorDomain", sourceLocation: sourceLocation)
        #expect(ns.code == code.rawValue, "got \(ns.code)", sourceLocation: sourceLocation)
        #expect((error as? HMError)?.code == code, sourceLocation: sourceLocation)
    }
}

final class Recorder: HMHomeManagerDelegate, HMHomeDelegate, HMAccessoryDelegate, HMAccessoryBrowserDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _log: [String] = []
    private var _offMain = 0

    var log: [String] { lock.lock(); defer { lock.unlock() }; return _log }
    var offMain: Int { lock.lock(); defer { lock.unlock() }; return _offMain }

    func note(_ s: String) {
        lock.lock()
        if !onMainQueue() { _offMain += 1 }
        _log.append(s)
        lock.unlock()
    }

    func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) { note("auth \(status.rawValue)") }
    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) { note("homes \(manager.homes.count)") }
    func homeManager(_ manager: HMHomeManager, didAdd home: HMHome) { note("add home \(home.name)") }
    func homeManager(_ manager: HMHomeManager, didRemove home: HMHome) { note("remove home \(home.name)") }

    func homeDidUpdateName(_ home: HMHome) { note("home name \(home.name)") }
    func home(_ home: HMHome, didAdd accessory: HMAccessory) { note("add accessory \(accessory.name)") }
    func home(_ home: HMHome, didRemove accessory: HMAccessory) { note("remove accessory \(accessory.name)") }
    func home(_ home: HMHome, didUpdate room: HMRoom, for accessory: HMAccessory) { note("room \(room.name) for \(accessory.name)") }
    func home(_ home: HMHome, didAdd room: HMRoom) { note("add room \(room.name)") }
    func home(_ home: HMHome, didRemove room: HMRoom) { note("remove room \(room.name)") }
    func home(_ home: HMHome, didUpdateNameFor room: HMRoom) { note("rename room \(room.name)") }
    func home(_ home: HMHome, didAdd zone: HMZone) { note("add zone \(zone.name)") }
    func home(_ home: HMHome, didRemove zone: HMZone) { note("remove zone \(zone.name)") }
    func home(_ home: HMHome, didAdd room: HMRoom, to zone: HMZone) { note("add room \(room.name) to \(zone.name)") }
    func home(_ home: HMHome, didRemove room: HMRoom, from zone: HMZone) { note("remove room \(room.name) from \(zone.name)") }
    func home(_ home: HMHome, didAdd group: HMServiceGroup) { note("add group \(group.name)") }
    func home(_ home: HMHome, didUpdateNameFor group: HMServiceGroup) { note("rename group \(group.name)") }
    func home(_ home: HMHome, didRemove group: HMServiceGroup) { note("remove group \(group.name)") }
    func home(_ home: HMHome, didAdd service: HMService, to group: HMServiceGroup) { note("add service \(service.name) to \(group.name)") }
    func home(_ home: HMHome, didAdd actionSet: HMActionSet) { note("add scene \(actionSet.name)") }
    func home(_ home: HMHome, didUpdateActionsFor actionSet: HMActionSet) { note("actions \(actionSet.name)") }
    func home(_ home: HMHome, didAdd trigger: HMTrigger) { note("add trigger \(trigger.name)") }
    func home(_ home: HMHome, didUpdate trigger: HMTrigger) { note("update trigger \(trigger.name)") }

    func accessoryDidUpdateName(_ accessory: HMAccessory) { note("accessory name \(accessory.name)") }
    func accessoryDidUpdateReachability(_ accessory: HMAccessory) { note("reachable \(accessory.isReachable)") }
    func accessory(_ accessory: HMAccessory, service: HMService, didUpdateValueFor characteristic: HMCharacteristic) {
        let v: String
        if let n = characteristic.value as? NSNumber { v = String(n.doubleValue) } else { v = characteristic.value.map { "\($0)" } ?? "nil" }
        note("value \(SwiftCodeHomeCatalog.characteristicType(characteristic.characteristicType)?.name ?? "?") \(v)")
    }
    func accessory(_ accessory: HMAccessory, didUpdateNameFor service: HMService) { note("service name \(service.name)") }

    func accessoryBrowser(_ browser: HMAccessoryBrowser, didFindNewAccessory accessory: HMAccessory) { note("found \(accessory.name)") }
    func accessoryBrowser(_ browser: HMAccessoryBrowser, didRemoveNewAccessory accessory: HMAccessory) { note("lost \(accessory.name)") }
}
