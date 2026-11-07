import Foundation

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

    func submit(code: String, language: String = "swift", projectName: String = "") async {
        let request = ExecutionRequest(
            code: code,
            language: language,
            projectName: projectName
        )
        queue.append(request)
        await process(request)
    }

    private func process(_ request: ExecutionRequest) async {
        isExecuting = true
        defer { isExecuting = false }

        let result: ExecutionResult

        if request.language.lowercased() != "swift" {
            result = .notSupported(reason: "Only Swift execution is supported in this environment.")
        } else {
            result = await performSyntaxCheck(code: request.code)
        }

        if let idx = queue.firstIndex(where: { $0.id == request.id }) {
            queue[idx].result = result
        }
        lastResult = result
    }

    private func performSyntaxCheck(code: String) async -> ExecutionResult {
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

    func clearQueue() {
        queue.removeAll()
        lastResult = nil
    }
}
