import Foundation

// MARK: - Code Execution Manager
// Manages code execution requests. On iOS, actual compilation is done via
// GitHub Actions or remote endpoints; this class queues and tracks requests.

enum ExecutionResult {
    case success(output: String)
    case failure(error: String)
    case notSupported(reason: String)
}

struct ExecutionRequest: Identifiable {
    let id = UUID()
    var code: String
    var language: String
    var projectName: String
    var createdAt: Date = Date()
    var result: ExecutionResult?
}

@MainActor
final class CodeExecutionManager: ObservableObject {
    static let shared = CodeExecutionManager()

    @Published var queue: [ExecutionRequest] = []
    @Published var isExecuting = false
    @Published var lastResult: ExecutionResult?

    private init() {}

    // MARK: - Submit

    func submit(code: String, language: String = "swift", projectName: String = "") async {
        let request = ExecutionRequest(
            code: code,
            language: language,
            projectName: projectName
        )
        queue.append(request)
        await process(request)
    }

    // MARK: - Process

    private func process(_ request: ExecutionRequest) async {
        isExecuting = true
        defer { isExecuting = false }

        // On iOS, we cannot run a Swift compiler directly.
        // We simulate or use a remote service.
        let result: ExecutionResult

        if request.language.lowercased() != "swift" {
            result = .notSupported(reason: "Only Swift execution is supported in this environment.")
        } else {
            // Attempt a lightweight syntax check using regex heuristics
            result = await performSyntaxCheck(code: request.code)
        }

        if let idx = queue.firstIndex(where: { $0.id == request.id }) {
            queue[idx].result = result
        }
        lastResult = result
    }

    // MARK: - Syntax Check (lightweight)

    private func performSyntaxCheck(code: String) async -> ExecutionResult {
        // Count braces as a trivial balance check (single pass)
        var opens = 0
        var closes = 0
        for ch in code {
            if ch == "{" { opens += 1 }
            else if ch == "}" { closes += 1 }
        }

        if opens != closes {
            let diff = abs(opens - closes)
            return .failure(error: "Unbalanced braces detected (\(diff) mismatch). Check your code structure.")
        }

        var parenO = 0
        var parenC = 0
        for ch in code {
            if ch == "(" { parenO += 1 }
            else if ch == ")" { parenC += 1 }
        }
        if parenO != parenC {
            return .failure(error: "Unbalanced parentheses detected.")
        }

        return .success(output: "Syntax check passed. Use GitHub Actions to compile and run on a real device.")
    }

    // MARK: - Clear

    func clearQueue() {
        queue.removeAll()
        lastResult = nil
    }
}
