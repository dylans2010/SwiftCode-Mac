import Foundation

// MARK: - Xcode source-editor compatibility adapter
//
// Models Apple's XcodeKit types (XCSourceEditorExtension,
// XCSourceEditorCommand, XCSourceEditorCommandInvocation,
// XCSourceTextBuffer, XCSourceTextRange, XCSourceTextPosition) as
// SwiftCode-native value types, so reusable source-editor command
// logic written against XcodeKit's *shape* can run here without
// XcodeKit itself — and without claiming that Xcode-managed extension
// binaries can execute inside SwiftCode. They cannot: XcodeKit
// extensions are packaged, signed, and activated by Xcode. The four
// categories are kept distinct in the UI and docs:
//   1. SwiftCode-native plugins (this SDK / VS Code host)
//   2. Reusable source-editor command logic (this adapter)
//   3. XcodeKit extension binaries (run under Xcode only)
//   4. External developer tools (documented interfaces, e.g. SourceKit-LSP)
//
// Positions are 0-based (line, column), following XcodeKit convention.
// Columns count Swift Characters (grapheme clusters), so an emoji is
// one column, not two UTF-16 units — verified by tests.

public struct ExtV2SourcePosition: Codable, Hashable, Sendable, Comparable {
    public let line: Int
    public let column: Int
    public init(line: Int, column: Int) { self.line = line; self.column = column }
    public static func < (lhs: ExtV2SourcePosition, rhs: ExtV2SourcePosition) -> Bool {
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        return lhs.column < rhs.column
    }
}

public struct ExtV2SourceRange: Codable, Hashable, Sendable {
    public let start: ExtV2SourcePosition
    public let end: ExtV2SourcePosition
    public init(start: ExtV2SourcePosition, end: ExtV2SourcePosition) { self.start = start; self.end = end }
    public var isEmpty: Bool { start == end }
}

/// A mutable text buffer mirroring XCSourceTextBuffer: lines plus the
/// current selections. `completeBuffer` is the joined text; edits go
/// through `applyEdits`, which validates ranges before touching text.
public final class ExtV2SourceTextBuffer: Sendable {
    private let lock = NSLock()
    private var _lines: [String]
    public var selections: [ExtV2SourceRange]

    public init(lines: [String], selections: [ExtV2SourceRange] = []) {
        self._lines = lines
        self.selections = selections
    }

    public convenience init(text: String, selections: [ExtV2SourceRange] = []) {
        self.init(lines: text.components(separatedBy: "\n"), selections: selections)
    }

    public var lines: [String] {
        lock.lock(); defer { lock.unlock() }
        return _lines
    }

    public var completeBuffer: String {
        lines.joined(separator: "\n")
    }

    public struct Edit: Sendable {
        public let range: ExtV2SourceRange
        public let newText: String
        public init(range: ExtV2SourceRange, newText: String) { self.range = range; self.newText = newText }
    }

    /// Applies edits atomically: all ranges are validated first, then
    /// applied in reverse order. Any failure leaves the buffer untouched.
    /// Overlapping ranges, out-of-bounds lines/columns, and reversed
    /// ranges are errors, not best-effort edits.
    public func applyEdits(_ edits: [Edit]) throws {
        lock.lock(); defer { lock.unlock() }
        var lines = _lines
        for edit in edits {
            guard edit.range.start <= edit.range.end else {
                throw ExtV2Error.invalidRequest("Source edit range is reversed.")
            }
            guard edit.range.start.line < lines.count, edit.range.end.line < lines.count else {
                throw ExtV2Error.invalidRequest("Source edit line is outside the buffer.")
            }
            guard edit.range.start.column <= lines[edit.range.start.line].count,
                  edit.range.end.column <= lines[edit.range.end.line].count else {
                throw ExtV2Error.invalidRequest("Source edit column is outside its line.")
            }
        }
        let sorted = edits.sorted { lhs, rhs in
            if lhs.range.start.line != rhs.range.start.line { return lhs.range.start.line > rhs.range.start.line }
            return lhs.range.start.column > rhs.range.start.column
        }
        var previousStart: ExtV2SourcePosition?
        for edit in sorted {
            if let prev = previousStart,
               edit.range.end > prev {
                throw ExtV2Error.invalidRequest("Overlapping source edits are not supported.")
            }
            previousStart = edit.range.start
            let startLine = lines[edit.range.start.line]
            let endLine = lines[edit.range.end.line]
            let startIndex = startLine.index(startLine.startIndex, offsetBy: edit.range.start.column)
            let endIndex = endLine.index(endLine.startIndex, offsetBy: edit.range.end.column)
            let replacement = (String(startLine[..<startIndex]) + edit.newText + String(endLine[endIndex...]))
                .components(separatedBy: "\n")
            lines.replaceSubrange(edit.range.start.line...edit.range.end.line, with: replacement)
        }
        _lines = lines
    }
}

/// Invocation handed to a command: the buffer, plus a cancellation
/// check. Cancellation is cooperative and checked by the command via
/// `Task.checkCancellation()` — a command that ignores cancellation
/// still finishes, it just cannot be force-stopped mid-edit, and its
/// edits are still validated before they land.
public struct ExtV2SourceEditorInvocation: Sendable {
    public let buffer: ExtV2SourceTextBuffer
    public let commandIdentifier: String
    public let uti: String

    public init(buffer: ExtV2SourceTextBuffer, commandIdentifier: String, uti: String = "public.swift-source") {
        self.buffer = buffer; self.commandIdentifier = commandIdentifier; self.uti = uti
    }

    public func checkCancellation() throws {
        try Task.checkCancellation()
    }
}

public protocol ExtV2SourceEditorCommand: Sendable {
    var identifier: String { get }
    var title: String { get }
    /// Performs the command. Returning means success; throwing means
    /// the command failed and the buffer is unchanged for *that*
    /// command's edits (edits are applied through the buffer, which
    /// validates before committing each batch).
    func perform(invocation: ExtV2SourceEditorInvocation) async throws
}

/// Registry for reusable command logic. Commands are looked up by
/// identifier — the same stable-key discipline as the rest of the
/// platform — and executed against a caller-supplied buffer.
public final class ExtV2XcodeCommandRegistry: Sendable {
    public static let shared = ExtV2XcodeCommandRegistry()
    private let lock = NSLock()
    private var commands: [String: any ExtV2SourceEditorCommand] = [:]

    public init() {}

    public func register(_ command: any ExtV2SourceEditorCommand) {
        lock.lock(); defer { lock.unlock() }
        commands[command.identifier] = command
    }

    public func command(for identifier: String) -> (any ExtV2SourceEditorCommand)? {
        lock.lock(); defer { lock.unlock() }
        return commands[identifier]
    }

    public var allIdentifiers: [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(commands.keys).sorted()
    }

    public func perform(identifier: String, buffer: ExtV2SourceTextBuffer) async throws {
        guard let command = command(for: identifier) else {
            throw ExtV2Error.invalidRequest("No Xcode-compatible command '\(identifier)' is registered.")
        }
        try await command.perform(invocation: ExtV2SourceEditorInvocation(buffer: buffer, commandIdentifier: identifier))
    }
}

/// Example reusable command (also the test fixture): sorts the lines
/// covered by the first selection, leaving everything else untouched.
public struct ExtV2SortLinesCommand: ExtV2SourceEditorCommand {
    public let identifier = "com.swiftcode.xcode.sortLines"
    public let title = "Sort Lines"
    public init() {}

    public func perform(invocation: ExtV2SourceEditorInvocation) async throws {
        try invocation.checkCancellation()
        guard let selection = invocation.buffer.selections.first else { return }
        let lines = invocation.buffer.lines
        guard selection.start.line < lines.count, selection.end.line < lines.count else {
            throw ExtV2Error.invalidRequest("Selection is outside the buffer.")
        }
        let sorted = lines[selection.start.line...selection.end.line].sorted()
        let range = ExtV2SourceRange(
            start: ExtV2SourcePosition(line: selection.start.line, column: 0),
            end: ExtV2SourcePosition(line: selection.end.line, column: lines[selection.end.line].count))
        try invocation.buffer.applyEdits([
            ExtV2SourceTextBuffer.Edit(range: range, newText: sorted.joined(separator: "\n"))
        ])
    }
}
