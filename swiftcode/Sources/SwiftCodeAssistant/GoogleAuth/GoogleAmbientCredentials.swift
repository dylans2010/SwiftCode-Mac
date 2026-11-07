import Foundation

#if canImport(Security)
import Security
#endif

public enum GoogleAmbientCredentials: Sendable {

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

    public static func parseAntigravityCredentials(from data: Data) -> AntigravityCredentials? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let creds = parseAntigravityJSON(json) {
            return creds
        }
        if let string = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            return parseAntigravityString(string)
        }
        return nil
    }

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

    public static func fetchAntigravityCredentialsFromKeychain() -> AntigravityCredentials? {
        #if canImport(Security)
        let accounts = ["antigravity", "antigravity-acp"]
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

    public enum ADCFile: Sendable, Equatable {
        case authorizedUser(clientID: String, refreshToken: String, clientSecret: String?)
        case accessToken(String)
        case none
    }

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

    public static func adcFilePaths(environment: [String: String], homeDirectory: URL) -> [URL] {
        var paths: [URL] = []
        if let credsPath = environment["GOOGLE_APPLICATION_CREDENTIALS"], !credsPath.isEmpty {
            paths.append(URL(fileURLWithPath: credsPath))
        }
        paths.append(homeDirectory.appendingPathComponent(".config/gcloud/application_default_credentials.json"))
        return paths
    }

    public static func adcEmail(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clientEmail = json["client_email"] as? String else {
            return nil
        }
        return clientEmail
    }

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

    public static func findAgyCLI(environment: [String: String], homeDirectory: URL) -> String? {
        agyCLICandidates(environment: environment, homeDirectory: homeDirectory).first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        })
    }

    public static func gcloudCLICandidates(homeDirectory: URL) -> [String] {
        [
            "/opt/homebrew/bin/gcloud",
            "/usr/local/bin/gcloud",
            "/usr/bin/gcloud",
            homeDirectory.appendingPathComponent("google-cloud-sdk/bin/gcloud").path,
        ]
    }

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
