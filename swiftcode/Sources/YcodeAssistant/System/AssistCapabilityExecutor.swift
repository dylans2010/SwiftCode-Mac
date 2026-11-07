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
