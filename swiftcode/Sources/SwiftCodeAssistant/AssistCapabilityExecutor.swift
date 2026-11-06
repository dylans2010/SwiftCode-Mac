// Ported from Legacy `SwiftCode/Backend/Assist/API/AssistCapabilityExecutor.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged only — not yet merged into swiftcode/Sources. See staging-wire/missing/DISPOSITIONS.md.
// Verbatim. Depends on AssistManager.shared.registerCapabilityExecution
// (staged in this same batch) and AssistCapabilityKind (defined in
// AssistCapability.swift, same target). Wiring: none — called by the
// extension/skill/connection capability paths.

import Foundation

@MainActor
public enum AssistCapabilityExecutor {
    public static func executeIfNeeded(
        kind: AssistCapabilityKind,
        name: String,
        identifiers: [String],
        payload: [String: String]
    ) {
        guard AssistCapability.isCapable(identifiers: identifiers) else { return }

        let details = payload
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")

        let content = """
        [Assist Capability]
        \(kind.rawValue.capitalized): \(name)
        Identifier: \(AssistCapability.toolIdentifier)
        \(details)
        """

        AssistManager.shared.registerCapabilityExecution(content)
    }
}
