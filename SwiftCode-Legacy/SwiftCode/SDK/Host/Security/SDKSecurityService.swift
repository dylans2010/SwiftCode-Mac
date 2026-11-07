import Foundation
import Security

public actor SDKSecurityService {

    public static let shared = SDKSecurityService()

    private init() {}

    private static let httpAuthorizationKind = "httpAuthorization"

    private static let httpRequestTimeout: TimeInterval = 30
    private static let httpResourceTimeout: TimeInterval = 50

    private static let maxBodyBytes = 1024 * 1024

    private static nonisolated(unsafe) let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func formattedISO8601(from date: Date) -> String {
        iso8601.string(from: date)
    }

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
        try Self.validateValueID(request.valueID)
        try Self.validateLabel(request.label)

        let existed = try KeychainSDK.hasValue(securityID: namespace, valueID: request.valueID)

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
            throw SDKError(
                code: .userCancelled,
                message: "The user cancelled the secure prompt; nothing was stored.",
                suggestion: "Ask the user to approve storing the value and try again."
            )
        }

        return SDKSecurityAddedValue(valueID: request.valueID, created: !existed)
    }

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

        await SDKAuditLog.shared.record(
            type: .securityValueUsed,
            extensionID: caller.extensionID,
            capability: .securityUseValue,
            detail: "securityID=\(request.securityID) valueID=\(request.valueID) operation=\(Self.httpAuthorizationKind)",
            correlationId: SDKError.newCorrelationId()
        )
        return SDKSecurityHTTPResponse(status: status, body: body)
    }

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

        let prefix = KeychainSDK.servicePrefix + "." + trimmed + "."
        let services = try Self.keychainServices(matchingPrefix: prefix)

        var wiped = 0
        for service in services {
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

    private func authorize(
        for caller: SDKCallerIdentity,
        securityID: String?,
        valueID: String?
    ) async throws {
        do {
            try await SDKCapabilityBroker.authorize(.useSecurity, for: caller)
        } catch {
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

    private static func appDisplayName(for extensionID: String) async -> String {
        await SDKExtensionRegistry.shared.installedExtension(id: extensionID)?.name ?? extensionID
    }

    private static func auditToken(_ value: String) -> String {
        value.count > 128 ? String(value.prefix(128)) : value
    }

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

        let capped = data.count > Self.maxBodyBytes ? Data(data.prefix(Self.maxBodyBytes)) : data
        let body = String(decoding: capped, as: UTF8.self)
        return (status: httpResponse.statusCode, body: body)
    }

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
        return Array(Set(names)).sorted()
    }
}

private extension Character {
    var isASCIILetterOrDigit: Bool {
        unicodeScalars.allSatisfy { scalar in
            let v = scalar.value
            return (v >= 0x30 && v <= 0x39)
                || (v >= 0x41 && v <= 0x5A)
                || (v >= 0x61 && v <= 0x7A)
        }
    }
}

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
