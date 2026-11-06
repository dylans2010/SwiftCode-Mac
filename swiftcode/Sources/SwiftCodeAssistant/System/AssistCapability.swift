// Ported from Legacy `SwiftCode/Backend/Assist/API/AssistCapability.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged only — not yet merged into swiftcode/Sources. See staging-wire/missing/DISPOSITIONS.md.
// Verbatim except for the appended AssistCapabilityKind: Legacy defined it in
// `SwiftCode/Backend/Assist/AssistModels.swift`, whose destination port deliberately
// skipped it (see AssistModels.swift header); it is defined here because
// AssistCapabilityExecutor.swift in this same target takes it as a parameter.
// Wiring: none — pure capability identifier/membership API.

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

// Legacy defined this enum in `SwiftCode/Backend/Assist/AssistModels.swift`
// (not ported there); it lives here because AssistCapabilityExecutor.swift
// in this same target takes it as a parameter.
public enum AssistCapabilityKind: String, Codable {
    case `extension`
    case skill
    case connection
}
