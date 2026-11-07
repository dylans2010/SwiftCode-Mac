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

public struct SDKAssistApplication: Sendable, Codable, Identifiable {
    public let id: UUID
    public let extensionID: String
    public let displayName: String
    public let apiKeyID: UUID
    public let sdkVariant: SDKAssistSDKVariant
    public let usageDescription: String
    public let hasOwnUI: Bool
    public let ownUIDescription: String?
    public let usesThirdPartyModels: Bool
    public let thirdPartyModels: String?
    public let dataLeavesDevice: Bool
    public let dataDestination: String?
    public let contactEmail: String
    public var status: SDKAssistApplicationStatus
    public let submittedAt: Date
    public var decidedAt: Date?

    public init(
        id: UUID = UUID(),
        extensionID: String,
        displayName: String,
        apiKeyID: UUID,
        sdkVariant: SDKAssistSDKVariant,
        usageDescription: String,
        hasOwnUI: Bool,
        ownUIDescription: String? = nil,
        usesThirdPartyModels: Bool,
        thirdPartyModels: String? = nil,
        dataLeavesDevice: Bool,
        dataDestination: String? = nil,
        contactEmail: String,
        status: SDKAssistApplicationStatus = .pending,
        submittedAt: Date = Date(),
        decidedAt: Date? = nil
    ) {
        self.id = id
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
        self.status = status
        self.submittedAt = submittedAt
        self.decidedAt = decidedAt
    }

    public static let minimumUsageDescriptionLength = 40

    public func validate() -> [SDKAssistApplicationField: String] {
        var errors: [SDKAssistApplicationField: String] = [:]

        let trimmedExtensionID = extensionID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedExtensionID.isEmpty {
            errors[.extensionID] = "Enter the extension ID of the app this application is for."
        }

        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDisplayName.isEmpty {
            errors[.displayName] = "Enter the display name of the app."
        }

        let trimmedUsage = usageDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedUsage.isEmpty {
            errors[.usageDescription] = "Describe how Assist will be used in your app."
        } else if trimmedUsage.count < Self.minimumUsageDescriptionLength {
            errors[.usageDescription] = "Give a fuller description (at least \(Self.minimumUsageDescriptionLength) characters) so the attestation is meaningful."
        }

        if hasOwnUI {
            let trimmed = (ownUIDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                errors[.ownUIDescription] = "Describe your own UI for Assist responses."
            }
        }

        if usesThirdPartyModels {
            let trimmed = (thirdPartyModels ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                errors[.thirdPartyModels] = "List the third-party providers and models you will use."
            }
        }

        if dataLeavesDevice {
            let trimmed = (dataDestination ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                errors[.dataDestination] = "Describe where user data goes when it leaves the device."
            }
        }

        let trimmedEmail = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedEmail.isEmpty {
            errors[.contactEmail] = "Enter a contact email."
        } else if !Self.isValidEmail(trimmedEmail) {
            errors[.contactEmail] = "Enter a valid email address."
        }

        return errors
    }

    public static func isValidEmail(_ value: String) -> Bool {
        let pattern = "^[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}

public actor SDKAssistApplicationStore {

    public static let shared = SDKAssistApplicationStore()

    private init() {}

    private static let applicationAccountPrefix = "sdk.assistapp."

    public func submit(_ application: SDKAssistApplication) async throws -> SDKAssistApplication {
        var errors = application.validate()

        let trimmedExtensionID = application.extensionID.trimmingCharacters(in: .whitespacesAndNewlines)
        if errors[.extensionID] == nil {
            let installed = await SDKExtensionRegistry.shared.installedExtension(id: trimmedExtensionID)
            if installed == nil {
                errors[.extensionID] = "No installed or registered app with the ID “\(trimmedExtensionID)” was found. Install and register the app first."
            }
        }

        if let key = await SDKAPIKeyStore.shared.list().first(where: { $0.id == application.apiKeyID }) {
            if key.revokedAt != nil {
                errors[.apiKey] = "The selected API key was revoked. Generate a new key in Studio → Settings → Developer API Keys."
            } else if key.isExpired {
                errors[.apiKey] = "The selected API key has expired. Generate a new key in Studio → Settings → Developer API Keys."
            }
        } else {
            errors[.apiKey] = "The selected API key does not exist. Generate one in Studio → Settings → Developer API Keys."
        }

        guard errors.isEmpty else {
            throw SDKAssistApplicationValidationError(errors: errors)
        }

        let stored = SDKAssistApplication(
            id: application.id,
            extensionID: trimmedExtensionID,
            displayName: application.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKeyID: application.apiKeyID,
            sdkVariant: application.sdkVariant,
            usageDescription: application.usageDescription,
            hasOwnUI: application.hasOwnUI,
            ownUIDescription: application.ownUIDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
            usesThirdPartyModels: application.usesThirdPartyModels,
            thirdPartyModels: application.thirdPartyModels?.trimmingCharacters(in: .whitespacesAndNewlines),
            dataLeavesDevice: application.dataLeavesDevice,
            dataDestination: application.dataDestination?.trimmingCharacters(in: .whitespacesAndNewlines),
            contactEmail: application.contactEmail.trimmingCharacters(in: .whitespacesAndNewlines),
            status: .pending,
            submittedAt: Date(),
            decidedAt: nil
        )
        try persist(stored)
        return stored
    }

    public func approve(id: UUID) async throws -> SDKAssistApplication {
        var application = try load(id: id)
        guard application.status == .pending else {
            throw SDKError(
                code: .invalidArgument,
                message: "This application is no longer pending and cannot be approved.",
                suggestion: "Reload the applications list — another approver may already have decided it."
            )
        }
        try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAssist, to: application.apiKeyID)
        if application.usesThirdPartyModels || application.dataLeavesDevice {
            try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAllowsCloud, to: application.apiKeyID)
        }
        application.status = .approved
        application.decidedAt = Date()
        try persist(application)
        return application
    }

    public func deny(id: UUID) async throws -> SDKAssistApplication {
        var application = try load(id: id)
        guard application.status == .pending else {
            throw SDKError(
                code: .invalidArgument,
                message: "This application is no longer pending and cannot be denied.",
                suggestion: "Reload the applications list — another approver may already have decided it."
            )
        }
        application.status = .denied
        application.decidedAt = Date()
        try persist(application)
        return application
    }

    public func revokeEntitlementsForExtension(_ extensionID: String) async -> Int {
        let approved = list().filter {
            $0.extensionID == extensionID && $0.status == .approved
        }
        var revoked = 0
        for application in approved {
            guard let key = await SDKAPIKeyStore.shared.list().first(where: { $0.id == application.apiKeyID }) else {
                continue
            }
            for entitlement in [SDKEntitlement.developerAIAssist, .developerAIAllowsCloud]
                where key.entitlements.contains(entitlement) {
                do {
                    try await SDKAPIKeyStore.shared.revokeEntitlement(entitlement, from: application.apiKeyID)
                    revoked += 1
                } catch {
                    continue
                }
            }
        }
        return revoked
    }

    public func list() -> [SDKAssistApplication] {
        guard let accounts = try? SDKKeychain.accountNames(withPrefix: Self.applicationAccountPrefix) else {
            return []
        }
        var applications: [SDKAssistApplication] = []
        for account in accounts {
            if let value = try? SDKKeychain.get(forKey: account),
               let data = value.data(using: .utf8),
               let application = try? JSONDecoder().decode(SDKAssistApplication.self, from: data)
            {
                applications.append(application)
            }
        }
        return applications.sorted { $0.submittedAt > $1.submittedAt }
    }

    public func pending() -> [SDKAssistApplication] {
        list().filter { $0.status == .pending }
    }

    private static func account(for id: UUID) -> String {
        applicationAccountPrefix + id.uuidString.lowercased()
    }

    private func persist(_ application: SDKAssistApplication) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(application)
        } catch {
            throw SDKError(
                code: .serviceUnavailable,
                message: "Could not store the Assist access application.",
                diagnostics: ["reason": "application-encode-failed"]
            )
        }
        guard let json = String(data: data, encoding: .utf8) else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "Could not store the Assist access application.",
                diagnostics: ["reason": "application-utf8-failed"]
            )
        }
        try SDKKeychain.set(json, forKey: Self.account(for: application.id))
    }

    private func load(id: UUID) throws -> SDKAssistApplication {
        let stored: String?
        do {
            stored = try SDKKeychain.get(forKey: Self.account(for: id))
        } catch {
            throw SDKError(
                code: .serviceUnavailable,
                message: "Could not read the Assist access application.",
                diagnostics: ["reason": "keychain-read-failed"]
            )
        }
        guard let json = stored,
              let data = json.data(using: .utf8),
              let application = try? JSONDecoder().decode(SDKAssistApplication.self, from: data)
        else {
            throw SDKError(
                code: .invalidArgument,
                message: "No Assist access application with that ID was found.",
                diagnostics: ["applicationId": id.uuidString]
            )
        }
        return application
    }
}
