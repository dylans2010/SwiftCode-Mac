import Foundation

public actor TextBufferEngine {
    public static let shared = TextBufferEngine()

    public func load(url: URL) throws -> String {
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func save(content: String, to url: URL) throws {
        try content.write(to: url, options: .atomic, encoding: .utf8)
    }
}
