import Foundation

public struct AgentContextBuilder: Sendable {
    public init() {}

    public static func keywords(for query: String) -> [String] {
        Array(query.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 }
            .prefix(5))
    }

    public func gatherCodebaseContext(for query: String, projectRoot: URL) async -> String {
        let keywords = Self.keywords(for: query)
        guard !keywords.isEmpty else { return "" }

        var gatheredFiles: [String: String] = [:]
        let enumerator = FileManager.default.enumerator(
            at: projectRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        var swiftFiles: [URL] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            let isRegular = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            guard isRegular else { continue }
            swiftFiles.append(fileURL)
        }

        for keyword in keywords {
            var matches = 0
            for fileURL in swiftFiles where matches < 3 {
                if gatheredFiles.count >= 5 { break }
                let relative = fileURL.path.hasPrefix(projectRoot.path + "/")
                    ? String(fileURL.path.dropFirst(projectRoot.path.count + 1))
                    : fileURL.lastPathComponent
                guard gatheredFiles[relative] == nil else { continue }
                guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
                      content.localizedCaseInsensitiveContains(keyword) else { continue }
                gatheredFiles[relative] = String(content.prefix(4000))
                matches += 1
            }
        }

        if gatheredFiles.isEmpty { return "" }

        var context = "\n--- RELEVANT CODEBASE CONTEXT ---\n"
        for (path, content) in gatheredFiles.sorted(by: { $0.key < $1.key }) {
            context += "\nFile: \(path)\n"
            context += "```\n\(content)\n```\n"
        }
        context += "---------------------------------\n"
        return context
    }

    public func activeSkillsContent() async -> String {
        let skills = await SkillsRuntime.shared.getActiveSkillsContent()
        return "\nActive Skills:\n\(skills)"
    }
}
