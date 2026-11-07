import Foundation

public struct ExtV2TextPosition: Codable, Hashable, Sendable {
    public let line: Int
    public let character: Int
    public init(line: Int, character: Int) { self.line = line; self.character = character }
}

public struct ExtV2TextRange: Codable, Hashable, Sendable {
    public let start: ExtV2TextPosition
    public let end: ExtV2TextPosition
    public init(start: ExtV2TextPosition, end: ExtV2TextPosition) { self.start = start; self.end = end }
}

public struct ExtV2TextEdit: Codable, Hashable, Sendable {
    public let range: ExtV2TextRange
    public let newText: String
    public init(range: ExtV2TextRange, newText: String) { self.range = range; self.newText = newText }
}

public struct ExtV2DocumentState: Sendable {
    public let relativePath: String
    public let content: String
    public let selection: Range<Int>?
}

public protocol ExtV2DocumentStore: Sendable {
    func read(relativePath: String) throws -> String
    func write(relativePath: String, content: String) throws
}

public struct ExtV2FileDocumentStore: ExtV2DocumentStore {
    private let workspace: ExtV2WorkspaceBridge
    private let extensionId: String

    public init(workspace: ExtV2WorkspaceBridge, extensionId: String) {
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

public enum ExtV2EditorBridge {
    public static func applyEdits(_ edits: [ExtV2TextEdit], to content: String) throws -> String {
        var lines = content.components(separatedBy: "\n")
        let sorted = edits.sorted { lhs, rhs in
            if lhs.range.start.line != rhs.range.start.line { return lhs.range.start.line > rhs.range.start.line }
            return lhs.range.start.character > rhs.range.start.character
        }
        var previousStart: (line: Int, character: Int)?
        for edit in sorted {
            if let prev = previousStart {
                if edit.range.end.line > prev.line
                    || (edit.range.end.line == prev.line && edit.range.end.character > prev.character) {
                    throw ExtV2Error.invalidRequest("Overlapping text edits are not supported.")
                }
            }
            previousStart = (edit.range.start.line, edit.range.start.character)
            guard edit.range.start.line < lines.count, edit.range.end.line < lines.count else {
                throw ExtV2Error.invalidRequest("Text edit range is outside the document.")
            }
            let startLine = lines[edit.range.start.line]
            let endLine = lines[edit.range.end.line]
            guard edit.range.start.character <= startLine.count,
                  edit.range.end.character <= endLine.count else {
                throw ExtV2Error.invalidRequest("Text edit column is outside its line.")
            }
            let startIndex = startLine.index(startLine.startIndex, offsetBy: edit.range.start.character)
            let endIndex = endLine.index(endLine.startIndex, offsetBy: edit.range.end.character)
            let before = String(startLine[..<startIndex])
            let after = String(endLine[endIndex...])
            let replacementLines = (before + edit.newText + after).components(separatedBy: "\n")
            lines.replaceSubrange(edit.range.start.line...edit.range.end.line, with: replacementLines)
        }
        return lines.joined(separator: "\n")
    }

    public static func offset(for position: ExtV2TextPosition, in content: String) -> Int? {
        let lines = content.components(separatedBy: "\n")
        guard position.line < lines.count, position.character <= lines[position.line].count else { return nil }
        var offset = 0
        for index in 0..<position.line {
            offset += lines[index].count + 1
        }
        return offset + position.character
    }
}
