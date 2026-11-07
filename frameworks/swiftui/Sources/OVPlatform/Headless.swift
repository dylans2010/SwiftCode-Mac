import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

@MainActor
public final class MemoryClipboard: PlatformClipboard {
    public var text: String?
    public var hasText: Bool { !(text ?? "").isEmpty }
    public init() {}
}

@MainActor
public final class HeadlessWindow: PlatformWindow {
    public let id: PlatformWindowID
    public var title: String
    public private(set) var size: CGSize
    public var scale: Double
    public var refreshRate: Double
    public private(set) var isClosed = false
    public private(set) var presentedFrames = 0
    public private(set) var lastFrame: PixelBuffer?
    public private(set) var isTextInputActive = false
    public private(set) var textInputCaret: CGRect?
    public var vulkan: (any PlatformVulkanSurface)? { nil }
    public let popupParent: PlatformWindowID?
    public let popupOrigin: CGPoint
    private weak var backend: HeadlessBackend?

    init(id: PlatformWindowID, configuration: WindowConfiguration, scale: Double, refreshRate: Double,
         backend: HeadlessBackend) {
        self.id = id
        title = configuration.title
        size = configuration.size
        self.scale = scale
        self.refreshRate = refreshRate
        popupParent = configuration.popupParent
        popupOrigin = configuration.popupOrigin
        self.backend = backend
    }

    public var pixelSize: (width: Int, height: Int) {
        (Int((size.width * scale).rounded()), Int((size.height * scale).rounded()))
    }

    public func setSize(_ size: CGSize) {
        self.size = size
        backend?.post(.window(id, .resized(size)))
    }

    public func present(_ frame: PixelBuffer) {
        presentedFrames += 1
        lastFrame = frame
    }

    public func readback() -> PixelBuffer? { lastFrame }

    public func startTextInput(caretRect: CGRect) {
        isTextInputActive = true
        textInputCaret = caretRect
    }

    public func stopTextInput() {
        isTextInputActive = false
        textInputCaret = nil
    }

    public private(set) var activations = 0
    public func activate() { activations += 1 }
    public private(set) var isMinimized = false
    public func minimize() {
        isMinimized = true
        backend?.post(.window(id, .minimized))
    }
    public func close() { isClosed = true }
}

@MainActor
public final class HeadlessBackend: PlatformBackend {
    public let name = "headless"
    public private(set) var now: TimeInterval
    public let clipboard: any PlatformClipboard = MemoryClipboard()
    public var defaultScale: Double
    public var defaultRefreshRate: Double
    public private(set) var openedURLs: [URL] = []
    public private(set) var idleWaits = 0
    private var allWindows: [HeadlessWindow] = []
    private var nextID: PlatformWindowID = 1
    private var queue: [(time: TimeInterval, seq: Int, event: PlatformEvent)] = []
    private var seq = 0

    public init(start: TimeInterval = 0, scale: Double = 2, refreshRate: Double = 60) {
        now = start
        defaultScale = scale
        defaultRefreshRate = refreshRate
    }

    public var windows: [any PlatformWindow] { allWindows.filter { !$0.isClosed } }
    public var headlessWindows: [HeadlessWindow] { allWindows.filter { !$0.isClosed } }

    public var refusesPopups = false

    public var settings = PlatformSettings() {
        didSet { if settings != oldValue { post(.settingsChanged) } }
    }

    public func makeWindow(_ configuration: WindowConfiguration) throws -> any PlatformWindow {
        if let parent = configuration.popupParent {
            guard !refusesPopups, headlessWindows.contains(where: { $0.id == parent }) else {
                throw PlatformError.windowCreationFailed("pop-up windows refused")
            }
        }
        let w = HeadlessWindow(id: nextID, configuration: configuration, scale: defaultScale,
                               refreshRate: defaultRefreshRate, backend: self)
        nextID += 1
        allWindows.append(w)
        return w
    }

    public func post(_ event: PlatformEvent) { post(event, at: now) }

    public func post(_ event: PlatformEvent, at time: TimeInterval) {
        seq += 1
        queue.append((max(time, now), seq, event))
        queue.sort { ($0.time, $0.seq) < ($1.time, $1.seq) }
    }

    public var nextEventTime: TimeInterval? { queue.first?.time }

    public func waitForEvents(until deadline: TimeInterval?) -> [PlatformEvent] {
        if let first = queue.first, first.time <= now + 1e-9 { return takeDue() }
        var target = deadline
        if let t = queue.first?.time { target = target.map { min($0, t) } ?? t }
        guard let target else {
            idleWaits += 1
            return []
        }
        if target > now { now = target }
        return takeDue()
    }

    private func takeDue() -> [PlatformEvent] {
        var out: [PlatformEvent] = []
        while let first = queue.first, first.time <= now + 1e-9 {
            out.append(first.event)
            queue.removeFirst()
        }
        return out
    }

    public func advanceClock(by seconds: TimeInterval) { now += max(0, seconds) }

    public func openExternally(_ url: URL) -> Bool {
        openedURLs.append(url)
        return true
    }

    public func shutdown() {
        for w in allWindows { w.close() }
    }
}
