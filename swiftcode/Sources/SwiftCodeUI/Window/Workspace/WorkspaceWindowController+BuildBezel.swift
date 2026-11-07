import AppKit
import UserNotifications
import SwiftCodeIDECore

struct BuildBezelState {
    var timeline = BezelTimeline()
    weak var view: BuildBezelView?
    var windowStateOverride: BuildNotificationPolicy.WindowState?
    var reduceMotionOverride: Bool?
    var systemNotices: [BuildNotice] = []
}

extension WorkspaceWindowController {
    var finishedActivityText: String? {
        if case .finished(let s)? = behaviorStore.tracker.previous { return s }
        return nil
    }

    public var notificationWindowStateOverride: BuildNotificationPolicy.WindowState? {
        get { behaviorStore.bezel.windowStateOverride }
        set { behaviorStore.bezel.windowStateOverride = newValue }
    }

    public var bezelReduceMotionOverride: Bool? {
        get { behaviorStore.bezel.reduceMotionOverride }
        set { behaviorStore.bezel.reduceMotionOverride = newValue }
    }

    public var buildBezelView: NSView? { behaviorStore.bezel.view }
    public var buildBezelTitle: String? { behaviorStore.bezel.view == nil ? nil : behaviorStore.bezel.timeline.notice?.title }
    public var buildBezelShowCount: Int { behaviorStore.bezel.timeline.showCount }
    public var systemNotices: [BuildNotice] { behaviorStore.bezel.systemNotices }

    var notificationWindowState: BuildNotificationPolicy.WindowState {
        if let o = behaviorStore.bezel.windowStateOverride { return o }
        return BuildNotificationPolicy.WindowState(isVisible: window?.isVisible ?? false, isMinimized: window?.isMiniaturized ?? false,
                                                   isKey: window?.isKeyWindow ?? false, appIsActive: NSApp.isActive)
    }

    func notify(_ n: BuildNotice) {
        switch BuildNotificationPolicy.route(notificationWindowState) {
        case .bezel: showBuildBezel(n)
        case .systemNotification:
            behaviorStore.bezel.systemNotices.append(n)
            SystemBuildNotifier.post(n, workspace: session.model.displayName)
        }
    }

    func showBuildBezel(_ n: BuildNotice) {
        guard let content = window?.contentView else { return }
        let reduce = behaviorStore.bezel.reduceMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let g = behaviorStore.bezel.timeline.show(n, at: Date(), reduceMotion: reduce)
        let v = behaviorStore.bezel.view ?? BuildBezelView()
        v.set(n)
        v.alphaValue = 1
        if v.superview !== content {
            v.removeFromSuperview()
            content.addSubview(v, positioned: .above, relativeTo: nil)
        }
        let s = BuildBezelView.side
        v.frame = NSRect(x: ((content.bounds.width - s) / 2).rounded(), y: ((content.bounds.height - s) / 2).rounded(), width: s, height: s)
        v.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        behaviorStore.bezel.view = v
        NSAccessibility.post(element: window as Any, notification: .announcementRequested,
                             userInfo: [.announcement: n.title, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        let timeline = behaviorStore.bezel.timeline
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeline.fadeStartsAfter * 1e9))
            self?.fadeBuildBezel(generation: g)
            try? await Task.sleep(nanoseconds: UInt64(timeline.currentFadeDuration * 1e9))
            self?.removeBuildBezel(generation: g)
        }
    }

    private func fadeBuildBezel(generation g: Int) {
        guard g == behaviorStore.bezel.timeline.generation, let v = behaviorStore.bezel.view else { return }
        let fade = behaviorStore.bezel.timeline.currentFadeDuration
        guard fade > 0 else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = fade
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            v.animator().alphaValue = 0
        }
    }

    private func removeBuildBezel(generation g: Int) {
        guard behaviorStore.bezel.timeline.expire(generation: g) else { return }
        behaviorStore.bezel.view?.removeFromSuperview()
        behaviorStore.bezel.view = nil
    }
}

final class BuildBezelView: NSView {
    static let side: CGFloat = 200
    static let radius: CGFloat = 18
    private let glyph = NSImageView()
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.side))
        wantsLayer = true
        glyph.imageScaling = .scaleProportionallyUpOrDown
        glyph.contentTintColor = NSColor(white: 1, alpha: 0.9)
        glyph.frame = NSRect(x: (Self.side - 112) / 2, y: 64, width: 112, height: 96)
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.frame = NSRect(x: 10, y: 28, width: Self.side - 20, height: 22)
        for v in [glyph, label] as [NSView] {
            v.setAccessibilityElement(false)
            addSubview(v)
        }
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func set(_ n: BuildNotice) {
        label.stringValue = n.title
        let config = NSImage.SymbolConfiguration(pointSize: 80, weight: .light)
        glyph.image = NSImage(systemSymbolName: n.symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        needsDisplay = true
    }

    var title: String { label.stringValue }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.08, alpha: 0.86).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: Self.radius, yRadius: Self.radius).fill()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
enum SystemBuildNotifier {
    private static var authorization: Bool?
    private static var asking = false

    static var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil }

    static func post(_ n: BuildNotice, workspace: String) {
        guard isAvailable else { return fallback() }
        if authorization == false { return fallback() }
        let title = n.title
        if authorization == true { return add(title: title, body: workspace) }
        guard !asking else { return fallback() }
        asking = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in
                asking = false
                authorization = granted
                if granted { add(title: title, body: workspace) } else { fallback() }
            }
        }
    }

    private static func add(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: "swiftcode.build-result", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            guard error != nil else { return }
            Task { @MainActor in fallback() }
        }
    }

    static func fallback() {
        guard NSApp.activationPolicy() == .regular else { return }
        NSApp.requestUserAttention(.informationalRequest)
    }
}
