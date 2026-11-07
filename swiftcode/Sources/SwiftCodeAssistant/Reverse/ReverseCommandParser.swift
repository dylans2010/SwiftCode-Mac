import Foundation

public enum ReverseCommandParser {
    public static let commandToken = "@Reverse"

    public static func parse(message: String) -> ReverseInvocation? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let prefix = String(trimmed.prefix(commandToken.count))
        guard prefix.lowercased() == commandToken.lowercased() else { return nil }
        let after = trimmed.dropFirst(commandToken.count)
        if let first = after.first, !first.isWhitespace {
            return nil
        }
        let remainder = after.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = remainder.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        var operation = ReverseOperation.inspectArtifact
        var objdumpOperation: ReverseObjdumpOperation?
        var targetPath: String?
        var symbol: String?
        var taskTokens: [String] = []

        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            let lower = token.lowercased()
            if let value = valueAfter(prefixes: ["symbol=", "symbol:"], in: lower, original: token) {
                symbol = value
                index += 1
                continue
            }
            if let value = valueAfter(prefixes: ["op=", "operation=", "op:", "operation:"], in: lower, original: token),
               let parsed = ReverseOperation(rawValue: value.lowercased()) {
                operation = parsed
                index += 1
                continue
            }
            if lower == "objdump" {
                if index + 1 < tokens.count,
                   let sub = ReverseObjdumpOperation(rawValue: tokens[index + 1].lowercased()) {
                    operation = .inspectWithObjdump
                    objdumpOperation = sub
                    index += 2
                    continue
                }
                operation = .inspectWithObjdump
                objdumpOperation = .fileHeaders
                index += 1
                continue
            }
            if targetPath == nil, let candidate = extractAbsolutePath(from: token) {
                targetPath = candidate
                index += 1
                continue
            }
            taskTokens.append(token)
            index += 1
        }

        if operation == .inspectWithObjdump && objdumpOperation == nil {
            objdumpOperation = .fileHeaders
        }
        return ReverseInvocation(
            task: taskTokens.joined(separator: " "),
            targetPath: targetPath,
            operation: operation,
            objdumpOperation: objdumpOperation,
            commandToken: commandToken,
            symbol: symbol
        )
    }

    public static func isIntentionalInvocation(message: String) -> Bool {
        parse(message: message) != nil
    }

    private static func valueAfter(prefixes: [String], in lower: String, original: String) -> String? {
        for prefix in prefixes where lower.hasPrefix(prefix) {
            let value = String(original.dropFirst(prefix.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`,.;:)]}"))
            if !value.isEmpty { return value }
        }
        return nil
    }

    public static func extractAbsolutePath(from token: String) -> String? {
        var cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`,.;:)]}"))
        while let first = cleaned.first, "\"'(`[{<".contains(first) {
            cleaned.removeFirst()
        }
        guard cleaned.hasPrefix("/") else { return nil }
        guard cleaned.count > 1 else { return nil }
        return cleaned
    }
}

public enum ReverseTargetValidator {
    private static let blockedPrefixes: [String] = [
        "/System", "/sbin", "/usr", "/bin", "/etc", "/var", "/Library", "/private", "/dev",
    ]

    private static let refusalPatterns: [String] = [
        "bypass drm", "circumvent drm", "remove drm", "break drm",
        "bypass license", "circumvent license", "license check", "licence check",
        "crack", "keygen", "serial key",
        "anti-cheat", "anticheat", "game cheat", "cheat engine",
        "bypass authentication", "bypass auth", "bypass login",
        "bot protection", "bypass captcha",
    ]

    public static func validateTarget(path: String?, workspaceRoot: URL) -> Result<String, ReverseError> {
        guard let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.invalidInput(
                "No target supplied. Usage: @Reverse <absolute path to a file you are authorized to analyze> <what to investigate>.",
                remediation: "Example: @Reverse /Users/you/Downloads/myapp Inspect how this authorized binary loads its configuration."
            ))
        }
        guard path.hasPrefix("/") else {
            return .failure(.invalidInput(
                "Target must be an absolute path (got '\(path)').",
                remediation: "Pass the full path, e.g. /Users/you/Downloads/myapp."
            ))
        }
        guard !path.contains("..") else {
            return .failure(.invalidInput(
                "Target path must not contain '..' segments.",
                remediation: "Pass the canonical absolute path without traversal segments."
            ))
        }
        let url = URL(fileURLWithPath: path)
        let resolved = url.resolvingSymlinksInPath()
        let resolvedPath = resolved.path
        for prefix in blockedPrefixes where resolvedPath == prefix || resolvedPath.hasPrefix(prefix + "/") {
            return .failure(.invalidInput(
                "Target '\(resolvedPath)' is inside a blocked system directory (\(prefix)).",
                remediation: "Analyze a copy in your project, Downloads, Desktop, or Documents instead."
            ))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if resolvedPath.hasPrefix(home + "/.") {
            return .failure(.invalidInput(
                "Target '\(resolvedPath)' is inside a hidden home directory, which is never in scope for Reverse.",
                remediation: "Move the artifact into Downloads, Desktop, Documents, or the open project."
            ))
        }
        let allowedRoots: [String] = [
            workspaceRoot.resolvingSymlinksInPath().path,
            (home as NSString).appendingPathComponent("Downloads"),
            (home as NSString).appendingPathComponent("Desktop"),
            (home as NSString).appendingPathComponent("Documents"),
        ]
        let inScope = allowedRoots.contains { root in
            resolvedPath == root || resolvedPath.hasPrefix(root + "/")
        }
        guard inScope else {
            return .failure(.invalidInput(
                "Target '\(resolvedPath)' is outside the Reverse scope (open project, ~/Downloads, ~/Desktop, ~/Documents).",
                remediation: "Move the artifact into one of those locations, or open the containing project in SwiftCode."
            ))
        }
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            return .failure(.invalidInput(
                "Target does not exist: \(resolvedPath)",
                remediation: "Check the path and try again."
            ))
        }
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: resolvedPath, isDirectory: &isDirectory)
        guard !isDirectory.boolValue else {
            return .failure(.invalidInput(
                "Target is a directory, not a file: \(resolvedPath)",
                remediation: "Pass the path of a single binary or artifact file."
            ))
        }
        return .success(resolvedPath)
    }

    public static func refusalError(forTask task: String) -> ReverseError? {
        let lower = task.lowercased()
        for pattern in refusalPatterns where lower.contains(pattern) {
            return .invalidInput(
                "Reverse cannot help with that request: analyzing software to circumvent DRM, license checks, anti-cheat systems, or authentication is outside REA's permitted use (see REA DISCLAIMER.md) and outside this integration's scope.",
                remediation: "Rephrase the investigation around behavior you are authorized to examine (e.g. configuration loading, file-format parsing, or error handling of software you own)."
            )
        }
        return nil
    }
}
