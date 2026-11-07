import Foundation

public func fourCC(_ s: String) -> UInt32 {
    var v: UInt32 = 0
    for b in s.utf8.prefix(4) { v = v << 8 | UInt32(b) }
    return v
}

public func fourCCText(_ v: UInt32) -> String {
    let bytes = [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    if bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) { return "'" + String(decoding: bytes, as: UTF8.self) + "'" }
    return "0x" + String(v, radix: 16)
}

public struct AudioPropertyAddress: Hashable, Sendable, CustomStringConvertible {
    public var selector: UInt32
    public var scope: UInt32
    public var element: UInt32
    public init(_ selector: UInt32, _ scope: UInt32 = AudioHAL.scopeGlobal, _ element: UInt32 = 0) {
        self.selector = selector
        self.scope = scope
        self.element = element
    }
    public init(_ selector: String, _ scope: UInt32 = AudioHAL.scopeGlobal, _ element: UInt32 = 0) {
        self.init(fourCC(selector), scope, element)
    }
    public var description: String { "\(fourCCText(selector))/\(fourCCText(scope))/\(element)" }
}

public enum AudioValue: Equatable, Sendable {
    case u32(UInt32)
    case f32(Float)
    case f64(Double)
    case u32s([UInt32])
    case f64s([Double])
    case string(String)
    case plist([UInt8])
    case bytes([UInt8])

    public var rawBytes: [UInt8] {
        switch self {
        case let .u32(v): return AudioHAL.le32(v)
        case let .f32(v): return AudioHAL.le32(v.bitPattern)
        case let .f64(v): return AudioHAL.le64(v.bitPattern)
        case let .u32s(a): return a.flatMap(AudioHAL.le32)
        case let .f64s(a): return a.flatMap { AudioHAL.le64($0.bitPattern) }
        case let .string(s): return Array(s.utf16).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
        case let .plist(b), let .bytes(b): return b
        }
    }
}

public enum AudioHAL {
    public static let scopeGlobal = fourCC("glob"), scopeInput = fourCC("inpt"), scopeOutput = fourCC("outp")
    public static let scopeWildcard = fourCC("****"), selectorWildcard = fourCC("****")
    public static let elementWildcard: UInt32 = 0xFFFF_FFFF

    public static let classSystem = fourCC("asys"), classObject = fourCC("aobj"), classDevice = fourCC("adev")
    public static let classAggregate = fourCC("aagg"), classSubdevice = fourCC("asub"), classStream = fourCC("astr")
    public static let classIOContext = fourCC("ioct")

    public static let unknownProperty = fourCC("who?"), badObject = fourCC("!obj"), illegalOperation = fourCC("nope")
    public static let unsupported = fourCC("unop"), badSize = fourCC("!siz")

    static func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)] }
    static func le64(_ v: UInt64) -> [UInt8] { le32(UInt32(v & 0xFFFF_FFFF)) + le32(UInt32(v >> 32)) }

    public static func streamFormat(sampleRate: Double, channels: UInt32) -> [UInt8] {
        let bytesPerFrame = 4 * channels
        return le64(sampleRate.bitPattern) + le32(fourCC("lpcm")) + le32(9) + le32(bytesPerFrame) + le32(1)
            + le32(bytesPerFrame) + le32(channels) + le32(32) + le32(0)
    }

    public static func channelLayout(labels: [UInt32]) -> [UInt8] {
        var b = le32(0) + le32(0) + le32(UInt32(labels.count))
        for l in labels { b += le32(l) + le32(0) + [UInt8](repeating: 0, count: 12) }
        return b
    }

    public static func gridRecord(device: UInt32, input: Bool, sampleRate: Double, channels: UInt32) -> [UInt8] {
        le32(device) + le32(input ? 1 : 0) + le32(1) + le32(0) + streamFormat(sampleRate: sampleRate, channels: channels)
    }

    static func xml(_ object: Any) -> [UInt8] {
        let data = (try? PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)) ?? Data()
        return [UInt8](data)
    }
}

public final class AudioObjectModel {
    public static let systemID: UInt32 = 1
    public static let deviceID: UInt32 = 32
    public static let streamID: UInt32 = 33
    public static let deviceUID = "dev.swiftcode.simulator.audio.output"
    public static let deviceName = "SwiftCode Simulator Output"
    public static let manufacturer = "SwiftCode"
    public static let sampleRate = 48_000.0
    public static let channels: UInt32 = 2
    public static let bufferFrames: UInt32 = 512
    public static let minimumFrames: UInt32 = 14, maximumFrames: UInt32 = 1024
    public static let transport = fourCC("bltn")

    public struct Aggregate: Equatable {
        public var id: UInt32
        public var streamID: UInt32
        public var subdeviceID: UInt32
        public var uid: String
        public var name: String
        public var creatorPID: Int32
        public var composition: [UInt8]
        public var preferredStereo: [UInt32] = [1, 2]
        public var layout: [UInt8] = AudioHAL.channelLayout(labels: [1, 2])
    }

    public struct IOContext: Equatable {
        public var id: UInt32
        public var deviceID: UInt32
        public var creatorPID: Int32
        public var bufferFrames: UInt32 = AudioObjectModel.bufferFrames
        public var streamUsage: [UInt32: [UInt32]] = [:]
    }

    public private(set) var aggregates: [UInt32: Aggregate] = [:]
    public private(set) var contexts: [UInt32: IOContext] = [:]
    public private(set) var nextID: UInt32 = 0x100
    public private(set) var powerHint: UInt32 = 0
    public private(set) var volume: Float = 1

    public init() {}

    public enum Kind: Equatable {
        case system, device, stream(owner: UInt32), aggregate, subdevice(owner: UInt32), ioContext
    }

    public func kind(of id: UInt32) -> Kind? {
        switch id {
        case Self.systemID: return .system
        case Self.deviceID: return .device
        case Self.streamID: return .stream(owner: Self.deviceID)
        default:
            if aggregates[id] != nil { return .aggregate }
            if contexts[id] != nil { return .ioContext }
            for a in aggregates.values {
                if a.streamID == id { return .stream(owner: a.id) }
                if a.subdeviceID == id { return .subdevice(owner: a.id) }
            }
            return nil
        }
    }

    public func classes(of id: UInt32) -> (UInt32, UInt32)? {
        switch kind(of: id) {
        case .system: return (AudioHAL.classSystem, AudioHAL.classObject)
        case .device: return (AudioHAL.classDevice, AudioHAL.classObject)
        case .stream: return (AudioHAL.classStream, AudioHAL.classObject)
        case .aggregate: return (AudioHAL.classAggregate, AudioHAL.classDevice)
        case .subdevice: return (AudioHAL.classSubdevice, AudioHAL.classDevice)
        case .ioContext: return (AudioHAL.classIOContext, AudioHAL.classObject)
        case nil: return nil
        }
    }

    public func deviceList(for pid: Int32) -> [UInt32] {
        [Self.deviceID] + aggregates.values.filter { $0.creatorPID == pid }.map(\.id).sorted()
    }

    private func allocateID() -> UInt32 {
        defer { nextID += 1 }
        return nextID
    }

    public func value(_ id: UInt32, _ a: AudioPropertyAddress, pid: Int32, qualifier: [UInt8] = []) -> AudioValue? {
        guard let kind = kind(of: id) else { return nil }
        let sel = a.selector
        let output = a.scope == AudioHAL.scopeOutput, input = a.scope == AudioHAL.scopeInput
        switch (kind, sel) {
        case (_, fourCC("clas")): return classes(of: id).map { .u32($0.0) }
        case (_, fourCC("bcls")): return classes(of: id).map { .u32($0.1) }
        case (.system, fourCC("ownr")): return .u32(0)
        case (.device, fourCC("ownr")), (.aggregate, fourCC("ownr")), (.ioContext, fourCC("ownr")): return .u32(Self.systemID)
        case (let .stream(owner), fourCC("ownr")), (let .subdevice(owner), fourCC("ownr")): return .u32(owner)
        case (.system, fourCC("cust")), (.device, fourCC("cust")), (.aggregate, fourCC("cust")),
             (.subdevice, fourCC("cust")):
            return .u32s([])

        case (.system, fourCC("vers")): return .u32(1)
        case (.system, fourCC("mlkf")): return .u32(2)
        case (.system, fourCC("powh")): return .u32(powerHint)
        case (.system, fourCC("plg#")), (.system, fourCC("box#")), (.system, fourCC("clk#")), (.system, fourCC("tps#")),
             (.system, fourCC("prs#")):
            return .u32s([])
        case (.system, fourCC("dev#")): return .u32s(deviceList(for: pid))
        case (.system, fourCC("dOut")), (.system, fourCC("sOut")): return .u32(Self.deviceID)
        case (.system, fourCC("dIn ")): return .u32(0)
        case (.system, fourCC("ownd")): return .u32s(deviceList(for: pid))

        case (.device, _), (.aggregate, _):
            return deviceValue(id, kind, a, output: output, input: input, qualifier: qualifier)

        case (.stream, fourCC("sdir")): return .u32(0)
        case (.stream, fourCC("schn")): return .u32(1)
        case (.stream, fourCC("ltnc")): return .u32(0)
        case (.stream, fourCC("sact")): return .u32(1)
        case (.stream, fourCC("term")): return .u32(fourCC("spkr"))
        case (.stream, fourCC("sfmt")), (.stream, fourCC("pft ")):
            return .bytes(AudioHAL.streamFormat(sampleRate: Self.sampleRate, channels: Self.channels))

        case (let .subdevice(owner), fourCC("uid ")):
            return aggregates[owner].map { _ in .string(Self.deviceUID) }
        case (.subdevice, fourCC("lnam")): return .string(Self.deviceName)
        case (.subdevice, fourCC("xltn")): return .f64(0)
        case (.subdevice, fourCC("drft")): return .u32(1)
        case (.subdevice, fourCC("drfq")): return .u32(127)

        case (.ioContext, fourCC("grid")):
            guard let c = contexts[id] else { return nil }
            if input { return .bytes([]) }
            guard output || a.scope == AudioHAL.scopeGlobal else { return nil }
            return .bytes(AudioHAL.gridRecord(device: c.deviceID, input: false, sampleRate: Self.sampleRate, channels: Self.channels))
        case (.ioContext, fourCC("fsiz")): return contexts[id].map { .u32($0.bufferFrames) }
        case (.ioContext, fourCC("fsz#")): return .f64s([Double(Self.minimumFrames), Double(Self.maximumFrames)])
        case (.ioContext, fourCC("guse")):
            guard let c = contexts[id] else { return nil }
            if let u = c.streamUsage[a.scope] { return .u32s(u) }
            return .u32s(output ? [1] : [])
        default:
            return nil
        }
    }

    private func deviceValue(_ id: UInt32, _ kind: Kind, _ a: AudioPropertyAddress, output: Bool, input: Bool,
                             qualifier: [UInt8]) -> AudioValue? {
        let isAggregate = kind == .aggregate
        let agg = aggregates[id]
        switch a.selector {
        case fourCC("uid "): return .string(agg?.uid ?? Self.deviceUID)
        case fourCC("lnam"): return .string(agg?.name ?? Self.deviceName)
        case fourCC("lmak"): return .string(Self.manufacturer)
        case fourCC("tran"): return .u32(isAggregate ? fourCC("grup") : Self.transport)
        case fourCC("alv?"): return .u32(1)
        case fourCC("hidn"): return .u32(0)
        case fourCC("dflt"), fourCC("sflt"): return isAggregate || input ? .u32(0) : .u32(1)
        case fourCC("nsrt"): return .f64(Self.sampleRate)
        case fourCC("nsra"): return .f64s([Self.sampleRate, Self.sampleRate])
        case fourCC("ltnc"), fourCC("saft"): return .u32(0)
        case fourCC("fsiz"): return .u32(Self.bufferFrames)
        case fourCC("fsz#"): return .f64s([Double(Self.minimumFrames), Double(Self.maximumFrames)])
        case fourCC("ctrl"): return .u32s([])
        case fourCC("stm#"):
            let stream = agg?.streamID ?? Self.streamID
            return input ? .u32s([]) : .u32s([stream])
        case fourCC("ownd"):
            let classes = stride(from: 0, to: qualifier.count - qualifier.count % 4, by: 4).map { i in
                UInt32(qualifier[i]) | UInt32(qualifier[i + 1]) << 8 | UInt32(qualifier[i + 2]) << 16 | UInt32(qualifier[i + 3]) << 24
            }
            if let agg {
                if classes.isEmpty { return .u32s([agg.subdeviceID]) }
                var out: [UInt32] = []
                if classes.contains(where: { [AudioHAL.classSubdevice, AudioHAL.classDevice, AudioHAL.classObject].contains($0) }) {
                    out.append(agg.subdeviceID)
                }
                if classes.contains(where: { [AudioHAL.classStream, AudioHAL.classObject].contains($0) }) { out.append(agg.streamID) }
                return .u32s(out)
            }
            if classes.isEmpty || classes.contains(AudioHAL.classStream) || classes.contains(AudioHAL.classObject) {
                return .u32s([Self.streamID])
            }
            return .u32s([])
        case fourCC("ioct"): return .plist(ioContextDescription(id))
        case fourCC("dch2"):
            guard output else { return nil }
            return .u32s(agg?.preferredStereo ?? [1, 2])
        case fourCC("srnd"):
            guard output else { return nil }
            return .bytes(agg?.layout ?? AudioHAL.channelLayout(labels: [1, 2]))
        case fourCC("appv"):
            guard output, !isAggregate else { return nil }
            return .f32(volume)
        case fourCC("acom"):
            return agg.map { .plist($0.composition) }
        case fourCC("agrp"):
            return isAggregate ? .u32s([Self.deviceID]) : nil
        default:
            return nil
        }
    }

    public func ioContextDescription(_ id: UInt32) -> [UInt8] {
        let agg = aggregates[id]
        var entry: [String: Any] = ["index": 0, "uid": Self.deviceUID]
        if agg != nil {
            entry["drift"] = true
            entry["drift algorithm"] = 0
            entry["drift quality"] = 127
            entry["extra latency"] = 0
            entry["synch padding"] = true
        }
        var d: [String: Any] = [
            "device id": Int(id),
            "grid-out": [["channels": Int(Self.channels), "stream groups": [[entry]]] as [String: Any]],
            "master uid": Self.deviceUID,
        ]
        if agg != nil {
            d["LDCM"] = false
            d["vocal isolation type"] = 0
            d["voice activity detection enable"] = 0
        }
        return AudioHAL.xml(d)
    }

    public func isSettable(_ id: UInt32, _ a: AudioPropertyAddress) -> Bool {
        switch (kind(of: id), a.selector) {
        case (.system, fourCC("powh")): return true
        case (.device, fourCC("appv")): return a.scope == AudioHAL.scopeOutput
        case (.aggregate, fourCC("dch2")), (.aggregate, fourCC("srnd")): return a.scope == AudioHAL.scopeOutput
        case (.ioContext, fourCC("guse")), (.ioContext, fourCC("fsiz")): return true
        default: return false
        }
    }

    public func set(_ id: UInt32, _ a: AudioPropertyAddress, _ v: AudioValue) -> UInt32 {
        guard kind(of: id) != nil else { return AudioHAL.badObject }
        guard isSettable(id, a) else { return AudioHAL.unknownProperty }
        switch (a.selector, v) {
        case (fourCC("powh"), let .u32(x)): powerHint = x
        case (fourCC("appv"), let .f32(x)): volume = x
        case (fourCC("dch2"), let .u32s(x)): aggregates[id]?.preferredStereo = x
        case (fourCC("srnd"), let .bytes(x)): aggregates[id]?.layout = x
        case (fourCC("guse"), let .u32s(x)): contexts[id]?.streamUsage[a.scope] = x
        case (fourCC("fsiz"), let .u32(x)):
            guard (Self.minimumFrames...Self.maximumFrames).contains(x) else { return AudioHAL.illegalOperation }
            contexts[id]?.bufferFrames = x
        default:
            return AudioHAL.badSize
        }
        return 0
    }

    public func createIOContext(description: [UInt8], pid: Int32) -> Result<UInt32, AudioModelError> {
        guard let d = Self.dictionary(description) else { return .failure(.status(AudioHAL.illegalOperation, "unreadable description")) }
        let device = (d["device id"] as? NSNumber)?.uint32Value ?? Self.deviceID
        guard device == Self.deviceID || aggregates[device] != nil else {
            return .failure(.status(AudioHAL.badObject, "unknown device \(device)"))
        }
        let id = allocateID()
        contexts[id] = IOContext(id: id, deviceID: device, creatorPID: pid)
        return .success(id)
    }

    public func createAggregate(description: [UInt8], pid: Int32) -> Result<UInt32, AudioModelError> {
        guard var d = Self.dictionary(description) else { return .failure(.status(AudioHAL.illegalOperation, "unreadable description")) }
        let uid = d["uid"] as? String ?? "aggregate-\(nextID)"
        if aggregates.values.contains(where: { $0.uid == uid }) {
            return .failure(.status(AudioHAL.illegalOperation, "an aggregate with UID \(uid) exists"))
        }
        let name = d["name"] as? String ?? uid
        if var subs = d["subdevices"] as? [[String: Any]] {
            for i in subs.indices {
                subs[i]["don't pad"] = 0
                subs[i]["drift algorithm"] = 0
                subs[i]["drift quality"] = 127
                subs[i]["latency-in"] = 0
                subs[i]["latency-out"] = 0
            }
            d["subdevices"] = subs
        }
        let id = allocateID(), stream = allocateID(), sub = allocateID()
        aggregates[id] = Aggregate(id: id, streamID: stream, subdeviceID: sub, uid: uid, name: name, creatorPID: pid,
                                   composition: AudioHAL.xml(d))
        return .success(id)
    }

    @discardableResult
    public func removeClient(pid: Int32) -> (aggregates: Int, contexts: Int, objects: [UInt32]) {
        let aggs = aggregates.values.filter { $0.creatorPID == pid }
        for a in aggs { aggregates[a.id] = nil }
        let ctxs = contexts.values.filter { $0.creatorPID == pid }.map(\.id)
        for c in ctxs { contexts[c] = nil }
        return (aggs.count, ctxs.count, aggs.flatMap { [$0.id, $0.streamID, $0.subdeviceID] } + ctxs)
    }

    public func context(_ id: UInt32) -> IOContext? { contexts[id] }
    public func isAggregate(_ id: UInt32) -> Bool { aggregates[id] != nil }

    static func dictionary(_ xml: [UInt8]) -> [String: Any]? {
        var bytes = xml
        while bytes.last == 0 { bytes.removeLast() }
        return (try? PropertyListSerialization.propertyList(from: Data(bytes), options: [], format: nil)) as? [String: Any]
    }

    public struct State: Equatable {
        public var aggregates: [Aggregate]
        public var contexts: [IOContext]
        public var nextID: UInt32
        public var powerHint: UInt32
        public var volume: Float
    }

    public var state: State {
        State(aggregates: aggregates.values.sorted { $0.id < $1.id }, contexts: contexts.values.sorted { $0.id < $1.id },
              nextID: nextID, powerHint: powerHint, volume: volume)
    }

    public func restore(_ s: State) {
        aggregates = Dictionary(uniqueKeysWithValues: s.aggregates.map { ($0.id, $0) })
        contexts = Dictionary(uniqueKeysWithValues: s.contexts.map { ($0.id, $0) })
        nextID = s.nextID
        powerHint = s.powerHint
        volume = s.volume
    }
}

public enum AudioModelError: Error, Equatable {
    case status(UInt32, String)
    public var code: UInt32 { if case let .status(s, _) = self { return s }; return 0 }
}
