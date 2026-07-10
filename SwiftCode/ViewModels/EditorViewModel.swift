import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
public class EditorViewModel {
    public var activeDocument: SourceFileDocument?
    public var openDocuments: [SourceFileDocument] = []
    public var selectedTabID: UUID?
    public var tokenizedLines: [TokenizedLine] = []

    public init() {}

    public func openFile(url: URL) async {
        if let existing = openDocuments.first(where: { $0.url == url }) {
            // SAFETY: Clear tokens before switching document to avoid stale highlighting
            tokenizedLines = []
            activeDocument = existing
            selectedTabID = existing.id
            await tokenize()
            return
        }

        do {
            tokenizedLines = []
            let content = try await TextBufferEngine.shared.load(url: url)
            let doc = SourceFileDocument(url: url, content: content, lastDiskModificationDate: Date())
            openDocuments.append(doc)
            activeDocument = doc
            selectedTabID = doc.id
            await tokenize()
        } catch {
            LoggingTool.error("Failed to open file: \(error)")
        }
    }

    public func saveActiveDocument() async {
        guard let doc = activeDocument else { return }
        do {
            try await TextBufferEngine.shared.save(content: doc.content, to: doc.url)
            if let index = openDocuments.firstIndex(where: { $0.id == doc.id }) {
                openDocuments[index].isDirty = false
            }
            activeDocument?.isDirty = false
        } catch {
            LoggingTool.error("Failed to save file: \(error)")
        }
    }

    public func updateContent(_ content: String) {
        activeDocument?.content = content
        activeDocument?.isDirty = true
        Task {
            await tokenize()
        }
    }

    private func tokenize() async {
        // Highlighting is now handled asynchronously by CodeRenderEngine directly inside NativeTextView
    }
}
