import SwiftUI

/// Loads the detected SwiftUI root view and converts it into a runtime-compatible
/// container that can be safely rendered inside the IDE.
@MainActor
final class SwiftUIRuntimeLoader {

    struct RuntimeContainer: Identifiable {
        let id = UUID()
        let rootViewName: String
        let projectName: String
        let sourceFiles: [URL]
        /// The source content of the root view file, used to render a code-based preview.
        let rootViewSource: String?
    }

    /// Builds a runtime container from the prepared preview context.
    func load(from context: PreviewEngine.PreviewContext) -> RuntimeContainer {
        let projectName = context.projectDirectory.lastPathComponent

        // Attempt to read the source of the root view file for display
        let rootViewSource = findRootViewSource(
            named: context.rootViewName,
            in: context.swiftFiles
        )

        return RuntimeContainer(
            rootViewName: context.rootViewName,
            projectName: projectName,
            sourceFiles: context.swiftFiles,
            rootViewSource: rootViewSource
        )
    }

    /// Searches the project Swift files for the source of the root view.
    private func findRootViewSource(named viewName: String, in files: [URL]) -> String? {
        // Use a regex with word boundaries to avoid matching view names that appear in
        // comments, string literals, or as substrings of other type names.
        guard let regex = try? NSRegularExpression(
            pattern: #"\bstruct\s+"# + NSRegularExpression.escapedPattern(for: viewName) + #"\s*:\s*\w*\s*View\b"#
        ) else { return nil }

        for fileURL in files {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let range = NSRange(content.startIndex..., in: content)
            if regex.firstMatch(in: content, range: range) != nil {
                return content
            }
        }
        return nil
    }
}
