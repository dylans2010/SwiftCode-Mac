import AppKit
import SwiftCodeIDECore

@MainActor
public final class SourceFileDocument: NSDocument, Identifiable {
    public static let typeName = "org.swiftcode.source-file"

    public override class var autosavesInPlace: Bool { false }

    public let id = UUID()
    public var url: URL { fileURL ?? URL(fileURLWithPath: "") }
    public var content = ""
    public var isDirty = false
    public var lastDiskModificationDate = Date()

    public convenience init(url: URL, content: String, lastDiskModificationDate: Date) {
        self.init()
        self.fileURL = url
        self.content = content
        self.lastDiskModificationDate = lastDiskModificationDate
    }

    public var fileWindowController: SingleFileWindowController? { windowControllers.first as? SingleFileWindowController }

    nonisolated public override func read(from url: URL, ofType typeName: String) throws {
        let data = try Data(contentsOf: url)
        guard String(data: data, encoding: .utf8) != nil else {
            throw CocoaError(.fileReadInapplicableStringEncoding, userInfo: [NSFilePathErrorKey: url.path])
        }
    }

    public override func makeWindowControllers() {
        guard let url = fileURL else { return }
        let wc = SingleFileWindowController(url: url)
        addWindowController(wc)
        wc.window?.center()
    }

    public override func save(_ sender: Any?) { try? fileWindowController?.editor.save() }

    public override var isDocumentEdited: Bool { false }
}

@MainActor
public final class SingleFileWindowController: NSWindowController, NSWindowDelegate {
    public static let defaultSize = NSSize(width: 900, height: 700)
    public let editor = SourceEditorController()
    public let url: URL

    public init(url: URL) {
        self.url = url
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.defaultSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = url.lastPathComponent
        window.minSize = NSSize(width: 400, height: 300)
        window.isRestorable = false
        super.init(window: window)
        window.delegate = self
        window.contentViewController = editor
        window.setContentSize(Self.defaultSize)
        try? editor.open(url)
        let name = url.lastPathComponent, bare = (name as NSString).deletingPathExtension
        editor.pathComponents = [(Preferences.shared.fileExtensions == .hide && !bare.isEmpty ? bare : name, "doc.text")]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override func windowTitle(forDocumentDisplayName displayName: String) -> String { url.lastPathComponent }

    public func windowWillClose(_ notification: Notification) { try? editor.save() }
}
