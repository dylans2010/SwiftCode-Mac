import Foundation

// MARK: - SDKConsoleStream
//
// The output stream a console entry was captured from. `system` covers
// editor-generated status lines (build started, process exited, errors
// from the host itself) rather than child-process output.

public enum SDKConsoleStream: String, Sendable, Codable, CaseIterable, Hashable {
    case stdout
    case stderr
    case system
}

// MARK: - SDKConsoleEntry
//
// One line (or chunk) of console output in the editor's console panel.
// `text` is BOUNDED: producers must not append unbounded strings —
// `SDKCodeEditorState.appendConsole(_:)` truncates to `maxTextLength`
// (4 KiB) and drops the entry count cap overflow (5,000 entries, oldest
// first). These bounds keep the console a diagnostic surface, not a
// memory leak.

public struct SDKConsoleEntry: Identifiable, Sendable, Hashable {
    /// Maximum characters kept per entry. Longer text is truncated at this
    /// bound (with an ellipsis marker) by `SDKCodeEditorState`.
    public static let maxTextLength: Int = 4_096

    public let id: UUID
    public let timestamp: Date
    public let stream: SDKConsoleStream
    public let text: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        stream: SDKConsoleStream,
        text: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.stream = stream
        self.text = text
    }

    /// Convenience for editor-generated status lines (stream = `.system`).
    public static func system(_ text: String, at date: Date = Date()) -> SDKConsoleEntry {
        SDKConsoleEntry(timestamp: date, stream: .system, text: text)
    }

    /// Convenience for child-process stdout.
    public static func stdout(_ text: String, at date: Date = Date()) -> SDKConsoleEntry {
        SDKConsoleEntry(timestamp: date, stream: .stdout, text: text)
    }

    /// Convenience for child-process stderr.
    public static func stderr(_ text: String, at date: Date = Date()) -> SDKConsoleEntry {
        SDKConsoleEntry(timestamp: date, stream: .stderr, text: text)
    }
}
