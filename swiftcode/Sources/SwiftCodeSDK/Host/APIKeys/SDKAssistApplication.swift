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
//
// KEY-ID ONLY (Wave 16 revision of the §5 / §19 item 8 flag): the
// application record stores only the key ID (`Field.apiKeyID`), never
// the presented secret. The secret is presented once at submit time as
// proof of possession — verified against the Keychain-backed key store,
// then dropped; nothing derived from the secret persists. Approval
// grants entitlements by key ID alone (re-reading key metadata, so a
// key revoked between submit and approve fails closed) and needs no
// secret. This restores Legacy's own shape: Legacy's
// `SDKAssistApplication` stored `apiKeyID: UUID`, never a secret — the
// presented-secret field was a Wave 14 port deviation, not Legacy
// behaviour.

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
        /// The developer API key the entitlements bind to on approval.
        /// Key ID ONLY — the presented secret is verified at submit time
        /// (see `SDKAssistApplicationStore.submit(_:apiKeySecret:)`) and
        /// never stored, in this field or anywhere derived from it.
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
            /// Pre–Wave 16 key: records written while `Field` stored the
            /// presented secret. Read-only migration source, never written.
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
                // One-way migration: recover the key ID from a stored
                // presented secret. The secret itself is discarded here —
                // the re-encoded record carries only the ID. Extraction
                // is unverified parsing (name only); the ID is trusted
                // only as a pointer — approval re-reads key metadata
                // from the store and refuses revoked/unknown keys.
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
            // Deliberately never writes the legacy "apiKey" key: a
            // migrated record re-encodes with the ID only, so the secret
            // leaves the store on the next persist.
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
    /// extension to be installed, and verifies the presented secret
    /// against the Keychain-backed key store. The secret is proof of
    /// possession only: it must verify AND name the key the application
    /// binds to (`field.apiKeyID`) — a secret for any other key is
    /// rejected, so an application can never be bound to a key its
    /// submitter does not hold. The secret is dropped after verification;
    /// the stored record carries only the key ID. `verify` enforces
    /// liveness (revoked/expired keys fail there), and approval later
    /// re-reads key metadata, so revocation between submit and approve
    /// is honoured without any secret at approval time.
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

    /// Approves a pending application. Grants `developerAIAssist` always,
    /// plus `developerAIAllowsCloud` when the app uses third-party models
    /// or its data leaves the device — grant BEFORE persist, so a stored
    /// approval never lacks its entitlement.
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

    // MARK: - Private

    private func keyID(for application: SDKAssistApplication) -> UUID {
        // The record stores the key ID directly — no extraction from a
        // secret, no unverified parsing on the approval path. The key
        // store re-verifies lifecycle state on every grant, so a key
        // revoked between submit and approve fails closed there.
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


// Ported from Legacy `SwiftCode/SDK/Host/APIKeys/SDKAssistApplication.swift` (Audit E §5 partial entry; H-E5).
// Types ported here: SDKAssistApplicationField, SDKAssistApplicationValidationError.

/// Every validated field of the Assist access application form. Field-level
/// validation errors are keyed by these, so Studio can render each error
/// inline next to its field.
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

/// Carries the field-level validation errors from
/// `SDKAssistApplication.validate()` (or from the registry / API-key
/// checks at submit time) keyed by field.
public struct SDKAssistApplicationValidationError: Error, Sendable {
    public let errors: [SDKAssistApplicationField: String]

    public init(errors: [SDKAssistApplicationField: String]) {
        self.errors = errors
    }
}
