import Foundation

public indirect enum DBusType: Hashable, Sendable, CustomStringConvertible {
    case byte, boolean, int16, uint16, int32, uint32, int64, uint64, double
    case string, objectPath, signature, unixFD, variant
    case array(DBusType)
    case structure([DBusType])
    case dictEntry(DBusType, DBusType)

    public var signature: String {
        switch self {
        case .byte: return "y"
        case .boolean: return "b"
        case .int16: return "n"
        case .uint16: return "q"
        case .int32: return "i"
        case .uint32: return "u"
        case .int64: return "x"
        case .uint64: return "t"
        case .double: return "d"
        case .string: return "s"
        case .objectPath: return "o"
        case .signature: return "g"
        case .unixFD: return "h"
        case .variant: return "v"
        case .array(let e): return "a" + e.signature
        case .structure(let f): return "(" + f.map(\.signature).joined() + ")"
        case .dictEntry(let k, let v): return "{" + k.signature + v.signature + "}"
        }
    }

    public var description: String { signature }

    public var alignment: Int {
        switch self {
        case .byte, .signature, .variant: return 1
        case .int16, .uint16: return 2
        case .boolean, .int32, .uint32, .unixFD, .string, .objectPath, .array: return 4
        case .int64, .uint64, .double, .structure, .dictEntry: return 8
        }
    }

    public var isBasic: Bool {
        switch self {
        case .array, .structure, .dictEntry, .variant: return false
        default: return true
        }
    }

    public static func parse(_ signature: String) throws -> [DBusType] {
        let bytes = Array(signature.utf8)
        guard bytes.count <= 255 else { throw DBusError.invalidSignature(signature, "longer than 255 bytes") }
        var parser = SignatureParser(bytes: bytes, text: signature)
        var out: [DBusType] = []
        while parser.index < bytes.count { out.append(try parser.completeType(arrayDepth: 0, structDepth: 0)) }
        return out
    }

    public static func parseSingle(_ signature: String) throws -> DBusType {
        let t = try parse(signature)
        guard t.count == 1 else { throw DBusError.invalidSignature(signature, "not a single complete type") }
        return t[0]
    }
}

private struct SignatureParser {
    let bytes: [UInt8]
    let text: String
    var index = 0

    func fail(_ why: String) -> DBusError { .invalidSignature(text, why) }

    mutating func completeType(arrayDepth: Int, structDepth: Int, inArray: Bool = false) throws -> DBusType {
        guard index < bytes.count else { throw fail("ends inside a type") }
        let c = bytes[index]
        index += 1
        switch c {
        case UInt8(ascii: "y"): return .byte
        case UInt8(ascii: "b"): return .boolean
        case UInt8(ascii: "n"): return .int16
        case UInt8(ascii: "q"): return .uint16
        case UInt8(ascii: "i"): return .int32
        case UInt8(ascii: "u"): return .uint32
        case UInt8(ascii: "x"): return .int64
        case UInt8(ascii: "t"): return .uint64
        case UInt8(ascii: "d"): return .double
        case UInt8(ascii: "s"): return .string
        case UInt8(ascii: "o"): return .objectPath
        case UInt8(ascii: "g"): return .signature
        case UInt8(ascii: "h"): return .unixFD
        case UInt8(ascii: "v"): return .variant
        case UInt8(ascii: "a"):
            guard arrayDepth < 32 else { throw fail("more than 32 nested arrays") }
            return .array(try completeType(arrayDepth: arrayDepth + 1, structDepth: structDepth, inArray: true))
        case UInt8(ascii: "("):
            guard structDepth < 32 else { throw fail("more than 32 nested structs") }
            var fields: [DBusType] = []
            while index < bytes.count && bytes[index] != UInt8(ascii: ")") {
                fields.append(try completeType(arrayDepth: arrayDepth, structDepth: structDepth + 1))
            }
            guard index < bytes.count else { throw fail("unclosed struct") }
            index += 1
            guard !fields.isEmpty else { throw fail("empty struct") }
            return .structure(fields)
        case UInt8(ascii: "{"):
            guard inArray else { throw fail("dict entry outside an array") }
            guard structDepth < 32 else { throw fail("more than 32 nested structs") }
            let key = try completeType(arrayDepth: arrayDepth, structDepth: structDepth + 1)
            guard key.isBasic else { throw fail("dict entry key is not a basic type") }
            let value = try completeType(arrayDepth: arrayDepth, structDepth: structDepth + 1)
            guard index < bytes.count, bytes[index] == UInt8(ascii: "}") else { throw fail("dict entry needs exactly two types") }
            index += 1
            return .dictEntry(key, value)
        default:
            throw fail("unexpected '\(Character(Unicode.Scalar(c)))'")
        }
    }
}

public indirect enum DBusValue: Hashable, Sendable, CustomStringConvertible {
    case byte(UInt8)
    case boolean(Bool)
    case int16(Int16)
    case uint16(UInt16)
    case int32(Int32)
    case uint32(UInt32)
    case int64(Int64)
    case uint64(UInt64)
    case double(Double)
    case string(String)
    case objectPath(String)
    case signature(String)
    case unixFD(UInt32)
    case array(DBusType, [DBusValue])
    case structure([DBusValue])
    case dictEntry(DBusValue, DBusValue)
    case variant(DBusValue)

    public var type: DBusType {
        switch self {
        case .byte: return .byte
        case .boolean: return .boolean
        case .int16: return .int16
        case .uint16: return .uint16
        case .int32: return .int32
        case .uint32: return .uint32
        case .int64: return .int64
        case .uint64: return .uint64
        case .double: return .double
        case .string: return .string
        case .objectPath: return .objectPath
        case .signature: return .signature
        case .unixFD: return .unixFD
        case .array(let e, _): return .array(e)
        case .structure(let f): return .structure(f.map(\.type))
        case .dictEntry(let k, let v): return .dictEntry(k.type, v.type)
        case .variant: return .variant
        }
    }

    public var signature: String { type.signature }

    public var description: String {
        switch self {
        case .byte(let v): return "y:\(v)"
        case .boolean(let v): return "b:\(v)"
        case .int16(let v): return "n:\(v)"
        case .uint16(let v): return "q:\(v)"
        case .int32(let v): return "i:\(v)"
        case .uint32(let v): return "u:\(v)"
        case .int64(let v): return "x:\(v)"
        case .uint64(let v): return "t:\(v)"
        case .double(let v): return "d:\(v)"
        case .string(let v): return "s:\"\(v)\""
        case .objectPath(let v): return "o:\(v)"
        case .signature(let v): return "g:\(v)"
        case .unixFD(let v): return "h:\(v)"
        case .array(_, let items): return "[" + items.map(\.description).joined(separator: ", ") + "]"
        case .structure(let f): return "(" + f.map(\.description).joined(separator: ", ") + ")"
        case .dictEntry(let k, let v): return "\(k): \(v)"
        case .variant(let v): return "<\(v)>"
        }
    }

    public static func dictionary(key: DBusType, value: DBusType, _ entries: [(DBusValue, DBusValue)]) -> DBusValue {
        .array(.dictEntry(key, value), entries.map { .dictEntry($0.0, $0.1) })
    }

    public static func stringDictionary(_ d: [String: String]) -> DBusValue {
        dictionary(key: .string, value: .string, d.keys.sorted().map { (.string($0), .string(d[$0] ?? "")) })
    }

    public static var emptyProperties: DBusValue { .array(.dictEntry(.string, .variant), []) }

    public static func strings(_ s: [String]) -> DBusValue { .array(.string, s.map { .string($0) }) }

    public var stringValue: String? {
        switch self {
        case .string(let s), .objectPath(let s), .signature(let s): return s
        default: return nil
        }
    }

    public var boolValue: Bool? { if case .boolean(let b) = self { return b } else { return nil } }

    public var intValue: Int? {
        switch self {
        case .byte(let v): return Int(v)
        case .int16(let v): return Int(v)
        case .uint16(let v): return Int(v)
        case .int32(let v): return Int(v)
        case .uint32(let v): return Int(v)
        case .int64(let v): return Int(v)
        case .uint64(let v): return Int(exactly: v)
        case .unixFD(let v): return Int(v)
        default: return nil
        }
    }

    public var doubleValue: Double? {
        if case .double(let d) = self { return d }
        return intValue.map(Double.init)
    }

    public var arrayValue: [DBusValue]? { if case .array(_, let a) = self { return a } else { return nil } }
    public var structValue: [DBusValue]? { if case .structure(let f) = self { return f } else { return nil } }
    public var variantValue: DBusValue? {
        guard case .variant(var v) = self else { return nil }
        while case .variant(let inner) = v { v = inner }
        return v
    }

    public var dictionaryValue: [String: DBusValue]? {
        guard case .array(.dictEntry, let entries) = self else { return nil }
        var d: [String: DBusValue] = [:]
        for case .dictEntry(let k, let v) in entries {
            guard let key = k.stringValue else { return nil }
            d[key] = v
        }
        return d
    }
}

public enum DBusError: Error, Equatable, CustomStringConvertible {
    case invalidSignature(String, String)
    case invalidValue(String)
    case malformedMessage(String)
    case io(String)
    case authenticationFailed(String)
    case noAddress(String)
    case timeout(String)
    case disconnected
    case remote(name: String, message: String)

    public var description: String {
        switch self {
        case .invalidSignature(let s, let why): return "invalid signature \"\(s)\": \(why)"
        case .invalidValue(let s): return "invalid value: \(s)"
        case .malformedMessage(let s): return "malformed message: \(s)"
        case .io(let s): return "I/O: \(s)"
        case .authenticationFailed(let s): return "authentication failed: \(s)"
        case .noAddress(let s): return "no usable address: \(s)"
        case .timeout(let s): return "timed out: \(s)"
        case .disconnected: return "disconnected"
        case .remote(let n, let m): return "\(n): \(m)"
        }
    }
}

public enum DBusNames {
    public static func isValidObjectPath(_ p: String) -> Bool {
        let b = Array(p.utf8)
        guard b.first == UInt8(ascii: "/") else { return false }
        if b.count == 1 { return true }
        guard b.last != UInt8(ascii: "/") else { return false }
        var previousSlash = false
        for c in b.dropFirst() {
            if c == UInt8(ascii: "/") {
                if previousSlash { return false }
                previousSlash = true
            } else {
                guard isElementByte(c) else { return false }
                previousSlash = false
            }
        }
        return true
    }

    public static func isValidInterfaceName(_ n: String) -> Bool {
        let elements = n.split(separator: ".", omittingEmptySubsequences: false)
        guard n.utf8.count <= 255, elements.count >= 2 else { return false }
        return elements.allSatisfy { e in
            guard let f = e.utf8.first, !(f >= UInt8(ascii: "0") && f <= UInt8(ascii: "9")) else { return false }
            return e.utf8.allSatisfy(isElementByte)
        }
    }

    public static func isValidMemberName(_ n: String) -> Bool {
        guard let f = n.utf8.first, n.utf8.count <= 255, !(f >= UInt8(ascii: "0") && f <= UInt8(ascii: "9")) else { return false }
        return n.utf8.allSatisfy(isElementByte)
    }

    public static func isValidBusName(_ n: String) -> Bool {
        guard n.utf8.count <= 255 else { return false }
        let unique = n.hasPrefix(":")
        let body = unique ? String(n.dropFirst()) : n
        let elements = body.split(separator: ".", omittingEmptySubsequences: false)
        guard elements.count >= 2 else { return false }
        return elements.allSatisfy { e in
            guard let f = e.utf8.first else { return false }
            if !unique && f >= UInt8(ascii: "0") && f <= UInt8(ascii: "9") { return false }
            return e.utf8.allSatisfy { isElementByte($0) || $0 == UInt8(ascii: "-") }
        }
    }

    static func isElementByte(_ c: UInt8) -> Bool {
        (c >= UInt8(ascii: "A") && c <= UInt8(ascii: "Z")) || (c >= UInt8(ascii: "a") && c <= UInt8(ascii: "z"))
            || (c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9")) || c == UInt8(ascii: "_")
    }
}
