import AppKit

@MainActor
final class ComposerScrollView: NSScrollView {
    static let cornerRadius: CGFloat = 8
    private var contrastObserver: NSObjectProtocol?

    override init(frame: NSRect) {
        super.init(frame: frame)
        autohidesScrollers = true
        guard #available(macOS 26, *) else { borderType = .bezelBorder; return }
        borderType = .noBorder
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        contrastObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateStroke() }
        }
        updateStroke()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateStroke()
    }

    private func updateStroke() {
        guard #available(macOS 26, *), let layer else { return }
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.borderColor = (contrast ? NSColor.secondaryLabelColor : NSColor.separatorColor).cgColor
        }
        layer.borderWidth = 1
    }
}
