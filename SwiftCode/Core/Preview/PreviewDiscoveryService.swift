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
