import Foundation
import Observation
import YcodeExtensions
import YcodeSDK
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - SDKCodeLanguage
//
// Legacy: `SwiftCode/SDK/Studio/CodeEditor/SDKCodeLanguage.swift`.
// Six languages, conservative inference (unknown extension → `.plaintext`,
// never a guess), stable raw values. Ycode's `SyntaxLanguage` is the full
// IDE lexer language set; this enum is the Studio editor's smaller contract
// (its cases map 1:1 onto `SyntaxLanguage.swift/.json/.markdown/.plain` plus
// TypeScript/JavaScript, which `SyntaxLanguage` does not model — the Studio
// highlighter below covers those two).

public enum SDKCodeLanguage: String, Sendable, Codable, CaseIterable, Hashable {
    case swift
    case typescript
    case javascript
    case json
    case markdown
    case plaintext

    public var displayName: String {
        switch self {
        case .swift: return "Swift"
        case .typescript: return "TypeScript"
        case .javascript: return "JavaScript"
        case .json: return "JSON"
        case .markdown: return "Markdown"
        case .plaintext: return "Plain Text"
        }
    }

    public var fileExtensions: [String] {
        switch self {
        case .swift: return ["swift"]
        case .typescript: return ["ts", "tsx", "mts", "cts"]
        case .javascript: return ["js", "jsx", "mjs", "cjs"]
        case .json: return ["json"]
        case .markdown: return ["md", "markdown"]
        case .plaintext: return ["txt"]
        }
    }

    public static func infer(fromFileExtension ext: String) -> SDKCodeLanguage {
        var normalized = ext.lowercased()
        if normalized.hasPrefix(".") { normalized.removeFirst() }
        guard !normalized.isEmpty else { return .plaintext }
        for language in SDKCodeLanguage.allCases where language.fileExtensions.contains(normalized) {
            return language
        }
        return .plaintext
    }

    public static func infer(fromFileURL url: URL) -> SDKCodeLanguage {
        infer(fromFileExtension: url.pathExtension)
    }
}

// MARK: - SDK syntax highlighting
//
// Legacy: `SwiftCode/SDK/Studio/CodeEditor/SDKSyntaxHighlighter.swift` +
// `SDKKeywordHighlighter.swift` (919 lines). The token contract is ported
// verbatim (UTF-16 half-open ranges, six kinds, non-overlapping, total
// function). The scanner itself is a compact single-pass implementation:
// Ycode's full lexers (`YcodeSyntax`: `SwiftClassifier`, `SwiftLineLexer`,
// `CFamilyLexer`) already serve the main IDE editor, so the Studio adapter
// only needs the Studio token shape — keywords, strings, comments
// (including nested Swift `/* */`), numbers, and capitalized type names —
// for the six Studio languages. It is not a second editor lexer.

public enum SDKTokenKind: String, Sendable, Codable, CaseIterable, Hashable {
    case keyword
    case string
    case comment
    case number
    case typeName
    case plain
}

public struct SDKToken: Sendable, Hashable {
    public let range: Range<Int>
    public let kind: SDKTokenKind

    public init(range: Range<Int>, kind: SDKTokenKind) {
        self.range = range
        self.kind = kind
    }

    public var length: Int { range.upperBound - range.lowerBound }
}

public protocol SDKSyntaxHighlighter: Sendable {
    func highlight(_ text: String, language: SDKCodeLanguage) -> [SDKToken]
}

public struct SDKKeywordHighlighter: SDKSyntaxHighlighter {
    public init() {}

    public func highlight(_ text: String, language: SDKCodeLanguage) -> [SDKToken] {
        guard !text.isEmpty else { return [] }
        let utf16 = Array(text.utf16)
        var tokens: [SDKToken] = []
        var i = 0
        let keywords: Set<String> = {
            switch language {
            case .swift: return Self.swiftKeywords
            case .typescript, .javascript: return Self.typeScriptKeywords
            case .json: return ["true", "false", "null"]
            case .markdown, .plaintext: return []
            }
        }()
        func isIdentStart(_ c: UInt16) -> Bool {
            (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c >= 128
        }
        func isIdent(_ c: UInt16) -> Bool { isIdentStart(c) || (c >= 48 && c <= 57) }
        func isDigit(_ c: UInt16) -> Bool { c >= 48 && c <= 57 }
        while i < utf16.count {
            let c = utf16[i]
            // Line comment.
            if c == 47, i + 1 < utf16.count, utf16[i + 1] == 47, language != .json {
                var j = i + 2
                while j < utf16.count, utf16[j] != 10 { j += 1 }
                tokens.append(SDKToken(range: i..<j, kind: .comment))
                i = j
                continue
            }
            // Block comment, nested for Swift.
            if c == 47, i + 1 < utf16.count, utf16[i + 1] == 42, language != .json {
                var j = i + 2
                var depth = 1
                while j + 1 < utf16.count, depth > 0 {
                    if utf16[j] == 47, utf16[j + 1] == 42 { depth += 1; j += 2 }
                    else if utf16[j] == 42, utf16[j + 1] == 47 { depth -= 1; j += 2 }
                    else { j += 1 }
                }
                if depth == 0 { j = min(j, utf16.count) } else { j = utf16.count }
                tokens.append(SDKToken(range: i..<j, kind: .comment))
                i = j
                continue
            }
            // String literal: "..." (Swift, TS, JS, JSON) and `...` / '...' (TS/JS).
            if c == 34 || ((language == .typescript || language == .javascript) && (c == 39 || c == 96)) {
                let quote = c
                var j = i + 1
                while j < utf16.count {
                    if utf16[j] == 92, j + 1 < utf16.count { j += 2; continue }
                    if utf16[j] == quote { j += 1; break }
                    if quote != 96, utf16[j] == 10 { break }
                    j += 1
                }
                tokens.append(SDKToken(range: i..<min(j, utf16.count), kind: .string))
                i = min(j, utf16.count)
                continue
            }
            // Number.
            if isDigit(c) || (c == 46 && i + 1 < utf16.count && isDigit(utf16[i + 1])) {
                var j = i
                while j < utf16.count, isDigit(utf16[j]) || utf16[j] == 46 || utf16[j] == 95 { j += 1 }
                tokens.append(SDKToken(range: i..<j, kind: .number))
                i = j
                continue
            }
            // Identifier: keyword, capitalized type name, or plain.
            if isIdentStart(c) {
                var j = i
                while j < utf16.count, isIdent(utf16[j]) { j += 1 }
                let word = String(decoding: utf16[i..<j], as: UTF16.self)
                if keywords.contains(word) {
                    tokens.append(SDKToken(range: i..<j, kind: .keyword))
                } else if let first = word.unicodeScalars.first, CharacterSet.uppercaseLetters.contains(first) {
                    tokens.append(SDKToken(range: i..<j, kind: .typeName))
                }
                i = j
                continue
            }
            i += 1
        }
        return tokens
    }

    public static let swiftKeywords: Set<String> = [
        "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func",
        "import", "init", "inout", "internal", "let", "open", "operator", "private",
        "precedencegroup", "protocol", "public", "rethrows", "static", "struct",
        "subscript", "typealias", "var", "break", "case", "catch", "continue", "default",
        "defer", "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat",
        "return", "throw", "switch", "where", "while", "as", "Any", "false", "is",
        "nil", "self", "Self", "super", "throws", "true", "try", "await", "actor",
        "async", "some", "nonisolated", "sending", "borrowing", "consuming",
    ]

    public static let typeScriptKeywords: Set<String> = [
        "const", "let", "var", "function", "class", "extends", "import", "export",
        "from", "default", "return", "if", "else", "for", "while", "do", "switch",
        "case", "break", "continue", "new", "typeof", "instanceof", "async", "await",
        "try", "catch", "finally", "throw", "interface", "type", "enum", "namespace",
        "declare", "readonly", "public", "private", "protected", "static", "get",
        "set", "in", "of", "this", "super", "true", "false", "null", "undefined",
        "void", "delete", "yield", "implements", "abstract", "keyof",
    ]
}

// MARK: - SDK console entries
//
// Legacy: `SwiftCode/SDK/Studio/CodeEditor/SDKConsoleEntry.swift`.
// Bounded text (4 KiB per entry, enforced by the state); `system` covers
// editor-generated status lines rather than child-process output.

public enum SDKConsoleStream: String, Sendable, Codable, CaseIterable, Hashable {
    case stdout
    case stderr
    case system
}

public struct SDKConsoleEntry: Identifiable, Sendable, Hashable {
    public static let maxTextLength: Int = 4_096

    public let id: UUID
    public let timestamp: Date
    public let stream: SDKConsoleStream
    public let text: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), stream: SDKConsoleStream, text: String) {
        self.id = id
        self.timestamp = timestamp
        self.stream = stream
        self.text = text
    }

    public static func system(_ text: String, at date: Date = Date()) -> SDKConsoleEntry {
        SDKConsoleEntry(timestamp: date, stream: .system, text: text)
    }

    public static func stdout(_ text: String, at date: Date = Date()) -> SDKConsoleEntry {
        SDKConsoleEntry(timestamp: date, stream: .stdout, text: text)
    }

    public static func stderr(_ text: String, at date: Date = Date()) -> SDKConsoleEntry {
        SDKConsoleEntry(timestamp: date, stream: .stderr, text: text)
    }
}

// MARK: - SDK code documents and tabs
//
// Legacy: `SwiftCode/SDK/Studio/CodeEditor/SDKCodeDocument.swift`.
// Value types: edits produce new values; `SDKCodeEditorState` owns the
// collection. Ycode's `EditorDocument`/`EditorBuffer` (YcodeEditorKit) is
// the main IDE's document model — the Studio pane keeps its own value-type
// document because its tabs, untitled buffers, and snippet/manifest flows
// are Studio-specific, and it delegates disk open/save/change detection to
// the same file semantics rather than duplicating `EditorDocument`.

public struct SDKCodeDocument: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let fileURL: URL?
    public let language: SDKCodeLanguage
    public let text: String
    public let isDirty: Bool
    public let cursorOffset: Int?
    public let lastKnownModificationDate: Date?
    public let hasExternalModification: Bool

    public init(id: UUID = UUID(), fileURL: URL?, language: SDKCodeLanguage, text: String,
                isDirty: Bool = false, cursorOffset: Int? = nil,
                lastKnownModificationDate: Date? = nil, hasExternalModification: Bool = false) {
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
        SDKCodeDocument(id: id, fileURL: fileURL, language: language, text: newText, isDirty: true,
                        cursorOffset: cursorOffset ?? self.cursorOffset,
                        lastKnownModificationDate: lastKnownModificationDate,
                        hasExternalModification: hasExternalModification)
    }

    public func saved(fileURL newURL: URL? = nil, modificationDate: Date? = nil) -> SDKCodeDocument {
        let resolvedURL = newURL ?? fileURL
        let resolvedLang = resolvedURL.map { SDKCodeLanguage.infer(fromFileURL: $0) } ?? language
        return SDKCodeDocument(id: id, fileURL: resolvedURL, language: resolvedLang, text: text,
                               isDirty: false, cursorOffset: cursorOffset,
                               lastKnownModificationDate: modificationDate ?? lastKnownModificationDate,
                               hasExternalModification: false)
    }

    public func withExternalModification(_ flag: Bool) -> SDKCodeDocument {
        SDKCodeDocument(id: id, fileURL: fileURL, language: language, text: text, isDirty: isDirty,
                        cursorOffset: cursorOffset, lastKnownModificationDate: lastKnownModificationDate,
                        hasExternalModification: flag)
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

// MARK: - SDK file tree node
//
// Legacy: `SwiftCode/SDK/Studio/CodeEditor/SDKCodeFileNode.swift`.
// Lazy children (`nil` until enumerated; files never carry children);
// expansion state survives reloads.

public struct SDKCodeFileNode: Identifiable, Sendable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let isDirectory: Bool
    public let children: [SDKCodeFileNode]?
    public let isExpanded: Bool

    public init(url: URL, isDirectory: Bool, children: [SDKCodeFileNode]? = nil, isExpanded: Bool = false) {
        self.url = url
        self.isDirectory = isDirectory
        self.children = isDirectory ? children : nil
        self.isExpanded = isExpanded
    }

    public var name: String { url.lastPathComponent }
    public var needsLoading: Bool { isDirectory && children == nil }

    public func withChildren(_ newChildren: [SDKCodeFileNode]) -> SDKCodeFileNode {
        SDKCodeFileNode(url: url, isDirectory: isDirectory, children: newChildren, isExpanded: isExpanded)
    }

    public func toggledExpanded() -> SDKCodeFileNode {
        SDKCodeFileNode(url: url, isDirectory: isDirectory, children: children, isExpanded: !isExpanded)
    }

    /// Enumerates one directory level, sorted directories-first. Hidden
    /// entries and `node_modules` are skipped, matching the Studio navigator.
    public static func loadChildren(of url: URL) -> [SDKCodeFileNode] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        return items
            .filter { $0.lastPathComponent != "node_modules" }
            .map { item in
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                return SDKCodeFileNode(url: item, isDirectory: isDir)
            }
            .sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }
}

// MARK: - Editor errors, navigation, diagnostics
//
// Legacy: `SwiftCode/SDK/Studio/CodeEditor/SDKCodeEditorState.swift`
// (header types).

public enum SDKCodeEditorError: Error, Sendable {
    case unreadableFile(url: URL, reason: String)
}

public struct SDKCodeNavigationTarget: Equatable, Sendable {
    public let id: UUID
    public let tabID: UUID
    public let line: Int
    public let column: Int?

    public init(id: UUID = UUID(), tabID: UUID, line: Int, column: Int? = nil) {
        self.id = id
        self.tabID = tabID
        self.line = max(1, line)
        self.column = column
    }
}

public struct SDKEditorDiagnostic: Identifiable, Equatable, Sendable, Hashable {
    public enum Severity: String, Sendable, Codable, Hashable {
        case error
        case warning
        case info
    }

    public let id: UUID
    public let severity: Severity
    public let source: String
    public let code: String
    public let message: String
    public let suggestion: String?
    public let fileURL: URL?
    public let line: Int?
    public let column: Int?

    public init(id: UUID = UUID(), severity: Severity, source: String, code: String, message: String,
                suggestion: String? = nil, fileURL: URL? = nil, line: Int? = nil, column: Int? = nil) {
        self.id = id
        self.severity = severity
        self.source = source
        self.code = code
        self.message = message
        self.suggestion = suggestion
        self.fileURL = fileURL
        self.line = line
        self.column = column
    }
}

// MARK: - SDKCodeEditorState
//
// Legacy: `SwiftCode/SDK/Studio/CodeEditor/SDKCodeEditorState.swift`.
// The single source of truth for a Studio editor session: tabs, active
// tab, project root (persisted in UserDefaults), diagnostics, console
// (capped at 5,000 entries, oldest first), find query, navigation
// requests, and external-modification tracking. `@Observable` (not
// `ObservableObject`) to match Ycode's shell models and stay testable
// headless on macOS and Linux.

@MainActor
@Observable
public final class SDKCodeEditorState {
    public static let maxConsoleEntries: Int = 5_000

    private static let persistedProjectRootKey = "com.swiftcode.sdk.studio.codeEditor.projectRootPath"

    public private(set) var tabs: [SDKCodeEditorTab] = []
    public private(set) var activeTabID: UUID?
    public private(set) var consoleEntries: [SDKConsoleEntry] = []
    public private(set) var diagnostics: [SDKEditorDiagnostic] = []
    public var findQuery: String = ""
    public var projectRootURL: URL? {
        didSet {
            if let root = projectRootURL {
                UserDefaults.standard.set(root.standardizedFileURL.path, forKey: Self.persistedProjectRootKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.persistedProjectRootKey)
            }
        }
    }
    public var requestedNavigationTarget: SDKCodeNavigationTarget?
    public var externalModificationTabIDs: Set<UUID> = []

    public init(projectRootURL: URL? = nil) {
        if let explicitRoot = projectRootURL {
            self.projectRootURL = explicitRoot.standardizedFileURL
        } else if let savedPath = UserDefaults.standard.string(forKey: Self.persistedProjectRootKey),
                  FileManager.default.fileExists(atPath: savedPath) {
            self.projectRootURL = URL(fileURLWithPath: savedPath).standardizedFileURL
        } else {
            self.projectRootURL = nil
        }
    }

    public func setProjectRoot(_ url: URL?) {
        projectRootURL = url?.standardizedFileURL
    }

    public var activeTab: SDKCodeEditorTab? {
        guard let activeTabID else { return nil }
        return tabs.first(where: { $0.id == activeTabID })
    }

    public var activeDocument: SDKCodeDocument? { activeTab?.document }
    public var hasUnsavedChanges: Bool { tabs.contains(where: { $0.document.isDirty }) }

    @discardableResult
    public func openTab(for document: SDKCodeDocument) -> UUID {
        if let existingIndex = indexOfTab(matching: document) {
            let id = tabs[existingIndex].id
            activateTab(id)
            return id
        }
        var docWithTimestamp = document
        if let url = document.fileURL, docWithTimestamp.lastKnownModificationDate == nil {
            docWithTimestamp = SDKCodeDocument(id: document.id, fileURL: url, language: document.language,
                                               text: document.text, isDirty: document.isDirty,
                                               cursorOffset: document.cursorOffset,
                                               lastKnownModificationDate: diskModificationDate(for: url),
                                               hasExternalModification: false)
        }
        let newTab = SDKCodeEditorTab(document: docWithTimestamp, isActive: true)
        tabs.append(newTab)
        activateTab(newTab.id)
        return newTab.id
    }

    @discardableResult
    public func openFile(_ url: URL) throws -> UUID {
        if let existing = tabs.first(where: {
            $0.document.fileURL == url || $0.document.fileURL?.standardizedFileURL == url.standardizedFileURL
        }) {
            activateTab(existing.id)
            return existing.id
        }
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw SDKCodeEditorError.unreadableFile(url: url, reason: error.localizedDescription)
        }
        let document = SDKCodeDocument(fileURL: url, language: SDKCodeLanguage.infer(fromFileURL: url),
                                       text: text, isDirty: false,
                                       lastKnownModificationDate: diskModificationDate(for: url))
        let tab = SDKCodeEditorTab(document: document)
        tabs.append(tab)
        activateTab(tab.id)
        return tab.id
    }

    @discardableResult
    public func openFile(at url: URL) throws -> UUID { try openFile(url) }

    @discardableResult
    public func newUntitledTab(language: SDKCodeLanguage = .typescript, initialText: String = "") -> UUID {
        let doc = SDKCodeDocument(fileURL: nil, language: language, text: initialText,
                                  isDirty: !initialText.isEmpty)
        return openTab(for: doc)
    }

    public func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        externalModificationTabIDs.remove(id)
        guard activeTabID == id else { return }
        if tabs.isEmpty {
            activeTabID = nil
        } else {
            activateTab(tabs[min(index, tabs.count - 1)].id)
        }
    }

    public func activateTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
        tabs = tabs.map { $0.withActive($0.id == id) }
    }

    public func updateText(_ text: String, for tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index] = tabs[index].withDocument(tabs[index].document.withText(text))
    }

    public func markSaved(tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let modDate = tabs[index].document.fileURL.flatMap { diskModificationDate(for: $0) }
        tabs[index] = tabs[index].withDocument(
            tabs[index].document.saved(fileURL: tabs[index].document.fileURL, modificationDate: modDate))
        externalModificationTabIDs.remove(tabID)
    }

    public func retargetTab(_ tabID: UUID, to destinationURL: URL) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let standardized = destinationURL.standardizedFileURL
        let modDate = diskModificationDate(for: standardized)
        tabs[index] = tabs[index].withDocument(
            tabs[index].document.saved(fileURL: standardized, modificationDate: modDate))
        externalModificationTabIDs.remove(tabID)
    }

    public func updateActiveDocument(_ transform: (SDKCodeDocument) -> SDKCodeDocument) {
        guard let activeTabID else { return }
        updateDocument(forTab: activeTabID, transform)
    }

    public func updateDocument(forTab tabID: UUID, _ transform: (SDKCodeDocument) -> SDKCodeDocument) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index] = tabs[index].withDocument(transform(tabs[index].document))
    }

    public func saveAllModifiedTabs() {
        for index in tabs.indices {
            let doc = tabs[index].document
            guard doc.isDirty, let url = doc.fileURL else { continue }
            do {
                try Data(doc.text.utf8).write(to: url, options: .atomic)
                let modDate = diskModificationDate(for: url)
                tabs[index] = tabs[index].withDocument(doc.saved(fileURL: url, modificationDate: modDate))
                externalModificationTabIDs.remove(tabs[index].id)
            } catch {
                appendConsole(SDKConsoleEntry(stream: .stderr,
                                              text: "Failed to save \(url.lastPathComponent): \(error.localizedDescription)"))
            }
        }
    }

    /// Writes one tab to disk (used by the editor view's Save). Returns
    /// `false` when the tab has no file URL (untitled — the view offers
    /// Save As instead) or the write fails.
    @discardableResult
    public func saveTab(_ tabID: UUID) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let url = tabs[index].document.fileURL else { return false }
        do {
            try Data(tabs[index].document.text.utf8).write(to: url, options: .atomic)
            markSaved(tabID: tabID)
            return true
        } catch {
            appendConsole(SDKConsoleEntry(stream: .stderr,
                                          text: "Failed to save \(url.lastPathComponent): \(error.localizedDescription)"))
            return false
        }
    }

    public func checkExternalModifications() {
        for index in tabs.indices {
            let tab = tabs[index]
            let doc = tab.document
            guard let url = doc.fileURL,
                  let diskDate = diskModificationDate(for: url),
                  let knownDate = doc.lastKnownModificationDate,
                  diskDate > knownDate.addingTimeInterval(0.5) else { continue }
            guard let diskData = try? Data(contentsOf: url),
                  let diskText = String(data: diskData, encoding: .utf8) else { continue }
            if diskText != doc.text {
                if !doc.isDirty {
                    let reloaded = SDKCodeDocument(id: doc.id, fileURL: url, language: doc.language,
                                                   text: diskText, isDirty: false, cursorOffset: doc.cursorOffset,
                                                   lastKnownModificationDate: diskDate,
                                                   hasExternalModification: false)
                    tabs[index] = tab.withDocument(reloaded)
                    externalModificationTabIDs.remove(tab.id)
                } else {
                    tabs[index] = tab.withDocument(doc.withExternalModification(true))
                    externalModificationTabIDs.insert(tab.id)
                }
            } else {
                tabs[index] = tab.withDocument(doc.saved(fileURL: url, modificationDate: diskDate))
            }
        }
    }

    public func reloadTabFromDisk(_ tabID: UUID) throws {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let url = tabs[index].document.fileURL else { return }
        let data = try Data(contentsOf: url)
        guard let diskText = String(data: data, encoding: .utf8) else { return }
        let doc = tabs[index].document
        let reloaded = SDKCodeDocument(id: doc.id, fileURL: url, language: doc.language, text: diskText,
                                       isDirty: false, cursorOffset: nil,
                                       lastKnownModificationDate: diskModificationDate(for: url),
                                       hasExternalModification: false)
        tabs[index] = tabs[index].withDocument(reloaded)
        externalModificationTabIDs.remove(tabID)
    }

    public func dismissExternalModification(for tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let doc = tabs[index].document
        let diskDate = doc.fileURL.flatMap { diskModificationDate(for: $0) } ?? doc.lastKnownModificationDate
        let updated = SDKCodeDocument(id: doc.id, fileURL: doc.fileURL, language: doc.language,
                                      text: doc.text, isDirty: true, cursorOffset: doc.cursorOffset,
                                      lastKnownModificationDate: diskDate, hasExternalModification: false)
        tabs[index] = tabs[index].withDocument(updated)
        externalModificationTabIDs.remove(tabID)
    }

    public func insertCodeSnippet(_ snippetCode: String, preferredLanguage: SDKCodeLanguage = .typescript,
                                  suggestedTitle: String? = nil) {
        let trimmed = snippetCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let activeID = activeTabID,
           let index = tabs.firstIndex(where: { $0.id == activeID }),
           !(tabs[index].document.displayName == "swiftcode.json" && preferredLanguage != .json) {
            let doc = tabs[index].document
            let updatedText: String
            if doc.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updatedText = trimmed + "\n"
            } else if let offset = doc.cursorOffset, offset >= 0, offset <= doc.text.utf16.count {
                var mutable = doc.text
                mutable.insert(contentsOf: "\n" + trimmed + "\n",
                               at: String.Index(utf16Offset: offset, in: doc.text))
                updatedText = mutable
            } else {
                var mutable = doc.text
                if !mutable.hasSuffix("\n") { mutable += "\n" }
                mutable += "\n" + trimmed + "\n"
                updatedText = mutable
            }
            tabs[index] = tabs[index].withDocument(doc.withText(updatedText))
            appendConsole(SDKConsoleEntry(stream: .system, text: "Inserted snippet into \(doc.displayName)"))
            return
        }
        if preferredLanguage == .typescript, let root = projectRootURL {
            let indexTS = root.appendingPathComponent("src/index.ts")
            if FileManager.default.fileExists(atPath: indexTS.path),
               let tabID = try? openFile(indexTS),
               let idx = tabs.firstIndex(where: { $0.id == tabID }) {
                let doc = tabs[idx].document
                var mutable = doc.text
                if !mutable.hasSuffix("\n") { mutable += "\n" }
                mutable += "\n" + trimmed + "\n"
                tabs[idx] = tabs[idx].withDocument(doc.withText(mutable))
                appendConsole(SDKConsoleEntry(stream: .system, text: "Inserted snippet into src/index.ts"))
                return
            }
        }
        let newDoc = SDKCodeDocument(fileURL: nil, language: preferredLanguage, text: trimmed + "\n", isDirty: true)
        _ = openTab(for: newDoc)
        appendConsole(SDKConsoleEntry(stream: .system,
                                      text: "Opened new \(preferredLanguage.displayName) buffer with snippet"))
    }

    /// Adds or updates a capability in the active project's
    /// `swiftcode.json` (JSON edited in place so unknown keys survive)
    /// and synchronizes any open `swiftcode.json` tab.
    @discardableResult
    public func addCapabilityToManifest(capabilityId: String, reason: String) -> Bool {
        guard let root = projectRootURL else { return false }
        let manifestURL = root.appendingPathComponent("swiftcode.json").standardizedFileURL
        guard let data = try? Data(contentsOf: manifestURL),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        let cleanReason = reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Required for \(capabilityId)"
            : reason.trimmingCharacters(in: .whitespacesAndNewlines)
        var caps = (object["capabilities"] as? [[String: Any]]) ?? []
        if let idx = caps.firstIndex(where: { ($0["id"] as? String) == capabilityId }) {
            caps[idx]["reason"] = cleanReason
        } else {
            caps.append(["id": capabilityId, "reason": cleanReason])
        }
        object["capabilities"] = caps
        guard let encoded = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let encodedString = String(data: encoded, encoding: .utf8) else { return false }
        do {
            try Data(encodedString.utf8).write(to: manifestURL, options: .atomic)
            let modDate = diskModificationDate(for: manifestURL)
            if let idx = tabs.firstIndex(where: { $0.document.fileURL?.standardizedFileURL == manifestURL }) {
                let doc = tabs[idx].document.withText(encodedString).saved(fileURL: manifestURL, modificationDate: modDate)
                tabs[idx] = tabs[idx].withDocument(doc)
            }
            appendConsole(SDKConsoleEntry(stream: .system, text: "Added capability \"\(capabilityId)\" to swiftcode.json"))
            return true
        } catch {
            return false
        }
    }

    public func navigateTo(fileURL: URL, line: Int, column: Int? = nil) {
        guard let tabID = try? openFile(fileURL) else { return }
        requestedNavigationTarget = SDKCodeNavigationTarget(tabID: tabID, line: line, column: column)
    }

    public func navigateActiveTabTo(line: Int, column: Int? = nil) {
        guard let activeTabID else { return }
        requestedNavigationTarget = SDKCodeNavigationTarget(tabID: activeTabID, line: line, column: column)
    }

    public func clearNavigationTarget() { requestedNavigationTarget = nil }

    public func setDiagnostics(_ items: [SDKEditorDiagnostic]) { diagnostics = items }

    public func appendDiagnostic(_ item: SDKEditorDiagnostic) {
        if !diagnostics.contains(where: {
            $0.fileURL == item.fileURL && $0.line == item.line && $0.code == item.code && $0.message == item.message
        }) {
            diagnostics.append(item)
        }
    }

    public func clearDiagnostics() { diagnostics.removeAll() }

    public func appendConsole(_ entry: SDKConsoleEntry) {
        var text = entry.text
        if text.count > SDKConsoleEntry.maxTextLength {
            text = String(text.prefix(SDKConsoleEntry.maxTextLength)) + "… (truncated)"
        }
        let bounded = text == entry.text
            ? entry
            : SDKConsoleEntry(id: entry.id, timestamp: entry.timestamp, stream: entry.stream, text: text)
        consoleEntries.append(bounded)
        let overflow = consoleEntries.count - Self.maxConsoleEntries
        if overflow > 0 { consoleEntries.removeFirst(overflow) }
    }

    public func clearConsole() { consoleEntries.removeAll() }

    private func indexOfTab(matching document: SDKCodeDocument) -> Int? {
        if let targetURL = document.fileURL?.standardizedFileURL {
            return tabs.firstIndex { $0.document.fileURL?.standardizedFileURL == targetURL }
        }
        return tabs.firstIndex { $0.document.id == document.id }
    }

    private func diskModificationDate(for url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}

// MARK: - Find
//
// Legacy: `SwiftCode/SDK/Studio/CodeEditor/Views/SDKCodeFindCoordinator.swift`.
// Literal substring search over the editor's current text (no regex);
// case-insensitivity folds via `.caseInsensitive`. Offsets are UTF-16
// code-unit offsets, the same convention as `SDKToken.range`.

@MainActor
public protocol SDKCodeFindableEditor: AnyObject {
    var findableText: String { get }
    func selectFindRange(_ range: Range<Int>)
}

@MainActor
@Observable
public final class SDKCodeFindCoordinator {
    public weak var editor: (any SDKCodeFindableEditor)? {
        didSet { recomputeMatches(selectFirst: !query.isEmpty) }
    }

    public private(set) var query: String = ""
    public var caseSensitive: Bool = false {
        didSet { recomputeMatches(selectFirst: true) }
    }
    public private(set) var matches: [Range<Int>] = []
    public private(set) var currentMatchIndex: Int?

    public init() {}

    public var hasMatches: Bool { currentMatchIndex != nil }

    public var matchSummaryText: String {
        if query.isEmpty { return "" }
        if matches.isEmpty { return "No matches" }
        if let index = currentMatchIndex { return "\(index + 1) of \(matches.count)" }
        return "\(matches.count) matches"
    }

    public func setQuery(_ newQuery: String) {
        guard newQuery != query else { return }
        query = newQuery
        recomputeMatches(selectFirst: true)
    }

    public func editorTextDidChange() {
        let previousIndex = currentMatchIndex
        recomputeMatches(selectFirst: false)
        if let previousIndex, previousIndex < matches.count {
            currentMatchIndex = previousIndex
        }
    }

    public func findNext() {
        guard !matches.isEmpty else { return }
        let next = ((currentMatchIndex ?? -1) + 1) % matches.count
        selectMatch(at: next)
    }

    public func findPrevious() {
        guard !matches.isEmpty else { return }
        let prev = ((currentMatchIndex ?? 0) - 1 + matches.count) % matches.count
        selectMatch(at: prev)
    }

    public func selectMatch(at index: Int) {
        guard matches.indices.contains(index) else { return }
        currentMatchIndex = index
        editor?.selectFindRange(matches[index])
    }

    public func findAllMatches(in text: String, query: String, caseSensitive: Bool) -> [Range<Int>] {
        guard !query.isEmpty else { return [] }
        var results: [Range<Int>] = []
        var searchFrom = text.startIndex
        let options: String.CompareOptions = caseSensitive ? [] : .caseInsensitive
        while searchFrom < text.endIndex,
              let range = text.range(of: query, options: options, range: searchFrom..<text.endIndex) {
            let lower = text.utf16.distance(from: text.utf16.startIndex, to: range.lowerBound)
            let upper = text.utf16.distance(from: text.utf16.startIndex, to: range.upperBound)
            results.append(lower..<upper)
            searchFrom = range.upperBound
            if range.isEmpty { break }
        }
        return results
    }

    private func recomputeMatches(selectFirst: Bool) {
        guard let editor else {
            matches = []
            currentMatchIndex = nil
            return
        }
        matches = findAllMatches(in: editor.findableText, query: query, caseSensitive: caseSensitive)
        if matches.isEmpty {
            currentMatchIndex = nil
        } else if selectFirst {
            selectMatch(at: 0)
        } else if let current = currentMatchIndex, current >= matches.count {
            currentMatchIndex = matches.count - 1
        }
    }
}

// MARK: - Build / run
//
// Legacy: `SwiftCode/SDK/Studio/CodeEditor/SDKBuildRunRequest.swift` +
// `SDKCodeBuildRunner.swift`. Each kind maps to a real command line:
// `.xcodebuildSwift` → the managed build service (`SDKBuildService` /
// `SDKBuildHandle`, Wave 15 — the xcodebuild path no longer runs a raw
// `Process`), `.typescriptExtension` → `npm run build`, `.nodeScript` →
// `node <entry>` (local processes). Output streams live into the editor
// console line by line; cancellation is cooperative by `taskID`
// (SIGTERM, then SIGKILL after 3 s for local processes; handle cancel
// for managed builds).

public enum SDKBuildRunKind: String, Sendable, Codable, CaseIterable, Hashable {
    case xcodebuildSwift
    case typescriptExtension
    case nodeScript

    public var displayName: String {
        switch self {
        case .xcodebuildSwift: return "xcodebuild (Swift)"
        case .typescriptExtension: return "TypeScript Extension"
        case .nodeScript: return "Node Script"
        }
    }
}

public struct SDKBuildRunRequest: Identifiable, Sendable, Hashable {
    public let taskID: UUID
    public let projectRoot: URL
    public let kind: SDKBuildRunKind
    public let schemeOrEntry: String?

    public init(taskID: UUID = UUID(), projectRoot: URL, kind: SDKBuildRunKind, schemeOrEntry: String? = nil) {
        self.taskID = taskID
        self.projectRoot = projectRoot
        self.kind = kind
        self.schemeOrEntry = schemeOrEntry
    }

    public var id: UUID { taskID }
}

public actor SDKCodeBuildRunner {
    public static let shared = SDKCodeBuildRunner()
    public static let hostExtensionID = "studio.editor"

    /// Stable digest for the host identity: SHA-256 of
    /// `"swiftcode.sdk.studio.editor"` (Legacy computed it at runtime via
    /// CryptoKit; this target has no Crypto dependency, so the constant
    /// is embedded — verify with
    /// `python3 -c "import hashlib; print(hashlib.sha256(b'swiftcode.sdk.studio.editor').hexdigest())"`).
    /// Distinct from every extension ID, so the managed build service's
    /// one-build-per-extension slot never collides with extension builds.
    public static let hostPackageDigest = "f4a6727600315b3f0074a3aa515bc73a4ce6f37f5055e97d8f9aecceead8a927"

    private static let cancelGraceNanoseconds: UInt64 = 3_000_000_000

    private struct LocalProcessSession {
        let process: Process
    }

    private enum ActiveEntry {
        case managedBuild(SDKBuildHandle)
        case localProcess(LocalProcessSession)
    }

    private var active: [UUID: ActiveEntry] = [:]

    public init() {}

    /// Validates the project at `projectRoot` (manifest via Ycode's strict
    /// `SwiftCodeManifestValidator`; entrypoint existence as a warning) and
    /// populates `editorState.diagnostics`. Returns `true` when zero errors
    /// are found. A root without `swiftcode.json` is a standalone project:
    /// verified structurally, not failed.
    @discardableResult
    public func validateProject(at projectRoot: URL, into editorState: SDKCodeEditorState) async -> Bool {
        await editorState.saveAllModifiedTabs()
        await editorState.clearDiagnostics()
        let root = projectRoot.standardizedFileURL
        let manifestURL = root.appendingPathComponent("swiftcode.json")
        let fm = FileManager.default
        await editorState.appendConsole(.system("Validating project at \(root.lastPathComponent)…"))
        guard fm.fileExists(atPath: manifestURL.path) else {
            let packageJSON = root.appendingPathComponent("package.json")
            let swiftFiles = (try? fm.contentsOfDirectory(atPath: root.path))?
                .filter { $0.hasSuffix(".swift") || $0.hasSuffix(".xcodeproj") } ?? []
            if !fm.fileExists(atPath: packageJSON.path) && swiftFiles.isEmpty {
                let diag = SDKEditorDiagnostic(severity: .warning, source: "project",
                                               code: "NO_MANIFEST_OR_PROJECT",
                                               message: "No swiftcode.json, package.json, or Swift project found in \(root.lastPathComponent).",
                                               suggestion: "Open an extension or project root directory.",
                                               fileURL: root, line: 1)
                await editorState.appendDiagnostic(diag)
                await editorState.appendConsole(.stderr("[WARN] \(diag.message)"))
            } else {
                await editorState.appendConsole(.system("Standalone project structure verified (no swiftcode.json manifest)."))
            }
            return true
        }
        let data: Data
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            let diag = SDKEditorDiagnostic(severity: .error, source: "swiftcode.json",
                                           code: "MANIFEST_READ_ERROR",
                                           message: "Could not read swiftcode.json: \(error.localizedDescription)",
                                           fileURL: manifestURL, line: 1)
            await editorState.appendDiagnostic(diag)
            await editorState.appendConsole(.stderr("[ERROR] \(diag.message)"))
            return false
        }
        let rawDiagnostics = SwiftCodeManifestValidator.validateWithDiagnostics(data: data, projectRoot: root)
        var errorCount = 0
        var warningCount = 0
        for item in rawDiagnostics {
            let sev: SDKEditorDiagnostic.Severity = item.severity == .error ? .error : (item.severity == .warning ? .warning : .info)
            if item.severity == .error { errorCount += 1 }
            if item.severity == .warning { warningCount += 1 }
            await editorState.appendDiagnostic(SDKEditorDiagnostic(
                severity: sev, source: "swiftcode.json", code: item.field, message: item.message,
                suggestion: item.suggestion, fileURL: manifestURL, line: item.line))
        }
        await editorState.appendConsole(.system(
            "Validation finished: \(errorCount) error(s), \(warningCount) warning(s)."))
        return errorCount == 0
    }

    /// Executes `request` for real, streaming output lines into
    /// `editorState` as they arrive. Does not return until the run reaches
    /// a terminal state (or the request fails to start); the caller keeps
    /// `request.taskID` and uses `cancel(taskID:)` to stop it early.
    /// The project is validated first (manifest schema, semantic rules)
    /// for TypeScript extensions and for any project with a
    /// `swiftcode.json`; a failed validation aborts the run before
    /// anything is launched.
    public func run(_ request: SDKBuildRunRequest, into editorState: SDKCodeEditorState) async {
        guard active[request.taskID] == nil else {
            await editorState.appendConsole(.system("Build/run ignored: task \(request.taskID.uuidString) is already in flight."))
            return
        }
        let manifestURL = request.projectRoot.appendingPathComponent("swiftcode.json")
        if request.kind == .typescriptExtension || FileManager.default.fileExists(atPath: manifestURL.path) {
            let valid = await validateProject(at: request.projectRoot, into: editorState)
            if !valid {
                await editorState.appendConsole(.stderr("Build aborted: fix swiftcode.json validation errors before building."))
                return
            }
        }
        switch request.kind {
        case .xcodebuildSwift:
            await runManagedBuild(request, into: editorState)
        case .typescriptExtension, .nodeScript:
            await runLocalProcess(request, into: editorState)
        }
    }

    // MARK: - Managed xcodebuild path (D-4, Wave 15)
    //
    // The xcodebuild path runs through the host's managed build service
    // (`SDKBuildService` / `SDKBuildHandle`), never a raw `Process`:
    // typed allow-list request, host environment only, one build per
    // caller, bounded streams, and a truthful terminal result (exit 0
    // AND `** BUILD SUCCEEDED **` AND zero parsed errors). When
    // xcodebuild is unavailable the service fails honestly — the runner
    // never fakes a build.
    //
    // Authorization: the service authorizes `build.execute` for the
    // Studio host identity (`studio.editor`) through the capability
    // broker, exactly as for an extension. With no grant the run fails
    // here with `.permissionDenied` and the diagnostic tells the user
    // to approve the capability for the Studio editor (Studio →
    // Extensions → grant manager pre-authorization). The host identity
    // is NOT auto-granted: silently granting the host its own build
    // capability would bypass the approval model.

    private func runManagedBuild(_ request: SDKBuildRunRequest, into editorState: SDKCodeEditorState) async {
        let taskID = request.taskID
        let scheme = request.schemeOrEntry?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sdkRequest = SDKBuildRequest(target: scheme)
        let caller = SDKCallerIdentity(
            extensionID: Self.hostExtensionID,
            packageDigest: Self.hostPackageDigest,
            projectRootPath: request.projectRoot.path,
            apiKey: nil
        )
        await editorState.appendConsole(.system(
            "Build requested (xcodebuild) — project: \(request.projectRoot.lastPathComponent), scheme: \(scheme.isEmpty ? "<explicit scheme required>" : "\"\(scheme)\"")"))

        let handle: SDKBuildHandle
        do {
            handle = try await SDKBuildService.shared.run(caller: caller, request: sdkRequest)
        } catch let sdkError as SDKError {
            var text = "Build could not start [\(sdkError.code.rawValue)]: \(sdkError.message)"
            if let suggestion = sdkError.suggestion, !suggestion.isEmpty {
                text += " \(suggestion)"
            }
            await editorState.appendDiagnostic(SDKEditorDiagnostic(
                severity: .error, source: "xcodebuild", code: sdkError.code.rawValue,
                message: sdkError.message, suggestion: sdkError.suggestion,
                fileURL: request.projectRoot, line: 1))
            await editorState.appendConsole(.system(text))
            return
        } catch {
            await editorState.appendConsole(.system("Build could not start: \(error.localizedDescription)"))
            return
        }
        active[taskID] = .managedBuild(handle)

        for await event in handle.events {
            await editorState.appendConsole(consoleEntry(for: event))
        }
        let result = await handle.wait()
        active[taskID] = nil
        for diagnostic in result.diagnostics {
            await editorState.appendDiagnostic(SDKEditorDiagnostic(
                severity: .error, source: "xcodebuild", code: "BUILD_DIAGNOSTIC",
                message: diagnostic.message,
                fileURL: diagnostic.file.map { request.projectRoot.appendingPathComponent($0) },
                line: diagnostic.line))
        }
        await editorState.appendConsole(terminalEntry(for: result))
    }

    private func consoleEntry(for event: SDKBuildOutputEvent) -> SDKConsoleEntry {
        switch event.kind {
        case .stdout: return .stdout(event.text)
        case .stderr: return .stderr(event.text)
        case .status: return .system(event.text)
        }
    }

    private func terminalEntry(for result: SDKBuildResult) -> SDKConsoleEntry {
        let duration = String(format: "%.1f", result.durationSeconds)
        switch result.status {
        case .succeeded:
            return .system("Build succeeded in \(duration)s.")
        case .failed:
            let exit = result.exitCode.map(String.init) ?? "?"
            return .system("Build failed (exit \(exit), \(result.errorCount) error(s), \(result.warningCount) warning(s), \(duration)s).")
        case .cancelled:
            return .system("Build cancelled.")
        case .timedOut:
            return .system("Build timed out after 30 minutes.")
        case .running:
            return .system("Build ended in an unexpected state (still marked running).")
        }
    }

    // MARK: - Local process path (npm / node)

    private func runLocalProcess(_ request: SDKBuildRunRequest, into editorState: SDKCodeEditorState) async {
        await editorState.appendConsole(.system("Starting \(request.kind.displayName) in \(request.projectRoot.lastPathComponent)…"))
        let process = Process()
        process.currentDirectoryURL = request.projectRoot
        switch request.kind {
        case .xcodebuildSwift:
            // Unreachable: the xcodebuild kind is handled by the managed
            // path above. Kept for exhaustiveness if the dispatch changes.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
            var args: [String] = []
            if let scheme = request.schemeOrEntry, !scheme.isEmpty { args += ["-scheme", scheme] }
            args += ["build"]
            process.arguments = args
        case .typescriptExtension:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["npm", "run", "build"]
        case .nodeScript:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["node", request.schemeOrEntry ?? "index.js"]
        }
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        let streamTask = Task {
            for await line in lines(from: stdoutPipe.fileHandleForReading) {
                await editorState.appendConsole(.stdout(line))
            }
        }
        let errorTask = Task {
            for await line in lines(from: stderrPipe.fileHandleForReading) {
                await editorState.appendConsole(.stderr(line))
            }
        }
        active[request.taskID] = .localProcess(LocalProcessSession(process: process))
        do {
            try process.run()
        } catch {
            await editorState.appendConsole(.stderr("[ERROR] Could not launch \(request.kind.displayName): \(error.localizedDescription)"))
            await editorState.appendDiagnostic(SDKEditorDiagnostic(
                severity: .error, source: request.kind.displayName, code: "LAUNCH_FAILED",
                message: error.localizedDescription, fileURL: request.projectRoot))
            active.removeValue(forKey: request.taskID)
            streamTask.cancel()
            errorTask.cancel()
            return
        }
        process.waitUntilExit()
        await streamTask.value
        await errorTask.value
        active.removeValue(forKey: request.taskID)
        let status = process.terminationStatus
        await editorState.appendConsole(.system(
            "\(request.kind.displayName) exited with status \(status)."))
        if status != 0 {
            await editorState.appendDiagnostic(SDKEditorDiagnostic(
                severity: .error, source: request.kind.displayName, code: "BUILD_FAILED",
                message: "\(request.kind.displayName) exited with status \(status).",
                fileURL: request.projectRoot))
        }
    }

    /// Genuine cancellation: terminates the underlying build handle or
    /// local process for `taskID`.
    public func cancel(taskID: UUID) async {
        guard let entry = active[taskID] else { return }
        switch entry {
        case .managedBuild(let handle):
            await handle.cancel()
        case .localProcess(let session):
            session.process.terminate()
            // SIGTERM, then SIGKILL after the grace period if the pid still
            // exists. Only the pid crosses into the detached task: the
            // Process itself is not Sendable.
            let pid = session.process.processIdentifier
            Task {
                try? await Task.sleep(nanoseconds: Self.cancelGraceNanoseconds)
                if kill(pid, 0) == 0 {
                    kill(pid, SIGKILL)
                }
            }
        }
        active.removeValue(forKey: taskID)
    }

    public func isRunning(taskID: UUID) -> Bool { active[taskID] != nil }

    private func lines(from handle: FileHandle) -> AsyncStream<String> {
        AsyncStream { continuation in
            var buffer = Data()
            handle.readabilityHandler = { h in
                let chunk = h.availableData
                if chunk.isEmpty {
                    if !buffer.isEmpty, let text = String(data: buffer, encoding: .utf8) {
                        continuation.yield(text)
                    }
                    handle.readabilityHandler = nil
                    continuation.finish()
                    return
                }
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer[..<newline]
                    buffer.removeSubrange(..<buffer.index(after: newline))
                    if let line = String(data: lineData, encoding: .utf8) {
                        continuation.yield(line)
                    }
                }
            }
            continuation.onTermination = { _ in handle.readabilityHandler = nil }
        }
    }
}

// MARK: - Snippets
//
// Legacy: `SwiftCode/SDK/Studio/CodeEditor/Views/SDKCodeSnippetLibraryView.swift`
// (`SDKSnippet`, `SDKSnippetStore`, `SDKSnippetCodeVariant`,
// `SDKSnippetCategoryFilter`). Legacy loads `snippets.json` (generated from
// the TypeScript package) and synthesizes one snippet per canonical
// capability so every capability has runnable code. Ycode has no
// `snippets.json` yet, so the store synthesizes the same per-capability
// catalog from `SDKCapabilityID.allCases` and accepts an optional decoded
// `snippets.json` override (`loadAll(fromJSON:)`) with the same
// "first non-empty file wins, then fill gaps" rule. The generated
// TypeScript is starter code (import + capability request shape), not a
// verbatim copy of the TypeScript package's per-scope calls — that package
// is the Host/TS slice's to port exactly.

public enum SDKSnippetCodeVariant: String, CaseIterable, Identifiable, Sendable {
    case typescript = "TypeScript"
    case swift = "Swift"
    case manifest = "swiftcode.json"

    public var id: String { rawValue }
}

public enum SDKSnippetCategoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case project = "Project"
    case sourceControl = "Source Control"
    case build = "Build"
    case ui = "UI & Views"
    case security = "Security & AI"
    case ai = "AI"

    public var id: String { rawValue }

    public func matches(_ snippet: SDKSnippet) -> Bool {
        switch self {
        case .all: return true
        case .project:
            return snippet.capabilityId.hasPrefix("project.") || snippet.capabilityId.hasPrefix("workspace.")
                || snippet.capabilityId == "docs.search" || snippet.capabilityId == "symbols.browse"
                || snippet.capabilityId == "dictionary.open"
        case .sourceControl:
            return snippet.capabilityId.hasPrefix("source-control.")
        case .build:
            return snippet.capabilityId == "build.execute" || snippet.capabilityId == "task.execute"
                || snippet.capabilityId == "terminal.sandbox"
        case .ui:
            return (snippet.capabilityId.hasPrefix("ui.") || snippet.capabilityId == "preview.live"
                || snippet.capabilityId == "simulator.view" || snippet.capabilityId == "uibuilder.open"
                || snippet.capabilityId == "virtualization.view" || snippet.capabilityId == "deployConsole.view"
                || snippet.capabilityId == "db.ExploreView" || snippet.capabilityId == "ci.VisualWF"
                || snippet.capabilityId == "deviceconnect.open" || snippet.capabilityId == "use.SwiftCodeModel")
                && !snippet.capabilityId.hasPrefix("use.Security")
        case .security:
            return snippet.capabilityId.hasPrefix("use.Security") || snippet.capabilityId == "credentials.use"
                || snippet.capabilityId == "network.request"
        case .ai:
            return snippet.capabilityId == "use.SwiftCodeModel" || snippet.capabilityId == "assist.invoke"
        }
    }
}

public struct SDKSnippet: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let capabilityId: String
    public let tags: [String]
    public let code: String

    public init(id: String, title: String, description: String, capabilityId: String,
                tags: [String], code: String) {
        self.id = id
        self.title = title
        self.description = description
        self.capabilityId = capabilityId
        self.tags = tags
        self.code = code
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, description, capabilityId, tags, code
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedId = try container.decode(String.self, forKey: .id)
        let decodedTitle = try container.decode(String.self, forKey: .title)
        let decodedDescription = try container.decode(String.self, forKey: .description)
        let decodedCapId = try container.decode(String.self, forKey: .capabilityId)
        let decodedTags = try container.decode([String].self, forKey: .tags)
        let decodedCode = try container.decodeIfPresent(String.self, forKey: .code)
        self.id = decodedId
        self.title = decodedTitle
        self.description = decodedDescription
        self.capabilityId = decodedCapId
        self.tags = decodedTags
        if let c = decodedCode, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.code = c
        } else {
            self.code = Self.defaultTypeScriptCode(for: decodedCapId, title: decodedTitle)
        }
    }

    public var swiftCode: String { Self.defaultSwiftCode(for: capabilityId, title: title) }

    public var manifestDeclarationJSON: String {
        let escapedReason = description
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        {
          "id": "\(capabilityId)",
          "reason": "\(escapedReason)"
        }
        """
    }

    public func executableCode(for variant: SDKSnippetCodeVariant = .typescript) -> String {
        switch variant {
        case .typescript: return code
        case .swift: return swiftCode
        case .manifest: return manifestDeclarationJSON
        }
    }

    public static func defaultTypeScriptCode(for capabilityId: String, title: String) -> String {
        """
        import { sdk } from "@swiftcode/sdk";

        // \(title) — capability "\(capabilityId)".
        // Declare the capability in swiftcode.json, then request it at runtime.
        const granted = await sdk.capabilities.request("\(capabilityId)", {
          reason: "Needed for \(title.lowercased()).",
        });
        if (!granted) {
          throw new Error("Capability \(capabilityId) was not granted.");
        }
        """
    }

    public static func defaultSwiftCode(for capabilityId: String, title: String) -> String {
        """
        // \(title) — capability "\(capabilityId)".
        // Swift hosts declare the capability in swiftcode.json and request it
        // through the host capability broker before use.
        // Capability: \(capabilityId)
        """
    }
}

public enum SDKSnippetStore {
    /// One synthesized snippet per canonical SDK capability
    /// (`SDKCapabilityID.allCases`, 35 ids), so every capability has code.
    public static func builtInSnippets() -> [SDKSnippet] {
        SDKCapabilityID.allCases.map { cap in
            let syntheticID = cap.rawValue.lowercased().replacingOccurrences(of: ".", with: "-")
            let tags = cap.rawValue.split(separator: ".").map(String.init) + [cap.riskLevel]
            return SDKSnippet(id: syntheticID, title: cap.rawValue, description: "Capability \(cap.rawValue) (risk: \(cap.riskLevel)).",
                              capabilityId: cap.rawValue, tags: tags,
                              code: SDKSnippet.defaultTypeScriptCode(for: cap.rawValue, title: cap.rawValue))
        }
    }

    /// Loads a `snippets.json` catalog when one decodes non-empty, then
    /// fills gaps so every canonical capability is represented — the same
    /// rule as Legacy's `loadAll()`.
    public static func loadAll(fromJSON data: Data? = nil) -> [SDKSnippet] {
        var loaded: [SDKSnippet] = []
        if let data,
           let decoded = try? JSONDecoder().decode([SDKSnippet].self, from: data),
           !decoded.isEmpty {
            loaded = decoded
        }
        var seenCapabilityIDs = Set(loaded.map(\.capabilityId))
        var seenSnippetIDs = Set(loaded.map(\.id))
        for snippet in builtInSnippets() where !seenCapabilityIDs.contains(snippet.capabilityId) {
            var uniqueID = snippet.id
            if seenSnippetIDs.contains(uniqueID) { uniqueID = "cap-\(uniqueID)" }
            seenSnippetIDs.insert(uniqueID)
            seenCapabilityIDs.insert(snippet.capabilityId)
            loaded.append(SDKSnippet(id: uniqueID, title: snippet.title, description: snippet.description,
                                     capabilityId: snippet.capabilityId, tags: snippet.tags, code: snippet.code))
        }
        return loaded
    }

    public static func filter(_ snippets: [SDKSnippet], query: String,
                              category: SDKSnippetCategoryFilter = .all) -> [SDKSnippet] {
        let categoryFiltered = snippets.filter { category.matches($0) }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return categoryFiltered }
        return categoryFiltered.filter { snippet in
            snippet.id.lowercased().contains(trimmed)
                || snippet.title.lowercased().contains(trimmed)
                || snippet.description.lowercased().contains(trimmed)
                || snippet.capabilityId.lowercased().contains(trimmed)
                || snippet.tags.contains(where: { $0.lowercased().contains(trimmed) })
                || snippet.code.lowercased().contains(trimmed)
        }
    }
}
