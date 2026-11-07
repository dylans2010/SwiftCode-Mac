import AppKit
import SwiftUI
import SwiftCodeIcon
import SwiftCodeIDECore

@MainActor
public final class IconComposerController: NSViewController {
    public let url: URL
    public private(set) var package: IconPackage?
    public var selectedPlatform: IconPlatform = .iOS {
        didSet { reloadPreview() }
    }
    public var selectedAppearance: IconAppearance = .light {
        didSet { reloadPreview() }
    }

    private let canvasContainer = NSView()
    private let iconPreviewView = IconRenderPreviewView()
    private let infoLabel = NSTextField(labelWithString: "")
    private let issuesStack = NSStackView()
    private let platformSegment = NSSegmentedControl(labels: ["iOS", "macOS", "watchOS"], trackingMode: .selectOne, target: nil, action: nil)
    private let appearanceSegment = NSSegmentedControl(labels: ["Light", "Dark", "Tinted"], trackingMode: .selectOne, target: nil, action: nil)

    public init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
        loadPackage()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public static func handles(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "icon"
    }

    public override func loadView() {
        let root = NSView()
        root.wantsLayer = true

        let topBar = NSStackView()
        topBar.orientation = .horizontal
        topBar.spacing = 16
        topBar.alignment = .centerY

        platformSegment.target = self
        platformSegment.action = #selector(platformChanged(_:))
        platformSegment.selectedSegment = 0

        appearanceSegment.target = self
        appearanceSegment.action = #selector(appearanceChanged(_:))
        appearanceSegment.selectedSegment = 0

        let titleLabel = NSTextField(labelWithString: url.deletingPathExtension().lastPathComponent)
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)

        topBar.addArrangedSubview(titleLabel)
        topBar.addArrangedSubview(platformSegment)
        topBar.addArrangedSubview(appearanceSegment)

        canvasContainer.wantsLayer = true
        canvasContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        canvasContainer.layer?.cornerRadius = 8

        iconPreviewView.translatesAutoresizingMaskIntoConstraints = false
        canvasContainer.addSubview(iconPreviewView)

        infoLabel.font = .systemFont(ofSize: 11)
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.alignment = .center

        issuesStack.orientation = .vertical
        issuesStack.spacing = 4
        issuesStack.alignment = .leading

        for v in [topBar, canvasContainer, infoLabel, issuesStack] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 12),
            topBar.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 32),

            canvasContainer.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 16),
            canvasContainer.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            canvasContainer.widthAnchor.constraint(equalToConstant: 320),
            canvasContainer.heightAnchor.constraint(equalToConstant: 320),

            iconPreviewView.centerXAnchor.constraint(equalTo: canvasContainer.centerXAnchor),
            iconPreviewView.centerYAnchor.constraint(equalTo: canvasContainer.centerYAnchor),
            iconPreviewView.widthAnchor.constraint(equalToConstant: 256),
            iconPreviewView.heightAnchor.constraint(equalToConstant: 256),

            infoLabel.topAnchor.constraint(equalTo: canvasContainer.bottomAnchor, constant: 12),
            infoLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            infoLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),

            issuesStack.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 12),
            issuesStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            issuesStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            issuesStack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -16)
        ])

        view = root
        reloadPreview()
    }

    private func loadPackage() {
        do {
            self.package = try IconPackage(contentsOf: url)
        } catch {
            infoLabel.stringValue = "Failed to load .icon package: \(error.localizedDescription)"
        }
    }

    private func reloadPreview() {
        guard let package else { return }
        let resolved = package.document.resolved(selectedAppearance, selectedPlatform)
        iconPreviewView.configure(with: package, resolved: resolved, platform: selectedPlatform)

        let groupCount = resolved.groups.count
        let layerCount = resolved.groups.reduce(0) { $0 + $1.layers.count }
        infoLabel.stringValue = "\(package.name).icon — \(groupCount) groups, \(layerCount) layers — Canvas: \(Int(selectedPlatform.canvasSize))pt"

        issuesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let issues = package.validate()
        for issue in issues.prefix(5) {
            let label = NSTextField(labelWithString: "• \(issue.description)")
            label.font = .systemFont(ofSize: 11)
            label.textColor = issue.severity == .error ? .systemRed : .systemOrange
            issuesStack.addArrangedSubview(label)
        }
    }

    @objc private func platformChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: selectedPlatform = .iOS
        case 1: selectedPlatform = .macOS
        case 2: selectedPlatform = .watchOS
        default: break
        }
    }

    @objc private func appearanceChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: selectedAppearance = .light
        case 1: selectedAppearance = .dark
        case 2: selectedAppearance = .tinted
        default: break
        }
    }
}

final class IconRenderPreviewView: NSView {
    private var fillColor: NSColor = .controlAccentColor
    private var isCircle = false
    private var layerImages: [(image: NSImage?, opacity: Double)] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(with package: IconPackage, resolved: IconResolvedDocument, platform: IconPlatform) {
        self.isCircle = (platform == .watchOS)

        if let fill = resolved.fill {
            if let c = fill.solidColor {
                self.fillColor = NSColor(red: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
            } else if let g = fill.gradient {
                if let first = g.stops.first {
                    self.fillColor = NSColor(red: first.color.red, green: first.color.green, blue: first.color.blue, alpha: first.color.alpha)
                }
            }
        } else {
            self.fillColor = .controlAccentColor
        }

        var images: [(NSImage?, Double)] = []
        for g in resolved.groups where !g.hidden {
            for l in g.layers where !l.hidden {
                if let name = l.imageName {
                    let assetURL = package.assetURL(name)
                    let img = NSImage(contentsOf: assetURL)
                    images.append((img, l.opacity * g.opacity))
                }
            }
        }
        self.layerImages = images
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds

        let path: NSBezierPath
        if isCircle {
            path = NSBezierPath(ovalIn: rect)
        } else {
            let radius = rect.width * 0.2237
            path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        }

        fillColor.setFill()
        path.fill()

        path.addClip()
        for (img, opacity) in layerImages {
            img?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: CGFloat(opacity))
        }
    }
}

public struct IconComposerDocumentView: View {
    public let url: URL
    @State private var platform: IconPlatform = .iOS
    @State private var appearance: IconAppearance = .light

    public init(url: URL) {
        self.url = url
    }

    public var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.headline)
                Spacer()
                Picker("Platform", selection: $platform) {
                    Text("iOS").tag(IconPlatform.iOS)
                    Text("macOS").tag(IconPlatform.macOS)
                    Text("watchOS").tag(IconPlatform.watchOS)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                Picker("Appearance", selection: $appearance) {
                    Text("Light").tag(IconAppearance.light)
                    Text("Dark").tag(IconAppearance.dark)
                    Text("Tinted").tag(IconAppearance.tinted)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            .padding(.horizontal)

            if let package = try? IconPackage(contentsOf: url) {
                let resolved = package.document.resolved(appearance, platform)
                ZStack {
                    RoundedRectangle(cornerRadius: platform == .watchOS ? 128 : 56, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: 256, height: 256)
                        .shadow(radius: 8)

                    Text("\(package.name)")
                        .foregroundColor(.white)
                        .font(.title2)
                        .bold()
                }
                .frame(height: 300)

                Text("\(resolved.groups.count) Groups · \(resolved.groups.reduce(0) { $0 + $1.layers.count }) Layers")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Unable to preview .icon package")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}
