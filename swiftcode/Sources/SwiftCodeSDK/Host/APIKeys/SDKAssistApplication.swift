import Foundation

public enum SDKAssistSDKVariant: String, Sendable, Codable, CaseIterable {
    case assistSDKUI = "assistSDK.UI"
    case assistSDK = "assistSDK"

    public var displayLabel: String {
        switch self {
        case .assistSDKUI: return "assistSDK.UI — with UI"
        case .assistSDK: return "assistSDK — headless"
        }
    }

    public var detail: String {
        switch self {
        case .assistSDKUI:
            return "Your app embeds SwiftCode's own Assist interface. You do not render Assist responses yourself."
        case .assistSDK:
            return "Your app calls the Assist API directly (sessions, streaming, tools) and renders all responses with your own UI."
        }
    }
}

public enum SDKAssistApplicationStatus: String, Sendable, Codable {
    case pending
    case approved
    case denied
}

public struct SDKAssistApplication: Sendable, Codable {
    public static let minimumUsageDescriptionLength = 40

    public struct Field: Sendable, Codable {
        public let extensionID: String
        public let displayName: String
        public let apiKeyID: UUID
        public let sdkVariant: SDKAssistSDKVariant
        public let usageDescription: String
        public let hasOwnUI: Bool
        public let ownUIDescription: String?
        public let usesThirdPartyModels: Bool
        public let thirdPartyModels: [String]
        public let dataLeavesDevice: Bool
        public let dataDestination: String?
        public let contactEmail: String

        public init(
            extensionID: String,
            displayName: String,
            apiKeyID: UUID,
            sdkVariant: SDKAssistSDKVariant,
            usageDescription: String,
            hasOwnUI: Bool,
            ownUIDescription: String? = nil,
            usesThirdPartyModels: Bool,
            thirdPartyModels: [String] = [],
            dataLeavesDevice: Bool,
            dataDestination: String? = nil,
            contactEmail: String
        ) {
            self.extensionID = extensionID
            self.displayName = displayName
            self.apiKeyID = apiKeyID
            self.sdkVariant = sdkVariant
            self.usageDescription = usageDescription
            self.hasOwnUI = hasOwnUI
            self.ownUIDescription = ownUIDescription
            self.usesThirdPartyModels = usesThirdPartyModels
            self.thirdPartyModels = thirdPartyModels
            self.dataLeavesDevice = dataLeavesDevice
            self.dataDestination = dataDestination
            self.contactEmail = contactEmail
        }

        private enum CodingKeys: String, CodingKey {
            case extensionID, displayName, apiKeyID, sdkVariant, usageDescription
            case hasOwnUI, ownUIDescription, usesThirdPartyModels, thirdPartyModels
            case dataLeavesDevice, dataDestination, contactEmail
            case legacyAPIKey = "apiKey"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            extensionID = try container.decode(String.self, forKey: .extensionID)
            displayName = try container.decode(String.self, forKey: .displayName)
            if let id = try container.decodeIfPresent(UUID.self, forKey: .apiKeyID) {
                apiKeyID = id
            } else if let secret = try container.decodeIfPresent(String.self, forKey: .legacyAPIKey),
                      let idString = SDKAPIKeyCodec.extractPresentedKeyID(from: secret),
                      let id = UUID(uuidString: idString) {
                apiKeyID = id
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .apiKeyID, in: container,
                    debugDescription: "Assist application field has neither apiKeyID nor a parseable legacy apiKey secret.")
            }
            sdkVariant = try container.decode(SDKAssistSDKVariant.self, forKey: .sdkVariant)
            usageDescription = try container.decode(String.self, forKey: .usageDescription)
            hasOwnUI = try container.decode(Bool.self, forKey: .hasOwnUI)
            ownUIDescription = try container.decodeIfPresent(String.self, forKey: .ownUIDescription)
            usesThirdPartyModels = try container.decode(Bool.self, forKey: .usesThirdPartyModels)
            thirdPartyModels = try container.decodeIfPresent([String].self, forKey: .thirdPartyModels) ?? []
            dataLeavesDevice = try container.decode(Bool.self, forKey: .dataLeavesDevice)
            dataDestination = try container.decodeIfPresent(String.self, forKey: .dataDestination)
            contactEmail = try container.decode(String.self, forKey: .contactEmail)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(extensionID, forKey: .extensionID)
            try container.encode(displayName, forKey: .displayName)
            try container.encode(apiKeyID, forKey: .apiKeyID)
            try container.encode(sdkVariant, forKey: .sdkVariant)
            try container.encode(usageDescription, forKey: .usageDescription)
            try container.encode(hasOwnUI, forKey: .hasOwnUI)
            try container.encodeIfPresent(ownUIDescription, forKey: .ownUIDescription)
            try container.encode(usesThirdPartyModels, forKey: .usesThirdPartyModels)
            try container.encode(thirdPartyModels, forKey: .thirdPartyModels)
            try container.encode(dataLeavesDevice, forKey: .dataLeavesDevice)
            try container.encodeIfPresent(dataDestination, forKey: .dataDestination)
            try container.encode(contactEmail, forKey: .contactEmail)
        }

        public func validate() throws {
            guard !extensionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SDKError(code: .invalidArgument, message: "The extension ID is required.")
            }
            guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SDKError(code: .invalidArgument, message: "The display name is required.")
            }
            guard usageDescription.trimmingCharacters(in: .whitespacesAndNewlines).count >= SDKAssistApplication.minimumUsageDescriptionLength else {
                throw SDKError(code: .invalidArgument, message: "The usage description must be at least \(SDKAssistApplication.minimumUsageDescriptionLength) characters.")
            }
            let emailPattern = "^[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}$"
            guard contactEmail.range(of: emailPattern, options: .regularExpression) != nil else {
                throw SDKError(code: .invalidArgument, message: "The contact email address is not valid.")
            }
            if hasOwnUI, (ownUIDescription?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                throw SDKError(code: .invalidArgument, message: "Describe the extension's own Assist UI.")
            }
            if usesThirdPartyModels, thirdPartyModels.isEmpty {
                throw SDKError(code: .invalidArgument, message: "List the third-party models the extension uses.")
            }
            if dataLeavesDevice, (dataDestination?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                throw SDKError(code: .invalidArgument, message: "State where the data goes when it leaves the device.")
            }
        }
    }

    public let id: UUID
    public let field: Field
    public let status: SDKAssistApplicationStatus
    public let submittedAt: Date
    public let decidedAt: Date?

    public init(id: UUID = UUID(), field: Field, status: SDKAssistApplicationStatus = .pending, submittedAt: Date = Date(), decidedAt: Date? = nil) {
        self.id = id
        self.field = field
        self.status = status
        self.submittedAt = submittedAt
        self.decidedAt = decidedAt
    }
}

public actor SDKAssistApplicationStore {
    public static let shared = SDKAssistApplicationStore(store: SDKSecretStoreFactory.defaultStore())

    public static let accountPrefix = "sdk.assistapp."

    private let store: any SDKSecretStoring

    public init(store: any SDKSecretStoring) {
        self.store = store
    }

    public func submit(_ field: SDKAssistApplication.Field, apiKeySecret: String) async throws -> SDKAssistApplication {
        try field.validate()
        guard await SDKExtensionRegistry.shared.installedExtension(id: field.extensionID) != nil else {
            throw SDKError(code: .invalidArgument, message: "The extension is not installed.")
        }
        let key = try await SDKAPIKeyStore.shared.verify(secret: apiKeySecret)
        guard key.id == field.apiKeyID else {
            throw SDKError(code: .apiKeyInvalid, message: "The developer API key is invalid.")
        }
        let application = SDKAssistApplication(field: field)
        try persist(application)
        return application
    }

    public func approve(id: UUID) async throws -> SDKAssistApplication {
        guard var application = try read(id: id), application.status == .pending else {
            throw SDKError(code: .invalidArgument, message: "Only a pending application can be decided.")
        }
        let keyID = keyID(for: application)
        try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAssist, toKeyID: keyID)
        if application.field.usesThirdPartyModels || application.field.dataLeavesDevice {
            try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAllowsCloud, toKeyID: keyID)
        }
        application = SDKAssistApplication(
            id: application.id, field: application.field,
            status: .approved, submittedAt: application.submittedAt, decidedAt: Date()
        )
        try persist(application)
        return application
    }

    public func deny(id: UUID) async throws -> SDKAssistApplication {
        guard var application = try read(id: id), application.status == .pending else {
            throw SDKError(code: .invalidArgument, message: "Only a pending application can be decided.")
        }
        application = SDKAssistApplication(
            id: application.id, field: application.field,
            status: .denied, submittedAt: application.submittedAt, decidedAt: Date()
        )
        try persist(application)
        return application
    }

    public func revokeEntitlementsForExtension(_ extensionID: String) async -> Int {
        var count = 0
        for application in list() where application.field.extensionID == extensionID {
            let keyID = keyID(for: application)
            _ = try? await SDKAPIKeyStore.shared.revokeEntitlement(.developerAIAssist, fromKeyID: keyID)
            _ = try? await SDKAPIKeyStore.shared.revokeEntitlement(.developerAIAllowsCloud, fromKeyID: keyID)
            count += 1
        }
        return count
    }

    public func list() -> [SDKAssistApplication] {
        let accounts = (try? store.accountNames(withPrefix: Self.accountPrefix)) ?? []
        var applications: [SDKAssistApplication] = []
        for account in accounts {
            guard let data = try? store.read(account: account),
                  let application = try? Self.decode(data) else { continue }
            applications.append(application)
        }
        return applications.sorted { $0.submittedAt > $1.submittedAt }
    }

    public func pending() -> [SDKAssistApplication] {
        list().filter { $0.status == .pending }
    }

    private func keyID(for application: SDKAssistApplication) -> UUID {
        application.field.apiKeyID
    }

    private func persist(_ application: SDKAssistApplication) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(application)
        try store.write(data, account: Self.accountPrefix + application.id.uuidString)
    }

    private func read(id: UUID) throws -> SDKAssistApplication? {
        guard let data = try store.read(account: Self.accountPrefix + id.uuidString) else { return nil }
        return try Self.decode(data)
    }

    private static func decode(_ data: Data) throws -> SDKAssistApplication {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SDKAssistApplication.self, from: data)
    }
}

public enum SDKAssistApplicationField: String, Sendable, Hashable, Codable, CaseIterable {
    case extensionID
    case displayName
    case apiKey
    case sdkVariant
    case usageDescription
    case hasOwnUI
    case ownUIDescription
    case usesThirdPartyModels
    case thirdPartyModels
    case dataLeavesDevice
    case dataDestination
    case contactEmail
}

public struct SDKAssistApplicationValidationError: Error, Sendable {
    public let errors: [SDKAssistApplicationField: String]

    public init(errors: [SDKAssistApplicationField: String]) {
        self.errors = errors
    }
}
