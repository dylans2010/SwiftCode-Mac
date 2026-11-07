import Foundation
import Testing
@testable import YcodeIDEShell

@MainActor
struct PersonalDocumentationTests {
    private func makeStore() -> PersonalDocStore {
        PersonalDocStore(projectID: UUID(), projectURL: FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-personaldocs-\(UUID().uuidString)"))
    }

    @Test func createFetchUpdateDelete() {
        let store = makeStore()
        let doc = store.createDocument(title: "Hello", kind: .meetingNotes, markdown: "Body text here.")
        #expect(store.fetchDocument(id: doc.id)?.title == "Hello")
        #expect(store.fetchDocuments(for: .meetingNotes).count == 1)
        var updated = doc
        updated.title = "Hello again"
        store.updateDocument(updated)
        #expect(store.fetchDocument(id: doc.id)?.title == "Hello again")
        store.deleteDocument(updated)
        #expect(store.fetchDocument(id: doc.id) == nil)
    }

    @Test func searchFindsTitleAndBody() {
        let store = makeStore()
        _ = store.createDocument(title: "Sourdough", kind: .learningNotes, markdown: "The starter needs feeding every day.")
        _ = store.createDocument(title: "Unrelated", kind: .scratchpad, markdown: "Nothing to see here.")
        let results = store.search(query: "sourdough")
        #expect(results.count == 1)
        #expect(results.first?.document.title == "Sourdough")
        #expect(store.search(query: "starter").count == 1)
        #expect(store.search(query: "zzzznope").isEmpty)
    }

    @Test func updateRecordsVersionHistory() {
        let store = makeStore()
        let doc = store.createDocument(title: "V1", kind: .dailyNotes, markdown: "first")
        var updated = doc
        updated.markdownSource = "second"
        store.updateDocument(updated)
        let versions = store.fetchVersions(for: doc.id)
        #expect(versions.count == 1)
        #expect(versions.first?.markdownSnapshot == "first")
    }

    @Test func defaultTemplatesSeeded() {
        let store = makeStore()
        #expect(!store.templates.isEmpty)
        #expect(store.fetchTemplates(for: .meetingNotes).contains { $0.title == "Meeting Notes" })
        #expect(store.fetchTemplates(for: .bugDatabase).contains { $0.title == "Bug Report" })
    }

    @Test func dailyNoteIsStablePerDay() {
        let store = makeStore()
        let first = try? store.getOrCreateDailyNote(for: Date(timeIntervalSince1970: 1_700_000_000))
        let second = try? store.getOrCreateDailyNote(for: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(first?.id == second?.id)
    }

    @Test func exportImportRoundTrip() throws {
        let store = makeStore()
        let doc = store.createDocument(title: "Export Me", kind: .technicalSpecification, markdown: "Some content.")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-personaldocs-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let mdURL = dir.appendingPathComponent("doc.md")
        try store.exportToMarkdown(document: doc, destinationURL: mdURL)
        let (title, content) = try store.importMarkdown(from: mdURL)
        #expect(title == "Export Me")
        #expect(content.contains("Some content."))
        let htmlURL = dir.appendingPathComponent("doc.html")
        try store.exportToHTML(document: doc, destinationURL: htmlURL)
        let html = try String(contentsOf: htmlURL, encoding: .utf8)
        #expect(html.contains("<h1>Export Me</h1>"))
    }

    @Test func localAnalyzerSummarizes() {
        let store = makeStore()
        _ = store.createDocument(title: "A", kind: .learningNotes, markdown: "Swift concurrency uses actors to protect mutable state. Actors serialize access.")
        _ = store.createDocument(title: "B", kind: .learningNotes, markdown: "SwiftUI views are a function of state. State changes re-render the view.")
        let summary = PersonalDocLocalAnalyzer.summarize(documents: store.documents)
        #expect(summary.contains("Local summary"))
        let missing = PersonalDocLocalAnalyzer.missingDocumentation(documents: store.documents)
        #expect(missing.contains("Bug Database"))
    }

    @Test func analyzeWithoutProviderUsesLocalAnalysis() async throws {
        let store = makeStore()
        _ = store.createDocument(title: "A", kind: .learningNotes, markdown: "Swift concurrency uses actors to protect mutable state.")
        let report = try await store.analyze(kind: .missingDocs)
        #expect(report.contains("Bug Database"))
    }

    @Test func snapshotRestoreArchivesMissingDocuments() {
        let store = makeStore()
        let kept = store.createDocument(title: "Kept", kind: .scratchpad)
        _ = store.createDocument(title: "Dropped", kind: .scratchpad)
        let snapshot = store.createSnapshot(title: "S", description: "")
        var dropped = store.fetchDocuments(for: .scratchpad).first { $0.title == "Dropped" }!
        dropped.archived = true
        store.updateDocument(dropped)
        _ = snapshot
        _ = kept
        let partial = PersonalDocSnapshot(projectID: store.projectID, title: "Partial", description: "", documentIDs: [kept.id])
        store.restoreSnapshot(partial)
        #expect(store.fetchDocument(id: kept.id)?.archived == false)
        #expect(store.fetchDocument(id: dropped.id)?.archived == true)
    }
}
