//
//  AssistDataInspectionTools.swift
//  SwiftCode
//
//  Created on 2026-10-18.
//

import Foundation
import CryptoKit

// MARK: - Helper

private func resolveWorkspaceDataInspectionURL(_ raw: String, workspaceRoot: URL) -> URL? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.contains("\0"), !trimmed.hasPrefix("~"), !trimmed.contains("..") else {
        return nil
    }
    let rootPath = workspaceRoot.standardized.path
    let candidate: URL
    if trimmed.hasPrefix("/") {
        candidate = URL(fileURLWithPath: trimmed).standardized
    } else {
        candidate = workspaceRoot.appendingPathComponent(trimmed).standardized
    }
    let candidatePath = candidate.path
    guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
        return nil
    }
    return candidate
}

// MARK: - File Compare Diff Tool (safeRead)

public struct AssistFileCompareDiffTool: AssistTool {
    public let id = "file_compare_diff"
    public let name = "Compare Two Files and Generate Diff"
    public let description = "Compares two files line-by-line and produces a formatted unified diff with added/removed stats."

    public init() {}

    public var capability: ToolCapability { .fileReading }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Compares two files line-by-line and produces a formatted unified diff with added/removed stats.",
            properties: [
                "pathA": JSONSchema(type: "string", description: "Workspace-relative path to the first/original file."),
                "pathB": JSONSchema(type: "string", description: "Workspace-relative path to the second/modified file.")
            ],
            required: ["pathA", "pathB"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let pathARaw = (input["pathA"] ?? input["fileA"]) as? String,
              let pathBRaw = (input["pathB"] ?? input["fileB"]) as? String else {
            return .failure("Missing required parameters: pathA and pathB")
        }

        guard let urlA = resolveWorkspaceDataInspectionURL(pathARaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("pathA is outside the workspace: \(pathARaw)")
        }
        guard let urlB = resolveWorkspaceDataInspectionURL(pathBRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("pathB is outside the workspace: \(pathBRaw)")
        }

        guard FileManager.default.fileExists(atPath: urlA.path) else {
            return .failure("File A not found: \(pathARaw)")
        }
        guard FileManager.default.fileExists(atPath: urlB.path) else {
            return .failure("File B not found: \(pathBRaw)")
        }

        do {
            let contentA = try String(contentsOf: urlA, encoding: .utf8)
            let contentB = try String(contentsOf: urlB, encoding: .utf8)

            let linesA = contentA.components(separatedBy: .newlines)
            let linesB = contentB.components(separatedBy: .newlines)

            if contentA == contentB {
                return .success(
                    "Files `\(pathARaw)` and `\(pathBRaw)` are identical (\(linesA.count) lines).",
                    data: ["identical": "true", "lineCount": "\(linesA.count)"]
                )
            }

            var diffLines: [String] = [
                "--- a/\(pathARaw)",
                "+++ b/\(pathBRaw)",
                "@@ -1,\(linesA.count) +1,\(linesB.count) @@"
            ]

            var added = 0
            var removed = 0

            let maxCount = max(linesA.count, linesB.count)
            for i in 0..<maxCount {
                let a = i < linesA.count ? linesA[i] : nil
                let b = i < linesB.count ? linesB[i] : nil

                if let a = a, let b = b {
                    if a == b {
                        diffLines.append("  \(a)")
                    } else {
                        diffLines.append("- \(a)")
                        diffLines.append("+ \(b)")
                        removed += 1
                        added += 1
                    }
                } else if let a = a {
                    diffLines.append("- \(a)")
                    removed += 1
                } else if let b = b {
                    diffLines.append("+ \(b)")
                    added += 1
                }
            }

            let diffText = diffLines.joined(separator: "\n")
            return .success(
                "Unified diff for `\(pathARaw)` vs `\(pathBRaw)` (+\(added), -\(removed) lines):\n\n\(diffText)",
                data: [
                    "pathA": pathARaw,
                    "pathB": pathBRaw,
                    "addedLines": "\(added)",
                    "removedLines": "\(removed)",
                    "identical": "false"
                ],
                diff: diffText
            )
        } catch {
            return .failure("Failed to read files for comparison: \(error.localizedDescription)")
        }
    }
}

// MARK: - Count File Lines Tool (safeRead)

public struct AssistCountFileLinesTool: AssistTool {
    public let id = "count_file_lines"
    public let name = "Count File Lines and Code Metrics"
    public let description = "Calculates total lines, code lines, comment lines, and blank lines across workspace files."

    public init() {}

    public var capability: ToolCapability { .fileReading }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Calculates total lines, code lines, comment lines, and blank lines across workspace files.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to a file or directory to analyze."),
                "extension": JSONSchema(type: "string", description: "Optional extension filter when analyzing directory (e.g. 'swift', 'm', 'h').")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let pathRaw = (input["path"] ?? input["targetPath"]) as? String else {
            return .failure("Missing required parameter: path")
        }

        guard let targetURL = resolveWorkspaceDataInspectionURL(pathRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Path is outside the workspace: \(pathRaw)")
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDir) else {
            return .failure("Path not found: \(pathRaw)")
        }

        let extFilter = (input["extension"] as? String)?.lowercased()

        var fileURLs: [URL] = []
        if isDir.boolValue {
            let enumerator = FileManager.default.enumerator(
                at: targetURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            while let url = enumerator?.nextObject() as? URL {
                if let ext = extFilter, url.pathExtension.lowercased() != ext {
                    continue
                }
                var isReg: AnyObject?
                try? (url as NSURL).getResourceValue(&isReg, forKey: .isRegularFileKey)
                if (isReg as? Bool) == true {
                    fileURLs.append(url)
                }
            }
        } else {
            fileURLs.append(targetURL)
        }

        var totalLines = 0
        var totalBlank = 0
        var totalComment = 0
        var totalCode = 0
        var totalBytes: Int64 = 0

        for fileURL in fileURLs {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            totalBytes += (attrs?[.size] as? NSNumber)?.int64Value ?? 0

            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                totalLines += 1
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    totalBlank += 1
                } else if trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") || trimmed.hasPrefix("#") {
                    totalComment += 1
                } else {
                    totalCode += 1
                }
            }
        }

        let output = """
        Code Metrics for \(pathRaw) (\(fileURLs.count) file(s)):
        - Total Lines: \(totalLines)
        - Code Lines: \(totalCode)
        - Comment Lines: \(totalComment)
        - Blank Lines: \(totalBlank)
        - Total File Size: \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)) (\(totalBytes) bytes)
        """

        return .success(
            output,
            data: [
                "path": pathRaw,
                "fileCount": "\(fileURLs.count)",
                "totalLines": "\(totalLines)",
                "codeLines": "\(totalCode)",
                "commentLines": "\(totalComment)",
                "blankLines": "\(totalBlank)",
                "totalBytes": "\(totalBytes)"
            ]
        )
    }
}

// MARK: - Extract Code Symbols Tool (safeRead)

public struct AssistExtractCodeSymbolsTool: AssistTool {
    public let id = "extract_code_symbols"
    public let name = "Extract Code Symbols"
    public let description = "Extracts top-level declarations (class, struct, enum, protocol, actor, func, extension) and signatures from a source file."

    public init() {}

    public var capability: ToolCapability { .fileReading }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Extracts top-level declarations (class, struct, enum, protocol, actor, func, extension) and signatures from a source file.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to the Swift or source code file.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let pathRaw = (input["path"] ?? input["filePath"]) as? String else {
            return .failure("Missing required parameter: path")
        }

        guard let fileURL = resolveWorkspaceDataInspectionURL(pathRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Path is outside the workspace: \(pathRaw)")
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .failure("File not found at: \(pathRaw)")
        }

        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)

            let keywords = ["class ", "struct ", "enum ", "protocol ", "actor ", "func ", "extension ", "typealias "]
            var symbols: [[String: String]] = []

            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") && !trimmed.hasPrefix("/*") && !trimmed.hasPrefix("*") else {
                    continue
                }

                for kw in keywords {
                    if trimmed.contains(kw) {
                        let lineNumber = index + 1
                        let signature = trimmed.components(separatedBy: "{").first?.trimmingCharacters(in: .whitespaces) ?? trimmed
                        symbols.append([
                            "line": "\(lineNumber)",
                            "kind": kw.trimmingCharacters(in: .whitespaces),
                            "signature": signature
                        ])
                        break
                    }
                }
            }

            let symbolList = symbols.map { "  • L\($0["line"] ?? ""): [\($0["kind"] ?? "")] \($0["signature"] ?? "")" }.joined(separator: "\n")
            let output = """
            Extracted \(symbols.count) declaration symbol(s) from `\(pathRaw)`:
            \(symbolList)
            """

            return .success(
                output,
                data: [
                    "path": pathRaw,
                    "symbolCount": "\(symbols.count)"
                ]
            )
        } catch {
            return .failure("Failed to read and extract symbols from `\(pathRaw)`: \(error.localizedDescription)")
        }
    }
}

// MARK: - Generate File Checksum Tool (safeRead)

public struct AssistGenerateFileChecksumTool: AssistTool {
    public let id = "generate_file_checksum"
    public let name = "Generate File Cryptographic Checksum"
    public let description = "Computes SHA-256, SHA-512, SHA-1, and MD5 cryptographic checksums of a file on disk."

    public init() {}

    public var capability: ToolCapability { .fileReading }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Computes SHA-256, SHA-512, SHA-1, and MD5 cryptographic checksums of a file on disk.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to the file to hash.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let pathRaw = (input["path"] ?? input["filePath"]) as? String else {
            return .failure("Missing required parameter: path")
        }

        guard let fileURL = resolveWorkspaceDataInspectionURL(pathRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Path is outside the workspace: \(pathRaw)")
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .failure("File not found at: \(pathRaw)")
        }

        do {
            let data = try Data(contentsOf: fileURL)

            let sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let sha512 = SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let md5 = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let sha1 = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()

            let output = """
            Checksums for \(pathRaw) (\(data.count) bytes):
            - SHA-256: \(sha256)
            - SHA-512: \(sha512)
            - SHA-1:   \(sha1)
            - MD5:     \(md5)
            """

            return .success(
                output,
                data: [
                    "path": pathRaw,
                    "sha256": sha256,
                    "sha512": sha512,
                    "sha1": sha1,
                    "md5": md5,
                    "size": "\(data.count)"
                ]
            )
        } catch {
            return .failure("Failed to compute file checksum: \(error.localizedDescription)")
        }
    }
}
