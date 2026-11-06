//
//  AssistUnusedImportsDetectorTool.swift
//  SwiftCode
//

import Foundation

public struct AssistUnusedImportsDetectorTool: AssistTool {
    public let id = "unused_imports_detector"
    public let name = "Unused Imports Detector"
    public let description = "Scans Swift files to detect redundant or unused framework imports."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Analyzes imports in a Swift file to detect unreferenced modules.",
            properties: [
                "path": JSONSchema(type: "string", description: "Relative path to the Swift file.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path")
        }

        let fileURL = path.hasPrefix("/") ? URL(fileURLWithPath: path) : context.workspaceRoot.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .failure("File not found at path: \(path)")
        }

        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return .failure("Unable to read content of \(path)")
        }

        let lines = content.components(separatedBy: .newlines)
        var importedModules: [(line: Int, module: String)] = []

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("import ") {
                let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 2 {
                    let mod = parts[1].replacingOccurrences(of: ";", with: "")
                    importedModules.append((line: i + 1, module: mod))
                }
            }
        }

        if importedModules.isEmpty {
            return .success("No framework imports found in `\(path)`.")
        }

        // Framework symbol map for common Apple frameworks
        let frameworkSymbols: [String: [String]] = [
            "Combine": ["AnyCancellable", "PassthroughSubject", "CurrentValueSubject", "Publisher", "sink", "store", "eraseToAnyPublisher"],
            "SwiftUI": ["View", "body", "some View", "Text", "VStack", "HStack", "State", "Binding", "Environment", "Color"],
            "AppKit": ["NSView", "NSViewController", "NSWindow", "NSApplication", "NSColor", "NSImage", "NSPasteboard", "NSWorkspace"],
            "UIKit": ["UIView", "UIViewController", "UIWindow", "UIApplication", "UIColor", "UIImage", "UIFont"],
            "os": ["Logger", "os_log", "OSLog"],
            "WebKit": ["WKWebView", "WKNavigationDelegate"],
            "AVFoundation": ["AVPlayer", "AVAudioSession", "AVCaptureSession"],
            "CoreData": ["NSManagedObject", "NSManagedObjectContext", "NSPersistentContainer"]
        ]

        var unusedCandidates: [String] = []

        // Remove the import lines to search the body
        let bodyContent = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("import ") }.joined(separator: "\n")

        for item in importedModules {
            let mod = item.module
            // If the module name itself is explicitly referenced
            if bodyContent.contains(mod + ".") {
                continue
            }

            // If we have known symbols for this framework, check if any appear
            if let symbols = frameworkSymbols[mod] {
                let foundSymbol = symbols.contains { bodyContent.contains($0) }
                if !foundSymbol {
                    unusedCandidates.append("Line \(item.line): `import \(mod)` — no known \(mod) symbols or explicit references found.")
                }
            }
        }

        if unusedCandidates.isEmpty {
            return .success("Import analysis clean: All imported modules appears to be referenced in `\(path)`.")
        } else {
            return .success("### Potentially Unused Imports in `\(path)`:\n\n" + unusedCandidates.map { "- \($0)" }.joined(separator: "\n"))
        }
    }
}
