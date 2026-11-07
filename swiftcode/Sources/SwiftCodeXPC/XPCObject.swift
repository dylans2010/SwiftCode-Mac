import Foundation

public enum XPCDisposition {
    public static let moveReceive: UInt32 = 16
    public static let moveSend: UInt32 = 17
    public static let moveSendOnce: UInt32 = 18
    public static let copySend: UInt32 = 19
    public static let makeSend: UInt32 = 20
    public static let makeSendOnce: UInt32 = 21
    public static let portReceive: UInt32 = 16
    public static let portSend: UInt32 = 17
    public static let portSendOnce: UInt32 = 18
}

public struct XPCPort: Equatable, Hashable, Sendable, CustomStringConvertible {
    public var name: UInt32
    public var disposition: UInt32

    public init(name: UInt32, disposition: UInt32) {
        self.name = name
        self.disposition = disposition
    }

    public var description: String { "0x" + String(name, radix: 16) + "/" + String(disposition) }
}

public indirect enum XPCObject: Equatable, Sendable {
    case null
    case bool(Bool)
    case int64(Int64)
    case uint64(UInt64)
    case double(Double)
    case date(Int64)
    case data([UInt8])
    case string(String)
    case uuid(UUID)
    case fd(XPCPort)
    case sharedMemory(size: UInt32, port: XPCPort)
    case sendRight(XPCPort)
    case receiveRight(XPCPort)
    case largeData(length: UInt32, port: XPCPort)
    case array([XPCObject])
    case dictionary(XPCDict)

    public static func send(_ name: UInt32, disposition: UInt32 = XPCDisposition.makeSend) -> XPCObject {
        .sendRight(XPCPort(name: name, disposition: disposition))
    }

    public static func receive(_ name: UInt32, disposition: UInt32 = XPCDisposition.moveReceive) -> XPCObject {
        .receiveRight(XPCPort(name: name, disposition: disposition))
    }

    public var boolValue: Bool? { if case let .bool(v) = self { v } else { nil } }
    public var int64Value: Int64? { if case let .int64(v) = self { v } else { nil } }
    public var uint64Value: UInt64? { if case let .uint64(v) = self { v } else { nil } }
    public var doubleValue: Double? { if case let .double(v) = self { v } else { nil } }
    public var stringValue: String? { if case let .string(v) = self { v } else { nil } }
    public var uuidValue: UUID? { if case let .uuid(v) = self { v } else { nil } }
    public var dataValue: [UInt8]? { if case let .data(v) = self { v } else { nil } }
    public var arrayValue: [XPCObject]? { if case let .array(v) = self { v } else { nil } }
    public var dictionaryValue: XPCDict? { if case let .dictionary(v) = self { v } else { nil } }

    public var integerValue: UInt64? {
        switch self {
        case let .uint64(v): v
        case let .int64(v): UInt64(bitPattern: v)
        default: nil
        }
    }

    public var port: XPCPort? {
        switch self {
        case let .fd(p), let .sendRight(p), let .receiveRight(p): p
        case let .sharedMemory(_, p), let .largeData(_, p): p
        default: nil
        }
    }

    public var isPortBearing: Bool { port != nil }

    public var ports: [XPCPort] {
        var out: [XPCPort] = []
        collectPorts(into: &out)
        return out
    }

    func collectPorts(into out: inout [XPCPort]) {
        switch self {
        case let .array(items): for item in items { item.collectPorts(into: &out) }
        case let .dictionary(d): for e in d.entries { e.value.collectPorts(into: &out) }
        default: if let p = port { out.append(p) }
        }
    }

    public func bindingPorts(_ ports: [XPCPort]) -> XPCObject? {
        var index = 0
        let result = rebinding(ports, &index)
        return index == ports.count ? result : nil
    }

    func rebinding(_ ports: [XPCPort], _ index: inout Int) -> XPCObject? {
        func next() -> XPCPort? {
            guard index < ports.count else { return nil }
            defer { index += 1 }
            return ports[index]
        }
        switch self {
        case let .array(items):
            var out: [XPCObject] = []
            for item in items {
                guard let r = item.rebinding(ports, &index) else { return nil }
                out.append(r)
            }
            return .array(out)
        case let .dictionary(d):
            var out = XPCDict()
            for e in d.entries {
                guard let r = e.value.rebinding(ports, &index) else { return nil }
                out.append(key: e.key, value: r)
            }
            return .dictionary(out)
        case .fd: return next().map { .fd($0) }
        case .sendRight: return next().map { .sendRight($0) }
        case .receiveRight: return next().map { .receiveRight($0) }
        case let .sharedMemory(size, _): return next().map { .sharedMemory(size: size, port: $0) }
        case let .largeData(length, _): return next().map { .largeData(length: length, port: $0) }
        default: return self
        }
    }
}

public struct XPCDict: Equatable, Sendable, Sequence {
    public struct Entry: Equatable, Sendable {
        public var key: String
        public var value: XPCObject
        public init(key: String, value: XPCObject) {
            self.key = key
            self.value = value
        }
    }

    public var entries: [Entry]

    public init(_ entries: [Entry] = []) { self.entries = entries }

    public var count: Int { entries.count }
    public var isEmpty: Bool { entries.isEmpty }
    public var keys: [String] { entries.map(\.key) }

    public subscript(key: String) -> XPCObject? {
        get { entries.first { $0.key == key }?.value }
        set {
            if let newValue {
                if let i = entries.firstIndex(where: { $0.key == key }) {
                    entries[i].value = newValue
                } else {
                    entries.append(Entry(key: key, value: newValue))
                }
            } else {
                entries.removeAll { $0.key == key }
            }
        }
    }

    public mutating func append(key: String, value: XPCObject) {
        entries.append(Entry(key: key, value: value))
    }

    public func makeIterator() -> IndexingIterator<[Entry]> { entries.makeIterator() }
}

extension XPCDict: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, XPCObject)...) {
        entries = elements.map { Entry(key: $0.0, value: $0.1) }
    }
}

extension XPCObject: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral,
    ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral
{
    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: XPCObject...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, XPCObject)...) {
        self = .dictionary(XPCDict(elements.map { XPCDict.Entry(key: $0.0, value: $0.1) }))
    }
    public init(nilLiteral: ()) { self = .null }
}

extension XPCObject: CustomStringConvertible {
    public var description: String {
        switch self {
        case .null: return "null"
        case let .bool(v): return v ? "true" : "false"
        case let .int64(v): return "\(v)i"
        case let .uint64(v): return "\(v)"
        case let .double(v): return "\(v)d"
        case let .date(v): return "date(\(v))"
        case let .data(v):
            let hex = v.prefix(32).map { String(format: "%02x", $0) }.joined()
            return "<\(v.count) bytes\(v.isEmpty ? "" : ": " + hex)\(v.count > 32 ? "…" : "")>"
        case let .string(v): return XPCObject.quoted(v)
        case let .uuid(v): return v.uuidString
        case let .fd(p): return "fd(\(p))"
        case let .sharedMemory(size, p): return "shmem(\(size) bytes, \(p))"
        case let .sendRight(p): return "send(\(p))"
        case let .receiveRight(p): return "receive(\(p))"
        case let .largeData(length, p): return "<\(length) bytes in \(p)>"
        case let .array(items): return "[" + items.map(\.description).joined(separator: ", ") + "]"
        case let .dictionary(d): return d.description
        }
    }

    static func quoted(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\0": out += "\\0"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    out += String(format: "\\x%02x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}

extension XPCDict: CustomStringConvertible {
    public var description: String {
        "{" + entries.map { "\($0.key): \($0.value)" }.joined(separator: ", ") + "}"
    }
}
