import Foundation

public final class PromptEnhancer {
    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")
    private static let model = "openai/gpt-oss-120b:free"

    public static func enhancePrompt(userInput: String) async -> String {
        let trimmedInput = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return userInput }

        let systemPrompt = """
        You are an expert software architect. Rewrite vague user prompts into highly detailed, technically specific instructions for an autonomous coding agent.

        Rules:
        - Expand vague ideas into concrete steps
        - Specify frameworks and architecture
        - Infer missing details
        - Do not explain anything
        - Output must be directly executable
        """

        guard let apiKey = KeychainService.shared.get(forKey: KeychainService.openRouterAPIKey),
              !apiKey.isEmpty,
              let endpoint else {
            return userInput
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("SwiftCode Prompt Enhancer", forHTTPHeaderField: "X-Title")
        request.setValue("https://github.com/swiftcode/app", forHTTPHeaderField: "HTTP-Referer")

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "max_tokens": 1400,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": trimmedInput]
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return userInput
            }
            let decoded = try JSONDecoder().decode(PromptEnhancerResponse.self, from: data)
            let enhanced = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return enhanced.isEmpty ? userInput : enhanced
        } catch {
            return userInput
        }
    }
}

private struct PromptEnhancerResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }
        let message: Message
    }

    let choices: [Choice]
}
