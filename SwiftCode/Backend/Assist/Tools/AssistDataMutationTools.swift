//
//  AssistDataMutationTools.swift
//  SwiftCode
//
//  Created on 2026-10-18.
//

import Foundation

// MARK: - Helper

private func resolveWorkspaceDataMutationURL(_ raw: String, workspaceRoot: URL) -> URL? {
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

// MARK: - Format JSON File Tool

public struct AssistFormatJsonFileTool: AssistTool {
    public let id = "format_json_file"
    public let name = "Format and Validate JSON File"
    public let description = "Validates and pretty-prints a JSON file with consistent indentation and sorted keys."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Validates and pretty-prints a JSON file with consistent indentation and sorted keys.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to the JSON file to format.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let pathRaw = (input["path"] ?? input["filePath"]) as? String else {
            return .failure("Missing required parameter: path")
        }

        guard let fileURL = resolveWorkspaceDataMutationURL(pathRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Path is outside the workspace: \(pathRaw)")
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .failure("JSON file not found at: \(pathRaw)")
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            let formattedData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
            try formattedData.write(to: fileURL, options: .atomic)

            return .success(
                "Successfully formatted and validated JSON file at `\(pathRaw)` (\(formattedData.count) bytes).",
                data: ["path": pathRaw, "formattedBytes": "\(formattedData.count)"],
                filesChanged: [pathRaw]
            )
        } catch {
            return .failure("JSON formatting or validation error in `\(pathRaw)`: \(error.localizedDescription)")
        }
    }
}

// MARK: - CSV to JSON Tool

public struct AssistCsvToJsonTool: AssistTool {
    public let id = "csv_to_json"
    public let name = "Convert CSV to JSON"
    public let description = "Parses a tabular CSV file and converts records into a structured JSON array of objects."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Parses a tabular CSV file and converts records into a structured JSON array of objects.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to the input CSV file."),
                "destination": JSONSchema(type: "string", description: "Optional workspace-relative destination path for .json file. Defaults to <path>.json."),
                "delimiter": JSONSchema(type: "string", description: "Delimiter character: ',' (default), '\t', or ';'.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let pathRaw = (input["path"] ?? input["csvPath"]) as? String else {
            return .failure("Missing required parameter: path")
        }

        guard let fileURL = resolveWorkspaceDataMutationURL(pathRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Path is outside the workspace: \(pathRaw)")
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .failure("CSV file not found at: \(pathRaw)")
        }

        let delimiter = (input["delimiter"] as? String) ?? ","

        do {
            let rawString = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = rawString.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard !lines.isEmpty else {
                return .failure("CSV file is empty.")
            }

            let headers = lines[0].components(separatedBy: delimiter).map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\""))) }

            var records: [[String: String]] = []
            for line in lines.dropFirst() {
                let columns = line.components(separatedBy: delimiter).map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\""))) }
                var record: [String: String] = [:]
                for (idx, header) in headers.enumerated() {
                    let value = idx < columns.count ? columns[idx] : ""
                    record[header] = value
                }
                records.append(record)
            }

            let jsonData = try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])

            let baseName = (pathRaw as NSString).deletingPathExtension
            let defaultDest = "\(baseName).json"
            let destRaw = (input["destination"] as? String) ?? defaultDest

            guard let destURL = resolveWorkspaceDataMutationURL(destRaw, workspaceRoot: context.workspaceRoot) else {
                return .failure("Destination path is outside the workspace: \(destRaw)")
            }

            let parentDir = destURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDir.path) {
                try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }

            try jsonData.write(to: destURL, options: .atomic)

            return .success(
                "Successfully converted CSV `\(pathRaw)` to JSON at `\(destRaw)` (\(records.count) records parsed).",
                data: ["destination": destRaw, "recordCount": "\(records.count)"],
                filesChanged: [destRaw]
            )
        } catch {
            return .failure("Failed to convert CSV to JSON: \(error.localizedDescription)")
        }
    }
}

// MARK: - JSON to CSV Tool

public struct AssistJsonToCsvTool: AssistTool {
    public let id = "json_to_csv"
    public let name = "Convert JSON to CSV"
    public let description = "Converts a JSON array of objects into a standard CSV tabular file."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Converts a JSON array of objects into a standard CSV tabular file.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to the input JSON file."),
                "destination": JSONSchema(type: "string", description: "Optional workspace-relative destination path for .csv file. Defaults to <path>.csv.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let pathRaw = (input["path"] ?? input["jsonPath"]) as? String else {
            return .failure("Missing required parameter: path")
        }

        guard let fileURL = resolveWorkspaceDataMutationURL(pathRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Path is outside the workspace: \(pathRaw)")
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .failure("JSON file not found at: \(pathRaw)")
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])

            guard let array = jsonObject as? [[String: Any]], !array.isEmpty else {
                return .failure("JSON root must be a non-empty array of objects to convert to CSV.")
            }

            var allKeysSet = Set<String>()
            for item in array {
                allKeysSet.formUnion(item.keys)
            }
            let headers = allKeysSet.sorted()

            var csvLines: [String] = []
            csvLines.append(headers.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ","))

            for item in array {
                let row = headers.map { key -> String in
                    let val = item[key] != nil ? "\(item[key]!)" : ""
                    let escaped = val.replacingOccurrences(of: "\"", with: "\"\"")
                    return "\"\(escaped)\""
                }
                csvLines.append(row.joined(separator: ","))
            }

            let csvString = csvLines.joined(separator: "\n") + "\n"
            guard let csvData = csvString.data(using: .utf8) else {
                return .failure("Failed to encode CSV string to UTF-8 data.")
            }

            let baseName = (pathRaw as NSString).deletingPathExtension
            let defaultDest = "\(baseName).csv"
            let destRaw = (input["destination"] as? String) ?? defaultDest

            guard let destURL = resolveWorkspaceDataMutationURL(destRaw, workspaceRoot: context.workspaceRoot) else {
                return .failure("Destination path is outside the workspace: \(destRaw)")
            }

            let parentDir = destURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDir.path) {
                try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }

            try csvData.write(to: destURL, options: .atomic)

            return .success(
                "Successfully converted JSON `\(pathRaw)` to CSV at `\(destRaw)` (\(array.count) rows, \(headers.count) columns).",
                data: [
                    "destination": destRaw,
                    "rowCount": "\(array.count)",
                    "columnCount": "\(headers.count)"
                ],
                filesChanged: [destRaw]
            )
        } catch {
            return .failure("Failed to convert JSON to CSV: \(error.localizedDescription)")
        }
    }
}

// MARK: - Plist to JSON Tool

public struct AssistPlistToJsonTool: AssistTool {
    public let id = "plist_to_json"
    public let name = "Convert Plist to JSON"
    public let description = "Converts an Apple Property List (.plist) file directly into formatted JSON format."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Converts an Apple Property List (.plist) file directly into formatted JSON format.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to the .plist file."),
                "destination": JSONSchema(type: "string", description: "Optional workspace-relative destination path for .json file. Defaults to <path>.json.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let pathRaw = (input["path"] ?? input["plistPath"]) as? String else {
            return .failure("Missing required parameter: path")
        }

        guard let fileURL = resolveWorkspaceDataMutationURL(pathRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Path is outside the workspace: \(pathRaw)")
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .failure("Plist file not found at: \(pathRaw)")
        }

        do {
            let plistData = try Data(contentsOf: fileURL)
            var format: PropertyListSerialization.PropertyListFormat = .xml
            let plistObject = try PropertyListSerialization.propertyList(from: plistData, options: [], format: &format)

            let jsonData = try JSONSerialization.data(withJSONObject: plistObject, options: [.prettyPrinted, .sortedKeys])

            let baseName = (pathRaw as NSString).deletingPathExtension
            let defaultDest = "\(baseName).json"
            let destRaw = (input["destination"] as? String) ?? defaultDest

            guard let destURL = resolveWorkspaceDataMutationURL(destRaw, workspaceRoot: context.workspaceRoot) else {
                return .failure("Destination path is outside the workspace: \(destRaw)")
            }

            let parentDir = destURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDir.path) {
                try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }

            try jsonData.write(to: destURL, options: .atomic)

            return .success(
                "Successfully converted Plist `\(pathRaw)` to JSON at `\(destRaw)` (\(jsonData.count) bytes).",
                data: ["destination": destRaw, "size": "\(jsonData.count)"],
                filesChanged: [destRaw]
            )
        } catch {
            return .failure("Failed to convert Plist to JSON: \(error.localizedDescription)")
        }
    }
}

// MARK: - JSON to Plist Tool

public struct AssistJsonToPlistTool: AssistTool {
    public let id = "json_to_plist"
    public let name = "Convert JSON to Plist"
    public let description = "Converts a JSON file into an Apple Property List (.plist, XML or Binary format)."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Converts a JSON file into an Apple Property List (.plist, XML or Binary format).",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to the .json file."),
                "destination": JSONSchema(type: "string", description: "Optional workspace-relative destination path for .plist. Defaults to <path>.plist."),
                "binary": JSONSchema(type: "boolean", description: "Whether to encode as binary plist (default false: XML plist).")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let pathRaw = (input["path"] ?? input["jsonPath"]) as? String else {
            return .failure("Missing required parameter: path")
        }

        guard let fileURL = resolveWorkspaceDataMutationURL(pathRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Path is outside the workspace: \(pathRaw)")
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .failure("JSON file not found at: \(pathRaw)")
        }

        let isBinary = (input["binary"] as? Bool) ?? false

        do {
            let jsonData = try Data(contentsOf: fileURL)
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])

            let format: PropertyListSerialization.PropertyListFormat = isBinary ? .binary : .xml
            let plistData = try PropertyListSerialization.data(fromPropertyList: jsonObject, format: format, options: 0)

            let baseName = (pathRaw as NSString).deletingPathExtension
            let defaultDest = "\(baseName).plist"
            let destRaw = (input["destination"] as? String) ?? defaultDest

            guard let destURL = resolveWorkspaceDataMutationURL(destRaw, workspaceRoot: context.workspaceRoot) else {
                return .failure("Destination path is outside the workspace: \(destRaw)")
            }

            let parentDir = destURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDir.path) {
                try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }

            try plistData.write(to: destURL, options: .atomic)

            return .success(
                "Successfully converted JSON `\(pathRaw)` to Plist (\(isBinary ? "binary" : "xml")) at `\(destRaw)` (\(plistData.count) bytes).",
                data: [
                    "destination": destRaw,
                    "format": isBinary ? "binary" : "xml",
                    "size": "\(plistData.count)"
                ],
                filesChanged: [destRaw]
            )
        } catch {
            return .failure("Failed to convert JSON to Plist: \(error.localizedDescription)")
        }
    }
}

// MARK: - Batch Rename Files Tool

public struct AssistBatchRenameFilesTool: AssistTool {
    public let id = "batch_rename_files"
    public let name = "Batch Rename Files"
    public let description = "Renames multiple files in a directory matching a prefix, suffix, or substring pattern."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Renames multiple files in a directory matching a prefix, suffix, or substring pattern.",
            properties: [
                "directory": JSONSchema(type: "string", description: "Workspace-relative directory containing the files to rename."),
                "search": JSONSchema(type: "string", description: "Target substring or pattern in filenames to replace."),
                "replacement": JSONSchema(type: "string", description: "String to replace the search target with."),
                "extension": JSONSchema(type: "string", description: "Optional file extension filter (e.g. 'swift', 'png')."),
                "dryRun": JSONSchema(type: "boolean", description: "If true, simulates the rename without modifying files. Default: false.")
            ],
            required: ["directory", "search", "replacement"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let dirRaw = (input["directory"] ?? input["path"]) as? String,
              let searchStr = input["search"] as? String,
              let replacementStr = input["replacement"] as? String else {
            return .failure("Missing required parameters: directory, search, replacement")
        }

        guard let dirURL = resolveWorkspaceDataMutationURL(dirRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Directory path is outside the workspace: \(dirRaw)")
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue else {
            return .failure("Directory not found at: \(dirRaw)")
        }

        let extFilter = (input["extension"] as? String)?.lowercased()
        let isDryRun = (input["dryRun"] as? Bool) ?? false

        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: dirURL.path)
            var plannedRenames: [(from: String, to: String, oldURL: URL, newURL: URL)] = []

            for filename in contents.sorted() {
                if let ext = extFilter, (filename as NSString).pathExtension.lowercased() != ext {
                    continue
                }
                if filename.contains(searchStr) {
                    let newName = filename.replacingOccurrences(of: searchStr, with: replacementStr)
                    if newName != filename {
                        let oldURL = dirURL.appendingPathComponent(filename)
                        let newURL = dirURL.appendingPathComponent(newName)
                        plannedRenames.append((from: filename, to: newName, oldURL: oldURL, newURL: newURL))
                    }
                }
            }

            guard !plannedRenames.isEmpty else {
                return .success("No files in `\(dirRaw)` matched search pattern '\(searchStr)'.", data: ["renamedCount": "0"])
            }

            if isDryRun {
                let preview = plannedRenames.map { "  • \($0.from) -> \($0.to)" }.joined(separator: "\n")
                return .success(
                    "Dry run: \(plannedRenames.count) file(s) would be renamed in `\(dirRaw)`:\n\(preview)",
                    data: ["dryRun": "true", "matchCount": "\(plannedRenames.count)"]
                )
            }

            var changedFiles: [String] = []
            for item in plannedRenames {
                try FileManager.default.moveItem(at: item.oldURL, to: item.newURL)
                changedFiles.append((dirRaw as NSString).appendingPathComponent(item.to))
            }

            let summary = plannedRenames.map { "  • \($0.from) -> \($0.to)" }.joined(separator: "\n")
            return .success(
                "Successfully batch-renamed \(plannedRenames.count) file(s) in `\(dirRaw)`:\n\(summary)",
                data: ["renamedCount": "\(plannedRenames.count)"],
                filesChanged: changedFiles
            )
        } catch {
            return .failure("Failed to batch rename files in `\(dirRaw)`: \(error.localizedDescription)")
        }
    }
}
