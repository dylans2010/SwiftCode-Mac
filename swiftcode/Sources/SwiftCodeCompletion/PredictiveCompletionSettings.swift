import Foundation
import SwiftCodeAssistant

public struct PredictiveCompletionSettings: Codable, Sendable, Equatable {
    public enum Backend: String, Codable, Sendable, CaseIterable {
        case ollama
        case llamaServer
        case openAICompatible

        public var displayName: String {
            switch self {
            case .ollama: "Ollama"
            case .llamaServer: "llama.cpp server"
            case .openAICompatible: "OpenAI-compatible server"
            }
        }

        public var defaultAddress: String {
            switch self {
            case .ollama: OllamaProvider.defaultBaseURL
            case .llamaServer, .openAICompatible: ChatCompletionsProvider.defaultBaseURL
            }
        }
    }

    public static let defaultsKey = "SwiftCode.predictiveCompletion"
    public static let assistantDefaultsKey = "SwiftCode.codingAssistant"

    public var enabled = false
    public var backend: Backend = .ollama
    public var address: String?
    public var model = ""
    public var maxTokens = 128
    public var debounceMilliseconds = 250
    public var temperature: Double? = 0.2
    public var topP: Double?
    public var topK: Int?
    public var repeatPenalty: Double?
    public var prefixTokens = 1536
    public var suffixTokens = 512
    public var relatedTokens = 512
    public var fimFormat: FIMFormat = .auto
    public var maxLines = 12

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PredictiveCompletionSettings()
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? d.enabled
        backend = (try? c.decode(Backend.self, forKey: .backend)) ?? d.backend
        address = try? c.decodeIfPresent(String.self, forKey: .address)
        model = (try? c.decode(String.self, forKey: .model)) ?? d.model
        maxTokens = (try? c.decode(Int.self, forKey: .maxTokens)) ?? d.maxTokens
        debounceMilliseconds = (try? c.decode(Int.self, forKey: .debounceMilliseconds)) ?? d.debounceMilliseconds
        if c.contains(.temperature) {
            temperature = (try? c.decodeIfPresent(Double.self, forKey: .temperature)).flatMap { $0 }
        } else {
            temperature = d.temperature
        }
        topP = try? c.decodeIfPresent(Double.self, forKey: .topP)
        topK = try? c.decodeIfPresent(Int.self, forKey: .topK)
        repeatPenalty = try? c.decodeIfPresent(Double.self, forKey: .repeatPenalty)
        prefixTokens = (try? c.decode(Int.self, forKey: .prefixTokens)) ?? d.prefixTokens
        suffixTokens = (try? c.decode(Int.self, forKey: .suffixTokens)) ?? d.suffixTokens
        relatedTokens = (try? c.decode(Int.self, forKey: .relatedTokens)) ?? d.relatedTokens
        fimFormat = (try? c.decode(FIMFormat.self, forKey: .fimFormat)) ?? d.fimFormat
        maxLines = (try? c.decode(Int.self, forKey: .maxLines)) ?? d.maxLines
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(backend, forKey: .backend)
        try c.encodeIfPresent(address, forKey: .address)
        try c.encode(model, forKey: .model)
        try c.encode(maxTokens, forKey: .maxTokens)
        try c.encode(debounceMilliseconds, forKey: .debounceMilliseconds)
        try c.encode(temperature, forKey: .temperature)
        try c.encodeIfPresent(topP, forKey: .topP)
        try c.encodeIfPresent(topK, forKey: .topK)
        try c.encodeIfPresent(repeatPenalty, forKey: .repeatPenalty)
        try c.encode(prefixTokens, forKey: .prefixTokens)
        try c.encode(suffixTokens, forKey: .suffixTokens)
        try c.encode(relatedTokens, forKey: .relatedTokens)
        try c.encode(fimFormat, forKey: .fimFormat)
        try c.encode(maxLines, forKey: .maxLines)
    }

    enum CodingKeys: String, CodingKey {
        case enabled, backend, address, model, maxTokens, debounceMilliseconds, temperature, topP, topK, repeatPenalty
        case prefixTokens, suffixTokens, relatedTokens, fimFormat, maxLines
    }

    public func effectiveAddress(assistantOllamaURL: String? = nil) -> String {
        if let a = address?.trimmingCharacters(in: .whitespaces), !a.isEmpty { return a }
        if backend == .ollama, let s = assistantOllamaURL, !s.isEmpty { return s }
        return backend.defaultAddress
    }

    public var limits: ContextLimits {
        ContextLimits(prefixTokens: max(64, prefixTokens), suffixTokens: max(0, suffixTokens), relatedTokens: max(0, relatedTokens))
    }

    public static func load(from defaults: UserDefaults) -> PredictiveCompletionSettings {
        guard let d = defaults.data(forKey: defaultsKey), let s = try? JSONDecoder().decode(Self.self, from: d) else { return Self() }
        return s
    }

    public func save(to defaults: UserDefaults) {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        defaults.set(try? e.encode(self), forKey: Self.defaultsKey)
    }

    public static func assistantOllamaURL(in defaults: UserDefaults) -> String? {
        guard let d = defaults.data(forKey: assistantDefaultsKey), let s = try? JSONDecoder().decode(AssistantSettings.self, from: d) else { return nil }
        return s.ollamaURL
    }

    public static func assistantOllamaModel(in defaults: UserDefaults) -> String? {
        guard let d = defaults.data(forKey: assistantDefaultsKey), let s = try? JSONDecoder().decode(AssistantSettings.self, from: d),
              let m = s.model(for: .ollama), !m.isEmpty else { return nil }
        return m
    }

    public static let xcodeEditorSwitchKey = "DVTTextEnablePredictiveCompletion"
    public static let xcodeOnDeviceModelKey = "DVTEnableOnDeviceCodePredictions"

    @discardableResult
    public mutating func importXcodePreferences(_ values: [String: Any]) -> Bool {
        let flags = [Self.xcodeEditorSwitchKey, Self.xcodeOnDeviceModelKey].compactMap { values[$0].flatMap(Self.bool) }
        guard !flags.isEmpty else { return false }
        let on = flags.allSatisfy { $0 }
        defer { enabled = on }
        return enabled != on
    }

    static func bool(_ v: Any) -> Bool? {
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        if let i = v as? Int { return i != 0 }
        if let s = v as? String { return ["1", "yes", "true", "on"].contains(s.lowercased()) ? true : (["0", "no", "false", "off"].contains(s.lowercased()) ? false : nil) }
        return nil
    }
}
