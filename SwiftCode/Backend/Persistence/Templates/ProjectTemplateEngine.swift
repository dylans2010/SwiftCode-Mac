import Foundation

public actor ProjectScaffoldTemplateEngine {
    public static let shared = ProjectScaffoldTemplateEngine()

    public func createProject(at url: URL, template: any ProjectScaffoldTemplate) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for file in template.files {
            let fileURL = url.appendingPathComponent(file.path)
            try file.content.write(to: fileURL, options: .atomic, encoding: .utf8)
        }
    }
}

public protocol ProjectScaffoldTemplate: Sendable {
    var name: String { get }
    var description: String { get }
    var icon: String { get }
    var files: [TemplateFile] { get }
}

public struct TemplateFile: Sendable {
    public let path: String
    public let content: String
}
