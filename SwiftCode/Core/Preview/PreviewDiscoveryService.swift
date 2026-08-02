import Foundation
import os

public actor PreviewDiscoveryService {
    private let logger = Logger(subsystem: "com.swiftcode.preview", category: "DiscoveryService")

    public init() {}

    public func discoverPreviews(inSourceCode sourceCode: String) async -> [String] {
        return await discoverPreviewTargets(inSourceCode: sourceCode)
    }

    public func discoverPreviewTargets(inSourceCode sourceCode: String, filename: String? = nil) async -> [String] {
        logger.info("[BEGIN] Scanning source code for SwiftUI Previews with deterministic precedence")

        // 1. Modern #Preview macro
        var modernPreviews: [String] = []
        if let regexModern = try? NSRegularExpression(pattern: #"#Preview\s*(?:\(\s*\"([^\"]+)\"\s*\))?\s*\{"#, options: []) {
            let nsStr = sourceCode as NSString
            let matches = regexModern.matches(in: sourceCode, options: [], range: NSRange(location: 0, length: nsStr.length))
            var anonymousCount = 0
            for m in matches {
                if m.numberOfRanges > 1, let nameRange = Range(m.range(at: 1), in: sourceCode) {
                    modernPreviews.append(String(sourceCode[nameRange]))
                } else {
                    anonymousCount += 1
                    if anonymousCount == 1 {
                        modernPreviews.append("SwiftUI Preview")
                    } else {
                        modernPreviews.append("SwiftUI Preview \(anonymousCount)")
                    }
                }
            }
        }

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
                    // Filter out any PreviewProvider conforming structs or already matched targets
                    if !legacyPreviews.contains(viewName) {
                        bareViews.append(viewName)
                    }
                }
            }
        }

        // Log ambiguity if multiple bare views exist and there are no annotations (#Preview or PreviewProvider)
        if modernPreviews.isEmpty && legacyPreviews.isEmpty && bareViews.count > 1 {
            let firstSelected = bareViews.first ?? ""
            let message = "Ambiguity detected: multiple bare View types exist (\(bareViews.joined(separator: ", "))). Defaulting deterministically to '\(firstSelected)'."
            logger.warning("\(message)")
            await MainActor.run {
                PreviewDiagnostics.shared.addLog(category: "discovery", message: message)
            }
        }

        // Assemble final priority order: #Preview first, PreviewProvider next, bare View last
        let result = modernPreviews + legacyPreviews + bareViews
        logger.info("[END] Discovered \(result.count) preview targets")
        return result
    }
}

// MARK: - Swift View Detector Helper

public struct SwiftViewDetector {
    public static func detectViews(in sourceCode: String) -> [String] {
        var views: [String] = []
        // Standard SwiftUI view declaration: struct ViewName: View
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

        // Check if there is already a preview macro or PreviewProvider
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
