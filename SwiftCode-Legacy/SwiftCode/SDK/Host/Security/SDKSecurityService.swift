import Foundation
import Security

// MARK: - SDKSecurityService
//
// Host-side security broker for the SDK's `use.Security` capability: the
// per-app Keychain secret vault that extensions use through host mediation
// and never see in plaintext (spec §8.1, `Docs/Security-Keychain.md`).
//
// ---------------------------------------------------------------------------
// SECURITY RULES — ALL ENFORCED HOST-SIDE, EVERY CALL
// ---------------------------------------------------------------------------
// 1. Per-call broker authorization of the UMBRELLA ONLY. Every IPC-facing
//    method calls `SDKCapabilityBroker.authorize(.useSecurity, for:)` FIRST
//    — before any Keychain touch — and nothing else. The five granular
//    `security.*` capability IDs (`.securityAddValue`, `.securityHasValue`,
//    `.securityListValueIDs`, `.securityDeleteValue`, `.securityUseValue`)
//    are method scopes enforced under the single `use.Security` grant: they
//    are deliberately NOT separately grantable
//    (`grantableInCurrentRelease: false`), so the broker would deny them
//    and the service must not check them. A denial throws the broker's
//    typed PERMISSION_DENIED and is additionally recorded as a
//    `securityPermissionDenied` audit event carrying the targeted
//    identifiers. The Keychain is never touched on a denied call. There is
//    no cached or ambient authorization: revocation/expired grants fail the
//    next call.
//
// 2. Session-bound namespace. The Keychain partition's identity component
//    ALWAYS comes from the session-bound `SDKCallerIdentity.extensionID`
//    (host-created `SDKRuntimeSessionInfo`, validated manifest) — never
//    from an IPC payload field. The payload's `securityID` (the app's
//    Security ID, e.g. "api-keys") selects a sub-partition INSIDE the
//    caller's own namespace only: the composed partition is
//    `com.swiftcode.sdk.security.<extensionID>.<appSecurityID>`, so a
//    forged payload value can never address another extension's secrets.
//    A payload `securityID` that already carries the session's extension
//    namespace (a pre-composed/forged fully-qualified name) is rejected
//    outright — callers supply the bare app Security ID.
//
// 3. Secrets never cross IPC. `KeychainSDK.readValue` is module-internal
//    and used only by `useValue`, which injects the bytes into a
//    host-built `URLRequest` and lets them deallocate. Responses carry
//    metadata (`{valueID, created}`, `{hasValue}`, `{values: [...]}`) or
//    operation results (`{status, body}`) — never secret bytes. Audit
//    `detail` fields carry identifiers only (app Security ID, value ID,
//    operation kind) — never secrets, labels, request bodies, or URLs.
//
// 4. `deleteAllValues` is HOST-ONLY (no caller identity, no broker check):
//    it is called by the extension uninstall path, where the Studio
//    uninstall flow itself is the user authorization. It is NOT reachable
//    from extension IPC.
//
// Storage goes through `KeychainSDK` (`Host/Security/KeychainSDK.swift`):
// service `com.swiftcode.sdk.security.<namespace>`,
// `kSecClassGenericPassword`, accessibility
// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, no sync, no UserDefaults
// fallback, no in-memory cache. Keychain failures fail closed
// (`.serviceUnavailable`), never by degrading to a weaker store.

public actor SDKSecurityService {

    // MARK: - Shared instance

    public static let shared = SDKSecurityService()

    private init() {}

    // MARK: - Tuning

    /// The only host operation kind `useValue` supports in this release.
    private static let httpAuthorizationKind = "httpAuthorization"

    /// Network budget for one `useValue` HTTPS request. Stays under the IPC
    /// dispatcher's 60 s per-request watchdog so a slow endpoint surfaces
    /// as a typed `.requestTimeout`, not an `.ipcTimeout`.
    private static let httpRequestTimeout: TimeInterval = 30
    private static let httpResourceTimeout: TimeInterval = 50

    /// Response/request body bounds. The response body must fit the IPC
    /// frame discipline, so it is truncated at 1 MiB (documented, never
    /// silent in code review — see `useValue`).
    private static let maxBodyBytes = 1024 * 1024

    private static nonisolated(unsafe) let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func formattedISO8601(from date: Date) -> String {
        iso8601.string(from: date)
    }

    // MARK: - addValue

    /// Stores a secret under (`securityID`, `valueID`) for the calling
    /// extension. The secret itself is entered by the user into the host's
    /// secure prompt (`SDKSensitiveValuePrompt` → `EnterSecuritySDKView`),
    /// which writes it straight to the Keychain — the secret never passes
    /// through this service and the extension never handles it. Resolves
    /// with `{valueID, created}` metadata only.
    ///
    /// - Throws: the broker's typed denial when `.useSecurity` is not
    ///   granted; `.invalidArgument` for bad identifiers; `.userCancelled`
    ///   when the user dismisses the prompt; `.serviceUnavailable` on
    ///   Keychain failure.
    public func addValue(
        request: SDKSecurityAddRequest,
        caller: SDKCallerIdentity
    ) async throws -> SDKSecurityAddedValue {
        try await authorize(
            for: caller,
            securityID: request.securityID, valueID: request.valueID
        )
        let namespace = try Self.namespacedSecurityID(
            appSecurityID: request.securityID, caller: caller
        )
        // Validate BEFORE presenting the prompt: the user must not type a
        // secret only to be told the slot name was invalid. (The prompt
        // and `KeychainSDK` re-validate — defense in depth.)
        try Self.validateValueID(request.valueID)
        try Self.validateLabel(request.label)

        let existed = try KeychainSDK.hasValue(securityID: namespace, valueID: request.valueID)

        // The prompt presents the secure sheet and writes the Keychain item
        // itself; it also records `securityValueAdded` — this method must
        // NOT write or audit again. The namespace passed here is the
        // session-bound composed ID, never the raw payload value.
        let displayName = await Self.appDisplayName(for: caller.extensionID)
        do {
            try await SDKSensitiveValuePrompt.requestValue(
                securityID: namespace,
                appDisplayName: displayName,
                valueID: request.valueID,
                label: request.label,
                prompt: request.prompt
            )
        } catch is CancellationError {
            // The user dismissed the prompt (or this task was cancelled,
            // e.g. by the dispatcher's watchdog): nothing was stored by
            // this call. A dismissal is not a permission denial, so no
            // audit event is recorded.
            throw SDKError(
                code: .userCancelled,
                message: "The user cancelled the secure prompt; nothing was stored.",
                suggestion: "Ask the user to approve storing the value and try again."
            )
        }

        // Note: `existed` is read before the prompt, so two concurrent
        // `addValue` calls for the same slot can both report
        // `created: true`; the Keychain write itself is an atomic upsert
        // and the last write wins. The flag is informational, not a lock.
        return SDKSecurityAddedValue(valueID: request.valueID, created: !existed)
    }

    // MARK: - hasValue

    /// Existence check for one stored value. Returns `{hasValue}` — the
    /// secret bytes are never returned. A locked-device Keychain failure
    /// throws `.serviceUnavailable` and is NOT coerced to `false`.
    public func hasValue(
        request: SDKSecurityLookupRequest,
        caller: SDKCallerIdentity
    ) async throws -> SDKSecurityHasValue {
        try await authorize(
            for: caller,
            securityID: request.securityID, valueID: request.valueID
        )
        let namespace = try Self.namespacedSecurityID(
            appSecurityID: request.securityID, caller: caller
        )
        try Self.validateValueID(request.valueID)
        let exists = try KeychainSDK.hasValue(securityID: namespace, valueID: request.valueID)
        return SDKSecurityHasValue(hasValue: exists)
    }

    // MARK: - listValueIDs

    /// Inventory of one app Security ID: value IDs, labels, and creation
    /// dates. Names and metadata only — values stay in the Keychain.
    public func listValueIDs(
        request: SDKSecurityListRequest,
        caller: SDKCallerIdentity
    ) async throws -> SDKSecurityValueList {
        try await authorize(
            for: caller,
            securityID: request.securityID, valueID: nil
        )
        let namespace = try Self.namespacedSecurityID(
            appSecurityID: request.securityID, caller: caller
        )
        let metadata = try KeychainSDK.listValueIDs(securityID: namespace)
        let values = metadata.map { entry in
            SDKSecurityStoredValue(
                valueID: entry.valueID,
                label: entry.label ?? "",
                createdAt: Self.formattedISO8601(from: entry.created)
            )
        }
        return SDKSecurityValueList(values: values)
    }

    // MARK: - deleteValue

    /// Permanently deletes one stored value. Idempotent: deleting a value
    /// that does not exist succeeds.
    public func deleteValue(
        request: SDKSecurityLookupRequest,
        caller: SDKCallerIdentity
    ) async throws {
        try await authorize(
            for: caller,
            securityID: request.securityID, valueID: request.valueID
        )
        let namespace = try Self.namespacedSecurityID(
            appSecurityID: request.securityID, caller: caller
        )
        try Self.validateValueID(request.valueID)
        try KeychainSDK.deleteValue(securityID: namespace, valueID: request.valueID)
        await SDKAuditLog.shared.record(
            type: .securityValueDeleted,
            extensionID: caller.extensionID,
            capability: .securityDeleteValue,
            detail: "securityID=\(request.securityID) valueID=\(request.valueID)",
            correlationId: SDKError.newCorrelationId()
        )
    }

    // MARK: - useValue

    /// Host-mediated use of a stored secret: reads the secret via
    /// `KeychainSDK`'s internal (host-only) read, attaches it as the
    /// `Authorization` header of a host-built HTTPS request, performs the
    /// request, and returns only `{status, body}`. The secret NEVER enters
    /// the response, the audit log, or any error.
    ///
    /// Request validation (all host-side, re-checked even though the
    /// TypeScript client validates first): operation kind must be
    /// `httpAuthorization`; method must be a bare token; the URL must be
    /// absolute https with no embedded credentials; the extension must not
    /// supply `Authorization` (the host owns that header).
    public func useValue(
        request: SDKSecurityUseRequest,
        caller: SDKCallerIdentity
    ) async throws -> SDKSecurityHTTPResponse {
        try await authorize(
            for: caller,
            securityID: request.securityID, valueID: request.valueID
        )
        let namespace = try Self.namespacedSecurityID(
            appSecurityID: request.securityID, caller: caller
        )
        try Self.validateValueID(request.valueID)

        guard request.operation.kind == Self.httpAuthorizationKind else {
            throw SDKError(
                code: .invalidArgument,
                message: "Unsupported security operation kind \"\(request.operation.kind)\".",
                suggestion: "The only supported operation kind is \"\(Self.httpAuthorizationKind)\"."
            )
        }
        let validated = try Self.validatedHTTPRequest(request.operation.request)

        // Host-only read: the bytes live in memory only for this call.
        guard let secretData = try KeychainSDK.readValue(
            securityID: namespace, valueID: request.valueID
        ) else {
            throw SDKError(
                code: .invalidArgument,
                message: "No stored value for \"\(request.valueID)\".",
                suggestion: "Store a value with \"security.addValue\" first."
            )
        }
        var secretBytes = secretData
        defer { secretBytes.resetBytes(in: 0..<secretBytes.count) }
        guard let secret = String(data: secretBytes, encoding: .utf8), !secret.isEmpty else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "The stored security value is corrupt and cannot be used.",
                suggestion: "Delete the value and store it again with \"security.addValue\"."
            )
        }

        let (status, body) = try await Self.performHTTPRequest(validated, bearerSecret: secret)

        // Metadata-level audit: which app, which value, which operation —
        // never the secret, never the request body, never the URL (query
        // strings can carry tokens).
        await SDKAuditLog.shared.record(
            type: .securityValueUsed,
            extensionID: caller.extensionID,
            capability: .securityUseValue,
            detail: "securityID=\(request.securityID) valueID=\(request.valueID) operation=\(Self.httpAuthorizationKind)",
            correlationId: SDKError.newCorrelationId()
        )
        return SDKSecurityHTTPResponse(status: status, body: body)
    }

    // MARK: - deleteAllValues (host-only uninstall wipe)

    /// Deletes EVERY Keychain item in the extension's Security namespace —
    /// all app Security IDs, all value IDs. Called by the extension
    /// uninstall path (`SDKExtensionRegistry.removeInstallRecord`).
    ///
    /// HOST-ONLY: this takes the extension's own Security ID
    /// (`extensionID`), not a caller identity, and performs no broker
    /// check — the Studio uninstall flow is itself the user authorization,
    /// and this method is not reachable from extension IPC.
    ///
    /// - Returns: the number of values wiped (for the audit record).
    /// - Throws: `.invalidArgument` for a bad ID; `.serviceUnavailable`
    ///   on Keychain failure. The uninstall path treats any failure as
    ///   fatal so secrets can never silently survive an uninstall.
    public func deleteAllValues(securityID: String) async throws -> Int {
        let trimmed = securityID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SDKError(
                code: .invalidArgument,
                message: "Invalid security identifier.",
                suggestion: "Pass the extension's own Security ID (its extension ID)."
            )
        }
        guard !trimmed.contains(KeychainSDK.servicePrefix) else {
            throw SDKError(
                code: .invalidArgument,
                message: "Invalid security identifier.",
                suggestion: "Pass the extension's own Security ID, not a Keychain service string."
            )
        }

        // One extension owns every partition under
        // `com.swiftcode.sdk.security.<extensionID>.` — the trailing dot
        // keeps `com.example.app` from matching `com.example.app2`.
        let prefix = KeychainSDK.servicePrefix + "." + trimmed + "."
        let services = try Self.keychainServices(matchingPrefix: prefix)

        var wiped = 0
        for service in services {
            // Recover the composed namespace from the service string; the
            // prefix match above guarantees the shape.
            let composite = String(service.dropFirst(KeychainSDK.servicePrefix.count + 1))
            wiped += (try? KeychainSDK.listValueIDs(securityID: composite))?.count ?? 0
            try KeychainSDK.deleteAllValues(securityID: composite)
        }

        await SDKAuditLog.shared.record(
            type: .securityValuesWipedOnUninstall,
            extensionID: trimmed,
            detail: "securityID=\(trimmed) wipedValues=\(wiped)",
            correlationId: SDKError.newCorrelationId()
        )
        return wiped
    }

    // MARK: - Authorization

    /// The per-call gate: `.useSecurity` (the umbrella grant) ONLY — before
    /// any Keychain touch. The granular `security.*` IDs are method scopes,
    /// not separately grantable permissions, so they are deliberately never
    /// checked here: the broker would deny them. A denial is recorded as
    /// `securityPermissionDenied` (with the targeted identifiers, never
    /// secrets) and rethrown as the broker's typed denial.
    private func authorize(
        for caller: SDKCallerIdentity,
        securityID: String?,
        valueID: String?
    ) async throws {
        do {
            try await SDKCapabilityBroker.authorize(.useSecurity, for: caller)
        } catch {
            // Client-supplied identifiers are truncated: a hostile caller
            // must not be able to bloat the append-only audit log with
            // megabyte strings.
            var detail = "authorize(use.Security) denied"
            if let securityID, !securityID.isEmpty {
                detail += " securityID=\(Self.auditToken(securityID))"
            }
            if let valueID, !valueID.isEmpty {
                detail += " valueID=\(Self.auditToken(valueID))"
            }
            await SDKAuditLog.shared.record(
                type: .securityPermissionDenied,
                extensionID: caller.extensionID,
                capability: .useSecurity,
                detail: detail,
                correlationId: SDKError.newCorrelationId()
            )
            throw error
        }
    }

    // MARK: - Namespace derivation

    /// Derives the `KeychainSDK` partition's security ID for this caller:
    /// `<extensionID>.<appSecurityID>`.
    ///
    /// The extension component ALWAYS comes from the session-bound caller
    /// identity — never from the payload. The payload's `securityID` (the
    /// app's Security ID, e.g. "api-keys") only selects a sub-partition
    /// inside the caller's own namespace, so a forged value can never
    /// address another extension's secrets.
    ///
    /// - Throws: `.invalidArgument` when the app Security ID is empty,
    ///   when it already carries the session's extension namespace (a
    ///   pre-composed/forged fully-qualified name is rejected — callers
    ///   supply the bare app Security ID), or when it smuggles the
    ///   Keychain service prefix. The composed ID is re-validated
    ///   strictly by `KeychainSDK` on every use.
    private static func namespacedSecurityID(
        appSecurityID: String,
        caller: SDKCallerIdentity
    ) throws -> String {
        let trimmed = appSecurityID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SDKError(
                code: .invalidArgument,
                message: "The securityID must not be empty.",
                suggestion: "Pass the app's Security ID, e.g. \"api-keys\"."
            )
        }
        let extID = caller.extensionID
        if trimmed == extID
            || trimmed.hasPrefix(extID + ".")
            || trimmed.hasSuffix("." + extID)
            || trimmed.contains(KeychainSDK.servicePrefix) {
            throw SDKError(
                code: .invalidArgument,
                message: "The securityID does not match this session's namespace.",
                suggestion: "Pass the bare app Security ID (e.g. \"api-keys\"); the host binds it to the calling extension."
            )
        }
        return "\(extID).\(trimmed)"
    }

    /// Service-side value-ID validation, mirroring `KeychainSDK`'s rules
    /// (which re-validate on every write/read — defense in depth). Run
    /// BEFORE the secure prompt so the user never types a secret for an
    /// invalid slot name.
    private static func validateValueID(_ valueID: String) throws {
        guard !valueID.isEmpty, valueID.count <= 128 else {
            throw SDKError(
                code: .invalidArgument,
                message: "Invalid security value ID.",
                suggestion: "Value IDs look like \"github-token\": 1–128 characters."
            )
        }
        guard !valueID.contains("/"), !valueID.contains("..") else {
            throw SDKError(
                code: .invalidArgument,
                message: "Invalid security value ID.",
                suggestion: "Value IDs must not contain \"/\" or \"..\"."
            )
        }
        let chars = Array(valueID)
        guard let first = chars.first, let last = chars.last,
              first.isASCIILetterOrDigit, last.isASCIILetterOrDigit,
              chars.allSatisfy({ $0.isASCIILetterOrDigit || $0 == "." || $0 == "-" || $0 == "_" })
        else {
            throw SDKError(
                code: .invalidArgument,
                message: "Invalid security value ID.",
                suggestion: "Use letters and digits with interior \".\", \"-\", \"_\" (e.g. \"github-token\")."
            )
        }
    }

    /// Labels are free text shown in the host UI. They are never logged
    /// (free text can contain pasted secrets) and are bounded so one
    /// extension cannot bloat another surface.
    private static func validateLabel(_ label: String?) throws {
        guard let label else { return }
        guard !label.isEmpty, label.count <= 256, !label.contains("\0") else {
            throw SDKError(
                code: .invalidArgument,
                message: "Invalid security label.",
                suggestion: "Labels are 1–256 characters without NUL bytes."
            )
        }
    }

    /// The extension's display name for the secure prompt, from the host's
    /// install registry — never from extension input. Falls back to the
    /// extension ID when the registry has no record.
    private static func appDisplayName(for extensionID: String) async -> String {
        await SDKExtensionRegistry.shared.installedExtension(id: extensionID)?.name ?? extensionID
    }

    /// Truncates a client-supplied identifier for audit `detail` fields so
    /// a hostile caller cannot bloat the append-only audit log.
    private static func auditToken(_ value: String) -> String {
        value.count > 128 ? String(value.prefix(128)) : value
    }

    // MARK: - HTTP request validation + execution

    /// A validated, host-safe HTTPS request: absolute https URL, no embedded
    /// credentials, bare-token method, no client-supplied Authorization.
    private struct ValidatedHTTPRequest: Sendable {
        struct Header: Sendable {
            let name: String
            let value: String
        }
        let url: URL
        let method: String
        let headers: [Header]
        let body: Data?
    }

    private static func validatedHTTPRequest(_ request: SDKSecurityHTTPRequest) throws -> ValidatedHTTPRequest {
        // Method: bare token, 1–16 ASCII letters (mirrors the TS client).
        guard request.method.count <= 16,
              !request.method.isEmpty,
              request.method.allSatisfy({ $0.isASCII && $0.isLetter })
        else {
            throw SDKError(
                code: .invalidArgument,
                message: "Invalid security HTTP method.",
                suggestion: "Use a bare method token such as \"GET\" or \"POST\"."
            )
        }

        guard let url = URL(string: request.url),
              let scheme = url.scheme?.lowercased(), scheme == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil
        else {
            throw SDKError(
                code: .invalidArgument,
                message: "Invalid security HTTP URL.",
                suggestion: "Use an absolute https URL without embedded credentials."
            )
        }

        var headers: [ValidatedHTTPRequest.Header] = []
        for (name, value) in request.headers ?? [:] {
            guard !name.isEmpty else {
                throw SDKError(
                    code: .invalidArgument,
                    message: "Invalid security HTTP header.",
                    suggestion: "Header names must not be empty."
                )
            }
            // The host owns the Authorization header — a client-supplied
            // one is rejected, never merged or overridden.
            guard name.lowercased() != "authorization" else {
                throw SDKError(
                    code: .invalidArgument,
                    message: "The security HTTP request must not set the Authorization header.",
                    suggestion: "The host attaches the stored secret as the Authorization header."
                )
            }
            headers.append(ValidatedHTTPRequest.Header(name: name, value: value))
        }

        let body: Data?
        if let bodyString = request.body {
            let data = Data(bodyString.utf8)
            guard data.count <= maxBodyBytes else {
                throw SDKError(
                    code: .invalidArgument,
                    message: "The security HTTP request body is too large.",
                    suggestion: "Keep request bodies under 1 MiB."
                )
            }
            body = data
        } else {
            body = nil
        }

        return ValidatedHTTPRequest(
            url: url,
            method: request.method.uppercased(),
            headers: headers,
            body: body
        )
    }

    /// Performs the HTTPS request with the secret attached as
    /// `Authorization: Bearer <secret>`. Cookies are disabled (neither the
    /// host's cookie jar nor the extension-driven request may leak into
    /// each other), redirects are constrained to https by the delegate,
    /// and the Authorization header is stripped on cross-host redirects.
    ///
    /// - Returns: `(status, body)` — the body truncated at 1 MiB. The
    ///   secret never appears in the result.
    private static func performHTTPRequest(
        _ request: ValidatedHTTPRequest,
        bearerSecret: String
    ) async throws -> (status: Int, body: String) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = httpRequestTimeout
        configuration.timeoutIntervalForResource = httpResourceTimeout
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never

        let delegate = SecurityHTTPRedirectDelegate(originalHost: request.url.host)
        let session = URLSession(
            configuration: configuration, delegate: delegate, delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }

        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpShouldHandleCookies = false
        urlRequest.setValue("Bearer \(bearerSecret)", forHTTPHeaderField: "Authorization")
        for header in request.headers {
            urlRequest.setValue(header.value, forHTTPHeaderField: header.name)
        }
        urlRequest.httpBody = request.body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let urlError as URLError {
            if urlError.code == .timedOut {
                throw SDKError(
                    code: .requestTimeout,
                    message: "The security HTTP request timed out.",
                    suggestion: "Retry the request; the remote endpoint may be slow."
                )
            }
            throw SDKError(
                code: .serviceUnavailable,
                message: "The security HTTP request failed.",
                suggestion: "Check the request URL and network connectivity, then retry.",
                diagnostics: ["reason": "url-error"]
            )
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "The security HTTP request did not return an HTTP response.",
                suggestion: "Check the request URL and retry."
            )
        }

        // The response body must fit the IPC frame discipline: truncate at
        // 1 MiB (lossy UTF-8 decode keeps this total even for binary
        // bodies). Truncation is documented here; the wire contract is
        // exactly {status, body}.
        let capped = data.count > Self.maxBodyBytes ? Data(data.prefix(Self.maxBodyBytes)) : data
        let body = String(decoding: capped, as: UTF8.self)
        return (status: httpResponse.statusCode, body: body)
    }

    // MARK: - Keychain enumeration (uninstall wipe)

    /// Service names of every generic-password Keychain item whose service
    /// starts with `prefix`. Attributes only — no secret data is returned
    /// (`kSecReturnData` is never set). Used solely by `deleteAllValues`
    /// to find every partition in the extension's Security namespace;
    /// host-side only, never reachable from extension IPC.
    private static func keychainServices(matchingPrefix prefix: String) throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "Could not enumerate the app's security values.",
                suggestion: "Check that the macOS Keychain is unlocked and try again.",
                diagnostics: ["operation": "enumerate-services", "osstatus": String(status)]
            )
        }
        guard let items = result as? [[String: Any]] else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "Could not enumerate the app's security values.",
                suggestion: "Check that the macOS Keychain is unlocked and try again.",
                diagnostics: ["operation": "enumerate-services", "reason": "unexpected-result-shape"]
            )
        }
        let names = items.compactMap { $0[kSecAttrService as String] as? String }
            .filter { $0.hasPrefix(prefix) }
        // De-duplicate: one service appears once per stored item.
        return Array(Set(names)).sorted()
    }
}

// MARK: - Character helpers

private extension Character {
    /// ASCII letter or digit only — by explicit Unicode-scalar ranges, so
    /// no locale or Unicode-shape surprise can widen the accepted set.
    /// (Mirrors the file-private helper in `KeychainSDK.swift`.)
    var isASCIILetterOrDigit: Bool {
        unicodeScalars.allSatisfy { scalar in
            let v = scalar.value
            return (v >= 0x30 && v <= 0x39)   // 0-9
                || (v >= 0x41 && v <= 0x5A)   // A-Z
                || (v >= 0x61 && v <= 0x7A)   // a-z
        }
    }
}

// MARK: - SecurityHTTPRedirectDelegate

/// Redirect policy for host-performed `useValue` requests. Stateless —
/// safe to share across requests.
///
/// - Redirects to non-https URLs are refused (no downgrade, ever).
/// - The `Authorization` header the host attached is stripped when the
///   redirect leaves the original host: a compromised or malicious
///   endpoint must not be able to bounce the secret to another origin
///   via a 30x. The follow-up request then goes out unauthenticated and
///   the extension sees the endpoint's honest 401 in `{status, body}`.
private final class SecurityHTTPRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let originalHost: String?

    init(originalHost: String?) {
        self.originalHost = originalHost?.lowercased()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url,
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            completionHandler(nil)
            return
        }
        var redirected = request
        if let originalHost, url.host?.lowercased() != originalHost {
            redirected.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(redirected)
    }
}