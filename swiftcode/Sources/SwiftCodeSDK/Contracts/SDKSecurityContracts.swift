import Foundation

public struct SDKSecurityAddRequest: Codable, Sendable {
    public let securityID: String
    public let valueID: String
    public let label: String?
    public let prompt: String?

    public init(securityID: String, valueID: String, label: String? = nil, prompt: String? = nil) {
        self.securityID = securityID
        self.valueID = valueID
        self.label = label
        self.prompt = prompt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        securityID = try container.decode(String.self, forKey: .securityID)
        valueID = try container.decode(String.self, forKey: .valueID)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
    }
}

public struct SDKSecurityLookupRequest: Codable, Sendable {
    public let securityID: String
    public let valueID: String

    public init(securityID: String, valueID: String) {
        self.securityID = securityID
        self.valueID = valueID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        securityID = try container.decode(String.self, forKey: .securityID)
        valueID = try container.decode(String.self, forKey: .valueID)
    }
}

public struct SDKSecurityListRequest: Codable, Sendable {
    public let securityID: String

    public init(securityID: String) {
        self.securityID = securityID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        securityID = try container.decode(String.self, forKey: .securityID)
    }
}

public struct SDKSecurityUseRequest: Codable, Sendable {
    public let securityID: String
    public let valueID: String
    public let operation: SDKSecurityUseOperation

    public init(securityID: String, valueID: String, operation: SDKSecurityUseOperation) {
        self.securityID = securityID
        self.valueID = valueID
        self.operation = operation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        securityID = try container.decode(String.self, forKey: .securityID)
        valueID = try container.decode(String.self, forKey: .valueID)
        operation = try container.decode(SDKSecurityUseOperation.self, forKey: .operation)
    }
}

public struct SDKSecurityUseOperation: Codable, Sendable {
    public let kind: String
    public let request: SDKSecurityHTTPRequest

    public init(kind: String, request: SDKSecurityHTTPRequest) {
        self.kind = kind
        self.request = request
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        request = try container.decode(SDKSecurityHTTPRequest.self, forKey: .request)
    }
}

public struct SDKSecurityHTTPRequest: Codable, Sendable {
    public let method: String
    public let url: String
    public let headers: [String: String]?
    public let body: String?

    public init(method: String, url: String, headers: [String: String]? = nil, body: String? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        method = try container.decode(String.self, forKey: .method)
        url = try container.decode(String.self, forKey: .url)
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers)
        body = try container.decodeIfPresent(String.self, forKey: .body)
    }
}

public struct SDKSecurityAddedValue: Codable, Sendable {
    public let valueID: String
    public let created: Bool

    public init(valueID: String, created: Bool) {
        self.valueID = valueID
        self.created = created
    }
}

public struct SDKSecurityHasValue: Codable, Sendable {
    public let hasValue: Bool

    public init(hasValue: Bool) {
        self.hasValue = hasValue
    }
}

public struct SDKSecurityStoredValue: Codable, Sendable, Equatable {
    public let valueID: String
    public let label: String
    public let createdAt: String

    public init(valueID: String, label: String, createdAt: String) {
        self.valueID = valueID
        self.label = label
        self.createdAt = createdAt
    }
}

public struct SDKSecurityValueList: Codable, Sendable {
    public let values: [SDKSecurityStoredValue]

    public init(values: [SDKSecurityStoredValue]) {
        self.values = values
    }
}

public struct SDKSecurityHTTPResponse: Codable, Sendable {
    public let status: Int
    public let body: String

    public init(status: Int, body: String) {
        self.status = status
        self.body = body
    }
}
