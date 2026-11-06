import Foundation

// MARK: - SDKSecurityService
//
// Ported from Legacy `SwiftCode/SDK/Host/Security/SDKSecurityService.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// The host mediator for extension secrets. Every call authorizes the
// `.useSecurity` UMBRELLA capability first — the granular `security.*`
// IDs are method scopes, never checked separately. Values live in the
// extension's own namespace
// `com.swiftcode.sdk.security.<extensionID>.<appSecurityID>`; a forged
// pre-composed namespace is rejected, never trusted.
//
// The extension NEVER sees plaintext: `addValue` collects the secret
// through the host's secure prompt, and `useValue` injects it host-side
// into one approved HTTPS request, zeroing the bytes afterwards.

public actor SDKSecurityService {
    public static let shared = SDKSecurityService()

    /// Maximum response body returned to the extension (1 MiB).
    public static let maxResponseBodyBytes = 1_048_576

    private init() {}

    // MARK: - Namespace

    /// The vault namespace for one extension + app Security ID.
    /// Pre-composed namespaces are rejected by the caller-facing
    /// methods — the namespace is always built here, never accepted.
    public func namespacedSecurityID(extensionID: String, appSecurityID: String) throws -> String {
        // The app Security ID must itself be a valid Security ID, and
        // the extension ID must be a plain identifier — anything else
        // is a forgery attempt.
        try KeychainSDK.validateSecurityID(appSecurityID)
        guard !extensionID.isEmpty,
              extensionID.unicodeScalars.allSatisfy({ $0.isASCIIAlphanumeric || $0 == "-" || $0 == "." }),
              !extensionID.contains("..") else {
            throw SDKError(code: .invalidArgument, message: "The extension ID is invalid.")
        }
        return "\(extensionID).\(appSecurityID)"
    }

    // MARK: - Add / has / list / delete

    /// Stores a secret. The value is collected through the host's
    /// secure prompt — this method never receives plaintext from the
    /// extension. Validates the value ID and label first; a cancelled
    /// prompt surfaces as `.userCancelled`. The audit event for the add
    /// is recorded by the prompt, not here. Returns whether a value
    /// already existed (`created == false`).
    public func addValue(
        caller: SDKCallerIdentity,
        request: SDKSecurityAddRequest
    ) async throws -> SDKSecurityAddedValue {
        try await SDKCapabilityBroker.authorize(.useSecurity, for: caller)
        let securityID = try namespacedSecurityID(extensionID: caller.extensionID, appSecurityID: request.securityID)
        try KeychainSDK.validateValueID(request.valueID)
        if let label = request.label { try KeychainSDK.validateLabel(label) }
        let value: Data
        do {
            value = try await SDKSensitiveValuePrompt.shared.requestValue(
                securityID: securityID,
                appDisplayName: await displayName(for: caller.extensionID),
                valueID: request.valueID,
                label: request.label,
                prompt: request.prompt
            )
        } catch is CancellationError {
            throw SDKError(code: .userCancelled, message: "The user cancelled the operation.")
        }
        let existed = try KeychainSDK.addValue(securityID: securityID, valueID: request.valueID, value: value, label: request.label)
        return SDKSecurityAddedValue(valueID: request.valueID, created: !existed)
    }

    public func hasValue(caller: SDKCallerIdentity, request: SDKSecurityLookupRequest) async throws -> SDKSecurityHasValue {
        try await SDKCapabilityBroker.authorize(.useSecurity, for: caller)
        let securityID = try namespacedSecurityID(extensionID: caller.extensionID, appSecurityID: request.securityID)
        let exists = try KeychainSDK.hasValue(securityID: securityID, valueID: request.valueID)
        return SDKSecurityHasValue(hasValue: exists)
    }

    /// Metadata only: value IDs, labels, and creation times. Values
    /// are never returned.
    public func listValueIDs(caller: SDKCallerIdentity, request: SDKSecurityListRequest) async throws -> SDKSecurityValueList {
        try await SDKCapabilityBroker.authorize(.useSecurity, for: caller)
        let securityID = try namespacedSecurityID(extensionID: caller.extensionID, appSecurityID: request.securityID)
        let metadata = try KeychainSDK.listValueIDs(securityID: securityID)
        let formatter = ISO8601DateFormatter()
        return SDKSecurityValueList(values: metadata.map {
            SDKSecurityStoredValue(valueID: $0.valueID, label: $0.label ?? "", createdAt: formatter.string(from: $0.created))
        })
    }

    public func deleteValue(caller: SDKCallerIdentity, request: SDKSecurityLookupRequest) async throws {
        try await SDKCapabilityBroker.authorize(.useSecurity, for: caller)
        let securityID = try namespacedSecurityID(extensionID: caller.extensionID, appSecurityID: request.securityID)
        try KeychainSDK.deleteValue(securityID: securityID, valueID: request.valueID)
        await SDKAuditLog.shared.record(
            .securityValueDeleted,
            extensionID: caller.extensionID,
            detail: "security \(auditToken(request.securityID)) value \(auditToken(request.valueID))"
        )
    }

    // MARK: - List all apps (host-only enumeration, S-4)

    /// Every app Security namespace that holds at least one stored
    /// value, with per-app value metadata. Metadata only — secret values
    /// are never returned.
    ///
    /// HOST-ONLY: this is a Studio/host surface, never reachable from
    /// extension IPC (extensions list only their own namespace via
    /// `listValueIDs`). The grouping key is the namespaced Security ID
    /// (`<extensionID>.<appSecurityID>`) recorded in each value's
    /// envelope; values written before the envelope carried it fall back
    /// to a last-dot split of the account name (the value ID is the last
    /// segment), which mis-groups only pre-existing values whose value
    /// IDs themselves contain dots.
    public func listAllApps() async throws -> [SDKSecurityAppSummary] {
        await SDKExtensionRegistry.shared.scan()
        let installed = await SDKExtensionRegistry.shared.installedExtensions()
        let store = SDKSecretStoreFactory.defaultStore()
        let prefix = KeychainSDK.servicePrefix + "."
        let accounts: [String]
        do {
            accounts = try store.accountNames(withPrefix: prefix)
        } catch {
            throw SDKError(
                code: .serviceUnavailable,
                message: "Could not list stored security values.",
                suggestion: "Check that the secret store is reachable and try again.",
                diagnostics: ["operation": "list-all-apps", "underlying": "\(error)"]
            )
        }
        var securityIDs: Set<String> = []
        for account in accounts {
            let remainder = account.dropFirst(prefix.count)
            guard !remainder.isEmpty else { continue }
            if let data = try? store.read(account: account),
               let recorded = KeychainSDK.securityIDInEnvelope(data),
               !recorded.isEmpty {
                securityIDs.insert(recorded)
                continue
            }
            // Legacy envelope: split at the last dot — the value ID is
            // the last segment, the rest is the namespaced Security ID.
            let segments = remainder.split(separator: ".", omittingEmptySubsequences: false)
            guard segments.count >= 3 else { continue }
            securityIDs.insert(segments.dropLast().joined(separator: "."))
        }
        var summaries: [SDKSecurityAppSummary] = []
        for securityID in securityIDs.sorted() {
            let metadata = (try? KeychainSDK.listValueIDs(securityID: securityID)) ?? []
            guard !metadata.isEmpty else { continue }
            let formatter = ISO8601DateFormatter()
            let values = metadata.map {
                SDKSecurityStoredValue(valueID: $0.valueID, label: $0.label ?? "", createdAt: formatter.string(from: $0.created))
            }
            let extensionID = installed
                .map(\.id)
                .filter { securityID == $0 || securityID.hasPrefix($0 + ".") }
                .max(by: { $0.count < $1.count })
            summaries.append(SDKSecurityAppSummary(securityID: securityID, extensionID: extensionID, values: values))
        }
        return summaries
    }

    // MARK: - Use (host-side injection only)

    /// The only supported use of a stored value: inject it as the
    /// `Authorization` header of an approved HTTPS request performed by
    /// the host. The extension never sees the plaintext; the bytes are
    /// zeroed after the request. Only the `httpAuthorization` kind is
    /// supported — anything else is `.invalidArgument`.
    public func useValue(
        caller: SDKCallerIdentity,
        request: SDKSecurityUseRequest
    ) async throws -> SDKSecurityHTTPResponse {
        try await SDKCapabilityBroker.authorize(.useSecurity, for: caller)
        guard request.operation.kind == "httpAuthorization" else {
            throw SDKError(code: .invalidArgument, message: "Unsupported security use operation.")
        }
        let httpRequest = request.operation.request
        try validateHTTPRequest(httpRequest)
        let securityID = try namespacedSecurityID(extensionID: caller.extensionID, appSecurityID: request.securityID)
        guard var secret = try KeychainSDK.readValue(securityID: securityID, valueID: request.valueID) else {
            throw SDKError(code: .invalidArgument, message: "No stored value exists for that ID.")
        }
        defer {
            // Zero the secret bytes the moment the request is done.
            secret.withUnsafeMutableBytes { buffer in
                guard let base = buffer.baseAddress else { return }
                memset(base, 0, buffer.count)
            }
        }
        guard let secretString = String(data: secret, encoding: .utf8), !secretString.isEmpty else {
            throw SDKError(code: .invalidArgument, message: "The stored value is not usable as an authorization header.")
        }
        let response = try await performHTTPRequest(httpRequest, authorization: secretString)
        await SDKAuditLog.shared.record(
            .securityValueUsed,
            extensionID: caller.extensionID,
            detail: "security \(auditToken(request.securityID)) value \(auditToken(request.valueID)) host \(auditToken(URL(string: httpRequest.url)?.host ?? ""))"
        )
        return response
    }

    // MARK: - Uninstall wipe (host-only)

    /// Deletes every value the extension stored, across all app
    /// Security IDs. Host-only: called by the uninstall flow, never by
    /// an extension. Returns the count wiped. Audited.
    public func deleteAllValues(securityID extensionID: String) async throws -> Int {
        // The wipe namespace is the extension's own prefix — every app
        // Security ID under it. The prefix scan uses the raw extension
        // ID, so validate it as an identifier first.
        guard !extensionID.isEmpty,
              extensionID.unicodeScalars.allSatisfy({ $0.isASCIIAlphanumeric || $0 == "-" || $0 == "." }),
              !extensionID.contains("..") else {
            throw SDKError(code: .invalidArgument, message: "The extension ID is invalid.")
        }
        let prefix = "\(KeychainSDK.servicePrefix).\(extensionID)."
        // KeychainSDK's per-namespace delete needs a valid Security ID;
        // enumerate the vault directly for the extension prefix instead.
        let store = SDKSecretStoreFactory.defaultStore()
        let accounts = (try? store.accountNames(withPrefix: prefix)) ?? []
        var count = 0
        for account in accounts {
            try store.delete(account: account)
            count += 1
        }
        await SDKAuditLog.shared.record(
            .securityValuesWipedOnUninstall,
            extensionID: extensionID,
            detail: "wiped \(count) values"
        )
        return count
    }

    // MARK: - Private

    /// Display name for the prompt, from the registry when installed.
    public func displayName(for extensionID: String) async -> String {
        await SDKExtensionRegistry.shared.installedExtension(id: extensionID)?.name ?? extensionID
    }

    private func auditToken(_ value: String) -> String {
        String(value.prefix(128))
    }

    private func validateHTTPRequest(_ request: SDKSecurityHTTPRequest) throws {
        // Method: bare token, 1–16 letters.
        guard (1...16).contains(request.method.count),
              request.method.unicodeScalars.allSatisfy({ ($0.value >= 65 && $0.value <= 90) || ($0.value >= 97 && $0.value <= 122) }) else {
            throw SDKError(code: .invalidArgument, message: "The HTTP method is invalid.")
        }
        // Absolute HTTPS URL, no embedded credentials.
        guard let url = URL(string: request.url),
              url.scheme?.lowercased() == "https",
              url.host != nil, !url.host!.isEmpty,
              url.user == nil, url.password == nil else {
            throw SDKError(code: .invalidArgument, message: "The request URL must be an absolute HTTPS URL without embedded credentials.")
        }
        // The host owns `Authorization`; the client must not supply it.
        if let headers = request.headers {
            for key in headers.keys where key.lowercased() == "authorization" {
                throw SDKError(code: .invalidArgument, message: "The request must not supply its own Authorization header.")
            }
        }
    }

    private func performHTTPRequest(
        _ request: SDKSecurityHTTPRequest,
        authorization: String
    ) async throws -> SDKSecurityHTTPResponse {
        guard let url = URL(string: request.url) else {
            throw SDKError(code: .invalidArgument, message: "The request URL is invalid.")
        }
        var urlRequest = URLRequest(url: url, timeoutInterval: 30)
        urlRequest.httpMethod = request.method
        urlRequest.setValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization")
        for (key, value) in request.headers ?? [:] {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        if let body = request.body {
            urlRequest.httpBody = Data(body.utf8)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 50
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        let delegate = SDKSecurityRedirectHandler()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw SDKError(code: .serviceUnavailable, message: "The request did not return an HTTP response.")
            }
            let truncated = data.count > Self.maxResponseBodyBytes
            let bodyData = truncated ? data.prefix(Self.maxResponseBodyBytes) : data[...]
            let body = String(decoding: bodyData, as: UTF8.self)
            return SDKSecurityHTTPResponse(status: http.statusCode, body: body)
        } catch let error as SDKError {
            throw error
        } catch {
            throw SDKError(
                code: .serviceUnavailable,
                message: "The request failed.",
                suggestion: "Check the network connection and try again.",
                diagnostics: ["underlyingError": String(describing: error).prefix(300).description]
            )
        }
    }
}

/// Redirect policy for host-performed security requests: HTTPS only,
/// and the `Authorization` header is stripped on any cross-host
/// redirect so the secret never leaks to another host.
private final class SDKSecurityRedirectHandler: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, url.scheme?.lowercased() == "https" else {
            completionHandler(nil)
            return
        }
        var redirected = request
        if redirected.url?.host != task.originalRequest?.url?.host {
            redirected.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(redirected)
    }
}

/// One app Security namespace in the host vault, as returned by
/// `SDKSecurityService.listAllApps`. Metadata only: value IDs, labels,
/// and creation times — secret values are never returned.
/// `extensionID` is the longest installed-extension prefix of the
/// namespaced Security ID, or nil when the extension is not installed
/// (leftover values from an uninstalled extension).
public struct SDKSecurityAppSummary: Sendable, Codable, Equatable {
    /// Namespaced Security ID (`<extensionID>.<appSecurityID>`).
    public let securityID: String
    public let extensionID: String?
    public let values: [SDKSecurityStoredValue]

    public init(securityID: String, extensionID: String?, values: [SDKSecurityStoredValue]) {
        self.securityID = securityID
        self.extensionID = extensionID
        self.values = values
    }
}

private extension Unicode.Scalar {
    var isASCIIAlphanumeric: Bool {
        (value >= 48 && value <= 57) || (value >= 65 && value <= 90) || (value >= 97 && value <= 122)
    }
}
