// Ported from Legacy `SwiftCode/Frameworks/TextBuffer/TextBufferEngine.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Verbatim. Used by FullAppRunManager.saveAllEditorBuffers().

import Foundation

public actor TextBufferEngine {
    public static let shared = TextBufferEngine()

    public func load(url: URL) throws -> String {
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func save(content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
