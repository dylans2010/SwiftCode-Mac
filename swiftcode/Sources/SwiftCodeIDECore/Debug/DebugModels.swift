// Adapted from SwiftCode-Legacy SwiftCode/Core/Debug/DebugModels.swift (Dylan's own code;
// direct port authorised under MIT). See bulk/core-dispositions.tsv.
import Foundation

// `StackFrame` is declared once, in SwiftCodeDebug (the DAP client's
// model: name/file/line/column/instructionPointer). IDECore's debug UI
// imports SwiftCodeDebug and uses that shape; the bulk port's duplicate
// `function`/`location` struct shadowed it and broke every `.file` access.

public struct DebugVariable: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let value: String
    public let type: String

    public init(name: String, value: String, type: String) {
        self.id = UUID()
        self.name = name
        self.value = value
        self.type = type
    }
}
