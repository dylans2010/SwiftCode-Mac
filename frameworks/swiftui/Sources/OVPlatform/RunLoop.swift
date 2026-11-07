import Foundation

@MainActor
public protocol RunLoopClient: AnyObject {
    func handle(_ event: PlatformEvent)
    var nextTimerDeadline: TimeInterval? { get }
    func fireTimers(now: TimeInterval)
    var needsFrame: Bool { get }
    func renderFrame(at time: TimeInterval)
    var isFinished: Bool { get }
    func afterWait()
}

extension RunLoopClient {
    public func afterWait() {}
}

public struct DisplayLink: Sendable, Equatable {
    public var framesPerSecond: Double
    public private(set) var nextTick: TimeInterval
    public var period: TimeInterval { 1 / framesPerSecond }

    public init(framesPerSecond: Double = 60, start: TimeInterval = 0) {
        self.framesPerSecond = framesPerSecond > 0 ? framesPerSecond : 60
        nextTick = start
    }

    public func isDue(at now: TimeInterval) -> Bool { now + 1e-6 >= nextTick }

    public mutating func consume(at now: TimeInterval) -> TimeInterval {
        let time: TimeInterval
        if now - nextTick < period {
            time = max(nextTick, 0)
            nextTick += period
        } else {
            time = now
            nextTick = now + period
        }
        return time
    }
}

@MainActor
public final class PlatformRunLoop {
    public let backend: any PlatformBackend
    public var displayLink: DisplayLink
    public private(set) var framesRendered = 0
    public private(set) var idleWaits = 0
    public private(set) var iterations = 0
    private var stopRequested = false

    public init(backend: any PlatformBackend, framesPerSecond: Double = 60) {
        self.backend = backend
        displayLink = DisplayLink(framesPerSecond: framesPerSecond, start: backend.now)
    }

    public func stop() { stopRequested = true }

    public func run(_ client: any RunLoopClient) {
        stopRequested = false
        while !stopRequested && !client.isFinished { runOnce(client) }
    }

    public func run(_ client: any RunLoopClient, until deadline: TimeInterval) {
        stopRequested = false
        while !stopRequested && !client.isFinished && backend.now < deadline - 1e-9 {
            runOnce(client, cap: deadline)
        }
    }

    public func runOnce(_ client: any RunLoopClient, cap: TimeInterval? = nil) {
        iterations += 1
        var deadline = client.nextTimerDeadline
        if client.needsFrame {
            let tick = max(displayLink.nextTick, backend.now)
            deadline = deadline.map { min($0, tick) } ?? tick
        }
        if let cap { deadline = deadline.map { min($0, cap) } ?? cap }
        if deadline == nil { idleWaits += 1 }
        let events = backend.waitForEvents(until: deadline)
        client.afterWait()
        for e in events { client.handle(e) }
        let now = backend.now
        if let t = client.nextTimerDeadline, t <= now + 1e-9 { client.fireTimers(now: now) }
        if client.needsFrame && displayLink.isDue(at: now) {
            let time = displayLink.consume(at: now)
            framesRendered += 1
            client.renderFrame(at: time)
        }
    }
}
