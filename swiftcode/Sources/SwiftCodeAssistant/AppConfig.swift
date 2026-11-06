// MOVED by fix W-V2 (A6 slice) from SwiftCodeCloud/AppConfig.swift — no content change
// except this note. Why: LLMService (SwiftCodeAssistant) reads AppConfig.shared at
// three sites (openRouterAPIKey / geminiAPIKey / swiftCloudAPIURL) and Assistant
// cannot depend on SwiftCodeCloud (Cloud already depends on Assistant — a cycle).
// AppConfig is a leaf Foundation-only config struct with no Cloud dependencies, and
// its only production user is LLMService, so it belongs in the lower target.
// SwiftCodeCloud keeps seeing it through its existing SwiftCodeAssistant dependency.

import Foundation

/// Centralized backend configuration, ported from Legacy's
/// `SwiftCode/Config/AppConfig.swift`.
///
/// Configuration shapes and defaults only — never secrets. The API
/// keys here are the *configured* values (Info.plist keys, as in
/// Legacy); the keys Dylan actually signs in with live in the
/// secret store (Wave 9) and are read from there, not from here.
/// An unconfigured key reads as `""`, exactly as Legacy did for
/// OpenRouter/Gemini.
///
/// One deliberate correction: Legacy's `supabaseAnonKey` fell back
/// to a hardcoded JWT whose signature segment is literally
/// `mock-key-signature` — a placeholder, not a usable credential.
/// Copying it would ship a fake credential that authenticates
/// nothing and looks like a leaked key to every scanner. This port
/// returns `""` when no anon key is configured, and
/// `runDiagnostics` reports it `MISSING`, so the gap is visible
/// instead of papered over. The Supabase project URL default is
/// Legacy's own public project URL, kept verbatim — it is a
/// configuration default, not a secret.
public struct AppConfig: Sendable {
    public static let shared = AppConfig()

    /// Legacy's Supabase project URL default (public configuration).
    public static let defaultSupabaseURL = URL(string: "https://secctbuzkfbketdihzui.supabase.co")!
    /// Legacy's SwiftCloud API URL default (public configuration).
    public static let defaultSwiftCloudAPIURL = URL(string: "https://api.swiftcloud.ai/v1")!

    private let configuredSupabaseURL: URL?
    private let configuredSupabaseAnonKey: String?
    private let configuredOpenRouterAPIKey: String?
    private let configuredGeminiAPIKey: String?
    private let configuredSwiftCloudAPIURL: URL?

    public var supabaseURL: URL {
        configuredSupabaseURL ?? Self.defaultSupabaseURL
    }

    /// The configured Supabase anon key, or `""` when none is
    /// configured. Legacy fell back to a mock-signed JWT here; see
    /// the type documentation for why that string is not carried
    /// over.
    public var supabaseAnonKey: String {
        configuredSupabaseAnonKey ?? ""
    }

    public var openRouterAPIKey: String {
        configuredOpenRouterAPIKey ?? ""
    }

    public var geminiAPIKey: String {
        configuredGeminiAPIKey ?? ""
    }

    public var swiftCloudAPIURL: URL {
        configuredSwiftCloudAPIURL ?? Self.defaultSwiftCloudAPIURL
    }

    /// Reads the five Info.plist keys Legacy read
    /// (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `OPENROUTER_API_KEY`,
    /// `GEMINI_API_KEY`, `SWIFTCLOUD_API_URL`). The explicit
    /// parameters are a test seam: pass a value to stand in for
    /// that key; `nil` (the default) reads the bundle, as in
    /// Legacy. A value that is empty, starts with `$`, or contains
    /// `placeholder` is treated as unconfigured, as in Legacy.
    public init(
        bundle: Bundle = .main,
        supabaseURL: String? = nil,
        supabaseAnonKey: String? = nil,
        openRouterAPIKey: String? = nil,
        geminiAPIKey: String? = nil,
        swiftCloudAPIURL: String? = nil
    ) {
        func loadString(_ override: String?, for key: String) -> String? {
            let raw: String?
            if let override {
                raw = override
            } else {
                raw = bundle.object(forInfoDictionaryKey: key) as? String
            }
            guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty, !value.hasPrefix("$"), !value.contains("placeholder") else {
                return nil
            }
            return value
        }

        self.configuredSupabaseURL = loadString(supabaseURL, for: "SUPABASE_URL").flatMap { URL(string: $0) }
        self.configuredSupabaseAnonKey = loadString(supabaseAnonKey, for: "SUPABASE_ANON_KEY")
        self.configuredOpenRouterAPIKey = loadString(openRouterAPIKey, for: "OPENROUTER_API_KEY")
        self.configuredGeminiAPIKey = loadString(geminiAPIKey, for: "GEMINI_API_KEY")
        self.configuredSwiftCloudAPIURL = loadString(swiftCloudAPIURL, for: "SWIFTCLOUD_API_URL").flatMap { URL(string: $0) }
    }

    /// Structured diagnostics of configuration load status, ported
    /// verbatim from Legacy: `LOADED` when the key was configured,
    /// `MISSING` otherwise. Values are never included.
    public func runDiagnostics() -> [String: String] {
        [
            "configuredSupabaseURL": configuredSupabaseURL != nil ? "LOADED" : "MISSING",
            "configuredSupabaseAnonKey": configuredSupabaseAnonKey != nil ? "LOADED" : "MISSING",
            "configuredOpenRouterAPIKey": configuredOpenRouterAPIKey != nil ? "LOADED" : "MISSING",
            "configuredGeminiAPIKey": configuredGeminiAPIKey != nil ? "LOADED" : "MISSING",
            "configuredSwiftCloudAPIURL": configuredSwiftCloudAPIURL != nil ? "LOADED" : "MISSING",
        ]
    }
}
