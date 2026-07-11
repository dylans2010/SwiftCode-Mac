import SwiftUI
import AppKit

struct BuildStatusView: View {
    let project: Project
    let owner: String
    let repo: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Native AppKit Build Status Container
            AppKitBuildStatusViewContainer(project: project, owner: owner, repo: repo)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 750, height: 650)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - AppKit Build Status Container

struct AppKitBuildStatusViewContainer: NSViewRepresentable {
    let project: Project
    let owner: String
    let repo: String

    func makeNSView(context: Context) -> NSView {
        let mainView = NSView()
        mainView.wantsLayer = true
        mainView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // Layout stack
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 16
        stackView.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        mainView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: mainView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: mainView.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: mainView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: mainView.trailingAnchor)
        ])

        // Add Section 1: Connection Hub Box
        let connectionBox = createConnectionBox()
        stackView.addArrangedSubview(connectionBox)

        // Add Section 2: Preparation Box
        let preparationBox = createPreparationBox()
        stackView.addArrangedSubview(preparationBox)

        // Add Section 3: Build Execution Box
        let executionBox = createExecutionBox()
        stackView.addArrangedSubview(executionBox)

        // Add Section 4: Live Logs & Guide Box
        let logsAndGuideBox = createLogsAndGuideBox()
        stackView.addArrangedSubview(logsAndGuideBox)

        return mainView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // AppKit updates managed natively
    }

    // MARK: - AppKit Component Builders

    private func createConnectionBox() -> NSBox {
        let box = NSBox()
        box.title = "Step 1: Repository Connection"
        box.boxType = .primary
        box.borderType = .lineBorder
        box.borderColor = NSColor.systemGreen.withAlphaComponent(0.4)
        box.translatesAutoresizingMaskIntoConstraints = false

        let innerStack = NSStackView()
        innerStack.orientation = .horizontal
        innerStack.spacing = 12
        innerStack.translatesAutoresizingMaskIntoConstraints = false

        let iconImageView = NSImageView(image: NSImage(systemSymbolName: "link.circle.fill", accessibilityDescription: "Link") ?? NSImage())
        iconImageView.contentTintColor = NSColor.systemGreen
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.widthAnchor.constraint(equalToConstant: 24).isActive = true
        iconImageView.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let repoLabel = NSTextField(labelWithString: owner.isEmpty ? "No active repository" : "\(owner)/\(repo)")
        repoLabel.font = NSFont.boldSystemFont(ofSize: 13)
        repoLabel.textColor = NSColor.labelColor

        let statusLabel = NSTextField(labelWithString: owner.isEmpty ? "Repository connection required" : "Connected and active")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = NSColor.secondaryLabelColor

        textStack.addArrangedSubview(repoLabel)
        textStack.addArrangedSubview(statusLabel)

        innerStack.addArrangedSubview(iconImageView)
        innerStack.addArrangedSubview(textStack)

        box.contentView = innerStack

        NSLayoutConstraint.activate([
            innerStack.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            innerStack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
            innerStack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            innerStack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12)
        ])

        return box
    }

    private func createPreparationBox() -> NSBox {
        let box = NSBox()
        box.title = "Step 2: Asset Preparation"
        box.translatesAutoresizingMaskIntoConstraints = false

        let innerStack = NSStackView()
        innerStack.orientation = .vertical
        innerStack.alignment = .leading
        innerStack.spacing = 8
        innerStack.translatesAutoresizingMaskIntoConstraints = false

        let descriptionLabel = NSTextField(labelWithString: "Scaffold visual assets, configure bundle structures, and synchronize provisioning headers recursively.")
        descriptionLabel.font = NSFont.systemFont(ofSize: 11)
        descriptionLabel.textColor = NSColor.secondaryLabelColor
        descriptionLabel.cell?.wraps = true

        let prepareButton = NSButton(title: "Prepare Compiling Assets", target: nil, action: nil)
        prepareButton.bezelStyle = .rounded
        prepareButton.translatesAutoresizingMaskIntoConstraints = false

        innerStack.addArrangedSubview(descriptionLabel)
        innerStack.addArrangedSubview(prepareButton)

        box.contentView = innerStack

        NSLayoutConstraint.activate([
            innerStack.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            innerStack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
            innerStack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            innerStack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12)
        ])

        return box
    }

    private func createExecutionBox() -> NSBox {
        let box = NSBox()
        box.title = "Step 3: Build Execution"
        box.translatesAutoresizingMaskIntoConstraints = false

        let innerStack = NSStackView()
        innerStack.orientation = .vertical
        innerStack.alignment = .leading
        innerStack.spacing = 8
        innerStack.translatesAutoresizingMaskIntoConstraints = false

        let statusTextStack = NSStackView()
        statusTextStack.orientation = .horizontal
        statusTextStack.spacing = 6

        let statusIndicator = NSProgressIndicator()
        statusIndicator.style = .spinning
        statusIndicator.isIndeterminate = true
        statusIndicator.controlSize = .small
        statusIndicator.translatesAutoresizingMaskIntoConstraints = false
        statusIndicator.widthAnchor.constraint(equalToConstant: 16).isActive = true
        statusIndicator.heightAnchor.constraint(equalToConstant: 16).isActive = true
        statusIndicator.startAnimation(nil)

        let statusTextLabel = NSTextField(labelWithString: "Ready to launch build...")
        statusTextLabel.font = NSFont.systemFont(ofSize: 11)
        statusTextLabel.textColor = NSColor.secondaryLabelColor

        statusTextStack.addArrangedSubview(statusIndicator)
        statusTextStack.addArrangedSubview(statusTextLabel)

        let actionButtonStack = NSStackView()
        actionButtonStack.orientation = .horizontal
        actionButtonStack.spacing = 8

        let compileButton = NSButton(title: "Compile (xcodebuild)", target: nil, action: nil)
        compileButton.bezelStyle = .rounded
        compileButton.keyEquivalent = "\r" // Enter key equivalent

        let cancelBuildButton = NSButton(title: "Cancel Active Build", target: nil, action: nil)
        cancelBuildButton.bezelStyle = .rounded
        cancelBuildButton.contentTintColor = NSColor.systemRed

        actionButtonStack.addArrangedSubview(compileButton)
        actionButtonStack.addArrangedSubview(cancelBuildButton)

        innerStack.addArrangedSubview(statusTextStack)
        innerStack.addArrangedSubview(actionButtonStack)

        box.contentView = innerStack

        NSLayoutConstraint.activate([
            innerStack.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            innerStack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
            innerStack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            innerStack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12)
        ])

        return box
    }

    private func createLogsAndGuideBox() -> NSBox {
        let box = NSBox()
        box.title = "Step 4: Monitoring & Output Guides"
        box.translatesAutoresizingMaskIntoConstraints = false

        let innerStack = NSStackView()
        innerStack.orientation = .vertical
        innerStack.alignment = .leading
        innerStack.spacing = 8
        innerStack.translatesAutoresizingMaskIntoConstraints = false

        let infoLabel = NSTextField(labelWithString: "Continuous build updates will be routed directly to the Xcode Build Center. Double-click failures to instantly trace diagnostic offsets.")
        infoLabel.font = NSFont.systemFont(ofSize: 11)
        infoLabel.textColor = NSColor.secondaryLabelColor
        infoLabel.cell?.wraps = true

        let localScanLabel = NSTextField(labelWithString: "Local network scan is fully active in background.")
        localScanLabel.font = NSFont.systemFont(ofSize: 10)
        localScanLabel.textColor = NSColor.systemOrange

        innerStack.addArrangedSubview(infoLabel)
        innerStack.addArrangedSubview(localScanLabel)

        box.contentView = innerStack

        NSLayoutConstraint.activate([
            innerStack.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            innerStack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
            innerStack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            innerStack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12)
        ])

        return box
    }
}
