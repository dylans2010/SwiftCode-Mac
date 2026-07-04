import Foundation

public struct GitAddTool: AgentTool {
    public static let identifier = "git_add"
    public let name = "git_add"
    public let description = "Adds files to the git staging area."
    public let schema: [String: JSON] = [
        "type": "object",
        "properties": [
            "repositoryPath": ["type": "string"],
            "files": ["type": "array", "items": ["type": "string"]]
        ],
        "required": ["repositoryPath", "files"]
    ]

    public func run(repositoryPath: String, files: [String]) async throws {
        let url = URL(fileURLWithPath: repositoryPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["add"] + files,
            workingDirectory: url
        )
        if result.exitCode != 0 { throw AgentError.toolError(result.stderr) }
    }

    public func execute(arguments: [String: JSON]) async throws -> String {
        guard case .string(let path) = arguments["repositoryPath"],
              case .array(let filesJSON) = arguments["files"] else {
            throw AgentError.toolError("Missing repositoryPath or files")
        }

        let files = filesJSON.compactMap { (item: JSON) -> String? in
            if case .string(let s) = item { return s }
            return nil
        }

        try await run(repositoryPath: path, files: files)
        return "Files added successfully"
    }
}
