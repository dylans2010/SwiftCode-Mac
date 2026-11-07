import Foundation
import SwiftCodeAssistant
import SwiftCodeIDECore
import SwiftCodeSDK

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
