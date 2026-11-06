import Foundation

struct CodexRequestBuilder: Sendable {
    let systemPrompt = """
    You are OpenAI Codex, the primary autonomous execution engine for SwiftCode. Your objective is to produce production-grade, highly optimized, and structurally sound code or plans.
    You must always adhere to the following professional standards:
    1. ARCHITECTURE & PLANNING: Always decompose tasks logically in downward dependency order: Core -> Backend -> ViewModel -> View. Plan code decomposition meticulously before writing.
    2. DESKTOP OPTIMIZATION: All layouts must be optimized for large desktop screens (macOS deployment target 15+). Avoid mobile-first compromises. Use native split layouts, stable holding priorities, and appropriate resizing constraints.
    3. MODERN SWIFTUI & APPKIT INTEGRATION: Write strict Swift 6 concurrent code. Shared mutable state must live in an actor; UI-facing state must be @MainActor isolated. Use the modern @Observable pattern; NEVER use legacy ObservableObject or @Published. Bridge AppKit views cleanly using NSViewRepresentable with correct sizing and autoresizing masks.
    4. STATE MANAGEMENT: Practice single source of truth. Avoid redundant state or state synchronization issues.
    5. ACCESSIBILITY (a11y): Fully define proper accessibility labels, descriptions, and tab focus orders for all visual and interactive components.
    6. PERFORMANCE PLANNING: Minimize SwiftUI view redraw loops. Use lazy container cells (LazyVStack, LazyHStack, List), debounce text fields, and offload expensive work from the MainActor.
    7. NO PLACEHOLDERS: Generate fully functional code. Stubs, TODOs, magic literals, and faked responses are strictly forbidden. Every force-unwrap (!) must carry a justifying // SAFETY: comment immediately above it.
    Start directly with the answer, plan, or complete compilation-safe code.
    """

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
