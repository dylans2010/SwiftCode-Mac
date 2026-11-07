public enum GDBRemoteInput: Equatable, Sendable {
    case packet([UInt8])
    case badChecksum
    case interrupt
    case ack
    case nack
}

public struct GDBRemoteDecoder: Sendable {
    private enum State: Sendable { case idle, body, escape, braceThenHash, checksum1, checksum2 }
    private var state = State.idle
    private var afterHash: [UInt8] = []
    private var body: [UInt8] = []
    private var sum: UInt8 = 0
    private var high: UInt8 = 0
    public var maximumBodyLength = 1 << 22

    public init() {}

    public mutating func append<S: Sequence>(_ bytes: S) -> [GDBRemoteInput] where S.Element == UInt8 {
        var out: [GDBRemoteInput] = []
        for b in bytes {
            switch state {
            case .idle:
                switch b {
                case UInt8(ascii: "$"):
                    state = .body
                    body.removeAll(keepingCapacity: true)
                    sum = 0
                case UInt8(ascii: "+"): out.append(.ack)
                case UInt8(ascii: "-"): out.append(.nack)
                case 0x03: out.append(.interrupt)
                default: break
                }
            case .body:
                switch b {
                case UInt8(ascii: "#"): state = .checksum1
                case UInt8(ascii: "}"):
                    sum &+= b
                    state = .escape
                case UInt8(ascii: "$"):
                    body.removeAll(keepingCapacity: true)
                    sum = 0
                default:
                    sum &+= b
                    body.append(b)
                    if body.count > maximumBodyLength { state = .idle }
                }
            case .escape where b == UInt8(ascii: "#"):
                afterHash.removeAll(keepingCapacity: true)
                state = .braceThenHash
            case .escape:
                sum &+= b
                body.append(b ^ 0x20)
                state = .body
            case .braceThenHash:
                afterHash.append(b)
                guard afterHash.count == 2 else { continue }
                if let h = GDBRemoteHex.nibble(afterHash[0]), let l = GDBRemoteHex.nibble(afterHash[1]), h << 4 | l == sum {
                    state = .idle
                    out.append(.packet(body + [UInt8(ascii: "}")]))
                } else {
                    sum &+= UInt8(ascii: "#")
                    body.append(UInt8(ascii: "#") ^ 0x20)
                    state = .body
                    out += append(afterHash)
                }
            case .checksum1:
                guard let v = GDBRemoteHex.nibble(b) else { state = .idle; out.append(.badChecksum); continue }
                high = v
                state = .checksum2
            case .checksum2:
                state = .idle
                guard let v = GDBRemoteHex.nibble(b), high << 4 | v == sum else { out.append(.badChecksum); continue }
                out.append(.packet(body))
            }
        }
        return out
    }
}

public enum GDBRemoteFraming {
    public static func checksum<S: Sequence>(_ bytes: S) -> UInt8 where S.Element == UInt8 {
        bytes.reduce(0) { $0 &+ $1 }
    }

    public static func escape(_ body: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(body.count)
        for b in body {
            switch b {
            case UInt8(ascii: "$"), UInt8(ascii: "#"), UInt8(ascii: "}"), UInt8(ascii: "*"):
                out.append(UInt8(ascii: "}"))
                out.append(b ^ 0x20)
            default:
                out.append(b)
            }
        }
        return out
    }

    public static func frame(_ body: [UInt8]) -> [UInt8] {
        let escaped = escape(body)
        let c = checksum(escaped)
        return [UInt8(ascii: "$")] + escaped + [UInt8(ascii: "#"), GDBRemoteHex.digit(c >> 4), GDBRemoteHex.digit(c & 0xF)]
    }

    public static func frame(_ body: String) -> [UInt8] { frame(Array(body.utf8)) }
}

public enum GDBRemoteHex {
    private static let digits = Array("0123456789abcdef".utf8)

    @inline(__always) public static func digit(_ v: UInt8) -> UInt8 { digits[Int(v & 0xF)] }

    @inline(__always) public static func nibble(_ c: UInt8) -> UInt8? {
        switch c {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): c - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): c - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): c - UInt8(ascii: "A") + 10
        default: nil
        }
    }

    public static func encode<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        var out: [UInt8] = []
        for b in bytes {
            out.append(digit(b >> 4))
            out.append(digit(b & 0xF))
        }
        return String(decoding: out, as: UTF8.self)
    }

    public static func encode(text: String) -> String { encode(Array(text.utf8)) }

    public static func decode<S: Collection>(_ text: S) -> [UInt8]? where S.Element == UInt8 {
        guard text.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(text.count / 2)
        var it = text.makeIterator()
        while let a = it.next(), let b = it.next() {
            guard let h = nibble(a), let l = nibble(b) else { return nil }
            out.append(h << 4 | l)
        }
        return out
    }

    public static func decode(_ text: String) -> [UInt8]? { decode(Array(text.utf8)) }

    public static func decodeText(_ text: String) -> String? { decode(text).map { String(decoding: $0, as: UTF8.self) } }

    public static func number<S: StringProtocol>(_ text: S) -> UInt64? {
        if text == "-1" { return UInt64.max }
        guard !text.isEmpty, text.count <= 16 else { return nil }
        return UInt64(text, radix: 16)
    }

    public static func littleEndian(_ value: UInt64, size: Int) -> String {
        encode((0..<size).map { UInt8(truncatingIfNeeded: value >> (8 * UInt64($0))) })
    }

    public static func littleEndianValue<C: Collection>(_ bytes: C) -> UInt64 where C.Element == UInt8 {
        var v: UInt64 = 0
        for (i, b) in bytes.prefix(8).enumerated() { v |= UInt64(b) << (8 * UInt64(i)) }
        return v
    }
}
