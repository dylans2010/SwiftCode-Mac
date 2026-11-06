import Foundation

// MARK: - SDK model selection (Wave 16, Slice D)
//
// Ported from Legacy (Dylan's own code; direct port authorised under
// MIT, spec-first where it costs nothing):
//   * `SwiftCode/Backend/Assist/AssistModelRouter.swift` —
//     `selectModelForSDK`, `buildSDKConfiguration`,
//     `createSyntheticSDKModel` (the last via
//     `AntigravitySDKCatalog.createSyntheticCandidate`), the
//     Gemini key-rotation branch of `handleTurnFailure`, and
//     `sdkDefaultModelIDs` (via `AntigravitySDKCatalog`).
//
// The Ycode equivalent of Legacy's `GoogleCloudSDKConfiguration`
// is `SDKSessionConfiguration`: the model, the host provider that
// will run it (`ChatRequest` + the chosen `ProviderKind`), the
// thinking level, and the execution mode. There is no
// `GoogleCloudSDKConfiguration` and no Antigravity SDK session in
// Ycode, so the fields that only a live SDK session consumes are
// not carried over: `vertex` / `project` / `location` (Vertex AI),
// `skillsPaths` / `workspaces` / `appDataDir` / `saveDir` (the
// SDK's on-disk session), `tools` (the SDK's tool table),
// `litertModelPath` / `litertBackend`, `serviceTier`,
// `maxSubagentDepth` / `allowedSubagents`, `systemInstructions`,
// `useSavedModels`, `toolkit`, `downloadIfMissing`,
// `enableSpeculativeDecoding`, `activeExecutionMode`.
// What survives is what the host needs to run the turn: which
// model, through which provider, at which thinking level, with
// subagents on or off, and by key or by OAuth session.
//
// The configuration never carries a secret: `hasAPIKey` is a
// boolean, never the key. The host resolves the actual key from
// the `SecretStore` / `GeminiKeyRotationManager` when it sends.

// MARK: - Session configuration

/// What the host needs to run a turn for a selected model (the
/// Ycode equivalent of Legacy's `GoogleCloudSDKConfiguration`).
public struct SDKSessionConfiguration: Sendable, Equatable {
    /// The provider-side model id to send.
    public var model: String
    /// The host provider that will run the turn.
    public var provider: ProviderKind
    /// "Low" / "Medium" / "High" / "Minimal", when the model id
    /// implies one.
    public var thinkingLevel: String?
    /// Whether the model may spawn subagents.
    public var enableSubagents: Bool
    /// How the turn is authorized: `"antigravity"` (a Google
    /// OAuth session) or `"api_key"` (a stored provider key).
    /// Nil when neither is available — the turn cannot run.
    public var executionMode: String?
    /// Whether a stored key exists for this model (never the key
    /// itself).
    public var hasAPIKey: Bool
    /// Whether the turn runs under a Google OAuth session.
    public var isOAuthAuthenticated: Bool
    /// The endpoint this model talks to, when it is not the
    /// provider's default.
    public var baseURL: String?

    public init(
        model: String,
        provider: ProviderKind,
        thinkingLevel: String? = nil,
        enableSubagents: Bool = true,
        executionMode: String? = nil,
        hasAPIKey: Bool = false,
        isOAuthAuthenticated: Bool = false,
        baseURL: String? = nil
    ) {
        self.model = model
        self.provider = provider
        self.thinkingLevel = thinkingLevel
        self.enableSubagents = enableSubagents
        self.executionMode = executionMode
        self.hasAPIKey = hasAPIKey
        self.isOAuthAuthenticated = isOAuthAuthenticated
        self.baseURL = baseURL
    }
}

/// Builds the session configuration for a selected model (Legacy
/// `AssistModelRouter.buildSDKConfiguration`, adapted).
///
/// Execution-mode rules, verbatim in shape:
///   * OAuth, when the host reports a Google OAuth session and
///     the model is a Google / catalog model or no direct key
///     exists: `"antigravity"`, no key.
///   * Otherwise, when the model is a Google model and Gemini
///     key rotation is enabled: `"api_key"` (the active rotated
///     key — the caller resolves it from the rotation manager).
///   * Otherwise: `"api_key"` when a direct key exists,
///     `"antigravity"` when only an OAuth token exists, else nil.
public enum SDKSessionConfigurationBuilder {
    public static func build(
        for model: AssistCandidateModel,
        objective: String = "",
        isGoogleOAuthAuthenticated: Bool = false,
        alternativeKeysEnabled: Bool = false,
        isAntigravityCatalogModel: Bool = false
    ) -> SDKSessionConfiguration {
        _ = objective
        let lowerID = model.modelIdentifier.lowercased()
        let isGoogleProvider = lowerID.contains("gemini") || model.id.lowercased().contains("gemini")
        let hasDirectKey = model.hasCredentials
        let derivedLevel = AntigravitySDKCatalog.deriveThinkingLevel(modelID: model.modelIdentifier, displayName: model.displayName)

        let executionMode: String?
        let oauth: Bool
        if isGoogleOAuthAuthenticated && (isGoogleProvider || isAntigravityCatalogModel || !hasDirectKey) {
            executionMode = "antigravity"
            oauth = true
        } else if isGoogleProvider && alternativeKeysEnabled {
            executionMode = "api_key"
            oauth = false
        } else {
            executionMode = hasDirectKey ? "api_key" : (isGoogleOAuthAuthenticated ? "antigravity" : nil)
            oauth = executionMode == "antigravity"
        }

        return SDKSessionConfiguration(
            model: model.modelIdentifier,
            provider: model.provider,
            thinkingLevel: derivedLevel,
            enableSubagents: model.supportsSubagents,
            executionMode: executionMode,
            hasAPIKey: executionMode == "api_key" && hasDirectKey,
            isOAuthAuthenticated: oauth,
            baseURL: model.endpointURL
        )
    }
}

// MARK: - Router: SDK selection & rotation-aware failover

extension AssistModelRouter {
    /// Selects the model for an SDK-style session (Legacy
    /// `AssistModelRouter.selectModelForSDK`).
    ///
    ///   * SwiftCode Cloud short-circuit: when the cloud toggle
    ///     is on and the selected id is a cloud id, the cloud
    ///     model is used under every strategy.
    ///   * `"default"` / `"rotation"`: ONLY models listed in
    ///     the Antigravity catalog (`sdkDefaultModelIDs`),
    ///     restricted to the ones that are configured. An
    ///     explicit custom / third-party id (contains `/`, or
    ///     mentions ollama / llama / claude / gpt) is honoured
    ///     as-is; otherwise the first configured catalog model
    ///     wins. When the catalog does not know the effective id
    ///     (stale selection, fetch not completed), the full
    ///     discovered-candidate list is consulted before falling
    ///     back to a synthetic catalog record.
    ///   * `"app_models"`: the whole discovered-candidate list.
    ///   * Anything else: `resolveDefaultModel`.
    ///
    /// `candidates` is the eligible, ranked candidate list (the
    /// caller passes `eligibleCandidates` output). The method
    /// never returns nil: the last resort is a synthetic catalog
    /// record for the effective id, as in Legacy.
    public func selectModelForSDK(
        objective: String = "",
        preferredID: String,
        strategy: AssistRoutingStrategy,
        candidates: [AssistCandidateModel],
        useCloudModel: Bool,
        cloudConfigured: Bool = false,
        cloudRemainingToday: Int = SCCloudProvider.dailyRequestLimit,
        cloudModels: [AssistCandidateModel] = [],
        catalog: AntigravitySDKCatalog,
        isGoogleOAuthAuthenticated: Bool = false,
        alternativeKeysEnabled: Bool = false
    ) async -> (model: AssistCandidateModel, config: SDKSessionConfiguration) {
        if useCloudModel, SCCloudProvider.isCloudModelID(preferredID) {
            let cloudModel = Self.syntheticCloudModel(
                forCloudModelID: preferredID,
                remainingToday: cloudRemainingToday,
                isConfigured: cloudConfigured,
                firstDiscoveredEndpointName: cloudModels.first?.modelIdentifier
            )
            let config = SDKSessionConfigurationBuilder.build(
                for: cloudModel,
                objective: objective,
                isGoogleOAuthAuthenticated: isGoogleOAuthAuthenticated,
                alternativeKeysEnabled: alternativeKeysEnabled
            )
            return (cloudModel, config)
        }

        let targetModel: AssistCandidateModel
        switch strategy {
        case .providerDefault:
            let catalogIDs = await catalog.sdkDefaultModelIDs
            let validIds = catalogIDs.filter { id in
                candidates.contains { ($0.id == id || $0.modelIdentifier == id) && $0.isConfigured }
                    || isGoogleOAuthAuthenticated
            }
            let lowerPreferred = preferredID.lowercased()
            let isExplicitCustomOrThirdParty = preferredID.contains("/")
                || lowerPreferred.contains("ollama") || lowerPreferred.contains("llama")
                || lowerPreferred.contains("claude") || lowerPreferred.contains("gpt")
            let effectiveModelID: String
            if isExplicitCustomOrThirdParty || validIds.contains(preferredID) {
                effectiveModelID = preferredID
            } else if let first = validIds.first {
                effectiveModelID = first
            } else {
                effectiveModelID = preferredID
            }
            if await catalog.getModel(byID: effectiveModelID) != nil {
                targetModel = await catalog.createSyntheticCandidate(
                    modelID: effectiveModelID,
                    isConfigured: validIds.contains(effectiveModelID) || isGoogleOAuthAuthenticated
                )
            } else if let match = candidates.first(where: { $0.id == effectiveModelID || $0.modelIdentifier == effectiveModelID }) {
                targetModel = match
            } else if isExplicitCustomOrThirdParty {
                targetModel = await catalog.createSyntheticCandidate(modelID: effectiveModelID, isConfigured: false)
            } else if let first = candidates.first {
                targetModel = first
            } else {
                targetModel = await catalog.createSyntheticCandidate(modelID: effectiveModelID, isConfigured: false)
            }
        case .appModels:
            if let match = candidates.first(where: { $0.id == preferredID || $0.modelIdentifier == preferredID }) {
                targetModel = match
            } else if let first = candidates.first {
                targetModel = first
            } else {
                targetModel = Self.resolveDefaultModel(
                    preferredID: preferredID,
                    discovered: candidates,
                    useCloudModel: useCloudModel,
                    cloudConfigured: cloudConfigured,
                    cloudRemainingToday: cloudRemainingToday,
                    cloudModels: cloudModels
                )
            }
        }

        let isCatalog = await catalog.isAntigravityCatalogModel(targetModel.modelIdentifier)
        let config = SDKSessionConfigurationBuilder.build(
            for: targetModel,
            objective: objective,
            isGoogleOAuthAuthenticated: isGoogleOAuthAuthenticated,
            alternativeKeysEnabled: alternativeKeysEnabled,
            isAntigravityCatalogModel: isCatalog
        )
        return (targetModel, config)
    }

    /// Handles a failed turn with Gemini key rotation first
    /// (Legacy `AssistModelRouter.handleTurnFailure`'s rotation
    /// branch, verbatim in shape).
    ///
    /// When rotation is enabled (`alternativeKeysEnabled`) and
    /// the failure is a rate limit / quota exhaustion, the active
    /// alternative key is marked rate-limited for 60s and the
    /// next available key is selected: the SAME model is retried
    /// with the new key, and the returned handoff names the
    /// rotated key's masked value. Only when no other key is
    /// usable does the turn fall through to the plain
    /// `handleTurnFailure` (next model, or nil when automatic
    /// switching is off). `keyRotated` reports which path was
    /// taken; the config is built for the returned model either
    /// way.
    public func handleTurnFailureWithKeyRotation(
        failedModel: AssistCandidateModel,
        error: Error,
        completedTurnContent: String,
        executedToolsCount: Int,
        objective: String = "",
        automaticallySwitchModels: Bool,
        eligibleCandidates: [AssistCandidateModel],
        keyRotation: GeminiKeyRotationManager?,
        alternativeKeysEnabled: Bool,
        isGoogleOAuthAuthenticated: Bool = false
    ) async -> (nextModel: AssistCandidateModel, continuationPrompt: String, keyRotated: Bool, config: SDKSessionConfiguration)? {
        let failureClass = Self.classify(error: error)
        if alternativeKeysEnabled, let rotation = keyRotation,
           failureClass == .rateLimited || failureClass == .quotaExhausted {
            if let activeId = await rotation.activeKeyId {
                await rotation.markRateLimited(id: activeId, retryAfterSeconds: 60)
            }
            if let nextKeyInfo = await rotation.selectNextAvailableKey() {
                markRateLimited(modelID: failedModel.id)
                markRateLimited(modelID: failedModel.modelIdentifier)
                let config = SDKSessionConfigurationBuilder.build(
                    for: failedModel,
                    objective: objective,
                    isGoogleOAuthAuthenticated: isGoogleOAuthAuthenticated,
                    alternativeKeysEnabled: alternativeKeysEnabled,
                    isAntigravityCatalogModel: false
                )
                var handoff = "CONTINUATION DIRECTIVE:\nRotated to next Gemini API key (\(nextKeyInfo.metadata.maskedValue)) due to rate limit.\n\n"
                if !completedTurnContent.isEmpty {
                    handoff += "Partial output:\n\"\"\"\n\(completedTurnContent)\n\"\"\"\n\n"
                }
                handoff += "Continue fulfilling the objective without repeating already completed work."
                return (failedModel, handoff, true, config)
            }
        }

        guard let result = handleTurnFailure(
            failedModel: failedModel,
            error: error,
            completedTurnContent: completedTurnContent,
            executedToolsCount: executedToolsCount,
            objective: objective,
            automaticallySwitchModels: automaticallySwitchModels,
            eligibleCandidates: eligibleCandidates
        ) else {
            return nil
        }
        let config = SDKSessionConfigurationBuilder.build(
            for: result.nextModel,
            objective: objective,
            isGoogleOAuthAuthenticated: isGoogleOAuthAuthenticated,
            alternativeKeysEnabled: alternativeKeysEnabled,
            isAntigravityCatalogModel: false
        )
        return (result.nextModel, result.continuationPrompt, false, config)
    }
}
