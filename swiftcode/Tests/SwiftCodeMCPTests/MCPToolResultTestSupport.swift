import Foundation
import Testing
@testable import SwiftCodeMCP
import SwiftCodeAssistant

// Shared read helpers for the MCP test module. `firstText`/`isToolError`
// were referenced by the migrated tests but never defined; the migrated
// sources expose `content: [AnyJSON]` and `isError` instead.

extension MCPToolResult {
    /// `isError` under the name the migrated tests use.
    var isToolError: Bool { isError }

    /// The first text content block's text, or "" when there is none.
    var firstText: String {
        for block in content where block["type"]?.string == "text" {
            if let text = block["text"]?.string { return text }
        }
        return ""
    }
}
