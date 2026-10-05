//
//  AssistAvailableModel.swift
//  SwiftCode
//
//  Universal internal model-provider abstraction for Assist and Antigravity.
//

import Foundation

public enum ModelSource: String, Codable, Sendable, CaseIterable {
    case gemini = "Gemini"
    case claude = "Claude"
    case openAI = "OpenAI"
    case appleFoundation = "Apple Foundation Models"
    case custom = "Custom Models"
    case local = "Local Models"
    case openRouter = "OpenRouter"

    public static let appleFoundationModels = ModelSource.appleFoundation

    public var iconName: String {
        switch self {
        case .gemini: return "sparkles"
        case .claude: return "brain"
        case .openAI: return "bolt.fill"
        case .appleFoundation: return "apple.logo"
        case .custom: return "cube.fill"
        case .local: return "desktopcomputer"
        case .openRouter: return "network"
        }
    }
}

public enum AssistModelStatus: String, Codable, Sendable {
    case available = "Available"
    case configured = "Configured"
    case unavailable = "Unavailable"
    case authRequired = "Authentication Required"
    case providerUnavailable = "Provider Unavailable"
    case rateLimited = "Rate Limited"
    case unsupportedAgentic = "Unsupported for Agentic Use"
}

public struct AssistAvailableModel: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let displayName: String
    public let providerID: String
    public let providerName: String
    public let modelIdentifier: String

    public let capabilities: ModelCapabilities
    public let source: ModelSource
    public let isConfigured: Bool
    public var isAvailable: Bool

    public let supportsStreaming: Bool
    public let supportsToolCalling: Bool
    public let supportsVision: Bool
    public let supportsStructuredOutput: Bool
    public let supportsAgenticUse: Bool
    public let supportsSubagents: Bool

    public let priority: Int
    public var statusDescription: String
    public var status: AssistModelStatus
    public var rateLimitedUntil: Date?
    public var lastFailureReason: String?
    public var contextWindow: Int
    public var endpointURL: String?

    public init(
        id: String,
        displayName: String,
        providerID: String,
        providerName: String,
        modelIdentifier: String,
        capabilities: ModelCapabilities = .standardCloud,
        source: ModelSource,
        isConfigured: Bool = true,
        isAvailable: Bool = true,
        supportsStreaming: Bool = true,
        supportsToolCalling: Bool = true,
        supportsVision: Bool = false,
        supportsStructuredOutput: Bool = true,
        supportsAgenticUse: Bool = true,
        supportsSubagents: Bool = true,
        priority: Int = 100,
        statusDescription: String = "Available",
        status: AssistModelStatus = .available,
        rateLimitedUntil: Date? = nil,
        lastFailureReason: String? = nil,
        contextWindow: Int = 128_000,
        endpointURL: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.providerID = providerID
        self.providerName = providerName
        self.modelIdentifier = modelIdentifier
        self.capabilities = capabilities
        self.source = source
        self.isConfigured = isConfigured
        self.isAvailable = isAvailable
        self.supportsStreaming = supportsStreaming
        self.supportsToolCalling = supportsToolCalling
        self.supportsVision = supportsVision
        self.supportsStructuredOutput = supportsStructuredOutput
        self.supportsAgenticUse = supportsAgenticUse
        self.supportsSubagents = supportsSubagents
        self.priority = priority
        self.statusDescription = statusDescription
        self.status = status
        self.rateLimitedUntil = rateLimitedUntil
        self.lastFailureReason = lastFailureReason
        self.contextWindow = contextWindow
        self.endpointURL = endpointURL
    }

    public var isCurrentlyRateLimited: Bool {
        guard let until = rateLimitedUntil else { return false }
        return Date() < until
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(modelIdentifier)
        hasher.combine(providerID)
    }

    public static func == (lhs: AssistAvailableModel, rhs: AssistAvailableModel) -> Bool {
        lhs.id == rhs.id && lhs.providerID == rhs.providerID && lhs.modelIdentifier == rhs.modelIdentifier
    }
}
