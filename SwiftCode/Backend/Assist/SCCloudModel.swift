//
//  SCCloudModel.swift
//  SwiftCode
//
//  SwiftCode Cloud Models — SwiftCode's hosted models, available in Assist through
//  the "Use SwiftCode's Cloud Model" toggle in Assist settings.
//
//  What this file owns:
//    • SCCloudConfiguration   — endpoint URLs, wire format, request building,
//                               response parsing, and the internal-ID scheme.
//    • SCCloudModelInfo       — one discovered model (endpoint name + metadata).
//    • SCCloudModelDiscovery  — dynamic model discovery: queries the server's
//                               model list (OpenAI-style /v1/models or Ollama
//                               /api/tags depending on the wire format), caches
//                               the result locally, and serves it to the picker,
//                               router, and settings UI. The server hosts MANY
//                               models — nothing here hardcodes a single model.
//    • SCCloudDeviceFingerprint — per-device rate-limit identity: "ssc_" + SHA-256
//                               of stable hardware identifiers. Generated when the
//                               user enables the toggle. Stored in the Keychain,
//                               NEVER exposed to the UI.
//    • SCCloudRateLimiter     — 10 requests per rolling 24-hour window. Once the
//                               limit is hit the device is locked out until 24h
//                               after its oldest request in the window.
//    • SCCloudModelClient     — sends a prompt to the cloud endpoint using the
//                               selected discovered model, attaching the
//                               fingerprint header so the backend can enforce
//                               fair use too.
//
//  Fair-use model: the client enforces the 10/day cap locally AND sends the
//  device fingerprint with every request so the server can enforce it
//  independently.

import Foundation
import CryptoKit
import os

private let logger = Logger(subsystem: "com.swiftcode.Assist", category: "SCCloudModel")

// MARK: - Configuration

public enum SCCloudConfiguration {

    /// Base URL of the cloud endpoint (Cloudflare tunnel fronting the model host).
    public static let baseURLString = "https://hawk-leaving-converter-federation.trycloudflare.com"

    /// Wire format used for chat requests and model discovery.
    ///
    /// `.openAICompatible` (recommended) uses:
    ///   chat     → POST /v1/chat/completions
    ///   discovery→ GET  /v1/models
    /// `.ollamaNative` uses:
    ///   chat     → POST /api/chat
    ///   discovery→ GET  /api/tags
    public enum WireFormat {
        case openAICompatible
        case ollamaNative
    }
    public static let wireFormat: WireFormat = .openAICompatible

    // Endpoint paths (joined onto baseURLString).
    public static let chatCompletionsPath = "/v1/chat/completions"
    public static let modelsListPath = "/v1/models"
    public static let ollamaChatPath = "/api/chat"
    public static let ollamaTagsPath = "/api/tags"

    /// Fallback model name sent when no discovery result exists yet
    /// (e.g. the server is unreachable on first launch). Leave empty to
    /// require a discovered model list instead of guessing a name.
    public static let defaultModelIdentifier = ""

    // MARK: Internal identity scheme
    //
    // Inside SwiftCode every cloud model gets a stable internal ID:
    //   "swiftcode-cloud"            — legacy single-model ID (pre-discovery).
    //   "swiftcode-cloud:<name>"    — one per discovered model, where <name>
    //                                 is the exact name the endpoint serves.
    // Callers must use isCloudModelID(_:) — never string-compare against a
    // single hardcoded ID — because the server hosts many models.

    public static let modelIDPrefix = "swiftcode-cloud"

    public static let displayName = "SwiftCode Cloud Model"
    public static let providerID = "swiftcode-cloud"
    public static let providerName = "SwiftCode Cloud"

    /// Header carrying the device fingerprint on every cloud request.
    /// The backend uses this value — and only this value — to rate-limit devices.
    public static let fingerprintHeaderName = "X-SwiftCode-Device-Fingerprint"

    /// Fair-use policy: at most this many requests per rolling 24-hour window.
    public static let dailyRequestLimit = 10
    public static let rateLimitWindow: TimeInterval = 24 * 60 * 60

    /// True for the legacy "swiftcode-cloud" ID and every per-model
    /// "swiftcode-cloud:<name>" ID.
    public static func isCloudModelID(_ id: String) -> Bool {
        id == modelIDPrefix || id.hasPrefix(modelIDPrefix + ":")
    }

    /// "swiftcode-cloud:llama3.1:8b" → "llama3.1:8b". Returns nil for the legacy
    /// ID (caller resolves the default model) and for non-cloud IDs.
    public static func endpointName(forInternalID id: String) -> String? {
        guard isCloudModelID(id), id != modelIDPrefix else { return nil }
        return String(id.dropFirst(modelIDPrefix.count + 1))
    }

    /// "llama3.1:8b" → "swiftcode-cloud:llama3.1:8b".
    public static func internalID(forEndpointName name: String) -> String {
        "\(modelIDPrefix):\(name)"
    }

    /// Full chat URL for the active wire format.
    public static var chatURL: URL? {
        let path: String
        switch wireFormat {
        case .openAICompatible: path = chatCompletionsPath
        case .ollamaNative: path = ollamaChatPath
        }
        return URL(string: baseURLString)?.appendingPathComponent(path)
    }

    /// Full model-list URL for the active wire format.
    public static var modelsListURL: URL? {
        let path: String
        switch wireFormat {
        case .openAICompatible: path = modelsListPath
        case .ollamaNative: path = ollamaTagsPath
        }
        return URL(string: baseURLString)?.appendingPathComponent(path)
    }

    /// True once the base URL is a real HTTPS URL.
    public static var isConfigured: Bool {
        guard !baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: baseURLString),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            return false
        }
        return true
    }

    /// True when the user enabled the toggle AND selected any cloud model.
    /// Reads the UI-facing settings only — the fingerprint itself is never consulted here.
    public static var isEnabledAndSelected: Bool {
        AppSettings.shared.useSwiftCodeCloudModel
            && isCloudModelID(AppSettings.shared.selectedAssistModelID)
    }

    // MARK: Request building
    //
    // Both wire formats POST { "model": "<name>", "messages": [...], "stream": false }.
    // If the endpoint expects a different shape, change ONLY this function
    // (and parseResponse below) — callers stay untouched.

    public static func makeRequest(
        prompt: String,
        history: [(role: String, content: String)],
        fingerprint: String,
        modelIdentifier: String
    ) throws -> URLRequest {
        guard isConfigured, let url = chatURL else {
            throw SCCloudError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(fingerprint, forHTTPHeaderField: fingerprintHeaderName)
        request.timeoutInterval = 120

        var messages: [[String: String]] = history.map { ["role": $0.role, "content": $0.content] }
        messages.append(["role": "user", "content": prompt])

        let body: [String: Any] = [
            "model": modelIdentifier,
            "messages": messages,
            "stream": false,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return request
    }

    // MARK: Response parsing
    //
    // Accepts, in order:
    //   1. OpenAI-style `choices[0].message.content`
    //   2. Ollama-style `message.content` (native /api/chat, non-streaming)
    //   3. Common single-string shapes ("response", "output", "text", …)
    //   4. A bare non-empty string body.
    // Adjust here if the endpoint returns something else.

    public static func parseResponse(_ data: Data) throws -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let choices = json["choices"] as? [[String: Any]],
               let first = choices.first,
               let message = first["message"] as? [String: Any],
               let content = message["content"] as? String,
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return content
            }
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? String,
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return content
            }
            for key in ["response", "output", "text", "content", "result", "answer"] {
                if let text = json[key] as? String,
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                }
            }
            throw SCCloudError.invalidResponse
        }
        if let text = String(data: data, encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        throw SCCloudError.invalidResponse
    }
}

// MARK: - Discovered model

/// One model served by the cloud endpoint, as reported by the server's
/// model-list endpoint. `endpointName` is the exact name to send in the
/// "model" field of chat requests.
public struct SCCloudModelInfo: Codable, Sendable, Hashable {
    public let endpointName: String
    public let ownedBy: String?
    public let contextWindow: Int?

    public init(endpointName: String, ownedBy: String? = nil, contextWindow: Int? = nil) {
        self.endpointName = endpointName
        self.ownedBy = ownedBy
        self.contextWindow = contextWindow
    }

    /// Stable internal ID used by the picker, router, and settings.
    public var internalID: String {
        SCCloudConfiguration.internalID(forEndpointName: endpointName)
    }

    /// Human-readable name. The endpoint name is shown verbatim so the user
    /// always knows exactly which server-side model is selected.
    public var displayName: String { endpointName }
}

// MARK: - Model discovery
//
// Queries the server for the models it actually serves instead of hardcoding
// a single model name. Results are cached in memory and persisted to disk
// (Application Support) with a 1-hour TTL. A failed refresh never wipes the
// previous list — the last known models stay selectable.

public final class SCCloudModelDiscovery: @unchecked Sendable {
    public static let shared = SCCloudModelDiscovery()

    /// How long a fetched model list is considered fresh.
    public static let cacheTTL: TimeInterval = 60 * 60

    private let lock = NSLock()
    private var cachedModels: [SCCloudModelInfo]?
    private var cachedUpdatedAt: Date?

    private init() {}

    /// Best-known model list: memory cache, else the persisted snapshot, else empty.
    public var models: [SCCloudModelInfo] {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cachedModels { return cached }
        let (persisted, updatedAt) = loadPersistedLocked()
        cachedModels = persisted
        cachedUpdatedAt = updatedAt
        return persisted
    }

    /// When the current list was fetched, or nil if never fetched.
    public var lastUpdated: Date? {
        lock.lock()
        defer { lock.unlock() }
        if cachedUpdatedAt != nil { return cachedUpdatedAt }
        let (_, updatedAt) = loadPersistedLocked()
        cachedUpdatedAt = updatedAt
        return updatedAt
    }

    /// True when there is no usable cached list or the cache is older than the TTL.
    public var isStale: Bool {
        guard let updatedAt = lastUpdated else { return true }
        return Date().timeIntervalSince(updatedAt) > Self.cacheTTL
    }

    /// Refreshes from the server when the cache is stale (or `force` is set).
    /// Returns the best-known list — freshly fetched, or the previous cache
    /// when the server is unreachable.
    @discardableResult
    public func refreshIfStale(force: Bool = false) async -> [SCCloudModelInfo] {
        if !force, !isStale { return models }
        return await refresh()
    }

    /// Fetches the model list from the server now. Never throws: on failure the
    /// previous cache is kept and returned.
    @discardableResult
    public func refresh() async -> [SCCloudModelInfo] {
        do {
            let fetched = try await fetchFromServer()
            if fetched.isEmpty {
                logger.warning("[SCCloud] Model discovery returned an empty list — keeping previous cache.")
                return models
            }
            let unique = Array(Dictionary(grouping: fetched, by: { $0.endpointName }).values.compactMap { $0.first })
                .sorted { $0.endpointName.localizedCaseInsensitiveCompare($1.endpointName) == .orderedAscending }
            lock.lock()
            cachedModels = unique
            cachedUpdatedAt = Date()
            lock.unlock()
            persistLocked(models: unique, updatedAt: Date())
            logger.info("[SCCloud] Discovered \(unique.count) cloud models.")
            return unique
        } catch {
            logger.warning("[SCCloud] Model discovery failed: \(error.localizedDescription, privacy: .public) — keeping previous cache.")
            return models
        }
    }

    // MARK: Network

    private func fetchFromServer() async throws -> [SCCloudModelInfo] {
        guard SCCloudConfiguration.isConfigured,
              let url = SCCloudConfiguration.modelsListURL else {
            throw SCCloudError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Identify the device for backend metering; discovery is NOT counted
        // against the daily chat quota.
        if let fingerprint = SCCloudDeviceFingerprint.current, !fingerprint.isEmpty {
            request.setValue(fingerprint, forHTTPHeaderField: SCCloudConfiguration.fingerprintHeaderName)
        }
        request.timeoutInterval = 30

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: config)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw SCCloudError.server(statusCode: code, message: "Model list request failed.")
        }

        switch SCCloudConfiguration.wireFormat {
        case .openAICompatible:
            return parseOpenAIModels(data)
        case .ollamaNative:
            return parseOllamaTags(data)
        }
    }

    /// OpenAI-style: { "data": [ { "id": "…", "owned_by": "…" } ] }
    private func parseOpenAIModels(_ data: Data) -> [SCCloudModelInfo] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else {
            return []
        }
        return items.compactMap { item in
            guard let id = item["id"] as? String,
                  !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let ownedBy = item["owned_by"] as? String
            return SCCloudModelInfo(endpointName: id, ownedBy: ownedBy)
        }
    }

    /// Ollama-style: { "models": [ { "name": "…", "details": { … } } ] }
    private func parseOllamaTags(_ data: Data) -> [SCCloudModelInfo] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["models"] as? [[String: Any]] else {
            return []
        }
        return items.compactMap { item in
            guard let name = (item["name"] as? String) ?? (item["model"] as? String),
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return SCCloudModelInfo(endpointName: name)
        }
    }

    // MARK: Persistence

    private struct Snapshot: Codable {
        let updatedAt: Double
        let models: [SCCloudModelInfo]
    }

    private var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("com.swiftcode.app", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sccloud-models.json")
    }

    private func persistLocked(models: [SCCloudModelInfo], updatedAt: Date) {
        let snapshot = Snapshot(updatedAt: updatedAt.timeIntervalSince1970, models: models)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    private func loadPersistedLocked() -> (models: [SCCloudModelInfo], updatedAt: Date?) {
        guard let data = try? Data(contentsOf: storeURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return ([], nil)
        }
        return (snapshot.models, Date(timeIntervalSince1970: snapshot.updatedAt))
    }
}

// MARK: - Device fingerprint
//
// Per-device rate-limit identity: "ssc_" + hex(SHA-256(stable hardware details)).
// Sources: host UUID, hardware model, CPU brand/count, non-loopback IP addresses.
// The raw hardware values are hashed in memory and never persisted — only the
// final "ssc_…" identifier is stored, in the Keychain.
//
// INTERNAL: this identifier must NEVER be exposed to the UI. It exists solely
// so the rate limiter (and the backend, via the request header) can tell
// devices apart for fair-use enforcement.

enum SCCloudDeviceFingerprint {
    private static let keychainKey = "com.swiftcode.sccloud.deviceFingerprint"
    private static let prefix = "ssc_"

    /// The stored fingerprint, or nil if the user never enabled the cloud model.
    static var current: String? {
        KeychainService.shared.get(forKey: keychainKey)
    }

    /// Returns the fingerprint, generating and securely storing one on first use.
    /// Called when the user flips the "Use SwiftCode's Cloud Model" toggle on.
    @discardableResult
    static func ensureFingerprint() -> String? {
        if let existing = current, !existing.isEmpty {
            return existing
        }
        let generated = generate()
        KeychainService.shared.set(generated, forKey: keychainKey)
        let stored = KeychainService.shared.get(forKey: keychainKey)
        logger.info("[SCCloud] Device fingerprint provisioned.")
        return stored ?? generated
    }

    /// One-way fingerprint: "ssc_" + SHA-256 hex of the hardware material.
    private static func generate() -> String {
        var components: [String] = []

        // Stable host UUID for this machine.
        var hostUUID: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        if gethostuuid(&hostUUID, nil) == 0 {
            let hex = withUnsafeBytes(of: hostUUID) { bytes in
                bytes.map { String(format: "%02x", $0) }.joined()
            }
            components.append("hostuuid=\(hex)")
        }

        // Hardware model (e.g. "Mac14,2"), CPU brand and core count.
        if let hwModel = sysctlString("hw.model") {
            components.append("hw.model=\(hwModel)")
        }
        if let cpuBrand = sysctlString("machdep.cpu.brand_string") {
            components.append("cpu=\(cpuBrand)")
        }
        var ncpu: Int32 = 0
        var ncpuSize = MemoryLayout<Int32>.size
        if sysctlbyname("hw.ncpu", &ncpu, &ncpuSize, nil, 0) == 0 {
            components.append("ncpu=\(ncpu)")
        }

        // Non-loopback IP addresses (best effort; hardware IDs dominate).
        for ip in ipAddresses() {
            components.append("ip=\(ip)")
        }

        let material = components.joined(separator: "|")
        let digest = SHA256.hash(data: Data(material.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return prefix + hex
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let value = String(cString: buffer).trimmingCharacters(in: .controlCharacters)
        return value.isEmpty ? nil : value
    }

    private static func ipAddresses() -> [String] {
        var result: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return result }
        defer { freeifaddrs(ifaddr) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            cursor = current.pointee.ifa_next
            let flags = Int32(current.pointee.ifa_flags)
            guard (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let addr = current.pointee.ifa_addr else { continue }
            let family = addr.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let addrLen: socklen_t = family == UInt8(AF_INET)
                ? socklen_t(MemoryLayout<sockaddr_in>.size)
                : socklen_t(MemoryLayout<sockaddr_in6>.size)
            if getnameinfo(addr, addrLen, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: host)
                // Skip link-local; they add churn without identifying value.
                if !ip.hasPrefix("fe80") && !ip.hasPrefix("169.254") {
                    result.append(ip)
                }
            }
        }
        return Array(Set(result)).sorted()
    }
}

// MARK: - Rate limiter
//
// Sliding 24-hour window, 10 requests max. Request timestamps persist in
// Application Support so the quota survives app restarts. Once the limit is
// hit the device stays locked out until 24h after its oldest request inside
// the window — i.e. quota frees up gradually as old requests age out.

public final class SCCloudRateLimiter: @unchecked Sendable {
    public static let shared = SCCloudRateLimiter()

    private let lock = NSLock()
    private var cachedTimestamps: [Date]?

    private init() {}

    public struct Gate: Sendable {
        public let allowed: Bool
        public let remaining: Int
        public let retryAfter: TimeInterval?
    }

    private var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("com.swiftcode.app", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sccloud-usage.json")
    }

    /// Evaluates the gate WITHOUT consuming quota.
    public func checkGate() -> Gate {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        let stamps = loadLocked().filter { now.timeIntervalSince($0) < SCCloudConfiguration.rateLimitWindow }
        saveLocked(stamps)

        let remaining = max(0, SCCloudConfiguration.dailyRequestLimit - stamps.count)
        if stamps.count >= SCCloudConfiguration.dailyRequestLimit,
           let oldest = stamps.min() {
            let retryAfter = max(0, SCCloudConfiguration.rateLimitWindow - now.timeIntervalSince(oldest))
            return Gate(allowed: false, remaining: 0, retryAfter: retryAfter)
        }
        return Gate(allowed: true, remaining: remaining, retryAfter: nil)
    }

    /// Records one completed request against the quota.
    public func recordRequest() {
        lock.lock()
        defer { lock.unlock() }
        var stamps = loadLocked()
        stamps.append(Date())
        // Bound storage growth: keep at most a few windows' worth.
        let cutoff = Date().addingTimeInterval(-SCCloudConfiguration.rateLimitWindow * 2)
        stamps = stamps.filter { $0 > cutoff }
        saveLocked(stamps)
    }

    /// UI-safe quota summary: counts only. The device fingerprint is never exposed.
    public var remainingToday: Int {
        checkGate().remaining
    }

    /// Human-readable lockout ("7h 12m"), or nil when requests are still allowed.
    public var lockoutDescription: String? {
        let gate = checkGate()
        guard !gate.allowed, let retryAfter = gate.retryAfter else { return nil }
        return Self.formatDuration(retryAfter)
    }

    public static func formatDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(1, Int((interval / 60).rounded(.up)))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    // MARK: Persistence

    private func loadLocked() -> [Date] {
        if let cached = cachedTimestamps { return cached }
        guard let data = try? Data(contentsOf: storeURL),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [Double] else {
            cachedTimestamps = []
            return []
        }
        let stamps = raw.map { Date(timeIntervalSince1970: $0) }
        cachedTimestamps = stamps
        return stamps
    }

    private func saveLocked(_ stamps: [Date]) {
        cachedTimestamps = stamps
        let raw = stamps.map { $0.timeIntervalSince1970 }
        if let data = try? JSONSerialization.data(withJSONObject: raw, options: []) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }
}

// MARK: - Errors

public enum SCCloudError: LocalizedError, Sendable {
    case notConfigured
    case fingerprintUnavailable
    case rateLimited(retryAfter: TimeInterval?)
    case network(underlying: Error)
    case server(statusCode: Int, message: String)
    case invalidResponse
    case noModelAvailable

    /// Message safe to show in the chat UI.
    public var userFacingMessage: String {
        switch self {
        case .notConfigured:
            return "The SwiftCode Cloud endpoint isn't configured yet. The developer needs to set the endpoint details in SCCloudModel.swift."
        case .fingerprintUnavailable:
            return "SwiftCode couldn't establish this device's identity for fair-use metering. Try toggling the cloud model off and on again in Assist settings."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Daily limit reached — the SwiftCode Cloud Model allows \(SCCloudConfiguration.dailyRequestLimit) requests per day per device for fair use. Try again in \(SCCloudRateLimiter.formatDuration(retryAfter))."
            }
            return "Daily limit reached — the SwiftCode Cloud Model allows \(SCCloudConfiguration.dailyRequestLimit) requests per day per device for fair use. Try again in 24 hours."
        case .network(let underlying):
            return "Couldn't reach the SwiftCode Cloud endpoint: \(underlying.localizedDescription)"
        case .server(let statusCode, let message):
            return "SwiftCode Cloud returned an error (HTTP \(statusCode)): \(message)"
        case .invalidResponse:
            return "The SwiftCode Cloud endpoint returned a response SwiftCode couldn't understand."
        case .noModelAvailable:
            return "SwiftCode couldn't find any models on the cloud server. Open Assist settings and tap Refresh Models, then try again."
        }
    }

    public var errorDescription: String? { userFacingMessage }
}

// MARK: - Client
//
// Sends a prompt to the cloud endpoint using the SELECTED discovered model —
// never a hardcoded single model. Every request carries the device fingerprint
// header so the backend can enforce the same 10/day fair-use policy server-side.

public final class SCCloudModelClient: Sendable {
    public static let shared = SCCloudModelClient()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 180
        self.session = URLSession(configuration: config)
    }

    /// Completes a prompt against the SwiftCode Cloud endpoint.
    /// - Parameters:
    ///   - modelIdentifier: exact server-side model name. When nil, it is
    ///     resolved from the user's selected cloud model (or the first
    ///     discovered model for the legacy single-model selection).
    /// - Throws: `SCCloudError` (rate-limited, not configured, network/server failures).
    public func complete(
        prompt: String,
        history: [(role: String, content: String)] = [],
        systemPrompt: String? = nil,
        modelIdentifier: String? = nil
    ) async throws -> String {
        guard SCCloudConfiguration.isConfigured else {
            throw SCCloudError.notConfigured
        }
        guard let fingerprint = SCCloudDeviceFingerprint.ensureFingerprint(), !fingerprint.isEmpty else {
            throw SCCloudError.fingerprintUnavailable
        }

        let gate = SCCloudRateLimiter.shared.checkGate()
        guard gate.allowed else {
            logger.warning("[SCCloud] Rate limit hit — request blocked locally.")
            throw SCCloudError.rateLimited(retryAfter: gate.retryAfter)
        }

        // Model discovery is a metadata refresh, never a gate: use a fresh list
        // when the cache is stale, but proceed with the previous cache when the
        // server is unreachable.
        await SCCloudModelDiscovery.shared.refreshIfStale()
        let resolvedModel = try resolveModelIdentifier(explicit: modelIdentifier)

        var fullHistory = history
        if let systemPrompt, !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fullHistory.insert((role: "system", content: systemPrompt), at: 0)
        }

        let request = try SCCloudConfiguration.makeRequest(
            prompt: prompt,
            history: fullHistory,
            fingerprint: fingerprint,
            modelIdentifier: resolvedModel
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SCCloudError.network(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SCCloudError.invalidResponse
        }

        // Any completed HTTP round-trip counts against the daily quota,
        // success or failure — the request reached the backend.
        SCCloudRateLimiter.shared.recordRequest()

        switch http.statusCode {
        case 200..<300:
            return try SCCloudConfiguration.parseResponse(data)
        case 429:
            logger.warning("[SCCloud] Backend reported 429 — treating as rate limited.")
            throw SCCloudError.rateLimited(retryAfter: nil)
        default:
            let message: String
            if let text = String(data: data, encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                message = String(text.prefix(300))
            } else {
                message = "No response body."
            }
            throw SCCloudError.server(statusCode: http.statusCode, message: message)
        }
    }

    /// Resolves the exact server-side model name for a chat request.
    private func resolveModelIdentifier(explicit: String?) throws -> String {
        if let explicit, !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicit
        }
        let selectedID = AppSettings.shared.selectedAssistModelID
        if let endpointName = SCCloudConfiguration.endpointName(forInternalID: selectedID) {
            return endpointName
        }
        // Legacy single-model selection (or nothing selected): use the first
        // discovered model, else the configured fallback.
        if let first = SCCloudModelDiscovery.shared.models.first {
            logger.info("[SCCloud] Legacy cloud selection — using first discovered model: \(first.endpointName, privacy: .public)")
            return first.endpointName
        }
        let fallback = SCCloudConfiguration.defaultModelIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallback.isEmpty {
            return fallback
        }
        throw SCCloudError.noModelAvailable
    }

    // MARK: UI-safe quota accessors (counts only — never the fingerprint)

    public var remainingRequestsToday: Int {
        SCCloudRateLimiter.shared.remainingToday
    }

    public var dailyRequestLimit: Int {
        SCCloudConfiguration.dailyRequestLimit
    }

    public var lockoutDescription: String? {
        SCCloudRateLimiter.shared.lockoutDescription
    }
}
