import AppKit
import YcodeAssistant
import YcodeIDECore

@MainActor
public final class NewConversationPromptController: NSViewController, NSTextViewDelegate {
    public static let size = NSSize(width: 342, height: 146)
    public static let hintInterval: TimeInterval = 4

    public let model: CodingAssistantModel
    public let promptView = ComposerTextView()
    public let attachButton = NSPopUpButton(frame: .zero, pullsDown: true)
    public let optionsButton = NSPopUpButton(frame: .zero, pullsDown: true)
    public let sendButton = NSButton()
    let attachedLabel = NSTextField(labelWithString: "")
    public var attachmentSource: (() -> (file: Attachment?, selection: Attachment?))?
    public var onSend: ((String, [Attachment]) -> Void)?
    public var onCancel: (() -> Void)?
    public var onOpenSettings: (() -> Void)?
    public private(set) var pendingAttachments: [Attachment] = []
    public private(set) var hintIndex = 0
    private var timer: Timer?

    public init(model: CodingAssistantModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public var hints: [String] {
        ["New conversation with \(model.providerKind.displayName)",
         "Ask about the current file",
         "Describe a change to propose",
         "Select code, then ask what it does"]
    }

    public var placeholder: String { promptView.placeholder }

    public override func loadView() {
        let root = NSView(frame: NSRect(origin: .zero, size: Self.size))
        promptView.isRichText = false
        promptView.font = .systemFont(ofSize: NSFont.systemFontSize)
        promptView.delegate = self
        promptView.drawsBackground = false
        promptView.onSubmit = { [weak self] in self?.send() }
        promptView.onCancel = { [weak self] in self?.onCancel?() }
        promptView.setAccessibilityLabel("Prompt")
        promptView.textContainerInset = NSSize(width: 2, height: 4)
        promptView.isVerticallyResizable = true
        promptView.autoresizingMask = [.width]
        promptView.textContainer?.widthTracksTextView = true
        let scroll = NSScrollView()
        scroll.documentView = promptView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true

        AttachMenu.configure(attachButton, target: self, action: #selector(attachChosen(_:)))
        optionsButton.isBordered = false
        (optionsButton.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        optionsButton.toolTip = "Model and options"
        optionsButton.setAccessibilityLabel("Options")
        attachedLabel.font = .systemFont(ofSize: 10)
        attachedLabel.textColor = .secondaryLabelColor
        attachedLabel.lineBreakMode = .byTruncatingMiddle
        attachedLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        sendButton.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: "Send")
        sendButton.isBordered = false
        sendButton.imageScaling = .scaleProportionallyUpOrDown
        sendButton.target = self
        sendButton.action = #selector(send)
        sendButton.toolTip = "Start the conversation (Return)"
        sendButton.setAccessibilityLabel("Send")
        let bottom = NSStackView(views: [attachButton, optionsButton, attachedLabel, NSView(), sendButton])
        bottom.orientation = .horizontal
        bottom.spacing = 6
        for v in [scroll, bottom] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: Self.size.width),
            root.heightAnchor.constraint(equalToConstant: Self.size.height),
            scroll.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            bottom.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 6),
            bottom.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            bottom.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            bottom.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
            sendButton.widthAnchor.constraint(equalToConstant: 24),
            sendButton.heightAnchor.constraint(equalToConstant: 24),
        ])
        view = root
        model.observe(owner: self) { [weak self] change in
            if change == .status { self?.reloadOptions(); self?.showHint() }
        }
        reloadOptions()
        showHint()
        updateSendButton()
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(promptView)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.hintInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceHint() }
        }
    }

    public override func viewWillDisappear() {
        super.viewWillDisappear()
        timer?.invalidate()
        timer = nil
    }

    public func advanceHint() {
        hintIndex = (hintIndex + 1) % hints.count
        showHint()
    }

    func showHint() {
        promptView.placeholder = hints[hintIndex % hints.count]
    }

    func reloadOptions() {
        optionsButton.menu = ProviderMenu.build(model, target: self, choose: #selector(choose(_:)), checkAgain: #selector(checkAgain),
                                                settings: #selector(openSettings), title: "",
                                                image: NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Options"))
    }

    @objc func choose(_ item: NSMenuItem) {
        guard let c = item.representedObject as? ProviderMenu.Choice else { return }
        model.choose(c.kind, model: c.model)
    }

    @objc func checkAgain() { model.refreshAvailability() }
    @objc func openSettings() { onOpenSettings?() }

    public func textDidChange(_ notification: Notification) { updateSendButton() }

    func updateSendButton() {
        sendButton.isEnabled = !promptView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func setPrompt(_ s: String) {
        promptView.string = s
        updateSendButton()
        promptView.needsDisplay = true
    }

    @objc public func send() {
        let text = promptView.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return NSSound.beep() }
        onSend?(text, pendingAttachments)
    }

    @objc func attachChosen(_ sender: NSPopUpButton) {
        guard let src = attachmentSource?() else { return }
        guard let a = sender.indexOfSelectedItem == 1 ? src.file : src.selection else { NSSound.beep(); return }
        attach(a)
    }

    public func attach(_ a: Attachment) {
        guard !pendingAttachments.contains(a) else { return }
        pendingAttachments.append(a)
        attachedLabel.stringValue = pendingAttachments.map(\.label).joined(separator: ", ")
        attachedLabel.toolTip = attachedLabel.stringValue
    }
}
