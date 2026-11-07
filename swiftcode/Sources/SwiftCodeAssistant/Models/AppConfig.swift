import Foundation

public struct AppConfig: Sendable {
    public static let shared = AppConfig()

    public static let defaultSupabaseURL = URL(string: "https://secctbuzkfbketdihzui.supabase.co")!
    public static let defaultSwiftCloudAPIURL = URL(string: "https://api.swiftcloud.ai/v1")!

    private let configuredSupabaseURL: URL?
    private let configuredSupabaseAnonKey: String?
    private let configuredOpenRouterAPIKey: String?
    private let configuredGeminiAPIKey: String?
    private let configuredSwiftCloudAPIURL: URL?

    public var supabaseURL: URL {
        configuredSupabaseURL ?? Self.defaultSupabaseURL
    }

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
