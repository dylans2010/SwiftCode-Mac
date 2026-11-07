import Foundation

public struct SDKStudioCodeEditorSection: Identifiable, Sendable, Hashable {
    public var id: String { "codeEditor" }

    public var title: String { "Code Editor" }

    public var systemImage: String { "chevron.left.forwardslash.chevron.right" }

    public init() {}
}
