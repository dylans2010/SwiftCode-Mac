import Foundation

public struct AgentContextBuilder: Sendable {
    public init() {}

    public func buildContext(messages: [AgentMessage], model: OpenRouterModel) async -> [AgentMessage] {
        // Heuristic character-based token approximation (Layer 3, Feature F11)
        let maxChars = model.contextLength * 4 // Rough estimate
        var currentChars = 0
        var result: [AgentMessage] = []

        // Include Skills (Layer 8.3)
        let skills = await SkillsRuntime.shared.getActiveSkillsContent()
        let systemContent = "You are the SwiftCode AI Agent.\n\nActive Skills:\n\(skills)"
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
}
