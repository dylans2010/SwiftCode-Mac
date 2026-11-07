import Foundation
import Testing
@testable import YcodeMCP
import YcodeAssistant

extension MCPToolResult {
    var isToolError: Bool { isError }

    var firstText: String {
        for block in content where block["type"]?.string == "text" {
            if let text = block["text"]?.string { return text }
        }
        return ""
    }
}
