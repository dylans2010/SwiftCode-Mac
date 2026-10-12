import Foundation

// MARK: - SDKCodeDocument
//
// An open document in the Studio code editor. A VALUE TYPE: editing
// produces new values (see `withText(_:)` / `saved()`); the mutable editor
// state (`SDKCodeEditorState`) owns the collection and publishes changes.
//
// `fileURL` is `nil` for untitled documents (e.g. a scratch buffer the
// user has not saved yet). `isDirty` means the in-memory `text` differs
// from what is on disk (or that an untitled document has content).

public struct SDKCodeDocument: Identifiable, Sendable, Hashable {
    public let id: UUID

    /// File backing this document, or `nil` for an untitled buffer.
    public let fileURL: URL?

    public let language: SDKCodeLanguage

    public let text: String

    /// `true` when the buffer differs from the last saved/disk state.
    public let isDirty: Bool

    /// Optional caret position as a UTF-16 code-unit offset into `text`,
    /// restored when a document is re-activated. `nil` means "no hint —
    /// place the caret at the start". Cheap to capture and restore; never
    /// treated as authoritative across text mutations.
    public let cursorOffset: Int?

    public init(
        id: UUID = UUID(),
        fileURL: URL?,
        language: SDKCodeLanguage,
        text: String,
        isDirty: Bool = false,
        cursorOffset: Int? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.language = language
        self.text = text
        self.isDirty = isDirty
        self.cursorOffset = cursorOffset
    }

    /// Display name for tabs and titles: the filename, or "Untitled".
    public var displayName: String {
        guard let fileURL else { return "Untitled" }
        let name = fileURL.lastPathComponent
        return name.isEmpty ? "Untitled" : name
    }

    /// Returns a copy with new text and `isDirty` set to `true`.
    /// The standard way to apply an edit.
    public func withText(_ newText: String) -> SDKCodeDocument {
        SDKCodeDocument(
            id: id,
            fileURL: fileURL,
            language: language,
            text: newText,
            isDirty: true,
            cursorOffset: cursorOffset
        )
    }

    /// Returns a copy with the dirty flag cleared (after a successful save).
    public func saved() -> SDKCodeDocument {
        SDKCodeDocument(
            id: id,
            fileURL: fileURL,
            language: language,
            text: text,
            isDirty: false,
            cursorOffset: cursorOffset
        )
    }
}

// MARK: - SDKCodeEditorTab
//
// One open document in the editor's tab bar. Tabs are value types owned by
// `SDKCodeEditorState`; `isActive` is derived from
// `SDKCodeEditorState.activeTabID`, not set independently — activate via
// the state's `activateTab(_:)`.

public struct SDKCodeEditorTab: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let document: SDKCodeDocument
    public let isActive: Bool

    public init(id: UUID = UUID(), document: SDKCodeDocument, isActive: Bool = false) {
        self.id = id
        self.document = document
        self.isActive = isActive
    }

    /// Returns a copy bound to a different document (same tab identity).
    public func withDocument(_ newDocument: SDKCodeDocument) -> SDKCodeEditorTab {
        SDKCodeEditorTab(id: id, document: newDocument, isActive: isActive)
    }

    /// Returns a copy with the given active state.
    public func withActive(_ active: Bool) -> SDKCodeEditorTab {
        SDKCodeEditorTab(id: id, document: document, isActive: active)
    }
}
