import Foundation
import os

public struct ParsedPreview: Sendable, Codable, Hashable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

/// Structured Preview target model representing a parsed `#Preview` declaration.
public struct PreviewTarget: Sendable, Codable, Hashable, Identifiable {
    public var id: String { title }
    public let title: String
    public let rootView: String
    public let device: String?
    public let traits: String?

    public init(title: String, rootView: String, device: String?, traits: String?) {
        self.title = title
        self.rootView = rootView
        self.device = device
        self.traits = traits
    }
}

public struct PreviewBlockParser {
    public static func parsePreviews(in sourceCode: String) -> [ParsedPreview] {
        var previews: [ParsedPreview] = []
        var index = sourceCode.startIndex

        while let previewRange = sourceCode[index...].range(of: "#Preview") {
            let start = previewRange.lowerBound
            let rest = sourceCode[previewRange.upperBound...]

            var title: String? = nil

            if let firstBraceRange = rest.range(of: "{") {
                let firstBraceIndex = firstBraceRange.lowerBound
                let candidate = rest[..<firstBraceIndex]
                if let openP = candidate.range(of: "(")?.lowerBound,
                   let closeP = candidate.range(of: ")")?.lowerBound {
                    let insideP = candidate[candidate.index(after: openP)..<closeP]

                    let args = insideP.components(separatedBy: ",")
                    for arg in args {
                        let trimmed = arg.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.contains(":") && trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") {
                            title = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        }
                    }
                }
            }

            guard let openBraceRange = sourceCode[start...].range(of: "{") else {
                index = previewRange.upperBound
                continue
            }

            let blockStart = openBraceRange.upperBound
            var braceCount = 1
            var current = blockStart
            let end = sourceCode.endIndex

            while current < end && braceCount > 0 {
                let char = sourceCode[current]
                if char == "{" {
                    braceCount += 1
                } else if char == "}" {
                    braceCount -= 1
                }
                if braceCount > 0 {
                    current = sourceCode.index(after: current)
                }
            }

            if braceCount == 0 {
                let bodyCode = String(sourceCode[blockStart..<current]).trimmingCharacters(in: .whitespacesAndNewlines)
                let rootView = determineRootView(from: bodyCode)
                let resolvedTitle = title ?? rootView
                previews.append(ParsedPreview(title: resolvedTitle, body: bodyCode))
                index = sourceCode.index(after: current)
            } else {
                index = previewRange.upperBound
            }
        }

        return previews
    }

    public static func parsePreviewTargets(in sourceCode: String) -> [PreviewTarget] {
        var targets: [PreviewTarget] = []
        var index = sourceCode.startIndex

        while let previewRange = sourceCode[index...].range(of: "#Preview") {
            let start = previewRange.lowerBound
            let rest = sourceCode[previewRange.upperBound...]

            var title: String? = nil
            var device: String? = nil
            var traits: String? = nil

            if let firstBraceRange = rest.range(of: "{") {
                let firstBraceIndex = firstBraceRange.lowerBound
                let candidate = rest[..<firstBraceIndex]
                if let openP = candidate.range(of: "(")?.lowerBound,
                   let closeP = candidate.range(of: ")")?.lowerBound {
                    let insideP = candidate[candidate.index(after: openP)..<closeP]

                    let args = insideP.components(separatedBy: ",")
                    for arg in args {
                        let trimmed = arg.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.contains(":") {
                            let parts = trimmed.components(separatedBy: ":")
                            if parts.count >= 2 {
                                let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                                let val = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
                                if key == "device" {
                                    device = val
                                } else if key == "traits" {
                                    traits = val
                                }
                            }
                        } else if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") {
                            title = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        }
                    }
                }
            }

            guard let openBraceRange = sourceCode[start...].range(of: "{") else {
                index = previewRange.upperBound
                continue
            }

            let blockStart = openBraceRange.upperBound
            var braceCount = 1
            var current = blockStart
            let end = sourceCode.endIndex

            while current < end && braceCount > 0 {
                let char = sourceCode[current]
                if char == "{" {
                    braceCount += 1
                } else if char == "}" {
                    braceCount -= 1
                }
                if braceCount > 0 {
                    current = sourceCode.index(after: current)
                }
            }

            if braceCount == 0 {
                let bodyCode = String(sourceCode[blockStart..<current]).trimmingCharacters(in: .whitespacesAndNewlines)
                let rootView = determineRootView(from: bodyCode)
                let resolvedTitle = title ?? rootView
                targets.append(PreviewTarget(
                    title: resolvedTitle,
                    rootView: rootView,
                    device: device,
                    traits: traits
                ))
                index = sourceCode.index(after: current)
            } else {
                index = previewRange.upperBound
            }
        }

        return targets
    }

    private static func determineRootView(from body: String) -> String {
        if let regex = try? NSRegularExpression(pattern: #"([A-Z][A-Za-z0-9_]*)\s*[\(\{]"#) {
            let nsStr = body as NSString
            if let match = regex.firstMatch(in: body, range: NSRange(location: 0, length: nsStr.length)) {
                if match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: body) {
                    return String(body[range])
                }
            }
        }
        return "ContentView"
    }
}

public actor PreviewDiscoveryService {
    private let logger = Logger(subsystem: "com.swiftcode.preview", category: "DiscoveryService")

    public init() {}

    public func discoverPreviews(inSourceCode sourceCode: String) async -> [String] {
        return await discoverPreviewTargets(inSourceCode: sourceCode)
    }

    public func discoverPreviewTargets(inSourceCode sourceCode: String, filename: String? = nil) async -> [String] {
        logger.info("[BEGIN] Scanning source code for SwiftUI Previews with deterministic precedence")

        // 1. Modern #Preview macro
        let parsed = PreviewBlockParser.parsePreviews(in: sourceCode)
        let modernPreviews = parsed.map { $0.title }

        // 2. Legacy PreviewProvider protocol
        var legacyPreviews: [String] = []
        if let regexLegacy = try? NSRegularExpression(pattern: #"struct\s+(\w+)\s*:\s*PreviewProvider"#, options: []) {
            let nsStr = sourceCode as NSString
            let matches = regexLegacy.matches(in: sourceCode, options: [], range: NSRange(location: 0, length: nsStr.length))
            for m in matches {
                if m.numberOfRanges > 1, let structRange = Range(m.range(at: 1), in: sourceCode) {
                    legacyPreviews.append(String(sourceCode[structRange]))
                }
            }
        }

        // 3. Bare View conforming types
        var bareViews: [String] = []
        let pattern = #"struct\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(?:[^\{]*\s+)?View\b"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = sourceCode as NSString
            let matches = regex.matches(in: sourceCode, options: [], range: NSRange(location: 0, length: nsString.length))
            for m in matches {
                if m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: sourceCode) {
                    let viewName = String(sourceCode[r])
                    if !legacyPreviews.contains(viewName) {
                        bareViews.append(viewName)
                    }
                }
            }
        }

        if modernPreviews.isEmpty && legacyPreviews.isEmpty && bareViews.count > 1 {
            let firstSelected = bareViews.first ?? ""
            let message = "Ambiguity detected: multiple bare View types exist (\(bareViews.joined(separator: ", "))). Defaulting deterministically to '\(firstSelected)'."
            logger.warning("\(message)")
            await MainActor.run {
                PreviewDiagnostics.shared.addLog(category: "discovery", message: message)
            }
        }

        let result = modernPreviews + legacyPreviews + bareViews
        logger.info("[END] Discovered \(result.count) preview targets")
        return result
    }
}

// MARK: - Swift View Detector Helper

public struct SwiftViewDetector {
    public static func detectViews(in sourceCode: String) -> [String] {
        var views: [String] = []
        let pattern = #"struct\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(?:[^\{]*\s+)?View\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let nsString = sourceCode as NSString
        let matches = regex.matches(in: sourceCode, options: [], range: NSRange(location: 0, length: nsString.length))
        for m in matches {
            if m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: sourceCode) {
                views.append(String(sourceCode[r]))
            }
        }
        return views
    }

    public static func determinePrimaryView(in sourceCode: String, filename: String?) -> String? {
        let views = detectViews(in: sourceCode)
        guard !views.isEmpty else { return nil }

        if let filename = filename {
            let baseName = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
            if views.contains(baseName) {
                return baseName
            }
        }

        for viewName in views {
            let publicPattern = #"public\s+struct\s+\b\#(viewName)\b"#
            if sourceCode.range(of: publicPattern, options: .regularExpression) != nil {
                return viewName
            }
        }

        return views.first
    }

    public static func prepareSourceCode(_ sourceCode: String, filename: String?) -> (preparedCode: String, targetView: String?) {
        guard let primaryView = determinePrimaryView(in: sourceCode, filename: filename) else {
            return (sourceCode, nil)
        }

        let hasPreview = sourceCode.contains("#Preview") || sourceCode.contains("PreviewProvider")
        if hasPreview {
            return (sourceCode, primaryView)
        }

        let previewBlock = """


#Preview {
    \(primaryView)()
}
"""
        return (sourceCode + previewBlock, primaryView)
    }
}
