import Foundation

public struct GoogleOAuthTokens: Codable, Sendable, Equatable {
    public let accessToken: String
    public let expiresIn: Int?
    public let refreshToken: String?
    public let scope: String?
    public let tokenType: String?
    public let idToken: String?

    public init(
        accessToken: String,
        expiresIn: Int? = nil,
        refreshToken: String? = nil,
        scope: String? = nil,
        tokenType: String? = nil,
        idToken: String? = nil
    ) {
        self.accessToken = accessToken
        self.expiresIn = expiresIn
        self.refreshToken = refreshToken
        self.scope = scope
        self.tokenType = tokenType
        self.idToken = idToken
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case tokenType = "token_type"
        case idToken = "id_token"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.accessToken = try container.decode(String.self, forKey: .accessToken)
        self.refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        self.scope = try container.decodeIfPresent(String.self, forKey: .scope)
        self.tokenType = try container.decodeIfPresent(String.self, forKey: .tokenType)
        self.idToken = try container.decodeIfPresent(String.self, forKey: .idToken)
        if let int = try? container.decodeIfPresent(Int.self, forKey: .expiresIn) {
            self.expiresIn = int
        } else if let double = try? container.decodeIfPresent(Double.self, forKey: .expiresIn) {
            self.expiresIn = Int(double)
        } else if let string = try? container.decodeIfPresent(String.self, forKey: .expiresIn) {
            self.expiresIn = Int(string)
        } else {
            self.expiresIn = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accessToken, forKey: .accessToken)
        try container.encodeIfPresent(expiresIn, forKey: .expiresIn)
        try container.encodeIfPresent(refreshToken, forKey: .refreshToken)
        try container.encodeIfPresent(scope, forKey: .scope)
        try container.encodeIfPresent(tokenType, forKey: .tokenType)
        try container.encodeIfPresent(idToken, forKey: .idToken)
    }
}

public struct GoogleOAuthErrorBody: Decodable, Sendable, Equatable {
    public let error: String?
    public let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }

    public func message(fallback: String) -> String {
        if let errorDescription, !errorDescription.isEmpty { return errorDescription }
        if let error, !error.isEmpty { return error }
        return fallback
    }
}
