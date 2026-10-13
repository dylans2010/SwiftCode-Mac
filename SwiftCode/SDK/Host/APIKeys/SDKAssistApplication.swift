import Foundation

// MARK: - SDKAssistSDKVariant
//
// The two SDK surfaces a developer can apply for (Docs/Intro-to-SDK.md §11).
// Raw strings are the public variant identifiers shared with the
// TypeScript package.

public enum SDKAssistSDKVariant: String, Sendable, Codable, CaseIterable {
    /// The UI variant: embeds the host's real Assist Main view inside the
    /// developer's app. The extension never touches Assist internals.
    case assistSDKUI = "assistSDK.UI"
    /// The headless variant: the full Assist API surface EXCEPT UI —
    /// sessions, streaming responses, tool access per the approved scope.
    /// The developer renders everything themselves.
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

// MARK: - SDKAssistApplicationStatus

/// Lifecycle of an Assist access application. Terminal states
/// (`approved` / `denied`) record `decidedAt` on the application.
public enum SDKAssistApplicationStatus: String, Sendable, Codable {
    case pending
    case approved
    case denied
}

// MARK: - SDKAssistApplicationField

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

// MARK: - SDKAssistApplicationValidationError

/// Carries the field-level validation errors from
/// `SDKAssistApplication.validate()` (or from the registry / API-key
/// checks at submit time) keyed by field.
public struct SDKAssistApplicationValidationError: Error, Sendable {
    public let errors: [SDKAssistApplicationField: String]

    public init(errors: [SDKAssistApplicationField: String]) {
        self.errors = errors
    }
}

// MARK: - SDKAssistApplication
//
// One Assist access application (Docs/Intro-to-SDK.md §10): how a developer
// will use Assist, stored with the request, gating the entitlement grant.
//
// Field rules (enforced by `validate()`):
//   1. App identity: `extensionID` + `displayName`, both non-empty. The
//      extension ID must additionally match an installed/registered app —
//      that check runs against `SDKExtensionRegistry` at submit time
//      (`SDKAssistApplicationStore.submit`), not in `validate()`.
//      `displayName` is the developer's label for the app; it is validated
//      as non-empty only.
//   2. SDK variant: `assistSDKUI` (`assistSDK.UI`) or `assistSDK`.
//   3. `usageDescription`: free text, minimum 40 characters (checked on the
//      trimmed text so whitespace padding cannot satisfy it), stored
//      verbatim — the exact string the developer typed is what is kept.
//   4. `hasOwnUI`: required choice. `ownUIDescription` is required
//      (non-empty) when `hasOwnUI` is true.
//   5. `usesThirdPartyModels`: required choice. `thirdPartyModels` is
//      required (non-empty) when true.
//   6. `dataLeavesDevice`: required choice. `dataDestination` is required
//      (non-empty) when true.
//   7. `contactEmail`: non-empty and must match a basic email format.
//   8. `apiKeyID`: the developer API key the entitlements will be bound to.
//      Verified at submit time (key must exist, not be revoked or expired).
//
// APPROVAL POLICY (v1): recorded self-attestation with
// revocation-on-abuse. There is NO human review queue in v1: approval is an
// explicit host action (Studio → Assist Access → Approve) that records the
// developer's answers as their attestation and grants the entitlements;
// abuse after approval is handled by entitlement revocation
// (`SDKAPIKeyStore.revokeEntitlement`), which takes effect immediately at
// the authorization boundary, and is recorded in the audit log.
//
// The manifest can never grant Assist access — only a verified entitlement
// on the developer's API key can (Docs/Intro-to-SDK.md §12).

public struct SDKAssistApplication: Sendable, Codable, Identifiable {
    public let id: UUID
    public let extensionID: String
    public let displayName: String
    /// The developer API key the entitlements are bound to on approval.
    public let apiKeyID: UUID
    public let sdkVariant: SDKAssistSDKVariant
    /// Stored verbatim — exactly what the developer typed.
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

    // MARK: - Field-level validation

    /// Minimum accepted length for `usageDescription`, measured on the
    /// trimmed text so whitespace padding cannot satisfy it.
    public static let minimumUsageDescriptionLength = 40

    /// Validates every field, returning one human-readable error per
    /// invalid field, keyed by `SDKAssistApplicationField`. Empty means
    /// valid. Pure: performs no I/O — the registry and API-key existence
    /// checks run at submit time in `SDKAssistApplicationStore.submit`.
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

    /// Pragmatic email format check (not a full RFC 5322 parser): a local
    /// part, an `@`, a domain with at least one dot and a TLD of 2+ letters.
    public static func isValidEmail(_ value: String) -> Bool {
        let pattern = "^[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}

// MARK: - SDKAssistApplicationStore
//
// Host-side authority for Assist access applications (Docs/Intro-to-SDK.md
// §10). An actor: submit / approve / deny are serialized, so two approvers
// cannot double-decide one application.
//
// PERSISTENCE: application records are JSON in `SDKKeychain` under
// `sdk.assistapp.<uuid>` — the same Keychain-backed metadata store as
// developer API key metadata (`SDKAPIKeyStore`). Application records carry
// the developer's contact email and usage description, so they get the
// same protection level as key metadata: Keychain-only, no UserDefaults
// fallback, no plaintext file.
//
// APPROVAL IS THE ENTITLEMENT GRANT PATH: `approve(id:)` flips the
// application to `approved` and calls `SDKAPIKeyStore.grantEntitlement` on
// the applicant's API key — there is no other way to gain an Assist
// entitlement. Grant mapping (v1):
//   - `.developerAIAssist` — always, on every approval.
//   - `.developerAIAllowsCloud` — additionally, when the application
//     declares third-party models or data leaving the device (the answers
//     that make SwiftCode cloud-model access relevant to the app).
// `deny(id:)` flips to `denied` and grants nothing. Grants and revocations
// are recorded in the audit log by `SDKAPIKeyStore` with key ID +
// entitlement ID (never secrets).

public actor SDKAssistApplicationStore {

    /// Process-wide shared store. The actor serializes all access.
    public static let shared = SDKAssistApplicationStore()

    private init() {}

    /// Keychain account prefix for per-application JSON records.
    private static let applicationAccountPrefix = "sdk.assistapp."

    // MARK: - Submit

    /// Validates the application and persists it as `pending`.
    ///
    /// Beyond `validate()` this performs the two checks that need I/O:
    ///   - `extensionID` must match an installed/registered app
    ///     (`SDKExtensionRegistry`).
    ///   - `apiKeyID` must reference an existing, non-revoked, non-expired
    ///     developer API key (`SDKAPIKeyStore`).
    ///
    /// All failures — field-level, registry, and API-key — are reported as
    /// `SDKAssistApplicationValidationError` keyed by field so Studio can
    /// render them inline.
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

        // The store is the timestamp authority: callers cannot backdate or
        // pre-decide an application.
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

    // MARK: - Decide

    /// Approves a pending application: flips it to `approved`, records
    /// `decidedAt`, and grants the entitlements on the applicant's API key
    /// (the approval step IS the entitlement grant path).
    ///
    /// Only pending applications can be decided. Entitlements are granted
    /// BEFORE the approved record is persisted: if the grant fails (e.g.
    /// the key was revoked between submit and approve), the application
    /// stays pending and the failure surfaces to the approver.
    public func approve(id: UUID) async throws -> SDKAssistApplication {
        var application = try load(id: id)
        guard application.status == .pending else {
            throw SDKError(
                code: .invalidArgument,
                message: "This application is no longer pending and cannot be approved.",
                suggestion: "Reload the applications list — another approver may already have decided it."
            )
        }
        // Grant first: these throw if the key is unknown or revoked, which
        // leaves the application pending (fail closed).
        try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAssist, to: application.apiKeyID)
        if application.usesThirdPartyModels || application.dataLeavesDevice {
            try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAllowsCloud, to: application.apiKeyID)
        }
        application.status = .approved
        application.decidedAt = Date()
        try persist(application)
        return application
    }

    /// Denies a pending application: flips it to `denied`, records
    /// `decidedAt`, and grants nothing.
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

    // MARK: - Uninstall revocation (Docs/Intro-to-SDK.md §14)

    /// Revokes every Assist entitlement bound to APPROVED applications for
    /// `extensionID`, returning how many entitlement revocations were
    /// performed.
    ///
    /// THE uninstall hook: called from `SDKExtensionManager.uninstall`.
    /// Uninstalling the app removes its entitlement bindings — each
    /// revocation goes through `SDKAPIKeyStore.revokeEntitlement`, so it
    /// takes effect immediately at the authorization boundary, closes the
    /// key's in-flight Assist sessions, and is audit-recorded (key ID +
    /// entitlement ID, never secrets).
    ///
    /// Application records themselves are kept as historical attestation:
    /// the ENTITLEMENT is the binding, and removing it is what revokes the
    /// approval's effect. A revoked key ID (or a key whose metadata is
    /// gone) is skipped — the binding is already dead — and the method
    /// continues with the rest rather than failing the uninstall.
    public func revokeEntitlementsForExtension(_ extensionID: String) async -> Int {
        let approved = list().filter {
            $0.extensionID == extensionID && $0.status == .approved
        }
        var revoked = 0
        for application in approved {
            // Only revoke entitlements the key actually carries, so the
            // returned count is honest (revokeEntitlement is idempotent and
            // would otherwise count no-ops).
            guard let key = await SDKAPIKeyStore.shared.list().first(where: { $0.id == application.apiKeyID }) else {
                continue // Key metadata is gone — the binding is already dead.
            }
            for entitlement in [SDKEntitlement.developerAIAssist, .developerAIAllowsCloud]
                where key.entitlements.contains(entitlement) {
                do {
                    try await SDKAPIKeyStore.shared.revokeEntitlement(entitlement, from: application.apiKeyID)
                    revoked += 1
                } catch {
                    // The binding died between the list() read and the
                    // revoke — nothing left to revoke. Never fail the
                    // uninstall over it.
                    continue
                }
            }
        }
        return revoked
    }

    // MARK: - Reading

    /// Returns all application records, newest first.
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

    /// Returns pending applications, newest first — the Studio review queue.
    public func pending() -> [SDKAssistApplication] {
        list().filter { $0.status == .pending }
    }

    // MARK: - Persistence

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
