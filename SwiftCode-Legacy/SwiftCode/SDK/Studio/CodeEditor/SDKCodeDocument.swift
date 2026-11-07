import Foundation

public struct SDKCodeDocument: Identifiable, Sendable, Hashable {
    public let id: UUID

    public let fileURL: URL?

    public let language: SDKCodeLanguage

    public let text: String

    public let isDirty: Bool

    public let cursorOffset: Int?

    public let lastKnownModificationDate: Date?

    public let hasExternalModification: Bool

    public init(
        id: UUID = UUID(),
        fileURL: URL?,
        language: SDKCodeLanguage,
        text: String,
        isDirty: Bool = false,
        cursorOffset: Int? = nil,
        lastKnownModificationDate: Date? = nil,
        hasExternalModification: Bool = false
    ) {
        self.id = id
        self.fileURL = fileURL
        self.language = language
        self.text = text
        self.isDirty = isDirty
        self.cursorOffset = cursorOffset
        self.lastKnownModificationDate = lastKnownModificationDate
        self.hasExternalModification = hasExternalModification
    }

    public var displayName: String {
        guard let fileURL else { return "Untitled.ts" }
        let name = fileURL.lastPathComponent
        return name.isEmpty ? "Untitled.ts" : name
    }

    public func withText(_ newText: String, cursorOffset: Int? = nil) -> SDKCodeDocument {
        SDKCodeDocument(
            id: id,
            fileURL: fileURL,
            language: language,
            text: newText,
            isDirty: true,
            cursorOffset: cursorOffset ?? self.cursorOffset,
            lastKnownModificationDate: lastKnownModificationDate,
            hasExternalModification: hasExternalModification
        )
    }

    public func saved(
        fileURL newURL: URL? = nil,
        modificationDate: Date? = nil
    ) -> SDKCodeDocument {
        let resolvedURL = newURL ?? fileURL
        let resolvedLang = resolvedURL.map { SDKCodeLanguage.infer(fromFileURL: $0) } ?? language
        return SDKCodeDocument(
            id: id,
            fileURL: resolvedURL,
            language: resolvedLang,
            text: text,
            isDirty: false,
            cursorOffset: cursorOffset,
            lastKnownModificationDate: modificationDate ?? lastKnownModificationDate,
            hasExternalModification: false
        )
    }

    public func withExternalModification(_ flag: Bool) -> SDKCodeDocument {
        SDKCodeDocument(
            id: id,
            fileURL: fileURL,
            language: language,
            text: text,
            isDirty: isDirty,
            cursorOffset: cursorOffset,
            lastKnownModificationDate: lastKnownModificationDate,
            hasExternalModification: flag
        )
    }
}

public struct SDKCodeEditorTab: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let document: SDKCodeDocument
    public let isActive: Bool

    public init(id: UUID = UUID(), document: SDKCodeDocument, isActive: Bool = false) {
        self.id = id
        self.document = document
        self.isActive = isActive
    }

    public func withDocument(_ newDocument: SDKCodeDocument) -> SDKCodeEditorTab {
        SDKCodeEditorTab(id: id, document: newDocument, isActive: isActive)
    }

    public func withActive(_ active: Bool) -> SDKCodeEditorTab {
        SDKCodeEditorTab(id: id, document: document, isActive: active)
    }
}
