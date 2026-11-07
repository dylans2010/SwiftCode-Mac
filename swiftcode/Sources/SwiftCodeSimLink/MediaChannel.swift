import Crypto
import Foundation

public struct MediaHeader: Equatable, Sendable {
    public static let size = 16
    public var direction: UInt8
    public var epoch: UInt8
    public var session: UInt32
    public var counter: UInt64

    public var bytes: [UInt8] {
        var b: [UInt8] = [0x59, 1, direction, epoch]
        for i in 0..<4 { b.append(UInt8(truncatingIfNeeded: session >> (8 * UInt32(i)))) }
        for i in 0..<8 { b.append(UInt8(truncatingIfNeeded: counter >> (8 * UInt64(i)))) }
        return b
    }

    public init(direction: UInt8, epoch: UInt8, session: UInt32, counter: UInt64) {
        (self.direction, self.epoch, self.session, self.counter) = (direction, epoch, session, counter)
    }

    public init?(_ p: [UInt8]) {
        guard p.count >= Self.size, p[0] == 0x59, p[1] == 1 else { return nil }
        direction = p[2]
        epoch = p[3]
        session = (0..<4).reduce(0) { $0 | UInt32(p[4 + $1]) << (8 * UInt32($1)) }
        counter = (0..<8).reduce(0) { $0 | UInt64(p[8 + $1]) << (8 * UInt64($1)) }
    }
}

public struct ReplayWindow: Sendable {
    public static let size: UInt64 = 4096
    private var highest: UInt64 = 0
    private var any = false
    private var bits = [UInt64](repeating: 0, count: Int(ReplayWindow.size / 64))

    public init() {}

    public mutating func accept(_ n: UInt64) -> Bool {
        if !any || n > highest {
            let shift = any ? n - highest : Self.size
            if shift >= Self.size {
                bits = [UInt64](repeating: 0, count: bits.count)
            } else {
                for k in (highest + 1)...n { clear(k) }
            }
            highest = n
            any = true
            set(n)
            return true
        }
        guard highest - n < Self.size, !isSet(n) else { return false }
        set(n)
        return true
    }

    private func index(_ n: UInt64) -> (Int, UInt64) { (Int((n % Self.size) / 64), n % 64) }
    private mutating func set(_ n: UInt64) { let (i, b) = index(n); bits[i] |= 1 << b }
    private mutating func clear(_ n: UInt64) { let (i, b) = index(n); bits[i] &= ~(1 << b) }
    private func isSet(_ n: UInt64) -> Bool { let (i, b) = index(n); return bits[i] & (1 << b) != 0 }
}

public struct MediaCrypto: Sendable {
    public static let rekeyEvery: UInt64 = 1 << 24
    public static let fragmentSize = 1200

    let baseKey: SymmetricKey
    public let session: UInt32
    public let direction: UInt8
    private var keys: [UInt8: SymmetricKey] = [:]
    private var counter: UInt64 = 0
    private var replay: [UInt8: ReplayWindow] = [:]
    private var newestEpoch: UInt8 = 0

    public init(key: SymmetricKey, session: UInt32, direction: UInt8) {
        baseKey = key
        self.session = session
        self.direction = direction
        keys[0] = key
    }

    mutating func key(epoch: UInt8) -> SymmetricKey {
        if let k = keys[epoch] { return k }
        var k = baseKey
        for _ in 0..<Int(epoch) {
            k = HKDF<SHA256>.deriveKey(inputKeyMaterial: k, salt: [UInt8](), info: Array("swiftcode-sim-link media rekey".utf8), outputByteCount: 32)
        }
        keys[epoch] = k
        if keys.count > 4 { keys = keys.filter { $0.key >= epoch &- 1 || $0.key == epoch } }
        return k
    }

    static func nonce(epoch: UInt8, counter: UInt64) -> [UInt8] {
        [epoch, 0, 0, 0] + (0..<8).map { UInt8(truncatingIfNeeded: counter >> (8 * UInt64($0))) }
    }

    public mutating func seal(_ payload: [UInt8]) throws -> [UInt8] {
        let epoch = UInt8(truncatingIfNeeded: counter / Self.rekeyEvery)
        let h = MediaHeader(direction: direction, epoch: epoch, session: session, counter: counter)
        counter += 1
        let ad = h.bytes
        let box = try ChaChaPoly.seal(payload, using: key(epoch: epoch), nonce: try ChaChaPoly.Nonce(data: Self.nonce(epoch: epoch, counter: h.counter)),
                                      authenticating: ad)
        return ad + Array(box.ciphertext) + Array(box.tag)
    }

    public mutating func open(_ packet: [UInt8], expectDirection: UInt8) -> [UInt8]? {
        guard let h = MediaHeader(packet), h.direction == expectDirection, h.session == session, packet.count >= MediaHeader.size + 16 else { return nil }
        guard h.epoch == newestEpoch || h.epoch == newestEpoch &+ 1 || h.epoch == newestEpoch &- 1 else { return nil }
        guard UInt64(h.epoch) == h.counter / Self.rekeyEvery % 256 else { return nil }
        let k = key(epoch: h.epoch)
        guard let nonce = try? ChaChaPoly.Nonce(data: Self.nonce(epoch: h.epoch, counter: h.counter)),
              let box = try? ChaChaPoly.SealedBox(nonce: nonce, ciphertext: packet[MediaHeader.size..<(packet.count - 16)], tag: packet.suffix(16)),
              let plain = try? ChaChaPoly.open(box, using: k, authenticating: packet.prefix(MediaHeader.size)) else { return nil }
        var w = replay[h.epoch] ?? ReplayWindow()
        guard w.accept(h.counter) else { return nil }
        replay[h.epoch] = w
        if h.epoch == newestEpoch &+ 1 {
            newestEpoch = h.epoch
            replay = replay.filter { $0.key == h.epoch || $0.key == h.epoch &- 1 }
        }
        return Array(plain)
    }
}

public enum MediaPayload {
    public static let fragment: UInt8 = 1
    public static let clientHello: UInt8 = 2

    public static func fragments(of message: [UInt8], id: UInt32, size: Int = MediaCrypto.fragmentSize) -> [[UInt8]] {
        let count = max(1, (message.count + size - 1) / size)
        precondition(count <= Int(UInt16.max))
        return (0..<count).map { i in
            var p: [UInt8] = [fragment]
            for k in 0..<4 { p.append(UInt8(truncatingIfNeeded: id >> (8 * UInt32(k)))) }
            p += [UInt8(i & 0xFF), UInt8(i >> 8), UInt8(count & 0xFF), UInt8(count >> 8)]
            p += message[(i * size)..<min(message.count, (i + 1) * size)]
            return p
        }
    }
}

public struct MediaReassembler: Sendable {
    struct Partial { var count: Int; var parts: [Int: [UInt8]]; var started: UInt64 }
    private var partial: [UInt32: Partial] = [:]
    private var next: UInt32?
    public private(set) var lost = 0
    public static let timeout: UInt64 = 200_000_000

    public init() {}

    public enum Output: Equatable { case message([UInt8]), lost(UInt32) }

    private func isOlder(_ id: UInt32) -> Bool {
        guard let n = next else { return false }
        return Int32(bitPattern: id &- n) < 0
    }

    public mutating func add(_ p: [UInt8], now: UInt64) -> [Output] {
        guard p.count >= 9, p[0] == MediaPayload.fragment else { return [] }
        let id = (0..<4).reduce(UInt32(0)) { $0 | UInt32(p[1 + $1]) << (8 * UInt32($1)) }
        let index = Int(p[5]) | Int(p[6]) << 8, count = Int(p[7]) | Int(p[8]) << 8
        guard count > 0, index < count, !isOlder(id) else { return expire(now: now) }
        var part = partial[id] ?? Partial(count: count, parts: [:], started: now)
        guard part.count == count else { return expire(now: now) }
        part.parts[index] = Array(p[9...])
        guard part.parts.count == count else {
            partial[id] = part
            return expire(now: now)
        }
        partial.removeValue(forKey: id)
        var out: [Output] = []
        if var k = next {
            var n = 0
            while k != id && n < 100_000 { out.append(.lost(k)); lost += 1; partial.removeValue(forKey: k); k &+= 1; n += 1 }
        }
        next = id &+ 1
        out.append(.message((0..<count).flatMap { part.parts[$0]! }))
        return out + expire(now: now)
    }

    public mutating func expire(now: UInt64) -> [Output] {
        var out: [Output] = []
        for (id, p) in partial.sorted(by: { Int32(bitPattern: $0.key &- $1.key) < 0 }) {
            if isOlder(id) { partial.removeValue(forKey: id); continue }
            guard now > p.started + Self.timeout else { continue }
            partial.removeValue(forKey: id)
            if var k = next { while k != id { out.append(.lost(k)); lost += 1; k &+= 1 } }
            out.append(.lost(id))
            lost += 1
            next = id &+ 1
        }
        return out
    }
}
