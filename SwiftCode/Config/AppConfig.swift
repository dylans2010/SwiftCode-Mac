import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.app", category: "AppConfig")

public struct AppConfig: Sendable {
    public static let shared = AppConfig()

    private let configuredSupabaseURL: URL?
    private let configuredSupabaseAnonKey: String?
    private let configuredOpenRouterAPIKey: String?
    private let configuredGeminiAPIKey: String?
    private let configuredSwiftCloudAPIURL: URL?

    public var supabaseURL: URL {
        if let configuredSupabaseURL { return configuredSupabaseURL }
        // SAFETY: The hardcoded fallback URL is known to be a valid and well-formed URL.
        return URL(string: "https://secctbuzkfbketdihzui.supabase.co")!
    }

    public var supabaseAnonKey: String {
        if let configuredSupabaseAnonKey { return configuredSupabaseAnonKey }
        return "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlY2N0YnV6a2Zia2V0ZGloenVpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MDcxMDUwMDAsImV4cCI6MjAyNjg2MTAwMH0.mock-key-signature"
    }

    public var openRouterAPIKey: String {
        return configuredOpenRouterAPIKey ?? ""
    }

    public var geminiAPIKey: String {
        return configuredGeminiAPIKey ?? ""
    }

    public var swiftCloudAPIURL: URL {
        if let configuredSwiftCloudAPIURL { return configuredSwiftCloudAPIURL }
        // SAFETY: The hardcoded fallback SwiftCloud API URL is known to be a valid and well-formed URL.
        return URL(string: "https://api.swiftcloud.ai/v1")!
    }

    private init() {
        let bundle = Bundle.main

        // Helper to load and sanitize string value from Bundle
        func loadString(for key: String) -> String? {
            guard let rawValue = bundle.object(forInfoDictionaryKey: key) as? String else {
                return nil
            }
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("$") || trimmed.contains("placeholder") {
                return nil
            }
            return trimmed
        }

        self.configuredSupabaseURL = loadString(for: "SUPABASE_URL").flatMap { URL(string: $0) }
        self.configuredSupabaseAnonKey = loadString(for: "SUPABASE_ANON_KEY")
        self.configuredOpenRouterAPIKey = loadString(for: "OPENROUTER_API_KEY")
        self.configuredGeminiAPIKey = loadString(for: "GEMINI_API_KEY")
        self.configuredSwiftCloudAPIURL = loadString(for: "SWIFTCLOUD_API_URL").flatMap { URL(string: $0) }

        logger.log("[AppConfig] Centralized configuration loaded successfully.")
    }

    /// Structured Diagnostics of configuration load status
    public func runDiagnostics() -> [String: String] {
        return [
            "configuredSupabaseURL": configuredSupabaseURL != nil ? "LOADED" : "MISSING",
            "configuredSupabaseAnonKey": configuredSupabaseAnonKey != nil ? "LOADED" : "MISSING",
            "configuredOpenRouterAPIKey": configuredOpenRouterAPIKey != nil ? "LOADED" : "MISSING",
            "configuredGeminiAPIKey": configuredGeminiAPIKey != nil ? "LOADED" : "MISSING",
            "configuredSwiftCloudAPIURL": configuredSwiftCloudAPIURL != nil ? "LOADED" : "MISSING"
        ]
    }
}
