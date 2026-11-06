import Foundation
import SwiftCodeAssistant
import SwiftCodeIDECore
import SwiftCodeSDK

// MARK: - SwiftCodeSDKAssistResolver
//
// Wave 16, Slice C: the host provider resolver for the SDK Assist
// backend (`SDKAssistHostBackend`). It answers one question — which
// host provider (and model) serves this extension session's turn —
// and it answers it from the host's own configuration only:
//
//   - Provider kind: the session's requested model, when set, routed
//     through the host's existing model→provider resolution
//     (`AssistantBackends.providerKind(forModelID:)`); otherwise the
//     provider the user chose in Settings ▸ Coding Assistant.
//   - Model: the session's requested model, otherwise the model the
//     user configured for that provider.
//   - The provider itself comes from `CodingAssistantServices`,
//     which builds it from host settings + the host secret store.
//     The key is read inside `AssistantBackends.provider(_:)` and
//     held opaquely by the provider; this resolver never sees a key
//     value, and nothing here is passed to the extension caller.
//
// What this resolver does NOT do: it never opens the host's
// conversation store, never hands the backend a host session, and
// never lets the extension pick a provider outside the host's own
// resolution (an extension-supplied model ID is only ever routed
// through `providerKind(forModelID:)` — a bare unknown ID resolves
// through the host's model specification, and the backend's
// text-completion allowlist still applies afterwards, so an
// agent-provider ID can never smuggle an agent turn through).
//
// The resolver runs on the main actor (`CodingAssistantServices` is
// `@MainActor`); the backend awaits it from its own isolation.

public struct SwiftCodeSDKAssistResolver: SDKAssistProviderResolving, Sendable {
    public init() {}

    public func resolveProvider(for session: SDKAssistSession) async throws -> SDKAssistProviderResolution {
        await MainActor.run {
            let services = CodingAssistantServices.shared
            let prefs = services.preferences ?? .shared
            let settings = prefs.codingAssistant
            let backends = services.backends(prefs)
            let kind: ProviderKind
            if let model = session.model, !model.isEmpty {
                kind = backends.providerKind(forModelID: model)
            } else {
                kind = settings.provider
            }
            let provider = services.provider(kind, prefs: prefs)
            let modelID = session.model ?? settings.model(for: kind)
            return SDKAssistProviderResolution(provider: provider, modelID: modelID)
        }
    }
}
