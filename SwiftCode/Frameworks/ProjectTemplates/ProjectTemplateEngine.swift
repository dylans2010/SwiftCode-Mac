import Foundation

public actor ProjectTemplateEngine {
    public static let shared = ProjectTemplateEngine()

    public func createProject(at url: URL, template: ProjectTemplate) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for file in template.files {
            let fileURL = url.appendingPathComponent(file.path)
            try file.content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
}

public protocol ProjectTemplate: Sendable {
    var name: String { get }
    var files: [TemplateFile] { get }
}

public struct TemplateFile: Sendable {
    public let path: String
    public let content: String
}
