import Foundation
import os

public actor PreviewDiscoveryService {
    private let logger = Logger(subsystem: "com.swiftcode.preview", category: "DiscoveryService")

    public init() {}

    public func discoverPreviews(inSourceCode sourceCode: String) async -> [String] {
        logger.info("[BEGIN] Scanning source code for SwiftUI Previews")
        var previews: [String] = []

        // Pattern 1: Modern #Preview macro
        if let regexModern = try? NSRegularExpression(pattern: #"#Preview\s*(?:\(\s*\"([^\"]+)\"\s*\))?\s*\{"#, options: []) {
            let nsStr = sourceCode as NSString
            let matches = regexModern.matches(in: sourceCode, options: [], range: NSRange(location: 0, length: nsStr.length))
            for m in matches {
                if m.numberOfRanges > 1, let nameRange = Range(m.range(at: 1), in: sourceCode) {
                    previews.append(String(sourceCode[nameRange]))
                } else {
                    previews.append("SwiftUI Preview")
                }
            }
        }

        // Pattern 2: Legacy PreviewProvider protocol
        if let regexLegacy = try? NSRegularExpression(pattern: #"struct\s+(\w+)\s*:\s*PreviewProvider"#, options: []) {
            let nsStr = sourceCode as NSString
            let matches = regexLegacy.matches(in: sourceCode, options: [], range: NSRange(location: 0, length: nsStr.length))
            for m in matches {
                if m.numberOfRanges > 1, let structRange = Range(m.range(at: 1), in: sourceCode) {
                    previews.append(String(sourceCode[structRange]))
                }
            }
        }

        logger.info("[END] Discovered \(previews.count) previews")
        return previews
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
