import Foundation

public enum CameraGuestProtocol {
    public static let serviceName = "dev.swiftcode.camera"
    public static let base: Int32 = 0x5943_4D00
    public static let version: UInt32 = 1

    public enum Request {
        public static let devices: Int32 = 1, start: Int32 = 2, stop: Int32 = 3, release: Int32 = 4
    }

    public enum ToClient {
        public static let frame: Int32 = 200, event: Int32 = 201
    }

    public enum Status {
        public static let ok: UInt32 = 0
        public static let noDevice: UInt32 = 1
        public static let busy: UInt32 = 2
        public static let badRequest: UInt32 = 3
        public static let failed: UInt32 = 4
    }

    public enum EventKind {
        public static let interrupted: UInt32 = 1
        public static let interruptionEnded: UInt32 = 2
        public static let disconnected: UInt32 = 3
        public static let reconnected: UInt32 = 4
        public static let failed: UInt32 = 5
    }

    public static let flagSynthetic: UInt32 = 1

    static let ndr: [UInt8] = [0, 0, 0, 0, 1, 0, 0, 0]

    public static func le(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)]
    }

    public static func body(_ words: [UInt32]) -> [UInt8] { ndr + words.flatMap(le) }

    public static func word(_ body: [UInt8], _ i: Int) -> UInt32 {
        let at = 8 + 4 * i
        guard body.count >= at + 4 else { return 0 }
        return UInt32(body[at]) | UInt32(body[at + 1]) << 8 | UInt32(body[at + 2]) << 16 | UInt32(body[at + 3]) << 24
    }

    public static func words(_ body: [UInt8]) -> Int { max(0, (body.count - 8) / 4) }

    public static func split(_ v: UInt64) -> [UInt32] { [UInt32(truncatingIfNeeded: v), UInt32(truncatingIfNeeded: v >> 32)] }
    public static func join(_ lo: UInt32, _ hi: UInt32) -> UInt64 { UInt64(lo) | UInt64(hi) << 32 }

    public static func frameWords(stream: UInt32, frame: CameraFrame, presentationTicks: UInt64, durationTicks: UInt64,
                                  dropped: Int) -> [UInt32] {
        [stream] + split(frame.sequence)
            + [frame.surfaceID, UInt32(frame.slot), frame.seed, UInt32(frame.width), UInt32(frame.height), frame.format.rawValue,
               UInt32(clamping: dropped), frame.synthetic ? flagSynthetic : 0]
            + split(presentationTicks) + split(durationTicks)
    }
}

public struct CameraGuestPresentation: Sendable, Equatable {
    public enum Placement: String, Sendable, CaseIterable { case back, front, external }

    public var placement: Placement
    public init(placement: Placement) { self.placement = placement }

    public var deviceType: String {
        placement == .external ? "AVCaptureDeviceTypeExternal" : "AVCaptureDeviceTypeBuiltInWideAngleCamera"
    }

    public var position: Int {
        switch placement {
        case .back: 1
        case .front: 2
        case .external: 0
        }
    }

    public func localizedName(hostName: String) -> String {
        switch placement {
        case .back: "Back Camera"
        case .front: "Front Camera"
        case .external: hostName
        }
    }

    public func uniqueID(hostID: String) -> String { "dev.swiftcode.camera.\(placement.rawValue):\(hostID)" }
}

public struct CameraGuestFormat: Sendable, Equatable {
    public var width: Int, height: Int
    public var minFPS: Double, maxFPS: Double
    public init(width: Int, height: Int, minFPS: Double, maxFPS: Double) {
        (self.width, self.height, self.minFPS, self.maxFPS) = (width, height, minFPS, maxFPS)
    }
}

public enum CameraGuestFormats {
    public static let preferredSizes: [(Int, Int)] = [(352, 288), (640, 480), (960, 540), (1280, 720), (1920, 1080), (3840, 2160)]

    public static func list(for device: CameraDevice) -> [CameraGuestFormat] {
        var rates: [String: (w: Int, h: Int, lo: Double, hi: Double)] = [:]
        for f in device.formats where f.format.isSupported {
            for s in f.sizes where !s.intervals.isEmpty {
                let fps = s.intervals.map(\.framesPerSecond)
                let key = "\(s.width)x\(s.height)"
                let old = rates[key]
                rates[key] = (s.width, s.height, min(old?.lo ?? .infinity, fps.min()!), max(old?.hi ?? 0, fps.max()!))
            }
        }
        let all = rates.values.map { CameraGuestFormat(width: $0.w, height: $0.h, minFPS: $0.lo, maxFPS: $0.hi) }
        let preferred = all.filter { f in preferredSizes.contains { $0.0 == f.width && $0.1 == f.height } }
        return (preferred.isEmpty ? all : preferred).sorted { ($0.width * $0.height, $0.width) < ($1.width * $1.height, $1.width) }
    }

    public static func plist(device: CameraDevice, presentation: CameraGuestPresentation) -> [String: Any] {
        let formats: [[String: Any]] = list(for: device).map {
            ["width": $0.width, "height": $0.height, "minFrameRate": $0.minFPS, "maxFrameRate": $0.maxFPS]
        }
        let d: [String: Any] = [
            "uniqueID": presentation.uniqueID(hostID: device.id),
            "localizedName": presentation.localizedName(hostName: device.name),
            "modelID": device.name,
            "manufacturer": "SwiftCode",
            "deviceType": presentation.deviceType,
            "position": presentation.position,
            "formats": formats,
        ]
        return ["version": Int(CameraGuestProtocol.version), "devices": [d]]
    }
}

public struct CameraGuestTime: Sendable, Equatable {
    public var hostNanoseconds: UInt64
    public var guestTicks: UInt64
    public var frequency: UInt64

    public init(hostNanoseconds: UInt64, guestTicks: UInt64, frequency: UInt64) {
        (self.hostNanoseconds, self.guestTicks, self.frequency) = (hostNanoseconds, guestTicks, max(frequency, 1))
    }

    public func ticks(atHostNanoseconds ns: Int64) -> UInt64 {
        let delta = ns - Int64(bitPattern: hostNanoseconds)
        let scaled = Self.scale(abs(delta), frequency)
        return delta >= 0 ? guestTicks &+ scaled : (guestTicks >= scaled ? guestTicks - scaled : 0)
    }

    public func ticks(forNanoseconds ns: Int64) -> UInt64 { Self.scale(max(ns, 0), frequency) }

    static func scale(_ ns: Int64, _ hz: UInt64) -> UInt64 {
        let (hi, lo) = UInt64(ns).multipliedFullWidth(by: hz)
        return hi >= 1_000_000_000 ? .max : UInt64(1_000_000_000).dividingFullWidth((hi, lo)).quotient
    }
}
