#if os(macOS)
import AppKit
import SwiftCodeDeviceModel
import SwiftCodeDisplayStream

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
public final class DeviceCanvasView: NSView, DeviceLiveSessionObserver {
    public enum Mode { case compact, hub }
    public let mode: Mode

    public private(set) var session: DeviceLiveSession?
    public private(set) var stoppedSpec: DeviceFrameSpec?
    public let frameView = DeviceFrameView(geometry: DeviceFrameGeometry(spec: .iPhoneDuo))
    public let controls = DeviceControlsRow()

    public var showsBezels = true { didSet { if showsBezels != oldValue { refreshGeometry() } } }
    public var zoom: DeviceZoomMode = .fit { didSet { if zoom != oldValue { needsLayout = true; onZoomChange?() } } }
    public var showsStatistics = false { didSet { statsLabel.isHidden = !showsStatistics; updateStatistics() } }
    public var topInset: CGFloat = 0 { didSet { needsLayout = true } }
    public var handlesKeyEquivalents = false
    public var commandFallback: ((DeviceCommand) -> Bool)?
    public var headsetCommandEnabled: (() -> Bool)?
    public var headsetCommandTitle: (() -> String)?
    public var onAction: (() -> Void)?
    public var onGeometryChange: (() -> Void)?
    public var onZoomChange: (() -> Void)?
    public var onCaptureChange: ((Bool) -> Void)?

    private let scroll = NSScrollView()
    private let document = FlippedView()
    private let messageLabel = NSTextField(labelWithString: "")
    private let statusStack = NSStackView()
    private var statusCapsule: GlassCapsule!
    private let statusLabel = NSTextField(labelWithString: "")
    private let actionButton = NSButton(title: "Start", target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private let problemLabel = NSTextField(wrappingLabelWithString: "")
    private let statsLabel = NSTextField(labelWithString: "")
    private var banner: GlassCapsule?
    private let bannerLabel = NSTextField(labelWithString: "")
    private var bannerTimer: Timer?
    private var captureBanner: GlassCapsule?
    private var hingeCapsule: GlassCapsule?
    private let hingeSlider = NSSlider(value: 0, minValue: 0, maxValue: 180, target: nil, action: nil)
    private let hingeLabel = NSTextField(labelWithString: "0°")
    private var hingeStartAngle = 0
    private var message: String?
    public var pairedTitle: String? { didSet { if pairedTitle != oldValue { updatePairedCapsule() } } }
    public var onPaired: (() -> Void)?
    public private(set) var pairedCapsule: GlassCapsule?
    static let pairedHeight: CGFloat = 28
    private var statusAction: String?
    private var statusBusy = false
    private var stoppedName = ""
    public private(set) var takenOverCapsule: GlassCapsule?
    private let takenOverTitle = NSTextField(labelWithString: "")
    private let takenOverButton = NSButton(title: "", target: nil, action: nil)
    public var onTakeBack: (() -> Void)?
    private var restoreCameraOnHello = false

    public init(mode: Mode) {
        self.mode = mode
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 700))
        wantsLayer = true
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = mode == .hub
        scroll.hasHorizontalScroller = mode == .hub
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero
        scroll.documentView = document
        scroll.contentView.drawsBackground = false
        addSubview(scroll)
        document.addSubview(frameView)
        problemLabel.alignment = .center
        problemLabel.textColor = .white.withAlphaComponent(0.8)
        problemLabel.font = .systemFont(ofSize: 12)
        frameView.addSubview(problemLabel)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.font = .systemFont(ofSize: 15)
        messageLabel.alignment = .center
        messageLabel.maximumNumberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        addSubview(messageLabel)
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        actionButton.isBordered = false
        actionButton.font = .systemFont(ofSize: 13, weight: .semibold)
        actionButton.contentTintColor = .controlAccentColor
        actionButton.identifier = .init("canvas-action-button")
        actionButton.target = self
        actionButton.action = #selector(actionClicked)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        statusStack.orientation = .horizontal
        statusStack.spacing = 8
        statusStack.edgeInsets = NSEdgeInsets(top: 0, left: 18, bottom: 0, right: 18)
        for v in [spinner, statusLabel, actionButton] { statusStack.addArrangedSubview(v) }
        statusCapsule = GlassCapsule(content: statusStack, height: DeviceControlsRow.height)
        statusCapsule.identifier = .init("canvas-status-capsule")
        statusCapsule.translatesAutoresizingMaskIntoConstraints = true
        addSubview(statusCapsule)
        statsLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        statsLabel.textColor = .secondaryLabelColor
        statsLabel.isHidden = true
        statsLabel.lineBreakMode = .byTruncatingTail
        addSubview(statsLabel)
        addSubview(controls)
        controls.onCommand = { [weak self] c in self?.perform(c) }
        controls.onHingeDrag = { [weak self] d in self?.hingeDrag(d) }
        frameView.onButton = { [weak self] kind, down in self?.frameButton(kind, down: down) }
        frameView.onHingeDrag = { [weak self] d in self?.hingeDrag(d) }
        frameView.screen.onCaptureCancelled = { [weak self] in self?.setCapturesKeyboard(false) }
        hingeSlider.isContinuous = true
        hingeSlider.target = self
        hingeSlider.action = #selector(hingeSlid(_:))
        hingeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        showMessage("No Selection")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    public func show(session s: DeviceLiveSession) {
        if session !== s {
            session?.removeObserver(self)
            session = s
            s.addObserver(self)
        }
        frameView.screen.input = s
        frameView.screen.image = s.image
        stoppedSpec = nil
        message = nil
        statusAction = nil
        refreshGeometry()
        refreshState()
    }

    public func showStopped(spec: DeviceFrameSpec, name: String, os: String, action: String?, busy: Bool = false) {
        detachSession()
        stoppedSpec = spec
        message = nil
        stoppedName = name
        statusLabel.stringValue = busy ? "Starting…" : ""
        statusAction = action
        statusBusy = busy
        refreshGeometry()
        refreshState()
    }

    public func showMessage(_ text: String) {
        detachSession()
        stoppedSpec = nil
        message = text
        refreshState()
    }

    private func detachSession() {
        session?.removeObserver(self)
        session = nil
        frameView.screen.input = nil
        frameView.screen.image = nil
        setCapturesKeyboard(false)
    }

    public var statusActionCapsule: GlassCapsule { statusCapsule }
    public var statusActionButton: NSButton { actionButton }

    public var stateDescription: String {
        if let message { return "message: \(message)" }
        if stoppedSpec != nil { return statusBusy ? "starting" : "stopped" }
        if let s = session, s.isTakenOver || s.isHeldForHeadset && takenOverCapsule != nil { return s.isHeldForHeadset ? "in headset" : "taken over" }
        if let s = session { return s.hasImage ? "live" : "connecting: \(s.problemText ?? "")" }
        return "empty"
    }

    private func refreshState() {
        let hasDevice = session != nil || stoppedSpec != nil
        messageLabel.stringValue = message ?? ""
        messageLabel.isHidden = message == nil
        scroll.isHidden = !hasDevice
        statusCapsule.isHidden = stoppedSpec == nil || (statusAction == nil && !statusBusy)
        actionButton.title = statusAction ?? ""
        actionButton.setAccessibilityLabel(statusAction)
        actionButton.isHidden = statusAction == nil || statusBusy
        statusLabel.isHidden = !statusBusy
        frameView.setAccessibilityLabel(stoppedSpec != nil ? stoppedName : nil)
        if statusBusy { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        controls.isHidden = session == nil
        let problem = session.flatMap { $0.hasImage ? nil : $0.problemText }
        problemLabel.stringValue = problem ?? ""
        problemLabel.isHidden = problem == nil
        if let s = session {
            controls.configure(.init(foldable: s.isFoldable, canRotate: s.canRotate, recording: s.isRecording, posture: s.posture,
                                     enabled: s.isLive, showsRotate: s.spec.rotates, showsHome: s.spec.family != .watch,
                                     spatial: s.isSpatial || s.spec.family == .vision))
        }
        statsLabel.isHidden = !showsStatistics || session == nil
        updateStatistics()
        updateTakenOver()
        needsLayout = true
    }

    private func updateTakenOver() {
        let s = session
        let shown = s?.isTakenOver == true
        frameView.alphaValue = shown ? 0.55 : 1
        guard shown, let s else {
            takenOverCapsule?.removeFromSuperview()
            takenOverCapsule = nil
            return
        }
        restoreCameraOnHello = true
        takenOverTitle.stringValue = s.isHeldForHeadset ? "In Headset" : "Another viewer has this device"
        takenOverTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        takenOverButton.title = s.isHeldForHeadset ? "Back to Desktop" : "Take Back"
        takenOverButton.isBordered = false
        takenOverButton.font = .systemFont(ofSize: 13, weight: .semibold)
        takenOverButton.contentTintColor = .controlAccentColor
        takenOverButton.identifier = .init("taken-over-button")
        takenOverButton.target = self
        takenOverButton.action = #selector(takeBackClicked)
        takenOverButton.setAccessibilityLabel(takenOverButton.title)
        guard takenOverCapsule == nil else { return }
        let glyph = NSImageView(image: NSImage(systemSymbolName: "eyeglasses", accessibilityDescription: nil) ?? NSImage())
        let stack = NSStackView(views: [glyph, takenOverTitle, takenOverButton])
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 14)
        let c = GlassCapsule(content: stack, height: 40)
        c.identifier = .init("taken-over-capsule")
        addSubview(c)
        takenOverCapsule = c
    }

    @objc private func takeBackClicked() {
        if let onTakeBack, session?.isHeldForHeadset == true { onTakeBack() } else { session?.takeBack() }
    }

    private func refreshGeometry() {
        let g: DeviceFrameGeometry
        if let s = session {
            g = s.frameGeometry(bezels: showsBezels)
            frameView.screen.pointSize = s.shownPointSize
            frameView.allowsHingeDrag = s.isFoldable
        } else if let spec = stoppedSpec {
            g = DeviceFrameGeometry(spec: spec, bezels: showsBezels)
            frameView.allowsHingeDrag = false
        } else {
            return
        }
        if g != frameView.geometry {
            frameView.geometry = g
            onGeometryChange?()
        }
        needsLayout = true
    }

    public func session(_ s: DeviceLiveSession, changed: DeviceSessionChange) {
        guard s === session else { return }
        switch changed {
        case .image:
            frameView.screen.image = s.image
            if !problemLabel.isHidden { refreshState() }
        case .hello, .displayState:
            frameView.screen.cancelInput()
            refreshGeometry()
            refreshState()
            if changed == .hello, restoreCameraOnHello {
                restoreCameraOnHello = false
                frameView.screen.restoreSpatialCamera()
            }
        case .phase:
            if s.phase == "disconnected", s.isRecording {
                s.stopRecording()
                showBanner("Screen recording was stopped because the device disconnected.", seconds: 4)
            }
            refreshState()
        case .recording:
            refreshState()
        case .notice(let text):
            showBanner(text, seconds: 3)
        case .statistics:
            updateStatistics()
        }
    }

    private func updateStatistics() {
        guard showsStatistics, let s = session else { return }
        statsLabel.stringValue = s.statisticsText
    }

    public var deviceSize: CGSize { frameView.geometry.size }

    var deviceArea: CGRect {
        let b = bounds
        if mode == .compact { return CGRect(x: 0, y: topInset, width: b.width, height: max(1, b.height - topInset)) }
        var area = DeviceControlsLayout.deviceArea(canvasWidth: Double(b.width), canvasHeight: Double(b.height), top: Double(topInset))
        if pairedCapsule != nil { area.size.height = max(1, area.height - Self.pairedHeight - CompactWindowLayout.controlsGap) }
        return area
    }

    var displayPointsPerInch: Double? {
        guard let screen = window?.screen ?? NSScreen.main,
              let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        let mm = CGDisplayScreenSize(CGDirectDisplayID(n.uint32Value))
        return DeviceZoom.displayPointsPerInch(pointWidth: Double(screen.frame.width), millimetresWide: Double(mm.width))
    }

    public var effectiveScale: Double {
        let size = deviceSize
        switch mode {
        case .compact:
            return CompactWindowLayout.scale(device: size, windowWidth: Double(bounds.width))
        case .hub:
            switch zoom {
            case .fit: return DeviceZoom.fit(size, in: deviceArea.size)
            case .scale(let s): return s
            case .actual:
                let spec = session?.spec ?? stoppedSpec ?? .iPhoneDuo
                let panel = spec.panels[min(session?.panelIndex ?? 0, spec.panels.count - 1)]
                return DeviceZoom.physical(panel: panel, displayPointsPerInch: displayPointsPerInch ?? 110)
            }
        }
    }

    public override func layout() {
        super.layout()
        let b = bounds
        messageLabel.frame.size = messageLabel.sizeThatFits(NSSize(width: min(b.width - 48, 480), height: .greatestFiniteMagnitude))
        messageLabel.frame.origin = CGPoint(x: ((b.width - messageLabel.frame.width) / 2).rounded(),
                                            y: (topInset + (b.height - topInset - messageLabel.frame.height) / 2).rounded())
        let area = deviceArea
        let scale = effectiveScale
        frameView.scale = scale
        let size = CGSize(width: (deviceSize.width * scale).rounded(), height: (deviceSize.height * scale).rounded())
        scroll.frame = area
        let need = CGSize(width: size.width + 2 * DeviceZoom.fitMargin, height: size.height + 2 * DeviceZoom.fitMargin)
        let doc = CGSize(width: need.width > area.width + 1 ? need.width : area.width, height: need.height > area.height + 1 ? need.height : area.height)
        document.frame = CGRect(origin: .zero, size: doc)
        var origin = CGPoint(x: ((doc.width - size.width) / 2).rounded(), y: ((doc.height - size.height) / 2).rounded())
        if mode == .compact {
            origin = CGPoint(x: ((b.width - size.width) / 2).rounded(), y: CompactWindowLayout.topGap)
        }
        frameView.frame = CGRect(origin: origin, size: size)
        frameView.needsLayout = true
        let screenRect = frameView.screen.frame
        problemLabel.frame = screenRect.insetBy(dx: 12, dy: max(0, screenRect.height / 2 - 30))
        let cs = controls.intrinsicContentSize
        let cy = b.height - CGFloat(DeviceControlsLayout.bottomMargin) - DeviceControlsRow.height
        controls.frame = CGRect(x: ((b.width - cs.width) / 2).rounded(), y: cy, width: cs.width, height: DeviceControlsRow.height)
        if let pairedCapsule {
            let w = pairedCapsule.fittingSize.width
            let py = cy - CompactWindowLayout.controlsGap - Self.pairedHeight
            pairedCapsule.frame = CGRect(x: ((b.width - w) / 2).rounded(), y: py.rounded(), width: w, height: Self.pairedHeight)
            pairedCapsule.isHidden = session == nil && stoppedSpec == nil
        }
        if stoppedSpec != nil {
            let w = statusStack.fittingSize.width + 8
            statusCapsule.frame = CGRect(x: ((b.width - w) / 2).rounded(), y: cy, width: w, height: DeviceControlsRow.height)
        }
        statsLabel.frame = CGRect(x: 10, y: b.height - 18, width: max(10, b.width - 20), height: 16)
        if let banner {
            let s = banner.fittingSize
            banner.frame = CGRect(x: ((b.width - s.width) / 2).rounded(), y: topInset + 12, width: s.width, height: 32)
        }
        if let captureBanner {
            let s = captureBanner.fittingSize
            captureBanner.frame = CGRect(x: ((b.width - s.width) / 2).rounded(), y: topInset + (banner == nil ? 12 : 50), width: s.width, height: 44)
        }
        if let c = takenOverCapsule {
            let s = c.fittingSize
            c.frame = CGRect(x: ((b.width - s.width) / 2).rounded(), y: (deviceArea.midY - 20).rounded(), width: s.width, height: 40)
        }
        if let hingeCapsule {
            let w: CGFloat = 220
            hingeCapsule.frame = CGRect(x: ((b.width - w) / 2).rounded(), y: controls.frame.minY - 44, width: w, height: 34)
        }
    }

    private func updatePairedCapsule() {
        pairedCapsule?.removeFromSuperview()
        pairedCapsule = nil
        if let title = pairedTitle {
            let b = NSButton(title: title, target: self, action: #selector(pairedClicked))
            b.isBordered = false
            b.font = .systemFont(ofSize: 12, weight: .medium)
            b.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
            b.imagePosition = .imageTrailing
            b.imageHugsTitle = true
            b.setAccessibilityLabel(title)
            b.identifier = .init("paired-capsule-button")
            let c = GlassCapsule(content: b, height: Self.pairedHeight)
            c.identifier = .init("paired-capsule")
            addSubview(c)
            pairedCapsule = c
        }
        needsLayout = true
    }

    @objc private func pairedClicked() { onPaired?() }

    public func zoomIn() { zoom = .scale(DeviceZoom.zoomIn(from: effectiveScale)) }
    public func zoomOut() { zoom = .scale(DeviceZoom.zoomOut(from: effectiveScale)) }
    public func zoomToFit() { zoom = .fit }
    public func zoomToActualSize() { zoom = .actual }

    public func canPerform(_ c: DeviceCommand) -> Bool {
        if c == .viewInHeadset { return headsetCommandEnabled?() ?? false }
        guard let s = session else {
            switch c {
            case .zoomIn, .zoomOut, .zoomToFit, .physicalSize, .toggleBezels: return stoppedSpec != nil
            default: return false
            }
        }
        switch c {
        case .rotateLeft, .rotateRight: return s.isLive && s.canRotate
        case .poseClosed, .posePartiallyOpen, .poseOpen: return s.isLive && s.isFoldable
        case .actionButton: return s.isLive && s.spec.hasActionButton
        case .volumeUp, .volumeDown: return s.isLive && s.spec.hasVolumeButtons
        case .appSwitcher: return s.isLive && s.spec.family != .watch
        case .resetCamera: return s.isLive && s.isSpatial
        case .physicalSize: return s.spec.family != .vision
        case .toggleBezels: return s.spec.hasFrame
        case .zoomIn, .zoomOut, .zoomToFit, .captureKeyboard: return true
        case .start, .restart, .shutDown, .forceShutDown: return false
        default: return s.isLive
        }
    }

    public func perform(_ c: DeviceCommand) {
        switch c {
        case .zoomIn: zoomIn(); return
        case .zoomOut: zoomOut(); return
        case .zoomToFit: zoomToFit(); return
        case .physicalSize: zoomToActualSize(); return
        case .toggleBezels: showsBezels.toggle(); return
        case .captureKeyboard: setCapturesKeyboard(!capturesKeyboard); return
        case .viewInHeadset: if commandFallback?(c) != true { NSSound.beep() }; return
        default: break
        }
        guard let s = session, s.isLive else {
            if commandFallback?(c) != true { NSSound.beep() }
            return
        }
        switch c {
        case .home: s.press(.home)
        case .lock: s.press(.lock)
        case .volumeUp: s.press(.volumeUp)
        case .volumeDown: s.press(.volumeDown)
        case .actionButton: s.press(s.displayButton(for: .action))
        case .appSwitcher: s.appSwitcher()
        case .resetCamera: frameView.screen.resetSpatialCamera()
        case .rotateLeft: s.rotate(left: true)
        case .rotateRight: s.rotate(left: false)
        case .poseClosed: s.fold(to: DevicePosture.closed.angle)
        case .posePartiallyOpen: s.fold(to: DevicePosture.halfOpen.angle)
        case .poseOpen: s.fold(to: DevicePosture.openFlat.angle)
        case .screenshot:
            s.saveScreenshot { [weak self] r in
                switch r {
                case .success: self?.showBanner("Screenshot Saved")
                case .failure(let e): self?.showBanner("Screenshot Failed: \(e.localizedDescription)", seconds: 4)
                }
            }
        case .recordScreen:
            if s.isRecording {
                s.stopRecording { [weak self] url in self?.showBanner(url == nil ? "Recording Failed" : "Recording Saved") }
            } else {
                do { try s.startRecording() } catch { showBanner("Cannot Record: \(error.localizedDescription)", seconds: 4) }
            }
        default:
            if commandFallback?(c) != true { NSSound.beep() }
        }
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard handlesKeyEquivalents, window?.isKeyWindow == true, !capturesKeyboard,
              let chars = event.charactersIgnoringModifiers else { return super.performKeyEquivalent(with: event) }
        var mods: DeviceKeyModifiers = []
        let f = event.modifierFlags
        if f.contains(.command) { mods.insert(.command) }
        if f.contains(.shift) { mods.insert(.shift) }
        if f.contains(.option) { mods.insert(.option) }
        if f.contains(.control) { mods.insert(.control) }
        guard let c = DeviceCommand.bound(to: chars, modifiers: mods), canPerform(c) else { return super.performKeyEquivalent(with: event) }
        perform(c)
        return true
    }

    private func frameButton(_ kind: DeviceFrameGeometry.ButtonKind, down: Bool) {
        guard let s = session, s.isLive else {
            if !down {
                let c: DeviceCommand = kind == .volumeUp ? .volumeUp : kind == .volumeDown ? .volumeDown : kind == .action ? .actionButton
                    : kind == .crown ? .home : .lock
                if commandFallback?(c) != true { NSSound.beep() }
            }
            return
        }
        let b = s.displayButton(for: kind)
        if down { s.buttonDown(b) } else { s.buttonUp(b) }
    }

    @objc private func actionClicked() { onAction?() }

    public private(set) var capturesKeyboard = false

    public func setCapturesKeyboard(_ on: Bool) {
        let on = on && session != nil
        guard on != capturesKeyboard else { return }
        capturesKeyboard = on
        frameView.screen.capturesKeyboard = on
        if on {
            window?.makeFirstResponder(frameView.screen)
            let title = NSTextField(labelWithString: "Capturing Keyboard")
            title.font = .systemFont(ofSize: 12, weight: .semibold)
            let sub = NSTextField(labelWithString: "Hold Escape to cancel")
            sub.font = .systemFont(ofSize: 11)
            sub.textColor = .secondaryLabelColor
            let stack = NSStackView(views: [title, sub])
            stack.orientation = .vertical
            stack.spacing = 1
            stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
            let c = GlassCapsule(content: stack, height: 44)
            c.identifier = .init("capture-banner")
            captureBanner?.removeFromSuperview()
            captureBanner = c
            addSubview(c)
        } else {
            captureBanner?.removeFromSuperview()
            captureBanner = nil
        }
        needsLayout = true
        onCaptureChange?(on)
    }

    public var showsCaptureNotice: Bool { captureBanner != nil }

    public var bannerText: String? { banner == nil ? nil : bannerLabel.stringValue }

    public func showBanner(_ text: String, seconds: TimeInterval = 2) {
        bannerTimer?.invalidate()
        banner?.removeFromSuperview()
        bannerLabel.stringValue = text
        bannerLabel.font = .systemFont(ofSize: 12, weight: .medium)
        bannerLabel.lineBreakMode = .byTruncatingTail
        let box = NSStackView(views: [bannerLabel])
        box.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        let c = GlassCapsule(content: box, height: 32)
        c.identifier = .init("feedback-banner")
        banner = c
        addSubview(c)
        needsLayout = true
        bannerTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.banner?.removeFromSuperview()
                self?.banner = nil
            }
        }
    }

    static let pointsPerDegree: CGFloat = 1.2

    public var showsHingeSlider: Bool { hingeCapsule != nil }

    func hingeDrag(_ d: CGFloat?) {
        guard let s = session, s.isFoldable else { return }
        guard let d else {
            s.fold(to: hingeSlider.integerValue)
            hingeCapsule?.removeFromSuperview()
            hingeCapsule = nil
            return
        }
        if hingeCapsule == nil {
            hingeStartAngle = s.hingeTarget ?? 0
            let stack = NSStackView(views: [hingeSlider, hingeLabel])
            stack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
            hingeSlider.widthAnchor.constraint(equalToConstant: 140).isActive = true
            let c = GlassCapsule(content: stack, height: 34)
            c.identifier = .init("hinge-slider")
            hingeCapsule = c
            addSubview(c)
            needsLayout = true
        }
        let angle = min(180, max(0, hingeStartAngle + Int((d / Self.pointsPerDegree).rounded())))
        hingeSlider.integerValue = angle
        hingeLabel.stringValue = "\(angle)°"
    }

    @objc private func hingeSlid(_ sender: NSSlider) { hingeLabel.stringValue = "\(sender.integerValue)°" }
}
#endif
