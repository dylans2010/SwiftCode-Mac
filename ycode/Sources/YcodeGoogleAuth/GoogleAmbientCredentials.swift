import Foundation

#if canImport(Security)
import Security
#endif

/// The ambient credentials the Google auth service falls back to
/// when no OAuth session of its own is stored: Antigravity's
/// keychain entry (from the `agy` CLI or Google Cloud tools), an
/// Application Default Credentials (ADC) file, and the `gcloud` CLI.
///
/// Ported from Legacy's `GoogleAccountAuthService` Antigravity and
/// ADC sections. The pure pieces (JSON parsing, path resolution,
/// CLI discovery) live here as static functions so tests can drive
/// them with fixtures; the pieces that need the network or the
/// keychain are composed by `GoogleAccountAuthService`.
///
/// Nothing here ever writes a credential anywhere: parsed
/// credentials are returned to the caller, which stores them in the
/// secret store through the service.
public enum GoogleAmbientCredentials: Sendable {

    // MARK: - Antigravity credentials

    /// Credentials read from Antigravity's keychain entry
    /// (service `gemini`, account `antigravity` /
    /// `antigravity-acp`): the OAuth client that minted them, its
    /// refresh token, a cached access token when present, and the
    /// scopes the entry records (empty when unknown — never
    /// fabricated).
    public struct AntigravityCredentials: Sendable, Equatable {
        public let clientID: String
        public let clientSecret: String?
        public let refreshToken: String
        public let accessToken: String?
        public let scopes: [String]

        public init(clientID: String, clientSecret: String? = nil, refreshToken: String, accessToken: String? = nil, scopes: [String] = []) {
            self.clientID = clientID
            self.clientSecret = clientSecret
            self.refreshToken = refreshToken
            self.accessToken = accessToken
            self.scopes = scopes
        }
    }

    /// Parses Antigravity credentials from raw keychain data: either
    /// direct JSON, or a UTF-8 string that may carry a
    /// `go-keyring-base64:` prefix. Returns nil when neither shape
    /// yields a refresh token or a non-empty access token.
    public static func parseAntigravityCredentials(from data: Data) -> AntigravityCredentials? {
        // Direct JSON format.
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let creds = parseAntigravityJSON(json) {
            return creds
        }
        // String representation (may contain go-keyring-base64: prefix or raw string).
        if let string = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            return parseAntigravityString(string)
        }
        return nil
    }

    /// Parses Antigravity credentials from a string, decoding the
    /// `go-keyring-base64:` wrapper when present.
    public static func parseAntigravityString(_ output: String) -> AntigravityCredentials? {
        var jsonStringToParse = output
        if output.hasPrefix("go-keyring-base64:") {
            let base64 = String(output.dropFirst("go-keyring-base64:".count))
            if let decodedData = Data(base64Encoded: base64),
               let decodedString = String(data: decodedData, encoding: .utf8) {
                jsonStringToParse = decodedString
            }
        }
        guard let jsonData = jsonStringToParse.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        return parseAntigravityJSON(json)
    }

    /// Parses Antigravity credentials from decoded JSON. Two shapes
    /// (Legacy's Structure 1 and 2):
    /// - nested `{ "token": { "refresh_token": ..., "access_token": ... } }`
    ///   (standard go-keyring / `agy` CLI);
    /// - flat `{ "refresh_token": ..., "client_id": ... }`.
    /// A missing `client_id` falls back to Ycode's own client id;
    /// unknown scopes stay empty.
    public static func parseAntigravityJSON(_ json: [String: Any]) -> AntigravityCredentials? {
        if let tokenObject = json["token"] as? [String: Any] {
            let refreshToken = (tokenObject["refresh_token"] as? String) ?? ""
            let accessToken = tokenObject["access_token"] as? String
            if !refreshToken.isEmpty || (accessToken != nil && !accessToken!.isEmpty) {
                return AntigravityCredentials(
                    clientID: (json["client_id"] as? String) ?? GoogleOAuthConfiguration.defaultClientID,
                    clientSecret: json["client_secret"] as? String,
                    refreshToken: refreshToken,
                    accessToken: accessToken,
                    scopes: (json["scopes"] as? [String]) ?? []
                )
            }
        }
        if let refreshToken = json["refresh_token"] as? String, !refreshToken.isEmpty {
            return AntigravityCredentials(
                clientID: (json["client_id"] as? String) ?? GoogleOAuthConfiguration.defaultClientID,
                clientSecret: json["client_secret"] as? String,
                refreshToken: refreshToken,
                accessToken: json["access_token"] as? String,
                scopes: (json["scopes"] as? [String]) ?? []
            )
        }
        return nil
    }

    /// Reads Antigravity credentials from the system keychain
    /// (direct `SecItemCopyMatching` for each account, then the
    /// `/usr/bin/security` CLI fallback). Apple-only: the Security
    /// framework and the `security` CLI do not exist on Linux, so
    /// this returns nil there and the ADC file / `gcloud` paths are
    /// the only ambient sources.
    public static func fetchAntigravityCredentialsFromKeychain() -> AntigravityCredentials? {
        #if canImport(Security)
        let accounts = ["antigravity", "antigravity-acp"]
        // 1. Direct SecItemCopyMatching for each account name.
        for account in accounts {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "gemini",
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecSuccess, let data = item as? Data,
               let creds = parseAntigravityCredentials(from: data) {
                return creds
            }
        }
        // 2. Fallback to /usr/bin/security CLI.
        for account in accounts {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = ["find-generic-password", "-s", "gemini", "-a", account, "-w"]
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       let creds = parseAntigravityString(output) {
                        return creds
                    }
                }
            } catch {
                continue
            }
        }
        return nil
        #else
        return nil
        #endif
    }

    // MARK: - Application Default Credentials files

    /// What an ADC JSON file contains, after parsing. An
    /// `authorized_user` file carries a client id + refresh token
    /// (the caller refreshes it into an access token); a file may
    /// also carry a bare `access_token` directly.
    public enum ADCFile: Sendable, Equatable {
        case authorizedUser(clientID: String, refreshToken: String, clientSecret: String?)
        case accessToken(String)
        case none
    }

    /// Parses an ADC JSON file's contents. Returns `.none` for
    /// unparsable data or for a file with neither a refresh token
    /// nor an access token.
    public static func parseADCFile(_ data: Data) -> ADCFile {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .none
        }
        if let clientID = json["client_id"] as? String,
           let refreshToken = json["refresh_token"] as? String {
            return .authorizedUser(clientID: clientID, refreshToken: refreshToken, clientSecret: json["client_secret"] as? String)
        }
        if let accessToken = json["access_token"] as? String, !accessToken.isEmpty {
            return .accessToken(accessToken)
        }
        return .none
    }

    /// The ADC file locations to try, in Legacy's order: the
    /// `GOOGLE_APPLICATION_CREDENTIALS` environment variable when
    /// set, then the standard
    /// `~/.config/gcloud/application_default_credentials.json`.
    public static func adcFilePaths(environment: [String: String], homeDirectory: URL) -> [URL] {
        var paths: [URL] = []
        if let credsPath = environment["GOOGLE_APPLICATION_CREDENTIALS"], !credsPath.isEmpty {
            paths.append(URL(fileURLWithPath: credsPath))
        }
        paths.append(homeDirectory.appendingPathComponent(".config/gcloud/application_default_credentials.json"))
        return paths
    }

    /// The email an ADC file records (`client_email`, service
    /// accounts), if any.
    public static func adcEmail(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clientEmail = json["client_email"] as? String else {
            return nil
        }
        return clientEmail
    }

    /// The account line of a `gcloud` active-config file
    /// (`~/.config/gcloud/configurations/config_default`):
    /// `account = someone@example.com`. Returns nil when the file
    /// has no account line.
    public static func gcloudConfigAccount(from content: String) -> String? {
        for line in content.components(separatedBy: .newlines) {
            if line.starts(with: "account =") {
                let parts = line.split(separator: "=")
                if parts.count == 2 {
                    return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return nil
    }

    // MARK: - CLI discovery

    /// The `agy` CLI's candidate locations, in Legacy's order: the
    /// `AGY_PATH` environment variable, then `~/.gemini/bin/agy`,
    /// `~/.local/bin/agy`, `/opt/homebrew/bin/agy`,
    /// `/usr/local/bin/agy`, `/usr/bin/agy`.
    public static func agyCLICandidates(environment: [String: String], homeDirectory: URL) -> [String] {
        var candidates: [String] = []
        if let custom = environment["AGY_PATH"], !custom.isEmpty {
            candidates.append(custom)
        }
        let home = homeDirectory.path
        candidates.append(contentsOf: [
            "\(home)/.gemini/bin/agy",
            "\(home)/.local/bin/agy",
            "/opt/homebrew/bin/agy",
            "/usr/local/bin/agy",
            "/usr/bin/agy",
        ])
        return candidates
    }

    /// The first executable `agy` CLI candidate, or nil when none
    /// is installed.
    public static func findAgyCLI(environment: [String: String], homeDirectory: URL) -> String? {
        agyCLICandidates(environment: environment, homeDirectory: homeDirectory).first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        })
    }

    /// The `gcloud` CLI's candidate locations, in Legacy's order.
    public static func gcloudCLICandidates(homeDirectory: URL) -> [String] {
        [
            "/opt/homebrew/bin/gcloud",
            "/usr/local/bin/gcloud",
            "/usr/bin/gcloud",
            homeDirectory.appendingPathComponent("google-cloud-sdk/bin/gcloud").path,
        ]
    }

    /// Runs `gcloud auth print-access-token` at `cliPath` and
    /// returns the token when it looks like one (Legacy required
    /// the `ya29.` prefix). Returns nil on any failure.
    public static func gcloudAccessToken(cliPath: String) -> String? {
        guard FileManager.default.fileExists(atPath: cliPath) else { return nil }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["auth", "print-access-token"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   output.hasPrefix("ya29.") {
                    return output
                }
            }
        } catch {
            return nil
        }
        return nil
    }
}
