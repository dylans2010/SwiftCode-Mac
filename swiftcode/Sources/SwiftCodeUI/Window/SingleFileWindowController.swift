import AppKit
import SwiftCodeIDECore

/// A source or resource file opened from outside SwiftCode (Finder, `open`, a
/// Dock drop) that no open workspace contains: it gets a window of its own
/// with the editor only (`specs/ide/reference-ui-6.md` §1.2.2, W3). A file
/// that an open workspace contains opens in that workspace's window
/// instead (`SwiftCodeDocumentController`).
@MainActor
public final class SourceFileDocument: NSDocument, Identifiable {
    public static let typeName = "org.swiftcode.source-file"

    public override class var autosavesInPlace: Bool { false }

    /// Editor-model state (W-V2 decision 2): `EditorViewModel`
    /// (SwiftCodeEditorKit) and `DocumentCoordinator` (SwiftCodeIDECore) use
    /// documents as values with a URL, in-memory text, dirty flag and
    /// last-known disk date — the Legacy `SourceFileDocument` struct's shape —
    /// while this class is the `NSDocument` the document machinery opens.
    /// These members bridge the two. `url` reads through to `fileURL`, so
    /// there is one source of truth and a save-as/move cannot desync them;
    /// it is read-only because changing files rebuilds the document instead
    /// (see `EditorViewModel.updateActiveConfigurationURLs`). All stored
    /// members carry defaults so the inherited `NSDocument` initializers
    /// (notably `init(contentsOf:ofType:)`, used by the window-identity
    /// tests) keep working. The fallback URL below is only reachable for a
    /// document created via bare `init()` and never given a file; no call
    /// site does that.
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

    /// The window controller, once made.
    public var fileWindowController: SingleFileWindowController? { windowControllers.first as? SingleFileWindowController }

    nonisolated public override func read(from url: URL, ofType typeName: String) throws {
        // The editor reads the file itself; this only checks that it is
        // text the editor can show, so a binary file fails here with the
        // document machinery's own error instead of an empty window.
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

    /// ⌘S writes the editor's text (the editor owns the file's contents).
    public override func save(_ sender: Any?) { try? fileWindowController?.editor.save() }

    /// Edits are written when the window closes, as in a workspace window,
    /// so closing never asks.
    public override var isDocumentEdited: Bool { false }
}

/// The single-file window: one source editor (jump bar, gutter, text).
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
        // The name as the navigator shows it (Settings ▸ General ▸ File Extensions).
        let name = url.lastPathComponent, bare = (name as NSString).deletingPathExtension
        editor.pathComponents = [(Preferences.shared.fileExtensions == .hide && !bare.isEmpty ? bare : name, "doc.text")]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// The title is the file's name (there is no workspace).
    public override func windowTitle(forDocumentDisplayName displayName: String) -> String { url.lastPathComponent }

    public func windowWillClose(_ notification: Notification) { try? editor.save() }
}
