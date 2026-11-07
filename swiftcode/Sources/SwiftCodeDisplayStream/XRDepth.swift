import Foundation

public enum XRDepthEncoding: UInt8, Sendable, Codable {
    case zlibPlanes = 1
    case raw = 2
}

public struct XRFrameDepth: Equatable, Sendable {
    public struct Flags: OptionSet, Sendable, Equatable {
        public let rawValue: UInt16
        public init(rawValue: UInt16) { self.rawValue = rawValue }
        public static let otherFrame = Flags(rawValue: 1)
        public static let windowsMerged = Flags(rawValue: 2)
        public static let roomOnly = Flags(rawValue: 4)
        public static let windowsMarked = Flags(rawValue: 8)
    }

    public var frameSequence: UInt64
    public var guestFrame: UInt64
    public var encoding: XRDepthEncoding
    public var view: XRView
    public var flags: Flags
    public var width: UInt16, height: UInt16
    public var near: Float
    public var fov: XRFieldOfView
    public var capturedAt: UInt64
    public var data: [UInt8]

    public init(frameSequence: UInt64, guestFrame: UInt64, encoding: XRDepthEncoding = .zlibPlanes, view: XRView = .mono,
                flags: Flags = [], width: UInt16, height: UInt16, near: Float = 0.1,
                fov: XRFieldOfView = .guest(width: 3840, height: 2160), capturedAt: UInt64 = 0, data: [UInt8]) {
        (self.frameSequence, self.guestFrame, self.encoding, self.view, self.flags) = (frameSequence, guestFrame, encoding, view, flags)
        (self.width, self.height, self.near, self.fov, self.capturedAt, self.data) = (width, height, near, fov, capturedAt, data)
    }

    public func payload() -> [UInt8] {
        var b: [UInt8] = []
        b.reserveCapacity(60 + data.count)
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { b += $0 } }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { b += $0 } }
        func u64(_ v: UInt64) { withUnsafeBytes(of: v.littleEndian) { b += $0 } }
        func f32(_ v: Float) { u32((v.isFinite ? v : 0).bitPattern) }
        u64(frameSequence)
        u64(guestFrame)
        b.append(encoding.rawValue)
        b.append(view.rawValue)
        u16(flags.rawValue)
        u16(width)
        u16(height)
        f32(near)
        let t = fov.tangents
        for v in [t.left, t.right, t.up, t.down] { f32(Float(v)) }
        u64(capturedAt)
        u32(UInt32(data.count))
        b += data
        return b
    }

    public init?(payload p: [UInt8]) {
        var i = 0
        func take(_ n: Int) -> ArraySlice<UInt8>? { guard i + n <= p.count else { return nil }; defer { i += n }; return p[i..<i + n] }
        func u(_ n: Int) -> UInt64? {
            guard let s = take(n) else { return nil }
            var v: UInt64 = 0
            for (k, x) in s.enumerated() { v |= UInt64(x) << (8 * UInt64(k)) }
            return v
        }
        func f() -> Float? { u(4).map { Float(bitPattern: UInt32($0)) } }
        guard let seq = u(8), let guest = u(8), let enc = u(1), let encoding = XRDepthEncoding(rawValue: UInt8(enc)),
              let rawView = u(1), let view = XRView(rawValue: UInt8(rawView)), let flags = u(2),
              let w = u(2), let h = u(2), let near = f(),
              let l = f(), let r = f(), let up = f(), let dn = f(), let captured = u(8), let n = u(4),
              let body = take(Int(n)) else { return nil }
        self.init(frameSequence: seq, guestFrame: guest, encoding: encoding, view: view, flags: Flags(rawValue: UInt16(flags)),
                  width: UInt16(w), height: UInt16(h), near: near,
                  fov: XRFieldOfView(tangentLeft: Double(l), right: Double(r), up: Double(up), down: Double(dn)),
                  capturedAt: captured, data: Array(body))
    }
}

public enum XRDepthSample {
    @inline(__always)
    public static func quantize(reverseZ d: Float) -> UInt16 {
        guard d.isFinite, d > 0 else { return 0 }
        if d >= 1 { return 65535 }
        return UInt16(max(1, min(65535, (d * 65535).rounded())))
    }

    @inline(__always)
    public static func reverseZ(_ q: UInt16) -> Float { Float(q) / 65535 }

    public static func distance(_ q: UInt16, near: Float) -> Float {
        q == 0 ? .infinity : near / reverseZ(q)
    }

    public static func sample(distance z: Float, near: Float) -> UInt16 {
        guard z.isFinite, z > 0 else { return 0 }
        return quantize(reverseZ: near / z)
    }
}

public struct XREnvironment: Equatable, Sendable {
    public enum Format: UInt8, Sendable { case rgba16Float = 1, rgba8sRGB = 2 }

    public var serial: UInt32
    public var compressed: Bool
    public var format: Format
    public var faceSize: UInt16
    public var level: UInt8
    public var orientationKnown: Bool
    public var orientation: SpatialQuaternion
    public var exposure: Float
    public var data: [UInt8]

    public init(serial: UInt32, compressed: Bool, format: Format = .rgba16Float, faceSize: UInt16, level: UInt8,
                orientationKnown: Bool = false, orientation: SpatialQuaternion = .identity, exposure: Float = 1, data: [UInt8]) {
        (self.serial, self.compressed, self.format, self.faceSize, self.level) = (serial, compressed, format, faceSize, level)
        (self.orientationKnown, self.orientation, self.exposure, self.data) = (orientationKnown, orientation, exposure, data)
    }

    public var bytesPerTexel: Int { format == .rgba16Float ? 8 : 4 }

    public func payload() -> [UInt8] {
        var b: [UInt8] = []
        b.reserveCapacity(40 + data.count)
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { b += $0 } }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { b += $0 } }
        func f32(_ v: Float) { u32((v.isFinite ? v : 0).bitPattern) }
        u32(serial)
        b.append(compressed ? 1 : 2)
        b.append(format.rawValue)
        u16(faceSize)
        b.append(level)
        b.append(orientationKnown ? 1 : 0)
        u16(0)
        for v in [orientation.x, orientation.y, orientation.z, orientation.w] { f32(Float(v)) }
        f32(exposure)
        u32(UInt32(data.count))
        b += data
        return b
    }

    public init?(payload p: [UInt8]) {
        var i = 0
        func u(_ n: Int) -> UInt64? {
            guard i + n <= p.count else { return nil }
            var v: UInt64 = 0
            for k in 0..<n { v |= UInt64(p[i + k]) << (8 * UInt64(k)) }
            i += n
            return v
        }
        func f() -> Float? { u(4).map { Float(bitPattern: UInt32($0)) } }
        guard let serial = u(4), let enc = u(1), let fmt = u(1), let format = Format(rawValue: UInt8(fmt)), let size = u(2),
              let level = u(1), let flags = u(1), u(2) != nil, let x = f(), let y = f(), let z = f(), let w = f(),
              let exposure = f(), let n = u(4), i + Int(n) <= p.count, enc == 1 || enc == 2 else { return nil }
        self.init(serial: UInt32(serial), compressed: enc == 1, format: format, faceSize: UInt16(size), level: UInt8(level),
                  orientationKnown: flags & 1 != 0, orientation: SpatialQuaternion(x: Double(x), y: Double(y), z: Double(z), w: Double(w)),
                  exposure: exposure, data: Array(p[i..<(i + Int(n))]))
    }
}
