import Foundation

public struct ClockSync: Sendable, Equatable {
    public struct Sample: Sendable, Equatable {
        public var rtt: Int64
        public var offset: Int64
        public var at: UInt64
    }

    public var window: UInt64 = 60_000_000_000
    public private(set) var samples: [Sample] = []

    public init() {}

    public mutating func add(sent t0: UInt64, server: UInt64, received t1: UInt64) {
        guard t1 >= t0 else { return }
        let rtt = Int64(t1 - t0)
        let mid = t0 / 2 + t1 / 2 + (t0 % 2 + t1 % 2) / 2
        let offset = Int64(bitPattern: server &- mid)
        samples.append(Sample(rtt: rtt, offset: offset, at: t1))
        samples.removeAll { t1 &- $0.at > window }
        if samples.count > 64 { samples.removeFirst(samples.count - 64) }
    }

    public var best: Sample? { samples.min { $0.rtt < $1.rtt } }

    public var offset: Int64? { best?.offset }

    public var uncertainty: Int64? { best.map { $0.rtt / 2 } }

    public func clientTime(server: UInt64) -> UInt64? {
        guard let o = offset else { return nil }
        return UInt64(bitPattern: Int64(bitPattern: server) &- o)
    }
}

public func viewerNanoseconds() -> UInt64 {
    var t = timespec()
    #if canImport(Darwin)
    clock_gettime(CLOCK_UPTIME_RAW, &t)
    #else
    clock_gettime(CLOCK_MONOTONIC, &t)
    #endif
    return UInt64(t.tv_sec) * 1_000_000_000 + UInt64(t.tv_nsec)
}
