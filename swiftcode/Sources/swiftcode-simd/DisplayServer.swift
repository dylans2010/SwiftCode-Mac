#if os(Linux) && arch(arm64)
import CSwiftCodeCodec
import Foundation
import Glibc
import SwiftCodeDisplayStream
import SwiftCodeHostServices
import SwiftCodeHypervisor

protocol GuestInputSink: AnyObject {
    var acceptsTouch: Bool { get }
    var acceptsKeyboard: Bool { get }
    var buttons: [DisplayButton] { get }
    func deliver(_ input: DisplayInput) -> Bool
    func deliver(viewPose: SpatialPose, devicePose: SpatialPose) -> Bool
    func reset()
}

func nameThread(_ name: String) { swiftcodec_name_thread(name) }

final class FrameRecordReader {
    let path: String
    let slot: Int
    private var fd: Int32 = -1
    private var reads = 0

    init(path: String, slot: Int = 0) {
        self.path = path
        self.slot = slot
    }
    deinit { if fd >= 0 { close(fd) } }

    func read() -> FrameRecord? {
        reads += 1
        if fd >= 0, reads % 256 == 0 {
            var st = stat()
            if fstat(fd, &st) != 0 || st.st_nlink == 0 { close(fd); fd = -1 }
        }
        if fd < 0 {
            fd = open(path, O_RDONLY | O_CLOEXEC)
            if fd < 0 { return nil }
        }
        var buf = [UInt8](repeating: 0, count: FrameRecord.size)
        let n = buf.withUnsafeMutableBytes { pread(fd, $0.baseAddress, FrameRecord.size, off_t(slot * FrameRecord.size)) }
        guard n > 0 else { return nil }
        return FrameRecord.parse(Substring(String(decoding: buf[0..<n], as: UTF8.self)))
    }
}

final class DisplayTrace: @unchecked Sendable {
    private let lock = NSLock()
    private let handle: FileHandle
    private let guestClock: (() -> UInt64?)?
    private var nextSync: UInt64 = 0

    init?(path: String, guestClock: (() -> UInt64?)?) {
        guard FileManager.default.createFile(atPath: path, contents: nil), let h = FileHandle(forWritingAtPath: path) else { return nil }
        handle = h
        self.guestClock = guestClock
    }

    func line(_ text: String) {
        let now = monotonicNanoseconds()
        lock.withLock {
            var out = ""
            if now >= nextSync, let g = guestClock?() {
                out += "sync \(monotonicNanoseconds()) \(g)\n"
                nextSync = now + 1_000_000_000
            }
            out += text + "\n"
            handle.write(Data(out.utf8))
        }
    }
}

final class FrameRecordWatcher: @unchecked Sendable {
    private let fd: Int32
    private let name: String
    private let lock = NSLock()
    private var stopped = false

    init?(path: String, onChange: @escaping @Sendable () -> Void) {
        let dir = (path as NSString).deletingLastPathComponent
        name = (path as NSString).lastPathComponent
        fd = inotify_init1(Int32(IN_CLOEXEC | IN_NONBLOCK))
        guard fd >= 0 else { return nil }
        let mask = UInt32(IN_MODIFY | IN_CLOSE_WRITE | IN_CREATE | IN_MOVED_TO)
        guard inotify_add_watch(fd, dir, mask) >= 0 else { close(fd); return nil }
        let t = Thread { [self] in run(onChange) }
        t.name = "display-watch"
        t.start()
    }

    func stop() { lock.withLock { stopped = true } }

    private func run(_ onChange: @Sendable () -> Void) {
        nameThread("display-watch")
        var buf = [UInt8](repeating: 0, count: 4096)
        while !lock.withLock({ stopped }) {
            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&p, 1, 100) > 0 else { continue }
            let n = buf.withUnsafeMutableBytes { Glibc.read(fd, $0.baseAddress, $0.count) }
            guard n > 0 else { continue }
            var off = 0, hit = false
            buf.withUnsafeBytes { b in
                while off + 16 <= n {
                    let len = Int(b.load(fromByteOffset: off + 12, as: UInt32.self))
                    if len > 0, off + 16 + len <= n {
                        let raw = b[(off + 16)..<(off + 16 + len)]
                        let s = String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
                        if s == name { hit = true }
                    }
                    off += 16 + len
                }
            }
            if hit { onChange() }
        }
        close(fd)
    }
}

final class DisplayServer: @unchecked Sendable {
    let listener: DisplayListener
    let statePath: String
    let surfaces: IOSurfaceHostService
    let started: UInt64
    let input: GuestInputSink?
    let screen: (width: Int, height: Int, scale: Double)
    var model = DeviceType.default.modelIdentifier
    var deviceTypeID: String?
    var osVersion: String?
    let log: (String) -> Void
    var trace: DisplayTrace?
    var hidSequence: (() -> UInt64)?
    var panels: [PanelInfo] = []
    var fold: FoldController?
    var commands: (@Sendable (String) -> String)?
    var spatial = false
    var rooms: [String]?
    private var shown: PanelInfo?
    private let lock = NSLock()
    private var current: DisplayClientSession?
    private var stopping = false
    private var stopMessage: String?

    init(address: DisplayAddress, statePath: String, surfaces: IOSurfaceHostService, started: UInt64,
         screen: (width: Int, height: Int, scale: Double), input: GuestInputSink?, log: @escaping (String) -> Void) throws {
        listener = try DisplayListener(address: address)
        self.statePath = statePath
        self.surfaces = surfaces
        self.started = started
        self.screen = screen
        self.input = input
        self.log = log
    }

    var encodings: [String] {
        (swiftcodec_jpeg_available() != 0 ? ["jpeg"] : []) + (swiftcodec_zlib_available() != 0 ? ["zlib"] : [])
            + (Self.videoOffered ? VideoFrameEncoder.offered.map(\.name) : [])
    }

    static let videoOffered = ProcessInfo.processInfo.environment["SWIFTCODE_DISPLAY_VIDEO"] != "0"

    func start() {
        log("display server: listening on \(listener.address) (encodings: \(encodings.joined(separator: ", ")); "
            + "input: \(input == nil ? "not delivered" : "delivered"))")
        if Self.videoOffered, VideoFrameEncoder.available { log("display server: NVENC: \(VideoFrameEncoder.capabilityLine)") }
        let t = Thread { [self] in acceptLoop() }
        t.name = "display-accept"
        t.start()
        if !AudioHostService.disabled {
            let a = Thread { [weak self] in
                while let self, !self.isStopping {
                    if let audio = DefaultHostServices.audio {
                        audio.deliver = { [weak self] samples, at in self?.audioBlock(samples, at: at) }
                        self.log("display server: the device's sound goes to viewers that ask for it (\(DisplayAudioPipe.serverCodecs.joined(separator: ", ")))")
                        return
                    }
                    Thread.sleep(forTimeInterval: 0.5)
                }
            }
            a.name = "display-audio-hook"
            a.start()
        }
    }

    func audioBlock(_ samples: [Float], at: UInt64) {
        lock.withLock { current }?.pushAudio(samples, at: at)
    }

    func stop(message: String) {
        let s = lock.withLock { () -> DisplayClientSession? in
            stopping = true
            stopMessage = message
            return current
        }
        s?.sendStatus(phase: "stopping", message: message)
        s?.close()
        listener.close()
    }

    var isStopping: Bool { lock.withLock { stopping } }
    var uptime: Int { Int(monotonicMilliseconds() - started) }

    private func acceptLoop() {
        while let c = listener.accept() {
            if isStopping { c.close(); break }
            let session = DisplayClientSession(connection: c, server: self)
            let old = lock.withLock { () -> DisplayClientSession? in
                defer { current = session }
                return current
            }
            if let old {
                old.sendNotice(DisplayNotice.takenOver)
                old.close()
            }
            session.start()
        }
    }

    func ended(_ session: DisplayClientSession) {
        lock.withLock { if current === session { current = nil } }
    }

    var hello: DisplayServerHello {
        var h = DisplayServerHello(deviceName: DeviceLayout.deviceName, model: model, pixelWidth: screen.width,
                                   pixelHeight: screen.height, scale: screen.scale, encodings: encodings,
                                   touch: input?.acceptsTouch ?? false, keyboard: input?.acceptsKeyboard ?? false,
                                   buttons: (input?.buttons ?? []).map(\.name), rotation: fold != nil,
                                   foldable: fold != nil ? true : nil, displays: panels.count > 1 ? panels.map(\.name) : nil)
        h.deviceType = deviceTypeID
        h.osVersion = osVersion
        h.audio = AudioHostService.disabled ? nil : DisplayAudioPipe.serverCodecs
        h.frameAcks = true
        if spatial {
            h.spatial = true
            h.rooms = rooms
            h.xr = true
            h.xrDepth = true
            h.xrEnvironment = true
        }
        return h
    }

    func panelState(records: [FrameRecord?]) -> (PanelInfo, DisplayPanelState)? {
        guard !panels.isEmpty else { return nil }
        let model = fold?.state
        let black = panels.count > 1 && model != nil ? records.map { surfaces.presentedFrameIsBlack($0) } : []
        let p = activePanel(panels, model: model, records: records, black: black)
        let o = model?.orientation ?? .portrait
        let state = DisplayPanelState(display: p.name, pixelWidth: p.width, pixelHeight: p.height, scale: p.scale,
                                      rotation: PanelPicture.viewRotation(mountRotation: p.mountRotation, orientation: o),
                                      hingeAngle: model?.angle ?? 0, targetAngle: fold?.sweepTarget,
                                      posture: (model?.posture ?? .closed).rawValue, orientation: o.name)
        return (p, state)
    }

    var touchPanel: PanelInfo? { lock.withLock { shown } }
    func setShown(_ p: PanelInfo) { lock.withLock { shown = p } }

    func presentedSurface(_ record: FrameRecord?) -> IOSurfaceInfo? {
        guard let record, let s = surfaces.surface(id: record.surface) else { return nil }
        guard s.bytesPerElement == 4, s.width > 0, s.height > 0,
              UInt64(s.bytesPerRow * (s.height - 1) + s.width * 4) <= s.memory.size else { return nil }
        return s
    }
}

final class DisplayClientSession: @unchecked Sendable {
    let connection: DisplayConnection
    unowned let server: DisplayServer
    private let condition = NSCondition()
    private var settings: DisplayClientHello?
    private var keyframeWanted = true
    private var closed = false
    private var lastInput: UInt32 = 0
    private var inputUntil: UInt64 = 0
    private var noticeSent = false
    private var recordDirty = false
    private var shownRotation = 0
    private var audioPipe: DisplayAudioPipe?
    private var xr: DisplayXRState?
    private var xrDepth: DisplayXRDepthSender?

    func pushAudio(_ samples: [Float], at: UInt64) { condition.withLock { audioPipe }?.push(samples, at: at) }
    private var window = XRFrameWindow(window: nil)
    private var gapLog = XRServerGapLog()
    private var hover = XRHoverCounter()
    private var framesSent = 0, bytesSent = 0, encodeNanoseconds: UInt64 = 0, scans = 0
    private let connectedAt = monotonicMilliseconds()

    init(connection: DisplayConnection, server: DisplayServer) {
        self.connection = connection
        self.server = server
    }

    func start() {
        server.log("display server: viewer connected")
        do { try connection.send(.hello(server.hello)) } catch { close(); return }
        let receiver = Thread { [self] in receiveLoop() }
        receiver.name = "display-receive"
        receiver.start()
        let sender = Thread { [self] in sendLoop() }
        sender.name = "display-send"
        sender.start()
    }

    var isClosed: Bool { condition.withLock { closed } }

    func close() {
        let first = condition.withLock { () -> Bool in
            defer { closed = true; condition.broadcast() }
            return !closed
        }
        connection.close()
        if first {
            if let p = condition.withLock({ audioPipe }) {
                p.stop()
                server.log("display server: sound: \(p.packetsSent) packets, \(p.bytesSent / 1000) KB, \(p.silentSkipped) silent packets not sent, \(p.dropped) blocks dropped")
            }
            server.input?.reset()
            if let x = condition.withLock({ xr }) { server.log("display server: headset viewer: \(x.summary)") }
            if let d = condition.withLock({ xrDepth }) { d.stop(); server.log("display server: headset viewer: \(d.summary)") }
            if condition.withLock({ xr }) != nil {
                let (w, g, h) = condition.withLock { (window, gapLog, hover) }
                let total = Double(monotonicMilliseconds() - connectedAt) / 1000
                let span = max(total, 0.001)
                server.log("display server: headset viewer: gaps over 250 ms: \(g.gaps) (\(xrFixed(g.gapMilliseconds / 1000, 1)) s, longest \(xrFixed(g.longest)) ms); frame window \(w.window): full \(w.held) times, \(w.timeouts) timeouts; "
                           + "picture bursts with the camera still \(h.bursts) (\(xrFixed(Double(h.bursts) / span, 2))/s), new places \(h.targetChanges) (\(xrFixed(Double(h.targetChanges) / span, 2))/s, hover target changes)")
            }
            let seconds = Double(monotonicMilliseconds() - connectedAt) / 1000
            let encodeMs = Double(encodeNanoseconds) / 1e6
            server.log(String(format: "display server: viewer gone after %.0f s: %d frames, %.1f MB, %.1f fps, %.2f MB/s, encode %.1f ms/frame, %d scans",
                              seconds, framesSent, Double(bytesSent) / 1e6, Double(framesSent) / max(seconds, 0.001),
                              Double(bytesSent) / 1e6 / max(seconds, 0.001), framesSent > 0 ? encodeMs / Double(framesSent) : 0, scans))
            server.ended(self)
        }
    }

    func sendStatus(phase: String, message: String? = nil, guestFrames: Int = 0) {
        try? connection.send(.status(DisplayStatus(phase: phase, uptimeMilliseconds: server.uptime, guestFrames: guestFrames, message: message)))
    }

    func sendNotice(_ text: String) { try? connection.send(.notice(text)) }

    func recordChanged() {
        if DisplayClientSession.abTest, (monotonicMilliseconds() / 1000) % 2 == 1 { return }
        condition.withLock { recordDirty = true; condition.broadcast() }
    }

    static let abTest = ProcessInfo.processInfo.environment["SWIFTCODE_DISPLAY_AB"] == "1"

    private func receiveLoop() {
        nameThread("display-receive")
        var parser = DisplayMessageParser()
        while let bytes = connection.receive() {
            parser.append(bytes)
            do {
                while let m = try parser.next() { handle(m) }
            } catch {
                server.log("display server: bad message from the viewer: \(error)")
                break
            }
        }
        close()
    }

    private func handle(_ m: DisplayMessage) {
        switch m {
        case .clientHello(var h):
            h.maxFPS = min(120, max(1, h.maxFPS))
            h.quality = min(100, max(1, h.quality))
            h.downscale = min(4, max(1, h.downscale))
            h.encoding = DisplayCodecChoice.serverPick(hello: h, offered: server.encodings)
            if DisplayEncoding(name: h.encoding) == nil { h.encoding = server.encodings.first ?? "zlib" }
            condition.withLock { window = XRFrameWindow(window: h.frameWindow.map { min(64, max(0, $0)) }) }
            if let req = h.xr, server.spatial, condition.withLock({ xr == nil }) {
                let input = server.input
                let state = DisplayXRState(request: req) { view, device in _ = input?.deliver(viewPose: view, devicePose: device) }
                condition.withLock { xr = state }
                let depth = DisplayXRDepthSender(request: req)
                if depth.active {
                    condition.withLock { xrDepth = depth }
                    server.log("display server: headset viewer: depth 1/\(depth.downscale), environment \(depth.environment)")
                }
                server.log("display server: headset viewer: \(state.mode.rawValue) views, latch \(state.latch) pictures, settle \(state.settleMilliseconds) ms")
            }
            server.log("display server: viewer \"\(h.client)\": \(h.encoding) "
                       + (DisplayEncoding(name: h.encoding)?.isVideo == true
                          ? (h.videoQP.map { "QP \($0)" } ?? "\(h.videoBitrate ?? VideoFrameEncoder.defaultBitrate) kbit/s")
                          : "q\(h.quality)")
                       + ", downscale \(h.downscale), at most \(h.maxFPS) fps")
            if condition.withLock({ audioPipe == nil }), !AudioHostService.disabled, let codec = DisplayAudioPipe.choose(client: h.audio) {
                let c = connection
                let pipe = DisplayAudioPipe(codec: codec) { m in (try? c.send(m)) != nil }
                condition.withLock { audioPipe = pipe }
                server.log("display server: sound to this viewer as \(codec == .opus ? "Opus" : "16-bit PCM"), 5 ms packets")
            }
            condition.withLock {
                settings = h
                keyframeWanted = true
                condition.broadcast()
            }
        case .ping(let token):
            try? connection.send(.pong(token: token, serverNanoseconds: monotonicNanoseconds()))
        case .frameAck(let sequence):
            condition.withLock {
                window.ack(sequence: sequence, at: monotonicNanoseconds())
                recordDirty = true
                condition.broadcast()
            }
        case .keyframeRequest:
            condition.withLock { xr }?.keyframe()
            condition.withLock { keyframeWanted = true; condition.broadcast() }
        case .screenshotRequest(let token):
            let png = screenshot()
            try? connection.send(.screenshot(token: token, png: png))
        case .rotate(let o):
            guard let fold = server.fold else { sendNotice("rotation is not supported for this device yet"); break }
            guard let orientation = DeviceMotionOrientation(rawValue: UInt32(o)), orientation != .ambiguous else {
                sendNotice("this device does not take that orientation"); break
            }
            if case .failure(let e) = fold.setOrientation(orientation) { sendNotice("rotate: \(e)") }
        case .fold(let angle, let instant):
            guard let fold = server.fold else { sendNotice("this device does not fold"); break }
            if case .failure(let e) = fold.fold(to: Int(angle), instant: instant) { sendNotice("fold: \(e)") }
        case .command(let token, let text):
            guard let commands = server.commands else {
                try? connection.send(.commandReply(token: token, text: "error: this device takes no commands"))
                break
            }
            let connection = connection
            Thread.detachNewThread {
                let answer = commands(text)
                try? connection.send(.commandReply(token: token, text: answer))
            }
        case .input(let event):
            let received = monotonicNanoseconds()
            let delivered: Bool
            if case .fovea(_, let u, let v) = event {
                condition.withLock { xr }?.setFovea(u: Double(u), v: Double(v))
                delivered = true
            } else if case .views(_, let v) = event {
                condition.withLock { xr }?.update(v)
                delivered = server.input != nil
            } else if case .selection(_, let sel) = event, let x = condition.withLock({ xr }) {
                if sel.anyPinch { x.noteInteraction() }
                condition.withLock { gapLog.selection(pinching: sel.anyPinch, at: monotonicNanoseconds()) }
                delivered = server.input?.deliver(event) ?? false
            } else {
                delivered = server.input?.deliver(event) ?? false
            }
            if let trace = server.trace {
                let kind: String
                switch event {
                case .touch(_, let c): kind = "touch" + (c.first.map { ".\($0.phase)" } ?? "")
                case .key: kind = "key"
                case .button: kind = "button"
                case .pose: kind = "pose"
                case .selection(_, let s): kind = s.anyPinch ? "selection.pinch" : "selection"
                case .dial: kind = "dial"
                case .fovea: kind = "fovea"
                case .views: kind = "views"
                }
                trace.line("input \(event.sequence) \(kind) \(received) \(monotonicNanoseconds()) \(server.hidSequence?() ?? 0)")
            }
            condition.withLock {
                lastInput = event.sequence
                inputUntil = monotonicMilliseconds() + 500
                condition.broadcast()
            }
            if !delivered && !noticeSent {
                noticeSent = true
                sendNotice(server.input == nil ? "this device takes no input (swiftcode-simd without the HID bundle)"
                    : "input not delivered: the guest's HID bundle has not registered (yet)")
            }
        default:
            break
        }
    }

    private func screenshot() -> [UInt8] {
        let slot = server.touchPanel?.slot ?? 0
        let reader = FrameRecordReader(path: server.statePath, slot: slot)
        guard let record = reader.read(), let snap = server.surfaces.snapshot(surfaceID: record.surface),
              snap.bytesPerElement == 4, snap.width > 0, snap.height > 0 else { return [] }
        let flat = PNG.rgba(fromBGRA: snap.bytes, width: snap.width, height: snap.height, bytesPerRow: snap.bytesPerRow)
        let rotation = condition.withLock { shownRotation }
        let (rgba, w, h) = PanelPicture.rotate(rgba: flat, width: snap.width, height: snap.height, degrees: rotation)
        return CompressedPNG.encode(width: w, height: h, rgba: rgba)
    }

    private func sendInset(_ xr: DisplayXRState, surface: IOSurfaceInfo, view: XRView, frame: UInt64, gaze: (u: Double, v: Double)) -> Bool {
        let t0 = monotonicNanoseconds()
        let r = XRInset.rect(u: gaze.u, v: gaze.v, width: surface.width, height: surface.height, fraction: xr.foveaFraction)
        let base = UnsafeRawPointer(surface.memory.host).advanced(by: r.y * surface.bytesPerRow + r.x * 4).assumingMemoryBound(to: UInt8.self)
        var out: UnsafeMutablePointer<UInt8>?
        var size = 0
        let quality = condition.withLock { settings?.quality ?? 80 }
        guard swiftcodec_jpeg_encode_bgra(base, Int32(r.width), Int32(r.height), surface.bytesPerRow, Int32(quality), &out, &size) == 0, let out else { return true }
        defer { swiftcodec_free(out) }
        let inset = XRInset(frameSequence: frame, view: view, encoding: .jpeg, x: r.x, y: r.y, width: r.width, height: r.height,
                            fullWidth: surface.width, fullHeight: surface.height, data: Array(UnsafeBufferPointer(start: out, count: size)))
        do { try connection.send(.inset(inset)) } catch { return false }
        xr.lastInset = (gaze.u, gaze.v, t0, frame)
        xr.insetsSent += 1
        xr.insetBytes += size
        xr.insetNs += monotonicNanoseconds() - t0
        bytesSent += size
        return true
    }

    static func loadAverage() -> String {
        (try? String(contentsOfFile: "/proc/loadavg", encoding: .utf8))?.split(separator: " ").first.map(String.init) ?? "?"
    }

    static let paceFromCapture = ProcessInfo.processInfo.environment["SWIFTCODE_DISPLAY_PACE"] != "send"

    private func sendLoop() {
        nameThread("display-send")
        let helloDeadline = monotonicMilliseconds() + 2000
        condition.withLock {
            while settings == nil && !closed && monotonicMilliseconds() < helloDeadline {
                _ = condition.wait(until: Date(timeIntervalSinceNow: 0.05))
            }
            if settings == nil { settings = DisplayClientHello(client: "unknown", encoding: server.encodings.first ?? "zlib") }
        }
        let readers = (server.panels.isEmpty ? [PanelInfo(name: "LCD", slot: 0, width: server.screen.width,
                                                          height: server.screen.height, scale: server.screen.scale, mountRotation: 0)]
                       : server.panels).map { FrameRecordReader(path: server.statePath, slot: $0.slot) }
        var lastPanelState: DisplayPanelState?
        let watcher = FrameRecordWatcher(path: server.statePath) { [weak self] in self?.recordChanged() }
        defer { watcher?.stop() }
        var mirror: DisplayMirror?
        var encoder: TileEncoder?
        var still: StillRefinement?
        var video: VideoFrameEncoder?
        var videoFailed = false
        var videoNeedsKey = true
        var lastRecord: FrameRecord?
        var phase = ""
        var settleUntil: UInt64 = 0
        var lastScan: UInt64 = 0
        var lastSent: UInt64 = 0
        var unscanned = false
        var recordSeenNs: UInt64 = 0
        var nextSafetyScan: UInt64 = 0
        var nextStatus: UInt64 = 0
        var sequence: UInt64 = 0
        var lastXRTag: (tag: XREyeScheduler.Send?, estimated: Bool)?
        var lastPoseCount = 0, lastPoseAt: UInt64 = 0
        while !isClosed {
            let now = monotonicMilliseconds()
            let records = readers.map { $0.read() }
            var slot = 0
            if let (panel, state) = server.panelState(records: records) {
                slot = panel.slot
                if state != lastPanelState {
                    let switched = lastPanelState?.display != state.display
                    let turned = lastPanelState?.rotation != state.rotation
                    lastPanelState = state
                    server.setShown(panel)
                    condition.withLock { shownRotation = state.rotation }
                    do { try connection.send(.displayState(state)) } catch { break }
                    if switched || turned {
                        server.log("display server: showing \(state.display) (turned \(state.rotation)°; hinge \(state.hingeAngle)°, \(state.orientation))")
                    }
                    if switched {
                        mirror = nil
                        lastRecord = nil
                    }
                    if switched || turned { condition.withLock { keyframeWanted = true } }
                }
            }
            let record = records.indices.contains(slot) ? records[slot] : nil
            if let record, record != lastRecord {
                lastRecord = record
                settleUntil = now + 300
                unscanned = true
                recordSeenNs = monotonicNanoseconds()
                still?.screenChanged(at: recordSeenNs)
                server.trace?.line("record \(record.frame) \(monotonicNanoseconds())"
                                   + (Self.abTest ? ((monotonicMilliseconds() / 1000) % 2 == 1 ? " poll" : " watch") : ""))
            }
            let anyFrame = records.contains { ($0?.surface ?? 0) != 0 }
            let newPhase = server.isStopping ? "stopping" : (anyFrame ? "live" : "booting")
            if newPhase != phase || now >= nextStatus {
                phase = newPhase
                sendStatus(phase: phase, guestFrames: Int(record?.frame ?? 0))
                nextStatus = now + (phase == "booting" ? 1000 : 5000)
            }
            let (s, keyframe, inputUntil) = condition.withLock { (settings!, keyframeWanted, self.inputUntil) }
            let intervalNs = 1_000_000_000 / UInt64(s.maxFPS)
            let nowNs = monotonicNanoseconds()
            let urgent = keyframe || unscanned
            let speculative = now < settleUntil || now < inputUntil || now >= nextSafetyScan
            let wanted = urgent || speculative
            let allowed = nowNs &- lastSent >= intervalNs && (urgent || nowNs &- lastScan >= intervalNs)
            let flowOpen = condition.withLock { () -> Bool in
                let open = wanted ? window.open(at: nowNs) : window.isOpen(at: nowNs)
                if wanted, !open { gapLog.heldBack() }
                return open
            }
            let xrState = condition.withLock { xr }
            xrState?.idle()
            if let xrState { condition.withLock { gapLog.poses(total: xrState.posesSent, at: nowNs) } }
            if let d = condition.withLock({ xrDepth }), !d.sendEnvironment(connection) { break }
            if let xrState {
                var shown: (tag: XREyeScheduler.Send?, estimated: Bool)?
                var capture: IOSurfaceInfo?
                var xrSeenNs: UInt64 = 0
                let t0 = monotonicNanoseconds()
                if wanted, allowed, flowOpen, let surface = server.presentedSurface(record) {
                    xrSeenNs = unscanned ? recordSeenNs : 0
                    lastScan = nowNs
                    unscanned = false
                    if now >= nextSafetyScan { nextSafetyScan = now + 1000 }
                    scans += 1
                    let signature = XRPictureSignature.of(UnsafeRawPointer(surface.memory.host), width: surface.width,
                                                          height: surface.height, bytesPerRow: surface.bytesPerRow)
                    shown = xrState.picture(signature: signature)
                    capture = surface
                    let changed = shown != nil
                    condition.withLock { gapLog.scanned(changed: changed) }
                }
                if shown == nil, flowOpen, let d = xrState.due() {
                    shown = d
                    if capture == nil { capture = server.presentedSurface(record) }
                }
                let keyframe = flowOpen && condition.withLock { () -> Bool in defer { keyframeWanted = false }; return keyframeWanted }
                if shown == nil && keyframe, let last = lastXRTag {
                    shown = last
                    if capture == nil { capture = server.presentedSurface(record) }
                }
                if let (tag, estimated) = shown, let surface = capture {
                    lastXRTag = (tag, estimated)
                    var enc = DisplayEncoding(name: s.encoding) ?? .zlibBGRA
                    if enc.isVideo && xrState.videoFailed { enc = server.encodings.contains("jpeg") ? .jpeg : .zlibBGRA }
                    let downscale = enc.isVideo ? 1 : s.downscale
                    let base = UnsafeRawPointer(surface.memory.host)
                    let view = tag?.view ?? .mono
                    var m = xrState.mirrors[view]
                    if m == nil || m!.width != surface.width || m!.height != surface.height || m!.tile != 32 * downscale {
                        m = DisplayMirror(width: surface.width, height: surface.height, tile: 32 * downscale)
                        xrState.mirrors[view] = m
                        xrState.needsFull.insert(view)
                    }
                    if encoder == nil || encoder!.encoding != enc || encoder!.quality != s.quality || encoder!.downscale != downscale {
                        encoder = TileEncoder(encoding: enc, quality: s.quality, downscale: downscale)
                    }
                    let full = xrState.takeFull(view) || keyframe
                    let rects = m!.update(from: base, bytesPerRow: surface.bytesPerRow, full: full)
                    if !rects.isEmpty {
                        let posesNow = xrState.posesSent
                        if posesNow != lastPoseCount { lastPoseCount = posesNow; lastPoseAt = t0 }
                        if t0 &- lastPoseAt >= 300_000_000, !condition.withLock({ gapLog.isPinching }), let first = rects.first {
                            var (x0, y0, x1, y1) = (first.x, first.y, first.x + first.width, first.y + first.height)
                            for r in rects.dropFirst() { (x0, y0, x1, y1) = (min(x0, r.x), min(y0, r.y), max(x1, r.x + r.width), max(y1, r.y + r.height)) }
                            let (w, h) = (Double(surface.width), Double(surface.height))
                            condition.withLock { hover.damage(x: Double(x0) / w, y: Double(y0) / h, width: Double(x1 - x0) / w, height: Double(y1 - y0) / h, at: t0) }
                        }
                        var tiles: [DisplayTile]
                        var isFull = full
                        if enc.isVideo {
                            var video = xrState.videos[view]
                            if video == nil || video!.width != surface.width || video!.height != surface.height {
                                video = VideoFrameEncoder(encoding: enc, width: surface.width, height: surface.height, fps: s.videoFPS ?? s.maxFPS,
                                                          bitrateKbps: s.videoBitrate ?? VideoFrameEncoder.defaultBitrate, qp: s.videoQP ?? 0,
                                                          constantBitrate: s.videoFPS != nil, log: server.log)
                                xrState.videos[view] = video
                            }
                            guard let coded = video?.encode(mirror: m!, rects: rects, keyframe: full) else {
                                let to = server.encodings.contains("jpeg") ? "jpeg" : "zlib"
                                server.log("display server: WARNING: \(enc.name) failed for the headset viewer, falling back to \(to) tiles")
                                sendNotice("WARNING: the server's \(enc.name) encoder failed; the stream falls back to \(to), expect \(DisplayCodecChoice.expectation(to))")
                                xrState.videoFailed = true
                                xrState.videos = [:]
                                xrState.keyframe()
                                continue
                            }
                            tiles = [coded.tile]
                            isFull = coded.idr
                        } else {
                            tiles = encoder!.encodeAll(rects, mirror: m!)
                        }
                        let t1 = monotonicNanoseconds()
                        encodeNanoseconds += t1 - t0
                        sequence += 1
                        let f = downscale
                        let (w, h) = ((surface.width + f - 1) / f, (surface.height + f - 1) / f)
                        let inputSeq = condition.withLock { lastInput }
                        let fv = XRFrameView(frameSequence: sequence, view: view, estimated: estimated, latch: UInt16(xrState.latch),
                                             poseSequence: tag?.poseSequence ?? 0, pose: tag?.pose ?? .identity,
                                             fov: .guest(width: surface.width, height: surface.height), guestFrame: record?.frame ?? 0)
                        let frame = DisplayFrame(sequence: sequence, guestFrame: record?.frame ?? 0, serverNanoseconds: t1, inputSequence: inputSeq,
                                                 width: w, height: h, encoding: enc, isFull: isFull, tiles: tiles)
                        let bytes = DisplayMessage.frame(frame).encoded()
                        do {
                            if tag != nil { try connection.send(.frameView(fv)) }
                            try connection.send(bytes)
                        } catch { break }
                        if let d = condition.withLock({ xrDepth }), !d.afterFrame(connection, sequence: sequence, guestFrame: record?.frame ?? 0,
                                                                                   view: view, fov: fv.fov, surface: surface.id) { break }
                        if s.timing == true {
                            let timing = DisplayFrameTiming(sequence: sequence, recordSeen: xrSeenNs, captureStart: t0, encodeEnd: t1, sendEnd: monotonicNanoseconds())
                            do { try connection.send(.frameTiming(timing)) } catch { break }
                        }
                        server.trace?.line("frame \(sequence) \(record?.frame ?? 0) \(t0) \(t1) \(monotonicNanoseconds()) \(bytes.count) \(tiles.count) \(inputSeq) view \(view.rawValue) pose \(fv.poseSequence)")
                        let sentAt = monotonicNanoseconds()
                        let gapLine = condition.withLock { () -> String? in
                            window.didSend(sequence: sequence, at: sentAt)
                            gapLog.poses(total: xrState.posesSent, at: sentAt)
                            gapLog.encode(took: t1 - t0)
                            return gapLog.frameSent(at: sentAt, record: record?.frame ?? 0, load: Self.loadAverage)
                        }
                        if let gapLine { server.log("display server: headset viewer: " + gapLine) }
                        lastSent = t0
                        framesSent += 1
                        bytesSent += bytes.count
                    }
                    if xrState.foveaFraction > 0, let g = xrState.fovea {
                        if !sendInset(xrState, surface: surface, view: view, frame: sequence, gaze: g) { break }
                    }
                    continue
                }
                if xrState.foveaFraction > 0, let g = xrState.fovea, let last = xrState.lastInset, sequence == last.frame,
                   abs(g.u - last.u) > 0.05 || abs(g.v - last.v) > 0.05, monotonicNanoseconds() &- last.time > 33_000_000,
                   let surface = capture ?? server.presentedSurface(record) {
                    if !sendInset(xrState, surface: surface, view: lastXRTag?.tag?.view ?? .mono, frame: sequence, gaze: g) { break }
                    continue
                }
                if capture != nil { continue }
            }
            if xrState == nil, wanted, allowed, flowOpen, let surface = server.presentedSurface(record) {
                var enc = DisplayEncoding(name: s.encoding) ?? .zlibBGRA
                if enc.isVideo && videoFailed { enc = server.encodings.contains("jpeg") ? .jpeg : .zlibBGRA }
                let downscale = enc.isVideo ? 1 : s.downscale
                if mirror == nil || mirror!.width != surface.width || mirror!.height != surface.height
                    || mirror!.tile != 32 * downscale {
                    mirror = DisplayMirror(width: surface.width, height: surface.height, tile: 32 * downscale)
                    still = StillRefinement(width: surface.width, height: surface.height, tile: 32 * downscale)
                    condition.withLock { keyframeWanted = true }
                }
                if encoder == nil || encoder!.encoding != enc || encoder!.quality != s.quality || encoder!.downscale != downscale {
                    if encoder?.encoding.isVideo == true || enc.isVideo { condition.withLock { keyframeWanted = true } }
                    encoder = TileEncoder(encoding: enc, quality: s.quality, downscale: downscale)
                }
                let full = condition.withLock { () -> Bool in defer { keyframeWanted = false }; return keyframeWanted }
                let inputSeq = condition.withLock { lastInput }
                let seenNs = unscanned ? recordSeenNs : 0
                lastScan = nowNs
                unscanned = false
                if now >= nextSafetyScan { nextSafetyScan = now + 1000 }
                scans += 1
                let t0 = monotonicNanoseconds()
                let rects = mirror!.update(from: UnsafeRawPointer(surface.memory.host), bytesPerRow: surface.bytesPerRow, full: full)
                if !rects.isEmpty {
                    let banded = !Self.abTest || sequence % 2 == 0
                    let tiles: [DisplayTile]
                    var isFull = full
                    if enc.isVideo {
                        if video == nil || video!.width != surface.width || video!.height != surface.height {
                            video = VideoFrameEncoder(encoding: enc, width: surface.width, height: surface.height, fps: s.videoFPS ?? s.maxFPS,
                                                      bitrateKbps: s.videoBitrate ?? VideoFrameEncoder.defaultBitrate, qp: s.videoQP ?? 0,
                                                      constantBitrate: s.videoFPS != nil, log: server.log)
                            if let video { server.log("display server: \(enc.name) \(video.width)x\(video.height) at \(video.bitrate) kbit/s (NVENC)") }
                        }
                        guard let coded = video?.encode(mirror: mirror!, rects: rects, keyframe: full || videoNeedsKey) else {
                            let to = server.encodings.contains("jpeg") ? "jpeg" : "zlib"
                            server.log("display server: WARNING: \(enc.name) failed, falling back to \(to) tiles")
                            sendNotice("WARNING: the server's \(enc.name) encoder failed; the stream falls back to \(to), expect \(DisplayCodecChoice.expectation(to))")
                            videoFailed = true
                            video = nil
                            condition.withLock { keyframeWanted = true }
                            continue
                        }
                        videoNeedsKey = false
                        tiles = [coded.tile]
                        isFull = coded.idr
                    } else {
                        tiles = banded ? encoder!.encodeAll(rects, mirror: mirror!)
                            : rects.compactMap { encoder!.encode($0, mirror: mirror!) }
                    }
                    let t1 = monotonicNanoseconds()
                    encodeNanoseconds += t1 - t0
                    sequence += 1
                    let f = downscale
                    let frame = DisplayFrame(sequence: sequence, guestFrame: record?.frame ?? 0, serverNanoseconds: t1, inputSequence: inputSeq,
                                             width: (surface.width + f - 1) / f, height: (surface.height + f - 1) / f, encoding: enc,
                                             isFull: isFull, tiles: tiles)
                    let bytes = DisplayMessage.frame(frame).encoded()
                    do { try connection.send(bytes) } catch { break }
                    let sentAt = monotonicNanoseconds()
                    condition.withLock { window.didSend(sequence: sequence, at: sentAt) }
                    let sentRects = (isFull ? [PixelRect(x: 0, y: 0, width: surface.width, height: surface.height)] : rects)
                        .map { StillRefinement.Rect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
                    if enc == .zlibBGRA { still?.sentLossless(sentRects) } else { still?.sentLossy(sentRects, at: sentAt) }
                    if s.timing == true {
                        let timing = DisplayFrameTiming(sequence: sequence, recordSeen: seenNs, captureStart: t0, encodeEnd: t1, sendEnd: monotonicNanoseconds())
                        do { try connection.send(.frameTiming(timing)) } catch { break }
                    }
                    server.trace?.line("frame \(sequence) \(record?.frame ?? 0) \(t0) \(t1) \(monotonicNanoseconds()) \(bytes.count) \(tiles.count) \(inputSeq)"
                                      + (Self.abTest ? " ab \(banded ? "banded" : "single") \((monotonicMilliseconds() / 1000) % 2 == 1 ? "poll" : "watch")" : ""))
                    lastSent = Self.paceFromCapture ? t0 : monotonicNanoseconds()
                    framesSent += 1
                    bytesSent += bytes.count
                }
                continue
            }
            if xrState == nil, s.stillLossless == true, flowOpen, let m = mirror, still?.isDue(at: nowNs) == true,
               let rects = still?.take(), !rects.isEmpty {
                let downscale = max(1, m.tile / 32)
                let lossless = TileEncoder(encoding: .zlibBGRA, quality: s.quality, downscale: downscale)
                let t0 = monotonicNanoseconds()
                let tiles = lossless.encodeAll(rects.map { PixelRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }, mirror: m)
                let t1 = monotonicNanoseconds()
                sequence += 1
                let isFull = rects.count == 1 && rects[0] == StillRefinement.Rect(x: 0, y: 0, width: m.width, height: m.height)
                let frame = DisplayFrame(sequence: sequence, guestFrame: lastRecord?.frame ?? 0, serverNanoseconds: t1,
                                         inputSequence: condition.withLock { lastInput },
                                         width: (m.width + downscale - 1) / downscale, height: (m.height + downscale - 1) / downscale,
                                         encoding: .zlibBGRA, isFull: isFull, tiles: tiles)
                let bytes = DisplayMessage.frame(frame).encoded()
                do { try connection.send(bytes) } catch { break }
                condition.withLock { window.didSend(sequence: sequence, at: monotonicNanoseconds()) }
                server.trace?.line("lossless \(sequence) \(t0) \(t1) \(bytes.count) \(tiles.count)")
                framesSent += 1
                bytesSent += bytes.count
                continue
            }
            var pause = now < settleUntil || now < inputUntil || keyframe ? 0.004 : 0.008
            if wanted, !allowed {
                let since = min(nowNs &- lastSent, urgent ? UInt64.max : nowNs &- lastScan)
                if since < intervalNs { pause = min(pause, Double(intervalNs - since) / 1e9) }
            }
            condition.withLock {
                if !closed && !recordDirty { _ = condition.wait(until: Date(timeIntervalSinceNow: pause)) }
                recordDirty = false
            }
        }
        close()
    }
}
#endif

#if os(Linux) && arch(arm64)
func startDisplayServer(config: ExecConfiguration, surfaces: IOSurfaceHostService?, session: DeviceSession?,
                        hid: HIDHostService?, fold: FoldController? = nil, vision: VisionInputController? = nil, started: UInt64,
                        guestClock: (() -> UInt64?)? = nil) -> DisplayServer? {
    guard let address = config.options.displayServer else { return nil }
    guard let device = config.device, let surfaces else {
        stderrLine("swiftcode-simd: --display-server needs --device and the IOSurface service; not started")
        return nil
    }
    let server: DisplayServer
    let screen = device.deviceType.screen
    let bridge = hid.map { HIDInputBridge(hid: $0, pointWidth: screen.pointWidth, pointHeight: screen.pointHeight) }
    bridge?.family = WatchInputCommand.buttonFamily(device.deviceType)
    bridge?.pixelScale = Double(screen.scale)
    bridge?.vision = vision
    do {
        server = try DisplayServer(address: address, statePath: device.framebufferStatePath, surfaces: surfaces, started: started,
                                   screen: (screen.width, screen.height, screen.scale),
                                   input: bridge,
                                   log: { stderrLine("swiftcode-simd: " + $0) })
        server.model = device.deviceType.modelIdentifier
        server.deviceTypeID = device.deviceType.id
        let version = device.runtimeVersion().version
        server.osVersion = version.isEmpty ? nil : "\(device.runtimePlatform().displayName) \(version)"
        if vision != nil {
            server.spatial = true
            server.rooms = VisionRooms.known
        }
    } catch {
        stderrLine("swiftcode-simd: cannot start the display server on \(address): \(error)")
        return nil
    }
    if let fold {
        let panels = device.deviceType.panels
        server.panels = panels
        server.fold = fold
        bridge?.panel = { [weak server] in
            let p = server?.touchPanel ?? panels[0]
            return (p.touchDisplay, Double(p.width) / p.scale, Double(p.height) / p.scale)
        }
    }
    if DeviceLayout.displayTiming {
        server.trace = DisplayTrace(path: device.displayTracePath, guestClock: guestClock)
        server.hidSequence = hid.map { h in { h.lastSequence } }
        server.log("display server: timing trace \(server.trace == nil ? "not available" : device.displayTracePath)")
    }
    server.start()
    if let snap = SnapshotSupport.shared, snap.handlesStopSignals {
        snap.beforeStop = { [weak server] in server?.stop(message: "the device is being saved; the next run continues from it") }
        return server
    }
    let signalCount = SignalCounter(0)
    for sig in [SIGTERM, SIGINT, SIGHUP] {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
        source.setEventHandler { [weak session, weak server] in
            let n = signalCount.increment()
            guard n == 1, let session, session.isBound else {
                stderrLine("swiftcode-simd: signal \(sig): exiting now")
                if case .unix(let path) = address { unlink(path) }
                _exit(128 + sig)
            }
            stderrLine("swiftcode-simd: signal \(sig): ending the device session (again to exit at once)")
            server?.stop(message: "the device is shutting down")
            session.end()
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                stderrLine("swiftcode-simd: the guest did not shut down within 30 s; exiting")
                _exit(128 + sig)
            }
        }
        source.resume()
        DisplaySignalSources.keep.append(source)
    }
    return server
}

enum DisplaySignalSources {
    nonisolated(unsafe) static var keep: [any DispatchSourceSignal] = []
}

final class SignalCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int
    init(_ value: Int) { self.value = value }
    func increment() -> Int { lock.withLock { value += 1; return value } }
}
#endif
