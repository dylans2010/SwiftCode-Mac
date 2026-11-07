#if os(macOS)
import AppKit
import YcodeDeviceModel

@MainActor
public final class GlassCapsule: NSView {
    public let content: NSView
    private let glass: NSView

    public init(content: NSView, height: CGFloat = 37, inset: CGFloat = 4) {
        self.content = content
        if #available(macOS 26, *) {
            let g = NSGlassEffectView()
            g.cornerRadius = height / 2
            g.style = .regular
            glass = g
        } else {
            let v = NSVisualEffectView()
            v.material = .hudWindow
            v.blendingMode = .withinWindow
            v.state = .active
            v.wantsLayer = true
            v.layer?.cornerRadius = height / 2
            v.layer?.masksToBounds = true
            glass = v
        }
        super.init(frame: .zero)
        for v in [glass, content] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor), glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor), glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset), content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: height),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

@MainActor
final class RowButton: NSButton {
    var command: DeviceCommand = .home
    var onOptionDrag: ((CGFloat?) -> Void)?

    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.option), let onOptionDrag, let window else { super.mouseDown(with: event); return }
        let start = event.locationInWindow.x
        onOptionDrag(0)
        while let e = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if e.type == .leftMouseUp { break }
            onOptionDrag(e.locationInWindow.x - start)
        }
        onOptionDrag(nil)
    }
}

@MainActor
public final class DeviceControlsRow: NSView {
    public static let height = CGFloat(DeviceControlsLayout.height)
    public var onCommand: ((DeviceCommand) -> Void)?
    public var onHingeDrag: ((CGFloat?) -> Void)?

    private var buttons: [DeviceCommand: RowButton] = [:]
    public private(set) var capsules: [GlassCapsule] = []
    public private(set) var configuration = Configuration()

    public struct Configuration: Equatable {
        public var foldable = false
        public var canRotate = false
        public var recording = false
        public var posture: DevicePosture?
        public var enabled = false
        public var showsRotate = true
        public var showsHome = true
        public var spatial = false
        public init(foldable: Bool = false, canRotate: Bool = false, recording: Bool = false, posture: DevicePosture? = nil,
                    enabled: Bool = false, showsRotate: Bool = true, showsHome: Bool = true, spatial: Bool = false) {
            self.foldable = foldable
            self.canRotate = canRotate
            self.recording = recording
            self.posture = posture
            self.enabled = enabled
            self.showsRotate = showsRotate
            self.showsHome = showsHome
            self.spatial = spatial
        }

        var device: DeviceControlsLayout.Device {
            .init(showsHome: showsHome, rotates: showsRotate, foldable: foldable, spatial: spatial)
        }
    }

    public override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Device Controls")
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    static func look(_ c: DeviceCommand, recording: Bool) -> (symbol: String, help: String) {
        switch c {
        case .home: ("circle.grid.3x3.fill", "Home")
        case .screenshot: ("camera.viewfinder", "Screenshot")
        case .recordScreen: recording ? ("stop.circle.fill", "Stop Recording") : ("record.circle", "Record Screen")
        case .rotateLeft: ("rotate.left", "Rotate (Option-click to rotate right)")
        case .resetCamera: ("arrow.counterclockwise", "Reset Camera")
        case .poseClosed: ("", "Closed")
        case .posePartiallyOpen: ("book", "Partially Open (Option-drag to set any angle)")
        case .poseOpen: ("", "Open")
        default: ("questionmark", c.title)
        }
    }

    public var groups: [[DeviceCommand]] { DeviceControlsLayout.groups(configuration.device) }

    public func configure(_ c: Configuration) {
        guard c != configuration else { return }
        let rebuildNeeded = c.device != configuration.device
        configuration = c
        if rebuildNeeded { rebuild() } else { update() }
    }

    public func button(for c: DeviceCommand) -> NSButton? { buttons[c] }

    private func makeButton(_ c: DeviceCommand) -> RowButton {
        let b = RowButton(title: "", target: self, action: #selector(clicked(_:)))
        b.command = c
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.imagePosition = .imageOnly
        b.imageScaling = .scaleNone
        b.refusesFirstResponder = true
        b.identifier = .init("device-control-\(c.rawValue)")
        if [.poseClosed, .posePartiallyOpen, .poseOpen].contains(c) {
            b.onOptionDrag = { [weak self] d in self?.onHingeDrag?(d) }
        }
        buttons[c] = b
        return b
    }

    private func rebuild() {
        capsules.forEach { $0.removeFromSuperview() }
        capsules = []
        buttons = [:]
        for (i, group) in groups.enumerated() {
            let inner = FlippedView()
            let w = CGFloat(DeviceControlsLayout.width(of: group))
            for (c, cx) in zip(group, DeviceControlsLayout.glyphCentres(of: group)) {
                let b = makeButton(c)
                b.frame = CGRect(x: CGFloat(cx - DeviceControlsLayout.buttonWidth / 2), y: 0,
                                 width: CGFloat(DeviceControlsLayout.buttonWidth), height: Self.height)
                inner.addSubview(b)
            }
            if let d = DeviceControlsLayout.dividerCentre(of: group) {
                let sep = DividerLine(frame: CGRect(x: CGFloat(d) - 0.5, y: (Self.height - 20) / 2, width: 1, height: 20))
                sep.identifier = .init("device-controls-divider")
                inner.addSubview(sep)
            }
            inner.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([inner.widthAnchor.constraint(equalToConstant: w), inner.heightAnchor.constraint(equalToConstant: Self.height)])
            let capsule = GlassCapsule(content: inner, height: Self.height, inset: 0)
            capsule.identifier = .init(i == 0 ? "device-controls-capture" : "device-controls-orientation")
            capsule.translatesAutoresizingMaskIntoConstraints = true
            addSubview(capsule)
            capsules.append(capsule)
        }
        update()
        needsLayout = true
    }

    private func update() {
        for (c, b) in buttons {
            let look = Self.look(c, recording: configuration.recording)
            switch c {
            case .poseClosed: b.image = DeviceGlyph.phone.image(height: 16, lit: true)
            case .poseOpen: b.image = DeviceGlyph.openFlat.image(height: 13, lit: true)
            default:
                b.image = NSImage(systemSymbolName: look.symbol, accessibilityDescription: look.help)?
                    .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
            }
            b.toolTip = look.help
            b.setAccessibilityLabel(look.help)
            b.contentTintColor = c == .recordScreen && configuration.recording ? .systemRed
                : Self.isCurrentPose(c, configuration.posture) ? .controlAccentColor : .labelColor
            switch c {
            case .rotateLeft: b.isEnabled = configuration.enabled && configuration.canRotate
            default: b.isEnabled = configuration.enabled
            }
        }
    }

    static func isCurrentPose(_ c: DeviceCommand, _ p: DevicePosture?) -> Bool {
        switch (c, p) {
        case (.poseClosed, .closed?), (.posePartiallyOpen, .halfOpen?), (.poseOpen, .openFlat?): true
        default: false
        }
    }

    public var highlightedPose: DeviceCommand? {
        [DeviceCommand.poseClosed, .posePartiallyOpen, .poseOpen].first { Self.isCurrentPose($0, configuration.posture) }
    }

    public override func layout() {
        super.layout()
        var x: CGFloat = 0
        for (g, c) in zip(groups, capsules) {
            let w = CGFloat(DeviceControlsLayout.width(of: g))
            c.frame = CGRect(x: x, y: 0, width: w, height: Self.height)
            x += w + CGFloat(DeviceControlsLayout.gap)
        }
    }

    @objc private func clicked(_ sender: RowButton) {
        var c = sender.command
        if c == .rotateLeft, NSApp.currentEvent?.modifierFlags.contains(.option) == true { c = .rotateRight }
        onCommand?(c)
    }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: CGFloat(DeviceControlsLayout.totalWidth(groups)), height: Self.height)
    }
}

@MainActor
final class DividerLine: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.backgroundColor = NSColor.separatorColor.cgColor }
}
#endif
