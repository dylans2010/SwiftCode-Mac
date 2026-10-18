//
//  AssistArchiveTools.swift
//  SwiftCode
//
//  Created on 2026-10-18.
//

import Foundation

// MARK: - Helper

private func resolveWorkspaceArchiveURL(_ raw: String, workspaceRoot: URL) -> URL? {
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

// MARK: - Zip File Tool

public struct AssistZipFileTool: AssistTool {
    public let id = "zip_file"
    public let name = "Zip File or Directory"
    public let description = "Compresses a file or directory into a .zip archive using the macOS system archive tool."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Compresses a file or directory into a .zip archive using the macOS system archive tool.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to the source file or directory to compress."),
                "destination": JSONSchema(type: "string", description: "Workspace-relative path for the resulting .zip archive.")
            ],
            required: ["path", "destination"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let sourceRaw = (input["path"] ?? input["source"] ?? input["sourcePath"]) as? String,
              let destRaw = (input["destination"] ?? input["destinationPath"] ?? input["dest"]) as? String else {
            return .failure("Missing required parameters: path and destination")
        }

        guard let sourceURL = resolveWorkspaceArchiveURL(sourceRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Source path is outside the workspace: \(sourceRaw)")
        }
        guard let destURL = resolveWorkspaceArchiveURL(destRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Destination path is outside the workspace: \(destRaw)")
        }

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return .failure("Source item not found at: \(sourceRaw)")
        }

        let parentDir = destURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        proc.arguments = ["-c", "-k", "--sequesterRsrc", sourceURL.path, destURL.path]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()
            proc.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

            if proc.terminationStatus == 0 {
                let attrs = try? FileManager.default.attributesOfItem(atPath: destURL.path)
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                return .success(
                    "Successfully compressed `\(sourceRaw)` into `\(destRaw)` (\(size) bytes).",
                    data: ["destination": destRaw, "size": "\(size)"],
                    filesChanged: [destRaw]
                )
            } else {
                return .failure("ditto zip failed with code \(proc.terminationStatus): \(output)")
            }
        } catch {
            return .failure("Failed to execute ditto compression: \(error.localizedDescription)")
        }
    }
}

// MARK: - Unzip File Tool

public struct AssistUnzipFileTool: AssistTool {
    public let id = "unzip_file"
    public let name = "Unzip Archive"
    public let description = "Extracts a .zip archive into a destination directory using the macOS system archive tool."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Extracts a .zip archive into a destination directory using the macOS system archive tool.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to the .zip archive to extract."),
                "destination": JSONSchema(type: "string", description: "Workspace-relative path to the target directory to extract files into.")
            ],
            required: ["path", "destination"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let sourceRaw = (input["path"] ?? input["archive"] ?? input["archivePath"]) as? String,
              let destRaw = (input["destination"] ?? input["destinationPath"] ?? input["dest"]) as? String else {
            return .failure("Missing required parameters: path and destination")
        }

        guard let sourceURL = resolveWorkspaceArchiveURL(sourceRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Source archive path is outside the workspace: \(sourceRaw)")
        }
        guard let destURL = resolveWorkspaceArchiveURL(destRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Destination path is outside the workspace: \(destRaw)")
        }

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return .failure("Archive file not found at: \(sourceRaw)")
        }

        if !FileManager.default.fileExists(atPath: destURL.path) {
            try? FileManager.default.createDirectory(at: destURL, withIntermediateDirectories: true)
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        proc.arguments = ["-x", "-k", sourceURL.path, destURL.path]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()
            proc.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

            if proc.terminationStatus == 0 {
                let items = (try? FileManager.default.contentsOfDirectory(atPath: destURL.path)) ?? []
                return .success(
                    "Successfully extracted `\(sourceRaw)` into `\(destRaw)` (\(items.count) extracted items).",
                    data: ["destination": destRaw, "extractedCount": "\(items.count)"],
                    filesChanged: [destRaw]
                )
            } else {
                return .failure("ditto unzip failed with code \(proc.terminationStatus): \(output)")
            }
        } catch {
            return .failure("Failed to execute ditto extraction: \(error.localizedDescription)")
        }
    }
}

// MARK: - Tar Archive Create Tool

public struct AssistTarArchiveCreateTool: AssistTool {
    public let id = "tar_archive_create"
    public let name = "Create Tar Archive"
    public let description = "Creates a .tar or .tar.gz archive from a directory or files using system tar."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Creates a .tar or .tar.gz archive from a directory or files using system tar.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path of the file or directory to archive."),
                "destination": JSONSchema(type: "string", description: "Workspace-relative path for the resulting archive file (.tar or .tar.gz)."),
                "gzip": JSONSchema(type: "boolean", description: "Whether to apply gzip compression (defaults to true for .tar.gz or .tgz, false for .tar).")
            ],
            required: ["path", "destination"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let sourceRaw = (input["path"] ?? input["source"] ?? input["sourcePath"]) as? String,
              let destRaw = (input["destination"] ?? input["destinationPath"]) as? String else {
            return .failure("Missing required parameters: path and destination")
        }

        guard let sourceURL = resolveWorkspaceArchiveURL(sourceRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Source path is outside the workspace: \(sourceRaw)")
        }
        guard let destURL = resolveWorkspaceArchiveURL(destRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Destination path is outside the workspace: \(destRaw)")
        }

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return .failure("Source file/folder not found at: \(sourceRaw)")
        }

        let parentDir = destURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        let isGzip = (input["gzip"] as? Bool) ?? (destRaw.hasSuffix(".gz") || destRaw.hasSuffix(".tgz"))
        let tarFlags = isGzip ? "-czf" : "-cf"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        proc.arguments = [
            tarFlags,
            destURL.path,
            "-C",
            sourceURL.deletingLastPathComponent().path,
            sourceURL.lastPathComponent
        ]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()
            proc.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

            if proc.terminationStatus == 0 {
                let attrs = try? FileManager.default.attributesOfItem(atPath: destURL.path)
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                return .success(
                    "Successfully created tar archive `\(destRaw)` (\(size) bytes).",
                    data: ["destination": destRaw, "size": "\(size)"],
                    filesChanged: [destRaw]
                )
            } else {
                return .failure("tar failed with code \(proc.terminationStatus): \(output)")
            }
        } catch {
            return .failure("Failed to execute tar: \(error.localizedDescription)")
        }
    }
}

// MARK: - Tar Archive Extract Tool

public struct AssistTarArchiveExtractTool: AssistTool {
    public let id = "tar_archive_extract"
    public let name = "Extract Tar Archive"
    public let description = "Extracts a .tar or .tar.gz archive into a destination directory using system tar."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Extracts a .tar or .tar.gz archive into a destination directory using system tar.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to the archive file (.tar, .tar.gz, .tgz)."),
                "destination": JSONSchema(type: "string", description: "Workspace-relative destination directory to extract into.")
            ],
            required: ["path", "destination"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let sourceRaw = (input["path"] ?? input["archive"]) as? String,
              let destRaw = (input["destination"] ?? input["destinationPath"]) as? String else {
            return .failure("Missing required parameters: path and destination")
        }

        guard let sourceURL = resolveWorkspaceArchiveURL(sourceRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Source archive path is outside the workspace: \(sourceRaw)")
        }
        guard let destURL = resolveWorkspaceArchiveURL(destRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Destination path is outside the workspace: \(destRaw)")
        }

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return .failure("Archive not found at: \(sourceRaw)")
        }

        if !FileManager.default.fileExists(atPath: destURL.path) {
            try? FileManager.default.createDirectory(at: destURL, withIntermediateDirectories: true)
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        proc.arguments = ["-xf", sourceURL.path, "-C", destURL.path]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()
            proc.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

            if proc.terminationStatus == 0 {
                let items = (try? FileManager.default.contentsOfDirectory(atPath: destURL.path)) ?? []
                return .success(
                    "Successfully extracted archive `\(sourceRaw)` into `\(destRaw)` (\(items.count) extracted items).",
                    data: ["destination": destRaw, "extractedCount": "\(items.count)"],
                    filesChanged: [destRaw]
                )
            } else {
                return .failure("tar extraction failed with code \(proc.terminationStatus): \(output)")
            }
        } catch {
            return .failure("Failed to execute tar extraction: \(error.localizedDescription)")
        }
    }
}

// MARK: - Gzip Compress Tool

public struct AssistGzipCompressTool: AssistTool {
    public let id = "gzip_compress_file"
    public let name = "Gzip Compress File"
    public let description = "Compresses a file into a .gz file using system gzip."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Compresses a file into a .gz file using system gzip.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to the source file to compress."),
                "destination": JSONSchema(type: "string", description: "Optional workspace-relative path for output .gz file. Defaults to <path>.gz.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let sourceRaw = (input["path"] ?? input["source"]) as? String else {
            return .failure("Missing required parameter: path")
        }

        guard let sourceURL = resolveWorkspaceArchiveURL(sourceRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Source path is outside the workspace: \(sourceRaw)")
        }

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return .failure("File not found at: \(sourceRaw)")
        }

        let defaultDestRaw = sourceRaw + ".gz"
        let destRaw = (input["destination"] as? String) ?? defaultDestRaw
        guard let destURL = resolveWorkspaceArchiveURL(destRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Destination path is outside the workspace: \(destRaw)")
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        proc.arguments = ["-c", "-k", "-f", sourceURL.path]

        let pipe = Pipe()
        proc.standardOutput = pipe
        let errPipe = Pipe()
        proc.standardError = errPipe

        do {
            try proc.run()
            let compressedData = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()

            if proc.terminationStatus == 0 {
                let parentDir = destURL.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: parentDir.path) {
                    try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
                }
                try compressedData.write(to: destURL, options: .atomic)
                return .success(
                    "Successfully compressed `\(sourceRaw)` to `\(destRaw)` (\(compressedData.count) bytes).",
                    data: ["destination": destRaw, "size": "\(compressedData.count)"],
                    filesChanged: [destRaw]
                )
            } else {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(decoding: errData, as: UTF8.self)
                return .failure("gzip compression failed: \(errStr)")
            }
        } catch {
            return .failure("Failed to execute gzip: \(error.localizedDescription)")
        }
    }
}

// MARK: - Gzip Decompress Tool

public struct AssistGzipDecompressTool: AssistTool {
    public let id = "gzip_decompress_file"
    public let name = "Gzip Decompress File"
    public let description = "Decompresses a .gz file into a destination file using system gzip."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Decompresses a .gz file into a destination file using system gzip.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to the .gz file to decompress."),
                "destination": JSONSchema(type: "string", description: "Optional workspace-relative path for decompressed file. Defaults to removing .gz suffix.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let sourceRaw = (input["path"] ?? input["source"]) as? String else {
            return .failure("Missing required parameter: path")
        }

        guard let sourceURL = resolveWorkspaceArchiveURL(sourceRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Source path is outside the workspace: \(sourceRaw)")
        }

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return .failure("Archive file not found at: \(sourceRaw)")
        }

        let defaultDestRaw: String
        if sourceRaw.hasSuffix(".gz") {
            defaultDestRaw = String(sourceRaw.dropLast(3))
        } else {
            defaultDestRaw = sourceRaw + ".decompressed"
        }

        let destRaw = (input["destination"] as? String) ?? defaultDestRaw
        guard let destURL = resolveWorkspaceArchiveURL(destRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Destination path is outside the workspace: \(destRaw)")
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        proc.arguments = ["-d", "-c", "-k", "-f", sourceURL.path]

        let pipe = Pipe()
        proc.standardOutput = pipe
        let errPipe = Pipe()
        proc.standardError = errPipe

        do {
            try proc.run()
            let decompressedData = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()

            if proc.terminationStatus == 0 {
                let parentDir = destURL.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: parentDir.path) {
                    try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
                }
                try decompressedData.write(to: destURL, options: .atomic)
                return .success(
                    "Successfully decompressed `\(sourceRaw)` to `\(destRaw)` (\(decompressedData.count) bytes).",
                    data: ["destination": destRaw, "size": "\(decompressedData.count)"],
                    filesChanged: [destRaw]
                )
            } else {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(decoding: errData, as: UTF8.self)
                return .failure("gzip decompression failed: \(errStr)")
            }
        } catch {
            return .failure("Failed to execute gzip decompression: \(error.localizedDescription)")
        }
    }
}
