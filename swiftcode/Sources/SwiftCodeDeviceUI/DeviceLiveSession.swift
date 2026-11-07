#if os(macOS)
import AppKit
import SwiftCodeDeviceModel
import SwiftCodeDisplayStream

public enum DeviceSessionChange: Sendable, Equatable {
    case hello, phase, displayState, image, notice(String), recording, statistics
}

@MainActor
public protocol DeviceLiveSessionObserver: AnyObject {
    func session(_ s: DeviceLiveSession, changed: DeviceSessionChange)
}

@MainActor
public final class DeviceLiveSession: NSObject, ViewerConnectionDelegate, DeviceInputHandler {
    public let connection: ViewerConnection
    public private(set) var hello: DisplayServerHello?
    public private(set) var panelState: DisplayPanelState?
    public private(set) var phase = "connecting"
    public private(set) var phaseDetail: String?
    public private(set) var uptimeMilliseconds = 0
    public private(set) var image: CGImage?
    public private(set) var spec: DeviceFrameSpec
    public var displayName: String?
    public var osTitle: String?
    public var log: (String) -> Void = { _ in }
    public var onFrame: ((DisplayFrame) -> Void)?

    private var frameTimes: [UInt64] = []
    private var lastBytes = 0
    private var lastStatsTime = nowNanoseconds()
    public private(set) var bandwidth: Double = 0
    public private(set) var rtt: Double?
    private var probes: [(seq: UInt32, sent: UInt64, label: String)] = []
    public private(set) var latencies: [(label: String, ms: Double)] = []
    public private(set) var lastLatency: Double?
    private var screenshotWaiters: [UInt32: ([UInt8]) -> Void] = [:]
    private var nextScreenshot: UInt32 = 1
    private var timer: Timer?
    private var observers: [WeakObserver] = []
    public private(set) var recorder: ScreenRecorder?

    public init(connection: ViewerConnection, spec: DeviceFrameSpec? = nil) {
        self.connection = connection
        self.spec = spec ?? .iPhoneDuo
        super.init()
        connection.delegate = self
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
    }

    public func start() { connection.start() }

    public func close() {
        stopRecording()
        timer?.invalidate()
        connection.stop()
    }

    private final class WeakObserver {
        weak var value: DeviceLiveSessionObserver?
        init(_ v: DeviceLiveSessionObserver) { value = v }
    }

    public func addObserver(_ o: DeviceLiveSessionObserver) {
        observers.removeAll { $0.value == nil || $0.value === o }
        observers.append(WeakObserver(o))
    }

    public func removeObserver(_ o: DeviceLiveSessionObserver) { observers.removeAll { $0.value == nil || $0.value === o } }

    private func notify(_ c: DeviceSessionChange) {
        for o in observers.compactMap(\.value) { o.session(self, changed: c) }
    }

    public var isLive: Bool { phase == "live" }
    public var isTakenOver: Bool { phase == DisplayNotice.takenOverPhase }
    public private(set) var isHeldForHeadset = false

    public func holdForHeadset() {
        isHeldForHeadset = true
        connection.expectTakeover(true)
        notify(.phase)
    }

    public func takeBack() {
        isHeldForHeadset = false
        connection.takeBack()
        notify(.phase)
    }
    public var hasImage: Bool { image != nil }
    public var isFoldable: Bool { hello?.foldable == true || (hello == nil && spec.isFoldable) }
    public var canRotate: Bool { hello?.rotation == true }
    public var title: String { displayName ?? (spec.typeID == "unknown" ? hello?.deviceName ?? "Device" : spec.name) }
    public var subtitle: String { osTitle ?? hello?.osVersion ?? "" }
    public var panelIndex: Int { spec.panelIndex(named: panelState?.display) }
    public var orientation: DeviceOrientation { DeviceOrientation(streamName: panelState?.orientation ?? hello?.orientation) }
    public var posture: DevicePosture? {
        guard isFoldable else { return nil }
        if let p = panelState.flatMap({ DevicePosture(rawValue: $0.posture) }) { return p }
        return .closed
    }
    public var hingeTarget: Int? { panelState.map { $0.targetAngle ?? $0.hingeAngle } }

    public var shownPointSize: CGSize {
        if let p = panelState {
            let s = p.shownPointSize
            return CGSize(width: s.width, height: s.height)
        }
        if isTallVision { return spec.panels[0].uprightPointSize }
        if let h = hello { return CGSize(width: h.pointWidth, height: h.pointHeight) }
        return spec.panels[0].uprightPointSize
    }

    public func frameGeometry(bezels: Bool) -> DeviceFrameGeometry {
        DeviceFrameGeometry(spec: spec, panelIndex: panelIndex, clockwiseQuarterTurns: orientation.clockwiseQuarterTurns,
                            posture: posture, bezels: bezels)
    }

    public var problemText: String? {
        switch phase {
        case "connecting": phaseDetail == nil ? "Connecting display" : "Connecting display (\(phaseDetail!))"
        case "disconnected": "The device is not running or the connection dropped; reconnecting"
        case "booting": "Starting… \(uptimeMilliseconds / 1000) s"
        case "stopping": "The device is shutting down"
        case "live": hasImage ? nil : "Waiting for the first frame"
        case DisplayNotice.takenOverPhase: isHeldForHeadset ? "In the headset" : "Another viewer has this device"
        default: phase
        }
    }

    public var statisticsText: String {
        let now = nowNanoseconds()
        let fps = frameTimes.filter { now - $0 < 1_000_000_000 }.count
        var t = "\(phase) · \(fps) fps · " + String(format: "%.0f KB/s", bandwidth / 1000)
        if let lastLatency { t += String(format: " · input→screen %.0f ms", lastLatency) }
        if let rtt { t += String(format: " · rtt %.0f ms", rtt) }
        if let p = panelState, isFoldable { t += " · \(p.display) hinge \(p.hingeAngle)°" }
        if let h = hello, !h.touch { t += " · input not delivered" }
        return t
    }

    private func tick() {
        let now = nowNanoseconds()
        let bytes = connection.stats.bytes
        bandwidth = Double(bytes - lastBytes) / (Double(now - lastStatsTime) / 1e9)
        lastBytes = bytes
        lastStatsTime = now
        frameTimes.removeAll { now - $0 > 1_000_000_000 }
        probes.removeAll { now - $0.sent > 5_000_000_000 }
        if phase == "live" || phase == "booting" { connection.ping() }
        notify(.statistics)
    }

    public func connection(_ c: ViewerConnection, phase: String, detail: String?) {
        self.phase = phase
        phaseDetail = detail
        if phase == "disconnected" { image = nil }
        notify(.phase)
    }

    public func connection(_ c: ViewerConnection, hello: DisplayServerHello) {
        self.hello = hello
        log("hello: \(hello.deviceName) \(hello.model) \(hello.pixelWidth)x\(hello.pixelHeight) @\(hello.scale), encodings \(hello.encodings), "
            + "touch \(hello.touch), keyboard \(hello.keyboard), buttons \(hello.buttons)"
            + (hello.deviceType.map { ", type \($0)" } ?? "") + (hello.osVersion.map { ", \($0)" } ?? ""))
        spec = DeviceFrameSpec.matching(typeID: hello.deviceType, model: hello.model, pixelWidth: hello.pixelWidth,
                                        pixelHeight: hello.pixelHeight, scale: hello.scale)
        if hello.foldable != true { panelState = nil }
        notify(.hello)
    }

    public func connection(_ c: ViewerConnection, displayState: DisplayPanelState) {
        let switched = panelState?.display != displayState.display || panelState?.rotation != displayState.rotation
        panelState = displayState
        if switched {
            log("display: \(displayState.display) turned \(displayState.rotation)° (hinge \(displayState.hingeAngle)°, \(displayState.posture), \(displayState.orientation))")
        }
        notify(.displayState)
    }

    public func connection(_ c: ViewerConnection, status: DisplayStatus) {
        if phase != status.phase { log("phase: \(status.phase) at \(status.uptimeMilliseconds) ms" + (status.message.map { " (\($0))" } ?? "")) }
        phase = status.phase
        uptimeMilliseconds = status.uptimeMilliseconds
        notify(.phase)
    }

    public var isTallVision: Bool {
        guard spec.family == .vision, let h = hello else { return false }
        return h.pixelHeight > h.pixelWidth
    }

    public static func desktopCrop(_ image: CGImage, aspect: Double) -> CGImage {
        let w = image.width, h = Int((Double(w) / aspect).rounded())
        guard h < image.height, h > 0 else { return image }
        return image.cropping(to: CGRect(x: 0, y: (image.height - h) / 2, width: w, height: h)) ?? image
    }

    public func connection(_ c: ViewerConnection, image: CGImage, frame: DisplayFrame, receivedAt: UInt64) {
        let first = self.image == nil
        let panel = spec.panels[0].uprightPointSize
        let image = isTallVision ? Self.desktopCrop(image, aspect: Double(panel.width / panel.height)) : image
        self.image = image
        if first { log("first frame: \(frame.width)x\(frame.height), \(frame.byteCount) bytes") }
        frameTimes.append(nowNanoseconds())
        if frame.inputSequence > 0 {
            let shown = nowNanoseconds()
            while let p = probes.first, p.seq <= frame.inputSequence {
                probes.removeFirst()
                let ms = Double(receivedAt - p.sent) / 1e6
                lastLatency = ms
                latencies.append((p.label, ms))
                log(String(format: "latency: %@ (input #%u) → first change %.0f ms (shown %.0f ms)", p.label, p.seq, ms,
                           Double(shown - p.sent) / 1e6))
            }
        }
        recorder?.append(image)
        notify(.image)
        if first { notify(.phase) }
        onFrame?(frame)
    }

    public func connection(_ c: ViewerConnection, notice: String) {
        log("notice: \(notice)")
        notify(.notice(notice))
    }

    public func connection(_ c: ViewerConnection, screenshot png: [UInt8], token: UInt32) {
        screenshotWaiters.removeValue(forKey: token)?(png)
    }

    public func connection(_ c: ViewerConnection, pongToken token: UInt64, rttMilliseconds: Double) { rtt = rttMilliseconds }

    private func probe(_ seq: UInt32, _ label: String?) {
        guard seq != 0, let label else { return }
        probes.append((seq, nowNanoseconds(), label))
    }

    public func sendTouch(_ contacts: [TouchContact], label: String?) {
        var contacts = contacts
        if let p = panelState, p.quarterTurns != 0 {
            contacts = contacts.map { c in
                let n = p.nativePoint(shownX: Double(c.x), shownY: Double(c.y))
                return TouchContact(finger: c.finger, phase: c.phase, x: Float(n.x), y: Float(n.y))
            }
        }
        probe(connection.sendInput { .touch(sequence: $0, contacts: contacts) }, label)
    }

    public func sendKey(usage: UInt16, down: Bool, label: String?) {
        let seq = connection.sendInput { .key(sequence: $0, down: down, usagePage: KeyMap.keyboardPage, usage: usage) }
        probe(seq, down ? label : nil)
    }

    public var scrollsTurnTheCrown: Bool { spec.family == .watch }

    public func rotateCrown(by delta: Double) {
        guard spec.family == .watch, delta.isFinite, delta != 0 else { return }
        connection.sendCommand(String(format: "crown %.3f", delta)) { _ in }
    }

    public var isSpatial: Bool { hello?.spatial == true }

    public func sendSelection(_ selection: SpatialSelection, label: String?) {
        guard isSpatial else { return }
        probe(connection.sendInput { .selection(sequence: $0, selection: selection) }, label)
    }

    public func sendPose(_ pose: SpatialPose) {
        guard isSpatial else { return }
        connection.sendInput { .pose(sequence: $0, pose: pose) }
    }

    public func turnDial(by delta: Double) {
        guard isSpatial, delta.isFinite, delta != 0 else { return }
        connection.sendInput { .dial(sequence: $0, delta: delta) }
    }

    public func press(_ button: DisplayButton) {
        buttonDown(button)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in buttonUp(button) }
    }

    public func buttonDown(_ button: DisplayButton) {
        probe(connection.sendInput { .button(sequence: $0, button: button, down: true) }, button.name)
    }

    public func buttonUp(_ button: DisplayButton) {
        connection.sendInput { .button(sequence: $0, button: button, down: false) }
    }

    public func appSwitcher() {
        press(.home)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [self] in press(.home) }
    }

    public static func displayButton(for kind: DeviceFrameGeometry.ButtonKind, watch: Bool = false,
                                     actionOnTheWire: Bool = false) -> DisplayButton {
        switch kind {
        case .side, .top: .lock
        case .sideButton: watch ? .side : .lock
        case .volumeUp: .volumeUp
        case .volumeDown: .volumeDown
        case .action: watch && actionOnTheWire ? .action : .side
        case .crown: .home
        }
    }

    public func displayButton(for kind: DeviceFrameGeometry.ButtonKind) -> DisplayButton {
        Self.displayButton(for: kind, watch: spec.family == .watch, actionOnTheWire: hello?.buttons.contains("action") == true)
    }

    public func rotate(left: Bool) { setOrientation(orientation.rotated(left: left)) }

    public func setOrientation(_ o: DeviceOrientation) {
        guard canRotate else { notify(.notice("This device does not rotate")); return }
        connection.send(.rotate(orientation: o.streamCode))
    }

    public func fold(to angle: Int) {
        guard isFoldable else { return }
        connection.send(.fold(angle: UInt16(min(180, max(0, angle))), instant: false))
    }

    public func refreshDisplay() { connection.send(.keyframeRequest) }

    public func requestScreenshot(_ done: @escaping ([UInt8]?) -> Void) {
        let token = nextScreenshot
        nextScreenshot += 1
        var answered = false
        screenshotWaiters[token] = { png in answered = true; done(png.isEmpty ? self.shownPNG() : png) }
        if !connection.send(.screenshotRequest(token: token)) {
            screenshotWaiters.removeValue(forKey: token)
            done(shownPNG())
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [self] in
            if !answered, screenshotWaiters.removeValue(forKey: token) != nil { done(shownPNG()) }
        }
    }

    public func shownPNG() -> [UInt8]? {
        guard let image else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]).map { [UInt8]($0) }
    }

    public static var captureDirectory: URL {
        if let d = ProcessInfo.processInfo.environment["SWIFTCODE_DEVICE_CAPTURE_DIR"], !d.isEmpty {
            return URL(fileURLWithPath: d, isDirectory: true)
        }
        if let loc = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"), !loc.isEmpty {
            let url = URL(fileURLWithPath: (loc as NSString).expandingTildeInPath, isDirectory: true)
            var dir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &dir), dir.boolValue { return url }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
    }

    public func saveScreenshot(_ done: @escaping (Result<URL, Error>) -> Void) {
        requestScreenshot { [self] png in
            guard let png else { done(.failure(CaptureError("no picture yet"))); return }
            let url = Self.captureDirectory.appendingPathComponent(DeviceCaptureNames.screenshot(device: title, at: Date()))
            do {
                try Data(png).write(to: url)
                log("screenshot: \(url.path)")
                done(.success(url))
            } catch {
                done(.failure(error))
            }
        }
    }

    public var isRecording: Bool { recorder != nil }

    public func startRecording() throws {
        guard recorder == nil else { return }
        let url = Self.captureDirectory.appendingPathComponent(DeviceCaptureNames.recording(device: title, at: Date()))
        let r = try ScreenRecorder(url: url)
        recorder = r
        if let image { r.append(image) }
        log("recording: \(url.path)")
        notify(.recording)
    }

    public func stopRecording(_ done: (@MainActor @Sendable (URL?) -> Void)? = nil) {
        guard let r = recorder else { done?(nil); return }
        recorder = nil
        notify(.recording)
        r.finish { url in
            DispatchQueue.main.async { MainActor.assumeIsolated { done?(url) } }
        }
    }

    public func sendCommand(_ text: String, reply: @escaping @MainActor @Sendable (String) -> Void) {
        connection.sendCommand(text, reply: reply)
    }
}

public struct CaptureError: Error, CustomStringConvertible, LocalizedError {
    public let description: String
    public init(_ d: String) { description = d }
    public var errorDescription: String? { description }
}
#endif
