import Foundation

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

public final class ExtV2SourceTextBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String]
    private var _selections: [ExtV2SourceRange]

    public var selections: [ExtV2SourceRange] {
        get { lock.lock(); defer { lock.unlock() }; return _selections }
        set { lock.lock(); defer { lock.unlock() }; _selections = newValue }
    }

    public init(lines: [String], selections: [ExtV2SourceRange] = []) {
        self._lines = lines
        self._selections = selections
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
    func perform(invocation: ExtV2SourceEditorInvocation) async throws
}

public final class ExtV2XcodeCommandRegistry: @unchecked Sendable {
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

public extension Notification.Name {
    static let ExtV2WorkspaceFileDidChange = Notification.Name("ExtV2WorkspaceFileDidChange")
}
