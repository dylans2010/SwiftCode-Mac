import Foundation

public struct CameraSourceFormat: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public init(_ code: String) {
        let b = Array(code.utf8) + [32, 32, 32, 32]
        rawValue = UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
    }

    public static let yuyv = CameraSourceFormat("YUYV")
    public static let uyvy = CameraSourceFormat("UYVY")
    public static let nv12 = CameraSourceFormat("NV12")
    public static let yu12 = CameraSourceFormat("YU12")
    public static let yv12 = CameraSourceFormat("YV12")
    public static let mjpeg = CameraSourceFormat("MJPG")

    public static let supported: [CameraSourceFormat] = [.nv12, .yuyv, .uyvy, .yu12, .yv12, .mjpeg]

    public var isSupported: Bool { Self.supported.contains(self) }
    public var isCompressed: Bool { self == .mjpeg }

    public var description: String {
        String(decoding: (0..<4).map { UInt8(truncatingIfNeeded: rawValue >> (8 * $0)) }, as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)
    }
}

public enum CameraPixelFormat: UInt32, Sendable, CaseIterable, CustomStringConvertible {
    case biPlanar420Video = 0x3432_3076
    case biPlanar420Full = 0x3432_3066
    case bgra = 0x4247_5241

    public var description: String {
        String(decoding: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: rawValue >> $0) }, as: UTF8.self)
    }

    public init?(name: String) {
        guard let f = Self.allCases.first(where: { $0.description == name || "\($0)".lowercased() == name.lowercased() })
        else { return nil }
        self = f
    }

    public var isBiPlanar: Bool { self != .bgra }
    public var isFullRange: Bool { self == .biPlanar420Full }
}

public struct CameraFrameInterval: Hashable, Sendable, CustomStringConvertible {
    public var numerator: UInt32, denominator: UInt32
    public init(numerator: UInt32, denominator: UInt32) { (self.numerator, self.denominator) = (numerator, denominator) }
    public init(fps: Double) {
        let f = max(fps, 0.001)
        if f.rounded() == f { self.init(numerator: 1, denominator: UInt32(f)) } else { self.init(numerator: 1000, denominator: UInt32(f * 1000)) }
    }
    public var framesPerSecond: Double { numerator == 0 ? 0 : Double(denominator) / Double(numerator) }
    public var nanoseconds: Int64 { denominator == 0 ? 0 : Int64(numerator) * 1_000_000_000 / Int64(denominator) }
    public var description: String {
        let f = framesPerSecond
        return f.rounded() == f ? "\(Int(f)) fps" : String(format: "%.2f fps", f)
    }
}

public struct CameraFrameSize: Hashable, Sendable {
    public var width: Int, height: Int
    public var intervals: [CameraFrameInterval]
    public init(width: Int, height: Int, intervals: [CameraFrameInterval]) {
        (self.width, self.height) = (width, height)
        self.intervals = intervals.sorted { $0.framesPerSecond > $1.framesPerSecond }
    }
    public var maxFramesPerSecond: Double { intervals.first?.framesPerSecond ?? 0 }
}

public struct CameraFormatDescription: Hashable, Sendable {
    public var format: CameraSourceFormat
    public var name: String
    public var sizes: [CameraFrameSize]
    public init(format: CameraSourceFormat, name: String, sizes: [CameraFrameSize]) {
        (self.format, self.name, self.sizes) = (format, name, sizes)
    }
}

public struct CameraDevice: Hashable, Sendable {
    public enum Kind: String, Sendable { case v4l2, synthetic }
    public var id: String
    public var kind: Kind
    public var name: String
    public var path: String?
    public var driver: String
    public var busInfo: String
    public var formats: [CameraFormatDescription]
    public init(id: String, kind: Kind, name: String, path: String?, driver: String, busInfo: String,
                formats: [CameraFormatDescription]) {
        (self.id, self.kind, self.name, self.path) = (id, kind, name, path)
        (self.driver, self.busInfo, self.formats) = (driver, busInfo, formats)
    }
}

public struct CameraConfiguration: Sendable, Equatable {
    public var width: Int
    public var height: Int
    public var framesPerSecond: Double
    public var output: CameraPixelFormat
    public var ringSize: Int
    public var holdFramesUntilReleased: Bool
    public var syntheticWhileAbsent: Bool
    public var sourceFormat: CameraSourceFormat?

    public init(width: Int = 1280, height: Int = 720, framesPerSecond: Double = 30, output: CameraPixelFormat = .biPlanar420Video,
                ringSize: Int = 4, holdFramesUntilReleased: Bool = false, syntheticWhileAbsent: Bool = true,
                sourceFormat: CameraSourceFormat? = nil) {
        (self.width, self.height, self.framesPerSecond, self.output) = (width, height, framesPerSecond, output)
        (self.ringSize, self.holdFramesUntilReleased, self.syntheticWhileAbsent) = (ringSize, holdFramesUntilReleased, syntheticWhileAbsent)
        self.sourceFormat = sourceFormat
    }
}

public struct CameraColorimetry: Hashable, Sendable {
    public var fullRange: Bool
    public var matrix: Int
    public init(fullRange: Bool, matrix: Int) { (self.fullRange, self.matrix) = (fullRange, matrix) }
    public static let video601 = CameraColorimetry(fullRange: false, matrix: 601)
    public static let full601 = CameraColorimetry(fullRange: true, matrix: 601)
}

public struct CameraStreamFormat: Hashable, Sendable, CustomStringConvertible {
    public var source: CameraSourceFormat
    public var width: Int, height: Int
    public var interval: CameraFrameInterval
    public var colorimetry: CameraColorimetry
    public var output: CameraPixelFormat
    public init(source: CameraSourceFormat, width: Int, height: Int, interval: CameraFrameInterval,
                colorimetry: CameraColorimetry, output: CameraPixelFormat) {
        (self.source, self.width, self.height, self.interval) = (source, width, height, interval)
        (self.colorimetry, self.output) = (colorimetry, output)
    }
    public var description: String {
        "\(source) \(width)x\(height) @ \(interval) -> \(output) (source: \(colorimetry.fullRange ? "full" : "video") range, BT.\(colorimetry.matrix))"
    }
}

public struct CameraFrame: Sendable, Equatable {
    public var sequence: UInt64
    public var deviceSequence: UInt32
    public var surfaceID: UInt32
    public var surfacePort: UInt32
    public var seed: UInt32
    public var slot: Int
    public var format: CameraPixelFormat
    public var width: Int, height: Int
    public var presentationTime: Int64
    public var duration: Int64
    public var droppedBefore: Int
    public var synthetic: Bool
}

public enum CameraEvent: Sendable, Equatable {
    case started(CameraStreamFormat)
    case disconnected(deviceID: String, fallback: Bool)
    case reconnected(CameraStreamFormat)
    case stopped
}

public struct CameraError: Error, CustomStringConvertible, Equatable {
    public enum Code: Sendable { case noDevice, busy, unsupported, io, permission, gone }
    public var code: Code
    public var message: String
    public init(_ code: Code, _ message: String) { (self.code, self.message) = (code, message) }
    public var description: String { message }

    static func errno(_ what: String, _ e: Int32, path: String) -> CameraError {
        let text = "\(path): \(what): \(String(cString: strerror(e)))"
        switch e {
        case EBUSY: return CameraError(.busy, text + " (another program holds the camera)")
        case EACCES, EPERM: return CameraError(.permission, text + " (the account needs the video group)")
        case ENODEV, ENXIO, ENOENT: return CameraError(.gone, text)
        default: return CameraError(.io, text)
        }
    }
}
