import Foundation
import OVPlatform
#if OPENVIEWS_RENAMED
import OpenViewsCore
#else
import SwiftUICore
#endif

struct StorageCodec<Value> {
    let encode: (Value) -> Any?
    let decode: (Any) -> Value?
}

extension StorageCodec {
    static func plain<T>(_: T.Type) -> StorageCodec<T> {
        StorageCodec<T>(encode: { $0 }, decode: { $0 as? T })
    }
}

func storageEqual(_ a: Any?, _ b: Any?) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case let (x?, y?):
        if let x = x as? AnyHashable, let y = y as? AnyHashable { return x == y }
        if let x = x as? NSObject, let y = y as? NSObject { return x.isEqual(y) }
        return String(describing: x) == String(describing: y)
    default: return false
    }
}

@MainActor
final class AppStorageCenter {
    static let shared = AppStorageCenter()
    private var locations: [ObjectIdentifier: WeakAppStorageLocation] = [:]
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                                          queue: nil) { _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated { AppStorageCenter.shared.refreshAll() }
            } else {
                DispatchQueue.main.async { MainActor.assumeIsolated { AppStorageCenter.shared.refreshAll() } }
            }
        }
    }

    func add(_ l: AppStorageLocationBase) { locations[ObjectIdentifier(l)] = WeakAppStorageLocation(l) }

    func refreshIfObserved() {
        guard !locations.isEmpty else { return }
        refreshAll()
    }

    func refreshAll() {
        for (id, w) in locations {
            guard let l = w.location else { locations[id] = nil; continue }
            l.refresh(transaction: Transaction())
        }
    }

    func changed(store: UserDefaults, key: String, except: AppStorageLocationBase?, transaction: Transaction) {
        for (id, w) in locations {
            guard let l = w.location else { locations[id] = nil; continue }
            if l !== except, l.store === store, l.key == key { l.refresh(transaction: transaction) }
        }
    }
}

final class WeakAppStorageLocation {
    weak var location: AppStorageLocationBase?
    init(_ l: AppStorageLocationBase) { location = l }
}

class AppStorageLocationBase: @unchecked Sendable {
    let dependency = DependencySource()
    let key: String
    let store: UserDefaults
    var lastObject: Any?

    init(key: String, store: UserDefaults) {
        self.key = key
        self.store = store
        lastObject = store.object(forKey: key)
    }

    @MainActor func refresh(transaction: Transaction) {
        let now = store.object(forKey: key)
        guard !storageEqual(now, lastObject) else { return }
        lastObject = now
        dependency.invalidateDependents(transaction: transaction)
    }
}

final class AppStorageLocation<Value>: AppStorageLocationBase, @unchecked Sendable {
    let defaultValue: Value
    let codec: StorageCodec<Value>

    init(key: String, store: UserDefaults, defaultValue: Value, codec: StorageCodec<Value>) {
        self.defaultValue = defaultValue
        self.codec = codec
        super.init(key: key, store: store)
    }

    func read() -> Value {
        DependencyTracker.recordRead(dependency)
        return current
    }

    var current: Value { store.object(forKey: key).flatMap(codec.decode) ?? defaultValue }

    @MainActor func write(_ v: Value, transaction: Transaction?) {
        let tx = transaction ?? Transaction._current
        if let o = codec.encode(v) { store.set(o, forKey: key) } else { store.removeObject(forKey: key) }
        let now = store.object(forKey: key)
        if !storageEqual(now, lastObject) {
            lastObject = now
            dependency.invalidateDependents(transaction: tx)
        }
        AppStorageCenter.shared.changed(store: store, key: key, except: self, transaction: tx)
    }
}

final class AppStorageHandle<Value>: @unchecked Sendable {
    var location: AppStorageLocation<Value>?
}

private enum DefaultAppStorageKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: UserDefaults? = nil
}

extension EnvironmentValues {
    var _defaultAppStorage: UserDefaults? {
        get { self[DefaultAppStorageKey.self] }
        set { self[DefaultAppStorageKey.self] = newValue }
    }
}

extension View {
    public func defaultAppStorage(_ store: UserDefaults) -> some View {
        environment(\._defaultAppStorage, store)
    }
}

extension Scene {
    public func defaultAppStorage(_ store: UserDefaults) -> _ModifiedScene<Self> {
        _ModifiedScene(content: self) { $0.environment.append { $0._defaultAppStorage = store } }
    }
}

@propertyWrapper
public struct AppStorage<Value>: DynamicProperty {
    let key: String
    let defaultValue: Value
    let store: UserDefaults?
    let codec: StorageCodec<Value>
    let handle = AppStorageHandle<Value>()

    init(key: String, defaultValue: Value, store: UserDefaults?, codec: StorageCodec<Value>) {
        self.key = key
        self.defaultValue = defaultValue
        self.store = store
        self.codec = codec
    }

    private var fallbackStore: UserDefaults { store ?? .standard }

    public var wrappedValue: Value {
        get {
            if let l = handle.location { return l.read() }
            return fallbackStore.object(forKey: key).flatMap(codec.decode) ?? defaultValue
        }
        nonmutating set {
            if let l = handle.location {
                let b = UncheckedBox(newValue)
                MainActor.assumeIsolated { l.write(b.value, transaction: nil) }
            } else if let o = codec.encode(newValue) {
                fallbackStore.set(o, forKey: key)
            } else {
                fallbackStore.removeObject(forKey: key)
            }
        }
    }

    public var projectedValue: Binding<Value> {
        let h = handle, key = key, codec = codec, d = defaultValue, s = fallbackStore
        return Binding(get: {
            h.location?.read() ?? (s.object(forKey: key).flatMap(codec.decode) ?? d)
        }, set: { v, tx in
            guard let l = h.location else { return }
            let b = UncheckedBox((v, tx))
            MainActor.assumeIsolated { l.write(b.value.0, transaction: b.value.1) }
        })
    }
}

extension AppStorage: @unchecked Sendable {}

extension AppStorage: GraphDynamicProperty {
    package func _install(in node: ViewNode, slot: Int) {
        let s = store ?? node.environment._defaultAppStorage ?? .standard
        if let l = node.slots[slot] as? AppStorageLocation<Value>, l.key == key, l.store === s {
            handle.location = l
            return
        }
        let l = AppStorageLocation(key: key, store: s, defaultValue: defaultValue, codec: codec)
        node.slots[slot] = l
        handle.location = l
        AppStorageCenter.shared.add(l)
    }
}

extension AppStorage: GraphInputComparable {
    package func _isGraphInputEqual(to other: Any) -> Bool {
        guard let o = other as? AppStorage<Value> else { return false }
        return o.key == key && o.store === store
    }
}

extension AppStorage {
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Bool {
        self.init(key: key, defaultValue: wrappedValue, store: store, codec: .plain(Bool.self))
    }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Int {
        self.init(key: key, defaultValue: wrappedValue, store: store,
                  codec: StorageCodec(encode: { $0 }, decode: { ($0 as? Int) ?? ($0 as? NSNumber)?.intValue }))
    }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Double {
        self.init(key: key, defaultValue: wrappedValue, store: store,
                  codec: StorageCodec(encode: { $0 }, decode: { ($0 as? Double) ?? ($0 as? NSNumber)?.doubleValue }))
    }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == String {
        self.init(key: key, defaultValue: wrappedValue, store: store, codec: .plain(String.self))
    }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == URL {
        self.init(key: key, defaultValue: wrappedValue, store: store,
                  codec: StorageCodec(encode: { $0.absoluteString }, decode: { ($0 as? String).flatMap(URL.init(string:)) }))
    }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Data {
        self.init(key: key, defaultValue: wrappedValue, store: store, codec: .plain(Data.self))
    }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Date {
        self.init(key: key, defaultValue: wrappedValue, store: store, codec: .plain(Date.self))
    }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil)
        where Value: RawRepresentable, Value.RawValue == Int {
        self.init(key: key, defaultValue: wrappedValue, store: store,
                  codec: StorageCodec(encode: { $0.rawValue }, decode: { (($0 as? Int) ?? ($0 as? NSNumber)?.intValue).flatMap(Value.init(rawValue:)) }))
    }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil)
        where Value: RawRepresentable, Value.RawValue == String {
        self.init(key: key, defaultValue: wrappedValue, store: store,
                  codec: StorageCodec(encode: { $0.rawValue }, decode: { ($0 as? String).flatMap(Value.init(rawValue:)) }))
    }
    public init(_ key: String, store: UserDefaults? = nil) where Value == Bool? {
        self.init(key: key, defaultValue: nil, store: store, codec: StorageCodec(encode: { $0 }, decode: { $0 as? Bool }))
    }
    public init(_ key: String, store: UserDefaults? = nil) where Value == Int? {
        self.init(key: key, defaultValue: nil, store: store,
                  codec: StorageCodec(encode: { $0 }, decode: { ($0 as? Int) ?? ($0 as? NSNumber)?.intValue }))
    }
    public init(_ key: String, store: UserDefaults? = nil) where Value == Double? {
        self.init(key: key, defaultValue: nil, store: store,
                  codec: StorageCodec(encode: { $0 }, decode: { ($0 as? Double) ?? ($0 as? NSNumber)?.doubleValue }))
    }
    public init(_ key: String, store: UserDefaults? = nil) where Value == String? {
        self.init(key: key, defaultValue: nil, store: store, codec: StorageCodec(encode: { $0 }, decode: { $0 as? String }))
    }
    public init(_ key: String, store: UserDefaults? = nil) where Value == URL? {
        self.init(key: key, defaultValue: nil, store: store,
                  codec: StorageCodec(encode: { $0?.absoluteString }, decode: { ($0 as? String).flatMap(URL.init(string:)) }))
    }
    public init(_ key: String, store: UserDefaults? = nil) where Value == Data? {
        self.init(key: key, defaultValue: nil, store: store, codec: StorageCodec(encode: { $0 }, decode: { $0 as? Data }))
    }
}

@MainActor
package final class SceneStorageStore {
    final class Entry: @unchecked Sendable {
        var value: Any?
        let dependency = DependencySource()
    }

    private var entries: [String: Entry] = [:]
    package var archiveKey = ""

    package init(values: [String: Any] = [:]) {
        for (k, v) in values {
            let e = Entry()
            e.value = v
            entries[k] = e
        }
    }

    func entry(_ key: String) -> Entry {
        if let e = entries[key] { return e }
        let e = Entry()
        entries[key] = e
        return e
    }

    package var values: [String: Any] { entries.compactMapValues(\.value) }

    package func value(forKey key: String) -> Any? { entries[key]?.value }
}

private enum SceneStorageStoreKey: EnvironmentKey {
    static let defaultValue: SceneStorageStore? = nil
}

extension EnvironmentValues {
    package var _sceneStorage: SceneStorageStore? {
        get { self[SceneStorageStoreKey.self] }
        set { self[SceneStorageStoreKey.self] = newValue }
    }
}

@MainActor
package final class SceneStorageArchive {
    package let directory: URL

    package init(directory: URL) { self.directory = directory }

    package static func forCurrentProcess() -> SceneStorageArchive {
        let env = ProcessInfo.processInfo.environment
        let base = env["XDG_STATE_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/state")
        let name = (Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName)
            .replacingOccurrences(of: "/", with: "_")
        return SceneStorageArchive(directory: base.appendingPathComponent("openviews/\(name)/scenes"))
    }

    private func file(_ key: String) -> URL {
        directory.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_") + ".plist")
    }

    package func save(_ store: SceneStorageStore) {
        guard !store.archiveKey.isEmpty else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? PropertyListSerialization.data(fromPropertyList: store.values, format: .binary, options: 0) else { return }
        try? data.write(to: file(store.archiveKey), options: .atomic)
    }

    package func restore(key: String) -> SceneStorageStore? {
        guard let data = try? Data(contentsOf: file(key)),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        return SceneStorageStore(values: plist)
    }

    package func discard(key: String) {
        guard !key.isEmpty else { return }
        try? FileManager.default.removeItem(at: file(key))
    }

    package func discardAll() { try? FileManager.default.removeItem(at: directory) }
}

final class SceneStorageHandle<Value>: @unchecked Sendable {
    var entry: SceneStorageStore.Entry?
}

@propertyWrapper
public struct SceneStorage<Value>: DynamicProperty {
    let key: String
    let defaultValue: Value
    let codec: StorageCodec<Value>
    let handle = SceneStorageHandle<Value>()

    init(key: String, defaultValue: Value, codec: StorageCodec<Value>) {
        self.key = key
        self.defaultValue = defaultValue
        self.codec = codec
    }

    public var wrappedValue: Value {
        get {
            guard let e = handle.entry else { return defaultValue }
            DependencyTracker.recordRead(e.dependency)
            return e.value.flatMap(codec.decode) ?? defaultValue
        }
        nonmutating set {
            guard let e = handle.entry else { return }
            let b = UncheckedBox(codec.encode(newValue))
            MainActor.assumeIsolated {
                guard !storageEqual(b.value, e.value) else { return }
                e.value = b.value
                e.dependency.invalidateDependents(transaction: Transaction._current)
            }
        }
    }

    public var projectedValue: Binding<Value> {
        let h = handle, codec = codec, d = defaultValue
        return Binding(get: {
            guard let e = h.entry else { return d }
            DependencyTracker.recordRead(e.dependency)
            return e.value.flatMap(codec.decode) ?? d
        }, set: { v, tx in
            guard let e = h.entry else { return }
            let b = UncheckedBox((codec.encode(v), tx))
            MainActor.assumeIsolated {
                guard !storageEqual(b.value.0, e.value) else { return }
                e.value = b.value.0
                e.dependency.invalidateDependents(transaction: b.value.1)
            }
        })
    }
}

extension SceneStorage: @unchecked Sendable {}

extension SceneStorage: GraphDynamicProperty {
    package func _install(in node: ViewNode, slot: Int) {
        guard let store = node.environment._sceneStorage else { return }
        handle.entry = store.entry(key)
    }
}

extension SceneStorage: GraphInputComparable {
    package func _isGraphInputEqual(to other: Any) -> Bool { (other as? SceneStorage<Value>)?.key == key }
}

extension SceneStorage {
    public init(wrappedValue: Value, _ key: String) where Value == Bool {
        self.init(key: key, defaultValue: wrappedValue, codec: .plain(Bool.self))
    }
    public init(wrappedValue: Value, _ key: String) where Value == Int {
        self.init(key: key, defaultValue: wrappedValue,
                  codec: StorageCodec(encode: { $0 }, decode: { ($0 as? Int) ?? ($0 as? NSNumber)?.intValue }))
    }
    public init(wrappedValue: Value, _ key: String) where Value == Double {
        self.init(key: key, defaultValue: wrappedValue,
                  codec: StorageCodec(encode: { $0 }, decode: { ($0 as? Double) ?? ($0 as? NSNumber)?.doubleValue }))
    }
    public init(wrappedValue: Value, _ key: String) where Value == String {
        self.init(key: key, defaultValue: wrappedValue, codec: .plain(String.self))
    }
    public init(wrappedValue: Value, _ key: String) where Value == URL {
        self.init(key: key, defaultValue: wrappedValue,
                  codec: StorageCodec(encode: { $0.absoluteString }, decode: { ($0 as? String).flatMap(URL.init(string:)) }))
    }
    public init(wrappedValue: Value, _ key: String) where Value == Data {
        self.init(key: key, defaultValue: wrappedValue, codec: .plain(Data.self))
    }
    public init(wrappedValue: Value, _ key: String) where Value: RawRepresentable, Value.RawValue == Int {
        self.init(key: key, defaultValue: wrappedValue,
                  codec: StorageCodec(encode: { $0.rawValue }, decode: { (($0 as? Int) ?? ($0 as? NSNumber)?.intValue).flatMap(Value.init(rawValue:)) }))
    }
    public init(wrappedValue: Value, _ key: String) where Value: RawRepresentable, Value.RawValue == String {
        self.init(key: key, defaultValue: wrappedValue,
                  codec: StorageCodec(encode: { $0.rawValue }, decode: { ($0 as? String).flatMap(Value.init(rawValue:)) }))
    }
    public init(_ key: String) where Value == String? {
        self.init(key: key, defaultValue: nil, codec: StorageCodec(encode: { $0 }, decode: { $0 as? String }))
    }
    public init(_ key: String) where Value == Int? {
        self.init(key: key, defaultValue: nil,
                  codec: StorageCodec(encode: { $0 }, decode: { ($0 as? Int) ?? ($0 as? NSNumber)?.intValue }))
    }
    public init(_ key: String) where Value == Bool? {
        self.init(key: key, defaultValue: nil, codec: StorageCodec(encode: { $0 }, decode: { $0 as? Bool }))
    }
}
