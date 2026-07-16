import Foundation

public struct AgentContextBuilder: Sendable {
    public init() {}

    public func buildContext(messages: [AgentMessage], model: OpenRouterModel, includeCodebaseContext: Bool = true) async -> [AgentMessage] {
        // Heuristic character-based token approximation (Layer 3, Feature F11)
        let maxChars = (model.contextLength ?? 128000) * 4 // Rough estimate
        var currentChars = 0
        var result: [AgentMessage] = []

        var systemContent = "You are the SwiftCode AI Agent.\n\n"

        if includeCodebaseContext, let lastUserMessage = messages.last(where: { $0.role == .user }) {
            // Extract the user's text from content
            let queryText = lastUserMessage.content.compactMap { content -> String? in
                if case .text(let text) = content { return text }
                return nil
            }.joined(separator: " ")

            let codebaseContext = await gatherCodebaseContext(for: queryText)
            systemContent += codebaseContext
        }

        // Include Skills (Layer 8.3)
        let skills = await SkillsRuntime.shared.getActiveSkillsContent()
        systemContent += "\nActive Skills:\n\(skills)"

        let systemMessage = AgentMessage(role: .system, content: [.text(systemContent)])

        result.append(systemMessage)
        currentChars += systemContent.count

        // Truncate oldest non-essential turns first
        for message in messages.dropFirst().reversed() {
            let messageSize = (try? JSONEncoder().encode(message).count) ?? 0
            if currentChars + messageSize < maxChars {
                result.insert(message, at: result.count > 0 ? 1 : 0)
                currentChars += messageSize
            } else {
                break
            }
        }

        return result
    }

    public func gatherCodebaseContext(for query: String) async -> String {
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        // Find keywords in query (alphanumeric words larger than 3 characters)
        let keywords = query.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 }
            .prefix(5)

        var gatheredFiles: [String: String] = [:]

        for keyword in keywords {
            let results = await CodeIndexService.shared.searchProject(query: keyword, at: projectRoot)
            for result in results.prefix(3) {
                if gatheredFiles.count >= 5 { break }
                let fileURL = projectRoot.appendingPathComponent(result.filePath)
                if gatheredFiles[result.filePath] == nil,
                   let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    // Limit individual file content to 4000 characters to prevent huge context bloat
                    gatheredFiles[result.filePath] = String(content.prefix(4000))
                }
            }
        }

        if gatheredFiles.isEmpty {
            return ""
        }

        var context = "\n--- RELEVANT CODEBASE CONTEXT ---\n"
        for (path, content) in gatheredFiles {
            context += "\nFile: \(path)\n"
            context += "```\n\(content)\n```\n"
        }
        context += "---------------------------------\n"
        return context
    }
}
