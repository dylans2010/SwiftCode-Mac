import Foundation

/// A genuinely empty project template with zero starter files.
/// Conforms to `ProjectScaffoldTemplate` with an empty file array.
public struct EmptyTemplate: ProjectScaffoldTemplate {
    public let name = "Empty"
    public let description = "A completely blank project with no starter files. Perfect for building from scratch."
    public let icon = "square.dashed"
    public let files: [TemplateFile] = []

    public init() {}
}
