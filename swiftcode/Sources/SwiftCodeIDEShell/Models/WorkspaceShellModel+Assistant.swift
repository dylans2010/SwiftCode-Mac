import Foundation
import SwiftCodeAssistant
import SwiftCodeEditorKit
import SwiftCodeIDECore

extension WorkspaceShellModel {

    public func showLeftPane(assistant: Bool) {
        if isNavigatorShown && self.assistant.isShown == assistant {
            isNavigatorShown = false
            return
        }
        if assistant { self.assistant.show() } else { self.assistant.isShown = false }
        isNavigatorShown = true
    }

    public var isAssistantPaneShown: Bool { isNavigatorShown && assistant.isShown }

    func isAssistantCommandEnabled(_ c: ShellCommand) -> Bool {
        switch c {
        case .showCodingAssistant, .newConversation: true
        case .jumpToNextActiveConversation: assistant.hasActiveConversations
        default: c.codingTool.map(assistant.canRun) ?? false
        }
    }

    func performAssistantCommand(_ c: ShellCommand) {
        switch c {
        case .showCodingAssistant: showLeftPane(assistant: true)
        case .newConversation: assistant.newConversation()
        case .jumpToNextActiveConversation: assistant.jumpToNextActive()
        default: if let t = c.codingTool { assistant.run(t) }
        }
    }

    public var assistantFolder: URL {
        let url = session.model.url
        return (session.model.kind == .package ? url : url.deletingLastPathComponent()).standardizedFileURL
    }

    func assistantRelativePath(_ path: String) -> String {
        let root = assistantFolder.path.hasSuffix("/") ? assistantFolder.path : assistantFolder.path + "/"
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        return p.hasPrefix(root) ? String(p.dropFirst(root.count)) : p
    }

    public func assistantPath(_ relative: String) -> String? {
        let url = assistantFolder.appendingPathComponent(relative).standardizedFileURL
        let root = assistantFolder.path.hasSuffix("/") ? assistantFolder.path : assistantFolder.path + "/"
        return url.path.hasPrefix(root) ? url.path : nil
    }

    public func assistantCurrentText(_ path: String) -> String? {
        if let d = openDocuments[path] { return d.buffer.text }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }

    public func assistantContext() -> WorkspaceContext {
        var ctx = WorkspaceContext(workspaceName: workspaceName)
        if let e = editor {
            let b = e.buffer
            let path = assistantRelativePath(e.path)
            ctx.currentFile = .init(path: path, text: b.text)
            ctx.caretLine = b.caretLine + 1
            let r = b.selection.range
            if !r.isEmpty {
                let start = b.document.line(containing: r.lowerBound)
                let end = b.document.line(containing: max(r.lowerBound, r.upperBound - 1))
                ctx.selection = .init(path: path, startLine: start + 1, endLine: end + 1, text: b.selectedText,
                                      location: r.lowerBound, length: r.count)
            }
        }
        var seen = Set(ctx.currentFile.map { [$0.path] } ?? [])
        for d in openDocuments.values.sorted(by: { $0.path < $1.path }) where d !== editor {
            let path = assistantRelativePath(d.path)
            if seen.insert(path).inserted { ctx.openFiles.append(.init(path: path, text: d.buffer.text)) }
        }
        ctx.issues = allIssues.prefix(100).map { i in
            WorkspaceContext.Issue(severity: i.severity.rawValue, message: i.message, path: i.file.map(assistantRelativePath), line: i.line)
        }
        return ctx
    }

    func applyAssistantChange(_ diff: AssistantChangeDiff, save: Bool) -> String? {
        let path = diff.path
        if diff.original == nil {
            let url = URL(fileURLWithPath: path)
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try diff.proposed.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                return "SwiftCode could not create \(url.lastPathComponent): \(error.localizedDescription)"
            }
            open(path)
            return nil
        }
        if editor?.path != path { open(path) }
        guard let e = editor, e.path == path else {
            return "\((path as NSString).lastPathComponent) can't be opened as text, so the change was not applied."
        }
        if let why = e.readOnlyReason { return why }
        guard e.buffer.text == diff.original else {
            return "\(e.name) changed since the review; ask again or review the proposal again."
        }
        Self.replaceChangedPart(of: e.buffer, with: diff.proposed)
        if save, !saveCurrent() { return "SwiftCode could not save \(e.name)." }
        return nil
    }

    static func replaceChangedPart(of b: EditorBuffer, with new: String) {
        let old = Array(b.text.utf16), now = Array(new.utf16)
        guard old != now else { return }
        var p = 0
        while p < old.count, p < now.count, old[p] == now[p] { p += 1 }
        var s = 0
        while s < old.count - p, s < now.count - p, old[old.count - 1 - s] == now[now.count - 1 - s] { s += 1 }
        if p > 0, UTF16.isLeadSurrogate(old[p - 1]) { p -= 1 }
        if s > 0, UTF16.isTrailSurrogate(old[old.count - s]) { s -= 1 }
        let range = NSRange(location: p, length: old.count - s - p)
        b.replace(range, with: String(decoding: now[p..<(now.count - s)], as: UTF16.self))
    }
}

extension ShellCommand {
    static let assistantActions: [ShellCommand: (selector: String, menu: String)] = [
        .showCodingAssistant: ("showCodingAssistant:", "View"),
        .newConversation: ("newConversation:", "File"),
        .jumpToNextActiveConversation: ("jumpToNextActiveConversation:", "Navigate"),
        .codingToolExplain: ("codingToolExplain:", "Editor"),
        .codingToolDocument: ("codingToolDocument:", "Editor"),
        .codingToolGeneratePlayground: ("codingToolGeneratePlayground:", "Editor"),
        .codingToolGeneratePreview: ("codingToolGeneratePreview:", "Editor"),
    ]

    public var isAssistant: Bool { Self.assistantActions[self] != nil }

    public var codingTool: CodingTool? {
        switch self {
        case .codingToolExplain: .explain
        case .codingToolDocument: .document
        case .codingToolGeneratePlayground: .generatePlayground
        case .codingToolGeneratePreview: .generatePreview
        default: nil
        }
    }
}
