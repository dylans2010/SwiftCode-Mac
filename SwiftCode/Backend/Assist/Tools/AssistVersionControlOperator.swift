import Foundation

public struct AssistVersionControlOperator: AssistTool {
    public let id = "version_control_operator"
    public let name = "Version Control Operator"
    public let description = "Performs branch, commit, rollback, and diff operations using git."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        #if os(macOS)
        let action = (input["action"] as? String ?? "status").lowercased()
        let command: String
        switch action {
        case "commit":
            let message = input["message"] as? String ?? "Assist automated commit"
            command = "git add -A && git commit -m \"\(message.replacingOccurrences(of: "\"", with: "\\\""))\""
        case "branch":
            let name = input["name"] as? String ?? "assist/automation"
            command = "git checkout -b \(name)"
        case "rollback":
            let ref = input["ref"] as? String ?? "HEAD~1"
            command = "git reset --hard \(ref)"
        case "diff":
            command = "git diff -- ."
        default:
            command = "git status --short"
        }
        let output = try run(command: command, cwd: context.workspaceRoot.path)
        return .success("Git action executed: \(action)", data: ["output": output])
        #else
        return .failure("Version control operations require macOS runtime")
        #endif
    }

    #if os(macOS)
    private func run(command: String, cwd: String) throws -> String {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-lc", command]
        p.currentDirectoryURL = URL(fileURLWithPath: cwd)
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
    #endif
}
