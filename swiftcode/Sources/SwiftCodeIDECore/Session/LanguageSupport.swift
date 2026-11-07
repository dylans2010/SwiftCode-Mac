import Foundation
import SwiftCodeBuild
import SwiftCodeDebug
import SwiftCodeLanguage

extension LineIndex {
    public func position(at offset: Int) -> Position {
        let line = self.line(at: offset)
        return Position(line: line - 1, character: offset - starts[line - 1])
    }

    public func offset(of p: Position) -> Int {
        guard let r = range(ofLine: p.line + 1) else { return length }
        return r.location + min(max(0, p.character), r.length)
    }
}

@MainActor
public final class LanguageService {
    public let client: LSPClient
    private var versions: [URL: Int] = [:]
    private var textHashes: [URL: Int] = [:]
    public private(set) var openTexts: [URL: String] = [:]
    public private(set) var liveIssues: [String: [Diagnostic]] = [:]
    public private(set) var liveDiagnostics: [String: [LSPDiagnostic]] = [:]
    package var onApplyEdit: ((WorkspaceEdit) -> Void)?
    var onIssuesChanged: (() -> Void)?
    var onEdited: ((String) -> Void)?

    public init(transport: DAPTransport, root: URL, initializationOptions: JSON? = nil) async throws {
        client = try LSPClient(transport: transport)
        let notes = client.notifications
        Task { [weak self] in
            for await n in notes {
                if n.method == "workspace/applyEdit" {
                    self?.onApplyEdit?(WorkspaceEdit(n.params["edit"]))
                    continue
                }
                guard n.method == "textDocument/publishDiagnostics", let (url, d) = LSPDiagnostic.published(n.params) else { continue }
                self?.publish(url: url, d)
            }
        }
        try await client.initialize(root: root, initializationOptions: initializationOptions)
    }

    public static func issues(file: String, _ list: [LSPDiagnostic]) -> [Diagnostic] {
        list.compactMap { d in
            let severity: Diagnostic.Severity
            switch d.severity {
            case 1: severity = .error
            case 2: severity = .warning
            default: return nil
            }
            let fixIts = d.fixIts.compactMap(\.edit).flatMap { e in
                e.changes.filter { $0.key.standardizedFileURL.path == file }.flatMap(\.value).map { t in
                    Diagnostic.FixIt(file: file, start: .init(file: file, line: t.start.line + 1, column: t.start.character + 1),
                                     end: .init(file: file, line: t.end.line + 1, column: t.end.character + 1), replacement: t.newText)
                }
            }
            return Diagnostic(severity: severity, message: d.message,
                              location: .init(file: file, line: d.start.line + 1, column: d.start.character + 1), fixIts: fixIts)
        }
    }

    private func publish(url: URL, _ list: [LSPDiagnostic]) {
        let path = url.standardizedFileURL.path
        liveIssues[path] = Self.issues(file: path, list)
        liveDiagnostics[path] = list
        onIssuesChanged?()
    }

    public func open(_ url: URL, text: String) {
        guard versions[url] == nil else { return change(url, text: text) }
        versions[url] = 1
        textHashes[url] = text.hashValue
        openTexts[url] = text
        client.didOpen(url, text: text)
    }

    public func change(_ url: URL, text: String) {
        let v = (versions[url] ?? 0) + 1
        versions[url] = v
        client.didChange(url, text: text, version: v)
        openTexts[url] = text
        let h = text.hashValue
        if textHashes.updateValue(h, forKey: url) != h { onEdited?(url.standardizedFileURL.path) }
    }

    public func saved(_ url: URL) {
        guard versions[url] != nil else { return }
        client.didSave(url)
    }

    public func close(_ url: URL) {
        guard versions.removeValue(forKey: url) != nil else { return }
        textHashes[url] = nil
        openTexts[url] = nil
        client.didClose(url)
    }

    public func fileChangedOnDisk(_ url: URL) {
        client.notify("workspace/didChangeWatchedFiles", ["changes": [["uri": .string(url.absoluteString), "type": 2]]])
    }

    public func stop() async { await client.shutdown() }
}

extension WorkspaceSession {
    var languageRoot: URL {
        model.kind == .package ? model.url : model.url.deletingLastPathComponent()
    }

    public func startLanguageService(transport: DAPTransport? = nil) async {
        let t: DAPTransport
        var root = languageRoot
        languageRestart.context = nil
        let startedContext = languageBuildContext
        var options: JSON?
        if let transport { t = transport } else {
            guard let path = await Task.detached(operation: { SourceKitLSP.locate() }).value else { return }
            t = ProcessTransport(executable: path)
            let (container, scheme, destination) = (model.url, startedContext.scheme, startedContext.destination)
            if let folder = await Task.detached(operation: {
                BuildServerLaunch.prepareWorkspaceFolder(container: container, scheme: scheme, destination: destination)
            }).value {
                (root, options) = (folder, BuildServerLaunch.initializationOptions)
                languageRestart.context = startedContext
            }
        }
        if transport != nil, model.kind != .package, languageRestart.makeTransport != nil { languageRestart.context = startedContext }
        do {
            let service = try await LanguageService(transport: t, root: root, initializationOptions: options)
            service.onIssuesChanged = { [weak self] in self?.languageIssuesChanged() }
            service.onEdited = { [weak self] in self?.noteFileEdited($0) }
            language = service
            buildContextChanged()
        } catch {
            appendConsole("SwiftCode: the language server did not start: \(error)\n")
        }
    }

    public func completions(_ url: URL, at p: Position) async -> [CompletionItem] {
        guard let language else { return [] }
        return (try? await language.client.completion(url, at: p)) ?? []
    }

    public func hover(_ url: URL, at p: Position) async -> String? {
        guard let language else { return nil }
        return try? await language.client.hover(url, at: p)
    }

    public func definition(_ url: URL, at p: Position) async -> Location? {
        guard let language else { return nil }
        return (try? await language.client.definition(url, at: p))?.first
    }

    public func documentHighlights(_ url: URL, at p: Position) async -> [DocumentHighlight] {
        guard let language else { return [] }
        return (try? await language.client.documentHighlights(url, at: p)) ?? []
    }
}
