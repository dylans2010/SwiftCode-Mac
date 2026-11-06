//  ReverseCommandParser.swift
//  SwiftCode
//
//  Parses `@Reverse` invocations in the Assist composer.
//
//  Recognition rule (exact):
//  - The trimmed message must START with `@Reverse` (case-insensitive),
//    and the token must be followed by end-of-text or whitespace.
//    `@ReverseXYZ`, `@Reverse!`, or prose such as
//    "I read about @Reverse yesterday" do NOT invoke Reverse.
//  - Everything after the command token is the task. The first
//    absolute-path token in the remainder is the target; `op=` /
//    `operation=` selects the operation; a bare `objdump <op>` selects
//    `inspect_with_objdump` with the fixed objdump sub-operation.
//  - `@Reverse` with no task parses successfully with an empty task and
//    no target; the adapter then returns an actionable error telling
//    the user to supply a target path. A recognized command is never
//    silently ignored, and an unrecognized mention never executes.
//
//  There is no pre-existing generic `@` command parser in the app to
//  extend (the composer popup is a resource/skill picker, not a command
//  parser), so this is a standalone, pure parser with unit coverage.

import Foundation

public enum ReverseCommandParser {
    public static let commandToken = "@Reverse"

    /// Parses a full composer message. Returns nil when the message is
    /// not an intentional `@Reverse` invocation.
    public static func parse(message: String) -> ReverseInvocation? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Must start with @Reverse (case-insensitive) followed by end or whitespace.
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
                // Bare `objdump <op>` selects the objdump operation.
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
        // `op=inspect_with_objdump` without a sub-operation defaults to file_headers.
        // The task preserves the user's words minus the consumed tokens.
        return ReverseInvocation(
            task: taskTokens.joined(separator: " "),
            targetPath: targetPath,
            operation: operation,
            objdumpOperation: objdumpOperation,
            commandToken: commandToken,
            symbol: symbol
        )
    }

    /// Whether the message is an intentional invocation (used by the
    /// composer popup / classifier without full parsing).
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

    /// Extracts an absolute path from one token, stripping trailing
    /// punctuation. Returns nil for non-absolute tokens.
    public static func extractAbsolutePath(from token: String) -> String? {
        var cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`,.;:)]}"))
        // Strip a leading quote/bracket the trailing-trim missed.
        while let first = cleaned.first, "\"'(`[{<".contains(first) {
            cleaned.removeFirst()
        }
        guard cleaned.hasPrefix("/") else { return nil }
        // Reject tokens that are only punctuation or a bare "/".
        guard cleaned.count > 1 else { return nil }
        return cleaned
    }
}

// MARK: - Target / scope validation

/// Pure target validation shared by the adapter and the tests.
///
/// Scope rule (documented, enforced inside `execute` regardless of
/// Autopilot — Reverse never consults the Autopilot bypass):
/// - Target must be an existing absolute path; `..` segments, `~`,
///   and empty paths are rejected.
/// - The symlink-resolved path must NOT be under a blocked system
///   directory: /System, /sbin, /usr, /bin, /etc, /var, /Library,
///   /private, /dev, or any dot-directory (e.g. ~/.ssh, ~/.gnupg).
/// - The resolved path must be inside ONE of: the workspace root, or
///   the user's ~/Downloads, ~/Desktop, ~/Documents. Everything else
///   (including other home subdirectories) is rejected with an
///   actionable message. This keeps analysis scoped to files the user
///   explicitly placed in analysis locations or in the open project.
/// - Task text is screened for REA-disclaimer refusals: circumventing
///   DRM / license checks / anti-cheat, game cheats, or bypassing
///   authentication. Matches reject with an actionable error.
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
        // Dot-directories under home (e.g. ~/.ssh) are never in scope.
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

    /// Screens task text against the REA disclaimer refusal boundary.
    /// Returns an error when the task asks for a refused use, else nil.
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
