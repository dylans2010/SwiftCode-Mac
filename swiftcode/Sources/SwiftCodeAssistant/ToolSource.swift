// Adapted from SwiftCode-Legacy SwiftCode/Core/AI/Agent/ToolSource.swift (Dylan's own code;
// direct port authorised under MIT). See bulk/core-dispositions.tsv.
import Foundation

public enum ToolSource: String, Sendable, CaseIterable {
    case core
    case skill
    case connection
    case plugin
}
