import Foundation

struct CodexRequestBuilder {
    let systemPrompt = "You are OpenAI Codex acting as the primary execution engine for SwiftCode. Produce concrete, developer-focused output, respect the current task, and prefer safe, precise actions. Never repeat or paraphrase the user's request unless explicitly asked to quote it. Start directly with the answer, plan, or code."

    func makeRequest(model: String, prompt: String, session: CodexSession, taskType: CodexTaskType, stream: Bool) throws -> URLRequest {
        guard let url = URL(string: "https://api.openai.com/v1/responses") else {
            throw LLMError.networkError("Invalid OpenAI URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let responseInput = buildInput(prompt: prompt, session: session, taskType: taskType)
        let payload: [String: Any] = [
            "model": model,
            "input": responseInput,
            "reasoning": ["effort": "medium"],
            "text": ["verbosity": "medium"],
            "store": false,
            "stream": stream
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    private func buildInput(prompt: String, session: CodexSession, taskType: CodexTaskType) -> [[String: Any]] {
        var items: [[String: Any]] = [[
            "role": "system",
            "content": [["type": "input_text", "text": "\(systemPrompt) Task type: \(taskType.rawValue)."]]
        ]]

        for message in session.messages.suffix(10) {
            items.append([
                "role": message.role,
                "content": [["type": "input_text", "text": message.content]]
            ])
        }

        items.append([
            "role": "user",
            "content": [["type": "input_text", "text": prompt]]
        ])
        return items
    }
}
