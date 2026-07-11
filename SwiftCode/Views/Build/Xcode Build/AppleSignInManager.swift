import Foundation
import Observation
import Security
import CryptoKit
import os.log

private let logger = Logger(subsystem: "com.swiftcode.Build", category: "AppleSignIn")

extension KeychainService {
    @discardableResult
    public func save(_ value: String, forKey key: String) -> Bool {
        return self.set(value, forKey: key)
    }
}

/// Standard base64URL helper structure for JWT signatures
public struct AppStoreConnectJWT: Sendable {
    public static func generate(
        keyID: String,
        issuerID: String,
        privateKeyPEM: String,
        expirationMinutes: Int = 20
    ) throws -> String {
        // 1. Prepare Header
        let header: [String: String] = [
            "alg": "ES256",
            "kid": keyID,
            "typ": "JWT"
        ]
        let headerData = try JSONSerialization.data(withJSONObject: header, options: [])
        let headerBase64 = base64URL(headerData)

        // 2. Prepare Payload
        let now = Int(Date().timeIntervalSince1970)
        let payload: [String: Any] = [
            "iss": issuerID,
            "exp": now + (expirationMinutes * 60),
            "aud": "appstoreconnect-v1"
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [])
        let payloadBase64 = base64URL(payloadData)

        // 3. Create String to sign
        let unsignedToken = "\(headerBase64).\(payloadBase64)"
        guard let unsignedData = unsignedToken.data(using: .utf8) else {
            throw NSError(
                domain: "AppStoreConnectJWT",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to convert unsigned token to data"]
            )
        }

        // 4. Load P-256 Private Key
        var pem = privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pem.contains("-----BEGIN PRIVATE KEY-----") {
            pem = "-----BEGIN PRIVATE KEY-----\n\(pem)\n-----END PRIVATE KEY-----"
        }
        let privateKey = try P256.Signing.PrivateKey(pemRepresentation: pem)

        // 5. Sign Data
        let signature = try privateKey.signature(for: unsignedData)
        let signatureBase64 = base64URL(signature.rawRepresentation)

        return "\(unsignedToken).\(signatureBase64)"
    }

    private static func base64URL(_ data: Data) -> String {
        var base64 = data.base64EncodedString()
        base64 = base64.replacingOccurrences(of: "+", with: "-")
        base64 = base64.replacingOccurrences(of: "/", with: "_")
        base64 = base64.replacingOccurrences(of: "=", with: "")
        return base64
    }
}

@Observable
@MainActor
public final class AppleSignInManager: Sendable {
    public static let shared = AppleSignInManager()

    public var developerAccounts: [AppleDeveloperAccount] = []
    public var selectedTeamID: String?
    public var sessionState: SessionState = .signedOut
    public var lastError: String?

    public enum SessionState: String, Sendable, Codable {
        case signedOut = "Signed Out"
        case loading = "Loading..."
        case signedIn = "Signed In"
        case expired = "Session Expired"
    }

    public struct CertificateInfo: Identifiable, Sendable, Codable {
        public var id: String { serialNumber }
        public let name: String
        public let type: String
        public let displayName: String
        public let serialNumber: String
        public let expirationDate: String
        public let content: String // Base64 DER encoding
    }

    public struct AppleDeveloperAccount: Identifiable, Sendable, Codable {
        public var id: String { appleID }
        public let appleID: String
        public let teamName: String
        public let teamID: String
        public let certificateName: String
        public let keyID: String?
        public let issuerID: String?
        public let certificates: [CertificateInfo]?

        public init(
            appleID: String,
            teamName: String,
            teamID: String,
            certificateName: String,
            keyID: String?,
            issuerID: String?,
            certificates: [CertificateInfo]?
        ) {
            self.appleID = appleID
            self.teamName = teamName
            self.teamID = teamID
            self.certificateName = certificateName
            self.keyID = keyID
            self.issuerID = issuerID
            self.certificates = certificates
        }
    }

    private init() {
        loadAccounts()
    }

    // MARK: - App Store Connect API Integration

    /// Fetch active certificates from Apple's App Store Connect API
    public func fetchCertificates(jwt: String) async throws -> [CertificateInfo] {
        guard let url = URL(string: "https://api.appstoreconnect.apple.com/v1/certificates") else {
            throw NSError(
                domain: "AppleSignInManager",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"]
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "AppleSignInManager",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server response"]
            )
        }

        if httpResponse.statusCode != 200 {
            if let errorJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errors = errorJSON["errors"] as? [[String: Any]],
               let firstError = errors.first,
               let detail = firstError["detail"] as? String {
                throw NSError(
                    domain: "AppleSignInManager",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: detail]
                )
            }
            throw NSError(
                domain: "AppleSignInManager",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "App Store Connect API returned status \(httpResponse.statusCode)"]
            )
        }

        // Decode App Store Connect Response
        struct ASCertificatesResponse: Decodable {
            let data: [ASCertificateData]
        }
        struct ASCertificateData: Decodable {
            let id: String
            let attributes: ASCertificateAttributes
        }
        struct ASCertificateAttributes: Decodable {
            let name: String
            let certificateType: String
            let displayName: String
            let serialNumber: String
            let expirationDate: String
            let certificateContent: String
        }

        let decoder = JSONDecoder()
        let result = try decoder.decode(ASCertificatesResponse.self, from: data)

        return result.data.map { cert in
            CertificateInfo(
                name: cert.attributes.name,
                type: cert.attributes.certificateType,
                displayName: cert.attributes.displayName,
                serialNumber: cert.attributes.serialNumber,
                expirationDate: cert.attributes.expirationDate,
                content: cert.attributes.certificateContent
            )
        }
    }

    /// Connect and validate a new App Store Connect account using API Key Credentials
    public func addAccount(
        appleID: String,
        teamName: String,
        teamID: String,
        keyID: String,
        issuerID: String,
        privateKey: String
    ) async {
        sessionState = .loading
        lastError = nil

        guard !appleID.isEmpty, !teamID.isEmpty, !keyID.isEmpty, !issuerID.isEmpty, !privateKey.isEmpty else {
            sessionState = .signedOut
            lastError = "All fields (Apple ID, Team ID, Key ID, Issuer ID, and Private Key) are required."
            return
        }

        do {
            // 1. Generate real JWT token
            let jwt = try AppStoreConnectJWT.generate(
                keyID: keyID,
                issuerID: issuerID,
                privateKeyPEM: privateKey
            )

            // 2. Fetch real certificates from Apple's App Store Connect API
            let certificates = try await fetchCertificates(jwt: jwt)

            // 3. Extract primary certificate name
            let primaryCertName = certificates.first?.name ?? "Apple Development: \(appleID)"

            // 4. Create and save the real developer account
            let account = AppleDeveloperAccount(
                appleID: appleID,
                teamName: teamName.isEmpty ? "My Apple Team" : teamName,
                teamID: teamID,
                certificateName: primaryCertName,
                keyID: keyID,
                issuerID: issuerID,
                certificates: certificates
            )

            // 5. Store privateKey securely in Keychain
            let key = "apple_dev_key_\(appleID)_\(teamID)"
            let success = KeychainService.shared.save(privateKey, forKey: key)

            if success {
                // Remove existing account with same ID if any
                developerAccounts.removeAll(where: { $0.appleID == appleID })
                developerAccounts.append(account)
                selectedTeamID = teamID
                sessionState = .signedIn
                saveAccounts()
            } else {
                sessionState = .signedOut
                lastError = "Failed to store credential in Keychain securely."
            }
        } catch {
            sessionState = .signedOut
            lastError = "Authentication failed: \(error.localizedDescription)"
            logger.error("Authentication failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func removeAccount(at indexSet: IndexSet) {
        for index in indexSet {
            let account = developerAccounts[index]
            let key = "apple_dev_key_\(account.appleID)_\(account.teamID)"
            _ = KeychainService.shared.delete(forKey: key)
        }
        developerAccounts.remove(atOffsets: indexSet)
        if developerAccounts.isEmpty {
            sessionState = .signedOut
            selectedTeamID = nil
        } else {
            selectedTeamID = developerAccounts.first?.teamID
        }
        saveAccounts()
    }

    // MARK: - App Codesigning Execution

    /// Real codesigning function that runs `/usr/bin/codesign` using ProcessRunnerTool
    public func codesign(appPath: String, withCertificateName certificateName: String) async throws -> Bool {
        guard !appPath.isEmpty, !certificateName.isEmpty else {
            throw NSError(
                domain: "AppleSignInManager",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "Invalid app path or certificate name"]
            )
        }

        let url = URL(fileURLWithPath: "/usr/bin/codesign")
        let arguments = [
            "-s", certificateName,
            "--force",
            "--deep",
            appPath
        ]

        logger.info("Executing codesign at path \(appPath, privacy: .public) with certificate \(certificateName, privacy: .public)")

        let result = try await ProcessRunnerTool.shared.run(
            executableURL: url,
            arguments: arguments
        )

        if result.exitCode == 0 {
            return true
        } else {
            let errorMsg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "AppleSignInManager",
                code: Int(result.exitCode),
                userInfo: [NSLocalizedDescriptionKey: errorMsg.isEmpty ? "Codesign failed with exit code \(result.exitCode)" : errorMsg]
            )
        }
    }

    // MARK: - Persistence

    private func saveAccounts() {
        if let data = try? JSONEncoder().encode(developerAccounts) {
            UserDefaults.standard.set(data, forKey: "apple_developer_accounts")
        }
    }

    private func loadAccounts() {
        if let data = UserDefaults.standard.data(forKey: "apple_developer_accounts"),
           let decoded = try? JSONDecoder().decode([AppleDeveloperAccount].self, from: data) {
            developerAccounts = decoded
            if !developerAccounts.isEmpty {
                sessionState = .signedIn
                selectedTeamID = developerAccounts.first?.teamID
            }
        }
    }
}
