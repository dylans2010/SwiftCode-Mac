import Foundation

public struct AssistPackageDependencyAddTool: AssistTool {
    public let id = "package_dependency_add"
    public let name = "Add Package Dependency"
    public let description = "Inserts a .package(url:from:) entry into the dependencies array in Package.swift."

    public init() {}

    public var capability: ToolCapability { .compilation }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Adds a Swift package dependency to Package.swift.",
            properties: [
                "url": JSONSchema(type: "string", description: "Repository URL of the package (e.g. https://github.com/apple/swift-argument-parser)."),
                "requirement": JSONSchema(type: "string", description: "Requirement such as 'from: \"1.0.0\"' or just '1.0.0'. Default: 'from: \"1.0.0\"'."),
                "product": JSONSchema(type: "string", description: "Optional product name to wire into a target's dependencies."),
                "target": JSONSchema(type: "string", description: "Optional target name whose dependencies array should gain the product.")
            ],
            required: ["url"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let url = input["url"] as? String, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Missing required parameter: url")
        }
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedURL.contains(" ") || trimmedURL.contains("\n") || trimmedURL.contains("\r") || trimmedURL.contains("\"") {
            return .failure("Invalid url: must not contain spaces, newlines, or quotes.")
        }
        let requirementRaw = (input["requirement"] as? String) ?? "from: \"1.0.0\""
        let requirement = normalizedRequirement(requirementRaw)
        let product = (input["product"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = (input["target"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        let manifestURL = context.workspaceRoot.standardizedFileURL.appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return .failure("Package.swift not found in the workspace root.")
        }
        guard var content = try? String(contentsOf: manifestURL, encoding: .utf8) else {
            return .failure("Failed to read Package.swift.")
        }
        if content.contains(trimmedURL) {
            return .success("Dependency already present in Package.swift: \(trimmedURL)", data: ["url": trimmedURL, "alreadyPresent": "true"])
        }
        guard let depsRange = dependenciesArrayRange(in: content) else {
            return .failure("Could not find a 'dependencies:' array in Package.swift. Add one manually first.")
        }
        let entry = ".package(url: \"\(trimmedURL)\", \(requirement))"
        let inserted = insertEntry(entry, into: &content, range: depsRange)
        if !inserted {
            return .failure("Failed to insert the dependency into the dependencies array.")
        }
        var targetWiringNote = "none"
        if let product = product, !product.isEmpty, let target = target, !target.isEmpty {
            if insertProductIntoTarget(product: product, target: target, content: &content) {
                targetWiringNote = "wired product '\(product)' into target '\(target)'"
            } else {
                targetWiringNote = "package added but target '\(target)' dependencies array not found; product '\(product)' not wired"
            }
        } else if (product != nil && !(product?.isEmpty ?? true)) || (target != nil && !(target?.isEmpty ?? true)) {
            targetWiringNote = "both product and target are required for target wiring; package added without wiring"
        }
        do {
            try content.write(to: manifestURL, atomically: true, encoding: .utf8)
        } catch {
            return .failure("Failed to write Package.swift: \(error.localizedDescription)")
        }
        guard let reRead = try? String(contentsOf: manifestURL, encoding: .utf8), reRead.contains(trimmedURL) else {
            return .failure("Verification failed: url not present in Package.swift after write.")
        }
        return .success("Added dependency \(trimmedURL) to Package.swift. Target wiring: \(targetWiringNote)", data: ["url": trimmedURL, "requirement": requirement, "targetWiring": targetWiringNote])
    }

    private func normalizedRequirement(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "from: \"1.0.0\"" }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("from:") || lower.hasPrefix("exact:") || lower.hasPrefix("branch:") || lower.hasPrefix("revision:") || lower.hasPrefix("upToNextMajor") || lower.hasPrefix("upToNextMinor") || lower.hasPrefix("range:") {
            return trimmed
        }
        let version = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return "from: \"\(version)\""
    }

    private func dependenciesArrayRange(in content: String) -> Range<String.Index>? {
        guard let depsMarker = content.range(of: "dependencies:") else { return nil }
        guard let openBracket = content.range(of: "[", range: depsMarker.upperBound..<content.endIndex) else { return nil }
        guard let closeBracket = content.range(of: "]", range: openBracket.upperBound..<content.endIndex) else { return nil }
        return openBracket.lowerBound..<closeBracket.upperBound
    }

    private func insertEntry(_ entry: String, into content: inout String, range: Range<String.Index>) -> Bool {
        let arrayText = String(content[range])
        guard arrayText.hasPrefix("[") && arrayText.hasSuffix("]") else { return false }
        let inner = String(arrayText.dropFirst().dropLast())
        let innerTrimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement: String
        if innerTrimmed.isEmpty {
            replacement = "[\n        \(entry)\n    ]"
        } else {
            let needsComma = !innerTrimmed.hasSuffix(",")
            if needsComma {
                replacement = "[\n" + inner + ",\n        \(entry)\n    ]"
            } else {
                replacement = "[\n" + inner + "\n        \(entry)\n    ]"
            }
        }
        content.replaceSubrange(range, with: replacement)
        return true
    }

    private func insertProductIntoTarget(product: String, target: String, content: inout String) -> Bool {
        let needle = "name: \"\(target)\""
        guard let nameRange = content.range(of: needle) else { return false }
        let afterName = content[nameRange.upperBound...]
        guard let depsMarker = afterName.range(of: "dependencies:") else { return false }
        let absoluteDepsStart = depsMarker.lowerBound
        guard let openBracket = content.range(of: "[", range: absoluteDepsStart..<content.endIndex) else { return false }
        guard let closeBracket = content.range(of: "]", range: openBracket.upperBound..<content.endIndex) else { return false }
        if String(content[openBracket.upperBound..<closeBracket.lowerBound]).contains("\"\(product)\"") {
            return true
        }
        let inner = String(content[openBracket.upperBound..<closeBracket.lowerBound])
        let innerTrimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement: String
        if innerTrimmed.isEmpty {
            replacement = "\"\(product)\""
        } else if innerTrimmed.hasSuffix(",") {
            replacement = inner + " \"\(product)\""
        } else {
            replacement = inner + ", \"\(product)\""
        }
        content.replaceSubrange(openBracket.upperBound..<closeBracket.lowerBound, with: replacement)
        return true
    }
}
