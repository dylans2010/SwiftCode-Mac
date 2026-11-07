import Foundation
import Observation
import SwiftUI

public struct SourceFileDocument: Identifiable, Sendable, Codable {
    public let id: UUID
    public let url: URL
    public var content: String
    public var isDirty: Bool
    public var lastDiskModificationDate: Date

    public init(id: UUID = UUID(), url: URL, content: String, lastDiskModificationDate: Date = Date()) {
        self.id = id
        self.url = url
        self.content = content
        self.isDirty = false
        self.lastDiskModificationDate = lastDiskModificationDate
    }
}

public struct TokenizedLine: Sendable, Identifiable {
    public var id: Int { lineNumber }
    public let lineNumber: Int
    public let tokens: [Token]

    public init(lineNumber: Int, tokens: [Token] = []) {
        self.lineNumber = lineNumber
        self.tokens = tokens
    }

    public struct Token: Sendable {
        public let text: String
        public let kind: String

        public init(text: String, kind: String = "plain") {
            self.text = text
            self.kind = kind
        }
    }
}

@Observable
@MainActor
public class EditorViewModel {
    public var activeDocument: SourceFileDocument?
    public var openDocuments: [SourceFileDocument] = []
    public var selectedTabID: UUID?
    public var tokenizedLines: [TokenizedLine] = []

    public init() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("com.swiftcode.visualUIEditorUpdate"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let code = notification.userInfo?["code"] as? String
            Task { @MainActor [weak self] in
                guard let self = self, let code = code else { return }
                if let activeDoc = self.activeDocument {
                    if activeDoc.content != code {
                        self.updateContent(code)
                    }
                }
            }
        }
    }

    public func openFile(url: URL) async {
        if let existing = openDocuments.first(where: { $0.url == url }) {
            tokenizedLines = []
            activeDocument = existing
            selectedTabID = existing.id
            await tokenize()
            return
        }

        do {
            tokenizedLines = []
            let isXcodeProj = url.pathExtension == "xcodeproj" || url.lastPathComponent == "project.pbxproj"
            let content: String
            if isXcodeProj {
                content = ""
            } else {
                content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            }
            let doc = SourceFileDocument(url: url, content: content, lastDiskModificationDate: Date())
            openDocuments.append(doc)
            activeDocument = doc
            selectedTabID = doc.id
            await tokenize()
        }
    }

    public func saveActiveDocument() async {
        guard let doc = activeDocument else { return }
        do {
            try doc.content.write(to: doc.url, atomically: true, encoding: .utf8)
            if let index = openDocuments.firstIndex(where: { $0.id == doc.id }) {
                openDocuments[index].isDirty = false
            }
            activeDocument?.isDirty = false
        } catch {}
    }

    public func updateContent(_ content: String) {
        activeDocument?.content = content
        activeDocument?.isDirty = true

        Task {
            await tokenize()
        }

        if content.contains("@SwiftCodeVisualUIBuilderDocument") {
            NotificationCenter.default.post(
                name: NSNotification.Name("com.swiftcode.visualUIBuilderSync"),
                object: nil,
                userInfo: ["code": content]
            )
        }
    }

    private func tokenize() async {
    }

    public func updateActiveConfigurationURLs(for project: Any? = nil) async {
    }
}
