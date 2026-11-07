import AppKit
import ImageIO
import UniformTypeIdentifiers
import SwiftCodeIDECore

@MainActor
public final class ImageViewerController: NSViewController {
    public let url: URL
    public private(set) var properties: ImageFileProperties?
    public var onLoaded: ((ImageFileProperties) -> Void)?
    public let imageView = FittedImageView()
    public let previewButton = NSButton(title: "Open with Preview", target: nil, action: nil)
    public let loadingLabel = NSTextField(labelWithString: "Loading…")
    private var loading: Task<Void, Never>?
    private var decodedEarly: ImageFileProperties.Decoded?
    public private(set) var isReady = false
    public var onReady: (() -> Void)?

    public init(url: URL, synchronousLimit: Int = ImageViewerLayout.synchronousDecodeLimit) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int.max
        if size <= synchronousLimit {
            decodedEarly = ImageFileProperties.decode(url)
            properties = decodedEarly?.properties
            isReady = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public static func handles(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image) && !type.conforms(to: .svg)
    }

    public override func loadView() {
        let root = ImageViewerBackground()
        loadingLabel.font = .systemFont(ofSize: 13)
        loadingLabel.textColor = .secondaryLabelColor
        loadingLabel.alignment = .center
        previewButton.target = self
        previewButton.action = #selector(openWithPreview(_:))
        ImageViewerLayout.stylePreviewButton(previewButton)
        imageView.isHidden = true
        loadingLabel.isHidden = true
        for v in [imageView, loadingLabel, previewButton] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        let g = root.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: g.topAnchor, constant: ImageViewerLayout.topMargin),
            imageView.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: ImageViewerLayout.sideMargin),
            imageView.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -ImageViewerLayout.sideMargin),
            imageView.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -ImageViewerLayout.bottomMargin),
            loadingLabel.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            loadingLabel.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            previewButton.centerXAnchor.constraint(equalTo: g.centerXAnchor),
            previewButton.heightAnchor.constraint(equalToConstant: ImageViewerLayout.buttonHeight),
            previewButton.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -ImageViewerLayout.buttonBottomGap),
        ])
        view = root
        load()
    }

    private func load() {
        if isReady {
            show(decodedEarly)
            decodedEarly = nil
            return
        }
        let url = url
        loading = Task { [weak self] in
            let decoded = await Task.detached(priority: .userInitiated) { ImageFileProperties.decode(url) }.value
            guard let self, !Task.isCancelled else { return }
            self.isReady = true
            self.show(decoded)
            self.onReady?()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + ImageViewerLayout.loadingDelay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isReady else { return }
                self.loadingLabel.isHidden = false
            }
        }
    }

    private func show(_ decoded: ImageFileProperties.Decoded?) {
        loadingLabel.isHidden = true
        guard let decoded else {
            loadingLabel.stringValue = "Unable to open the image"
            loadingLabel.isHidden = false
            return
        }
        properties = decoded.properties
        imageView.image = NSImage(cgImage: decoded.image, size: decoded.properties.pointSize)
        imageView.isHidden = false
        onLoaded?(decoded.properties)
    }

    public func loaded() async { await loading?.value }

    @objc private func openWithPreview(_ sender: Any?) {
        guard view.window?.isVisible == true else { return }
        let config = NSWorkspace.OpenConfiguration()
        if let preview = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview") {
            NSWorkspace.shared.open([url], withApplicationAt: preview, configuration: config)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    deinit { MainActor.assumeIsolated { loading?.cancel() } }
}

public enum ImageViewerLayout {
    public static let loadingDelay: TimeInterval = 0.45
    public static let synchronousDecodeLimit = 24 * 1024 * 1024
    public static let topMargin: CGFloat = 20
    public static let bottomMargin: CGFloat = 60
    public static let sideMargin: CGFloat = 20
    public static let buttonHeight: CGFloat = 20
    public static let buttonBottomGap: CGFloat = 20

    public static func fittedRect(imageSize: NSSize, in box: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0, box.width > 0, box.height > 0 else { return .zero }
        let scale = min(1, box.width / imageSize.width, box.height / imageSize.height)
        let w = imageSize.width * scale, h = imageSize.height * scale
        return NSRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
    }

    @MainActor
    static func stylePreviewButton(_ b: NSButton) {
        b.bezelStyle = .push
        b.isBordered = false
        b.wantsLayer = true
        b.font = .systemFont(ofSize: 12)
        b.contentTintColor = .labelColor
        b.layer?.cornerRadius = 5
        b.layer?.backgroundColor = NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.25, alpha: 1) : NSColor(white: 0xEC / 255.0, alpha: 1)
        }.cgColor
        b.setContentHuggingPriority(.required, for: .horizontal)
        let w = (b.title as NSString).size(withAttributes: [.font: b.font as Any]).width + 20
        b.widthAnchor.constraint(equalToConstant: ceil(w)).isActive = true
    }
}

public final class FittedImageView: NSView {
    public var image: NSImage? { didSet { needsDisplay = true } }
    public var imageRect: NSRect { image.map { ImageViewerLayout.fittedRect(imageSize: $0.size, in: bounds) } ?? .zero }
    public override var isFlipped: Bool { true }
    public override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                   hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)])
    }
}

final class ImageViewerBackground: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        Theme.backgroundColor.setFill()
        dirtyRect.intersection(bounds).fill()
    }
}

public struct ImageFileProperties: Equatable, Sendable {
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var dpi: Double
    public var colorSpace: String
    public var hasAlpha: Bool
    public var recordsResolution = true

    public var pointSize: NSSize {
        let scale = dpi > 0 ? 72 / dpi : 1
        return NSSize(width: Double(pixelWidth) * scale, height: Double(pixelHeight) * scale)
    }

    public var rows: [(String, String)] {
        [("Dimensions", "\(pixelWidth) × \(pixelHeight) pixels"),
         ("Resolution", recordsResolution ? "\(Int(dpi.rounded())) × \(Int(dpi.rounded())) DPI" : "--"),
         ("Color Space", colorSpace),
         ("Alpha Channel", hasAlpha ? "Yes" : "No")]
    }

    public static let placeholderRows: [(String, String)] = ["Dimensions", "Resolution", "Color Space", "Alpha Channel"].map { ($0, "--") }

    struct Decoded: @unchecked Sendable {
        let image: CGImage
        let properties: ImageFileProperties
    }

    static func decode(_ url: URL) -> Decoded? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        let dpi = (props[kCGImagePropertyDPIWidth] as? Double) ?? 72
        let model = (props[kCGImagePropertyColorModel] as? String) ?? "RGB"
        let alpha: Bool = switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
        var properties = ImageFileProperties(pixelWidth: image.width, pixelHeight: image.height, dpi: dpi, colorSpace: model, hasAlpha: alpha)
        properties.recordsResolution = props[kCGImagePropertyDPIWidth] != nil
        return Decoded(image: image, properties: properties)
    }
}
