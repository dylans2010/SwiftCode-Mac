import Foundation

public enum AssistCapability {
    public static let toolIdentifier = "com.SwiftCode.AssistTool"

    public static func identifiers(enabled: Bool) -> [String] {
        enabled ? [toolIdentifier] : []
    }

    public static func isCapable(identifiers: [String]) -> Bool {
        identifiers.contains(toolIdentifier)
    }
}

public enum AssistCapabilityKind: String, Codable {
    case `extension`
    case skill
    case connection
}
