import Foundation

// MARK: - SDKAssistApplication
//
// Ported from Legacy `SwiftCode/SDK/Host/APIKeys/SDKAssistApplication.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// A developer applies for Assist access for one extension. The host
// reviews the application (status pending → approved/denied); approval
// grants the key-bound `developerAIAssist` entitlement — and
// `developerAIAllowsCloud` when the app's data leaves the device — on
// the developer's API key. The grant happens BEFORE the approval is
// persisted, so a stored approval never lacks its entitlement.

/// Which Assist SDK variant the application is for.
public enum SDKAssistSDKVariant: String, Sendable, Codable, CaseIterable {
    /// The extension embeds the host's Assist main view.
    case assistSDKUI = "assistSDK.UI"
    /// The extension drives Assist headlessly over the IPC route.
    case assistSDK = "assistSDK"

    /// Human-readable label for Studio.
    public var displayLabel: String {
        switch self {
        case .assistSDKUI: return "assistSDK.UI — with UI"
        case .assistSDK: return "assistSDK — headless"
        }
    }

    /// Studio-facing description of what the variant unlocks.
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

/// One Assist application, stored by the host. The store's timestamp is
/// the authority for submission/decision time.
public struct SDKAssistApplication: Sendable, Codable {
    /// Minimum accepted length for the usage description, measured on
    /// the trimmed text (Legacy `SDKAssistApplication`).
    public static let minimumUsageDescriptionLength = 40

    public struct Field: Sendable, Codable {
        public let extensionID: String
        public let displayName: String
        public let apiKey: String
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
            apiKey: String,
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
            self.apiKey = apiKey
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

        /// Validates the application. Usage descriptions must be at least
        /// `SDKAssistApplication.minimumUsageDescriptionLength` characters
        /// (trimmed); the contact email must look like an email;
        /// conditional fields are required when their flag is set.
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

/// Stores Assist applications in the secret store (account
/// `sdk.assistapp.<uuid>`). Only pending applications can be decided.
public actor SDKAssistApplicationStore {
    public static let shared = SDKAssistApplicationStore(store: SDKSecretStoreFactory.defaultStore())

    public static let accountPrefix = "sdk.assistapp."

    private let store: any SDKSecretStoring

    public init(store: any SDKSecretStoring) {
        self.store = store
    }

    /// Submits an application: validates the fields, requires the
    /// extension to be installed, and requires the named API key to
    /// exist and be live (not revoked/expired). The stored record is
    /// timestamped here and starts `pending`.
    public func submit(_ field: SDKAssistApplication.Field) async throws -> SDKAssistApplication {
        try field.validate()
        guard await SDKExtensionRegistry.shared.installedExtension(id: field.extensionID) != nil else {
            throw SDKError(code: .invalidArgument, message: "The extension is not installed.")
        }
        // The application names an API key by its presented secret; the
        // store verifies it and the record must be live.
        let key = try await SDKAPIKeyStore.shared.verify(secret: field.apiKey)
        guard !key.isRevoked, !key.isExpired else {
            throw SDKError(code: .apiKeyInvalid, message: "The developer API key is invalid.")
        }
        let application = SDKAssistApplication(field: field)
        try persist(application)
        return application
    }

    /// Approves a pending application. Grants `developerAIAssist` always,
    /// plus `developerAIAllowsCloud` when the app uses third-party models
    /// or its data leaves the device — grant BEFORE persist, so a stored
    /// approval never lacks its entitlement.
    public func approve(id: UUID) async throws -> SDKAssistApplication {
        guard var application = try read(id: id), application.status == .pending else {
            throw SDKError(code: .invalidArgument, message: "Only a pending application can be decided.")
        }
        let keyID = try keyID(for: application)
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

    /// Denies a pending application. No entitlement is granted.
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

    /// Uninstall hook: revokes the Assist entitlements of every key
    /// bound to applications for `extensionID`. Returns the number of
    /// keys touched. Keys that no longer exist are skipped.
    public func revokeEntitlementsForExtension(_ extensionID: String) async -> Int {
        var count = 0
        for application in list() where application.field.extensionID == extensionID {
            guard let keyID = try? keyID(for: application) else { continue }
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

    // MARK: - Private

    private func keyID(for application: SDKAssistApplication) throws -> UUID {
        // The application stores the presented secret, not the key ID:
        // extract the (unverified) ID for the store lookup, then let the
        // key store re-verify lifecycle state on every grant.
        guard let idString = SDKAPIKeyCodec.extractPresentedKeyID(from: application.field.apiKey),
              let id = UUID(uuidString: idString) else {
            throw SDKError(code: .apiKeyInvalid, message: "The developer API key is invalid.")
        }
        return id
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
