import Foundation

public actor ImportManager {
    public init() {}

    public func importMarkdown(from url: URL) throws -> (title: String, content: String) {
        let text = try String(contentsOf: url, encoding: .utf8)
        let title = url.deletingPathExtension().lastPathComponent
        return (title: title, content: text)
    }
}
