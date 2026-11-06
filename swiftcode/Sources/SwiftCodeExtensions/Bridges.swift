import Foundation
import SwiftCodeSubprocess

// MARK: - Text / editor bridge (spec §8.2)

public struct TextPosition: Codable, Hashable, Sendable {
    public let line: Int
    public let character: Int

    public init(line: Int, character: Int) {
        self.line = line
        self.character = character
    }
}

public struct TextRange: Codable, Hashable, Sendable {
    public let start: TextPosition
    public let end: TextPosition

    public init(start: TextPosition, end: TextPosition) {
        self.start = start
        self.end = end
    }
}

public struct TextEdit: Codable, Hashable, Sendable {
    public let range: TextRange
    public let newText: String

    public init(range: TextRange, newText: String) {
        self.range = range
        self.newText = newText
    }
}

public struct DocumentState: Sendable {
    public let relativePath: String
    public let content: String
    public let selection: Range<Int>?

    public init(relativePath: String, content: String, selection: Range<Int>? = nil) {
        self.relativePath = relativePath
        self.content = content
        self.selection = selection
    }
}

public protocol DocumentStore: Sendable {
    func read(relativePath: String) throws -> String
    func write(relativePath: String, content: String) throws
}

public struct FileDocumentStore: DocumentStore {
    private let workspace: WorkspaceBridge
    private let extensionId: String

    public init(workspace: WorkspaceBridge, extensionId: String) {
        self.workspace = workspace
        self.extensionId = extensionId
    }

    public func read(relativePath: String) throws -> String {
        try workspace.readFile(relativePath: relativePath, extensionId: extensionId)
    }

    public func write(relativePath: String, content: String) throws {
        try workspace.writeFile(relativePath: relativePath, content: content, extensionId: extensionId)
    }
}

public enum EditorBridge {
    /// Lines/characters 0-based; characters are Swift Characters
    /// (grapheme clusters). Overlapping edits are rejected, not merged;
    /// out-of-range lines/columns are rejected; edits are applied in
    /// reverse order so earlier ranges stay valid. Multi-line
    /// replacement text is supported. Trailing-newline round-trip is
    /// preserved by the components/join behaviour.
    ///
    /// Honest limit (spec §8.2): an edit is a file write plus a
    /// document-changed notification; it does NOT reach into the
    /// editor's undo stack.
    public static func applyEdits(_ edits: [TextEdit], to content: String) throws -> String {
        var lines = content.components(separatedBy: "\n")
        let sorted = edits.sorted { lhs, rhs in
            if lhs.range.start.line != rhs.range.start.line { return lhs.range.start.line < rhs.range.start.line }
            return lhs.range.start.character < rhs.range.start.character
        }
        // Validate all ranges first, and reject overlaps.
        var previousEnd: TextPosition?
        for edit in sorted {
            try validate(range: edit.range, in: lines)
            if let previousEnd, !isOrdered(previousEnd, beforeOrAt: edit.range.start) {
                throw SwiftCodeExtensionError.invalidRequest("Text edits overlap.")
            }
            previousEnd = edit.range.end
        }
        // Apply in reverse order.
        for edit in sorted.reversed() {
            try apply(edit, to: &lines)
        }
        return lines.joined(separator: "\n")
    }

    public static func offset(for position: TextPosition, in content: String) -> Int? {
        let lines = content.components(separatedBy: "\n")
        guard position.line >= 0, position.line < lines.count else { return nil }
        guard position.character >= 0, position.character <= lines[position.line].count else { return nil }
        var offset = 0
        for index in 0..<position.line { offset += lines[index].count + 1 }
        return offset + position.character
    }

    private static func isOrdered(_ lhs: TextPosition, beforeOrAt rhs: TextPosition) -> Bool {
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        return lhs.character <= rhs.character
    }

    private static func validate(range: TextRange, in lines: [String]) throws {
        guard range.start.line >= 0, range.start.line < lines.count,
              range.end.line >= 0, range.end.line < lines.count else {
            throw SwiftCodeExtensionError.invalidRequest("Text edit range is out of bounds.")
        }
        guard range.start.character >= 0, range.start.character <= lines[range.start.line].count,
              range.end.character >= 0, range.end.character <= lines[range.end.line].count else {
            throw SwiftCodeExtensionError.invalidRequest("Text edit column is out of bounds.")
        }
        guard isOrdered(range.start, beforeOrAt: range.end) else {
            throw SwiftCodeExtensionError.invalidRequest("Text edit range is reversed.")
        }
    }

    private static func apply(_ edit: TextEdit, to lines: inout [String]) throws {
        let start = edit.range.start
        let end = edit.range.end
        let startLine = lines[start.line]
        let endLine = lines[end.line]
        let prefix = String(startLine.prefix(start.character))
        let suffix = String(endLine.suffix(endLine.count - end.character))
        let replacement = (prefix + edit.newText + suffix).components(separatedBy: "\n")
        lines.replaceSubrange(start.line...end.line, with: replacement)
    }
}

// MARK: - Workspace bridge (spec §8.1)

public struct WorkspaceFile: Sendable {
    public let relativePath: String
    public let isDirectory: Bool

    public init(relativePath: String, isDirectory: Bool) {
        self.relativePath = relativePath
        self.isDirectory = isDirectory
    }
}

/// The **only** path by which extension-host code touches the file
/// system. Capability-gated on every call.
public final class WorkspaceBridge: Sendable {
    public let root: URL
    private let permissions: PermissionManager

    public init(root: URL, permissions: PermissionManager) {
        self.root = root
        self.permissions = permissions
    }

    /// Rejects absolute paths; resolves symlinks on both the candidate
    /// and the root and requires the resolved path to equal the root or
    /// sit under it. A workspace-relative path that resolves outside
    /// the root is rejected even if it looks relative.
    public func resolvedPath(for relativePath: String, extensionId: String) throws -> URL {
        guard !relativePath.hasPrefix("/") else {
            throw SwiftCodeExtensionError.invalidRequest("Path '\(relativePath)' must be workspace-relative.")
        }
        let candidate = root.appendingPathComponent(relativePath).standardized
        let resolvedRoot = root.resolvingSymlinksInPath().standardized
        let resolved = candidate.resolvingSymlinksInPath().standardized
        guard resolved.path == resolvedRoot.path || resolved.path.hasPrefix(resolvedRoot.path + "/") else {
            throw SwiftCodeExtensionError.invalidRequest("Path '\(relativePath)' escapes the workspace.")
        }
        return resolved
    }

    /// Requires `workspaceRead`; recursive enumeration skipping hidden
    /// files, capped at 20,000 entries (silently stops, does not error).
    public func listFiles(extensionId: String) throws -> [WorkspaceFile] {
        try permissions.check(extensionId: extensionId, capability: .workspaceRead)
        var files: [WorkspaceFile] = []
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        for case let url as URL in enumerator {
            if files.count >= 20_000 { break }
            if url.lastPathComponent.hasPrefix(".") { continue }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            files.append(WorkspaceFile(relativePath: relative, isDirectory: isDirectory))
        }
        return files
    }

    public func readFile(relativePath: String, extensionId: String) throws -> String {
        try permissions.check(extensionId: extensionId, capability: .workspaceRead)
        let url = try resolvedPath(for: relativePath, extensionId: extensionId)
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw SwiftCodeExtensionError.unknown("Could not read '\(relativePath)': \(error.localizedDescription)")
        }
    }

    public func writeFile(relativePath: String, content: String, extensionId: String) throws {
        try permissions.check(extensionId: extensionId, capability: .workspaceWrite)
        let url = try resolvedPath(for: relativePath, extensionId: extensionId)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw SwiftCodeExtensionError.unknown("Could not write '\(relativePath)': \(error.localizedDescription)")
        }
        DiagnosticsService.shared.info("Extension '\(extensionId)' wrote '\(relativePath)'.", extensionId: extensionId)
    }

    /// Requires `sourceControl`; runs the real `/usr/bin/git -C <root>
    /// status --short`. Read-only; no other git command is exposed.
    public func gitStatus(extensionId: String) throws -> String {
        try permissions.check(extensionId: extensionId, capability: .sourceControl)
        let output: Subprocess.Output
        do {
            output = try Subprocess.run("/usr/bin/git", ["-C", root.path, "status", "--short"])
        } catch {
            throw SwiftCodeExtensionError.unknown("Could not run git status: \(error.localizedDescription)")
        }
        guard output.status == 0 else {
            throw SwiftCodeExtensionError.unknown("git status failed: \(output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return output.stdoutText
    }
}

// MARK: - Xcode source-editor compatibility (spec §7.4)

/// Positions are **0-based (line, column)**; columns count Swift
/// Characters / grapheme clusters — an emoji is one column, not two
/// UTF-16 units.
public struct SourcePosition: Codable, Hashable, Sendable, Comparable {
    public let line: Int
    public let column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }

    public static func < (lhs: SourcePosition, rhs: SourcePosition) -> Bool {
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        return lhs.column < rhs.column
    }
}

public struct SourceRange: Codable, Hashable, Sendable {
    public let start: SourcePosition
    public let end: SourcePosition

    public init(start: SourcePosition, end: SourcePosition) {
        self.start = start
        self.end = end
    }

    public var isEmpty: Bool { start == end }
}

public final class SourceTextBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String]
    public var selections: [SourceRange]

    public init(lines: [String], selections: [SourceRange] = []) {
        self._lines = lines
        self.selections = selections
    }

    public convenience init(text: String, selections: [SourceRange] = []) {
        self.init(lines: text.components(separatedBy: "\n"), selections: selections)
    }

    public var lines: [String] {
        lock.lock(); defer { lock.unlock() }
        return _lines
    }

    public var completeBuffer: String { lines.joined(separator: "\n") }

    public struct Edit: Sendable {
        public let range: SourceRange
        public let newText: String

        public init(range: SourceRange, newText: String) {
            self.range = range
            self.newText = newText
        }
    }

    /// Validates **all** ranges first — reversed ranges, out-of-bounds
    /// lines/columns, overlapping ranges are errors — then applies in
    /// reverse order; any failure leaves the buffer untouched.
    public func applyEdits(_ edits: [Edit]) throws {
        lock.lock()
        defer { lock.unlock() }
        let sorted = edits.sorted { $0.range.start < $1.range.start }
        var previousEnd: SourcePosition?
        for edit in sorted {
            guard edit.range.start.line >= 0, edit.range.start.line < _lines.count,
                  edit.range.end.line >= 0, edit.range.end.line < _lines.count else {
                throw SwiftCodeExtensionError.invalidRequest("Source edit range is out of bounds.")
            }
            guard edit.range.start.column >= 0, edit.range.start.column <= _lines[edit.range.start.line].count,
                  edit.range.end.column >= 0, edit.range.end.column <= _lines[edit.range.end.line].count else {
                throw SwiftCodeExtensionError.invalidRequest("Source edit column is out of bounds.")
            }
            guard edit.range.start <= edit.range.end else {
                throw SwiftCodeExtensionError.invalidRequest("Source edit range is reversed.")
            }
            if let previousEnd, previousEnd > edit.range.start {
                throw SwiftCodeExtensionError.invalidRequest("Source edits overlap.")
            }
            previousEnd = edit.range.end
        }
        for edit in sorted.reversed() {
            let start = edit.range.start
            let end = edit.range.end
            let prefix = String(_lines[start.line].prefix(start.column))
            let suffix = String(_lines[end.line].suffix(_lines[end.line].count - end.column))
            let replacement = (prefix + edit.newText + suffix).components(separatedBy: "\n")
            _lines.replaceSubrange(start.line...end.line, with: replacement)
        }
    }
}

public struct SourceEditorInvocation: Sendable {
    public let buffer: SourceTextBuffer
    public let commandIdentifier: String
    public let uti: String

    public init(buffer: SourceTextBuffer, commandIdentifier: String, uti: String = "public.swift-source") {
        self.buffer = buffer
        self.commandIdentifier = commandIdentifier
        self.uti = uti
    }

    public func checkCancellation() throws {
        try Task.checkCancellation()
    }
}

public protocol SourceEditorCommand: Sendable {
    var identifier: String { get }
    var title: String { get }
    func perform(invocation: SourceEditorInvocation) async throws
}

public final class XcodeCommandRegistry: @unchecked Sendable {
    public static let shared = XcodeCommandRegistry()

    private let lock = NSLock()
    private var commands: [String: any SourceEditorCommand] = [:]

    public init() {
        // The sort-lines command is available from app start.
        commands[SortLinesCommand().identifier] = SortLinesCommand()
    }

    public func register(_ command: any SourceEditorCommand) {
        lock.lock(); defer { lock.unlock() }
        commands[command.identifier] = command
    }

    public func command(for identifier: String) -> (any SourceEditorCommand)? {
        lock.lock(); defer { lock.unlock() }
        return commands[identifier]
    }

    /// Sorted identifiers.
    public var allIdentifiers: [String] {
        lock.lock(); defer { lock.unlock() }
        return commands.keys.sorted()
    }

    public func perform(identifier: String, buffer: SourceTextBuffer) async throws {
        guard let command = command(for: identifier) else {
            throw SwiftCodeExtensionError.invalidRequest(
                "Unknown Xcode command '\(identifier)'. Registered commands: \(allIdentifiers.joined(separator: ", ")).")
        }
        try await command.perform(invocation: SourceEditorInvocation(buffer: buffer, commandIdentifier: identifier))
    }
}

/// Built-in example and test fixture: sorts the lines covered by the
/// first selection, leaving everything else untouched; no selection →
/// no-op (returns successfully).
public struct SortLinesCommand: SourceEditorCommand {
    public let identifier: String = "com.swiftcode.xcode.sortLines"
    public let title: String = "Sort Lines"

    public init() {}

    public func perform(invocation: SourceEditorInvocation) async throws {
        guard let selection = invocation.buffer.selections.first, !selection.isEmpty else { return }
        let lines = invocation.buffer.lines
        guard selection.start.line >= 0, selection.end.line < lines.count else { return }
        let sorted = lines[selection.start.line...selection.end.line].sorted()
        let edit = SourceTextBuffer.Edit(
            range: SourceRange(
                start: SourcePosition(line: selection.start.line, column: 0),
                end: SourcePosition(line: selection.end.line, column: lines[selection.end.line].count)),
            newText: sorted.joined(separator: "\n"))
        try invocation.buffer.applyEdits([edit])
    }
}
