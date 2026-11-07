import Foundation
import Crypto
#if canImport(Glibc)
import Glibc
#endif
import os

private let logger = Logger(subsystem: "com.swiftcode.Assist", category: "SCCloudModel")

public enum SCCloudConfiguration {

    public static let defaultBaseURLString = "https://gives-appearance-bands-procedure.trycloudflare.com"

    public static func readEndpointFromJSFile() -> String? {
        let fileName = "SCCloudModelsEndpoint.js"
        var candidatePaths: [String] = []

        if let bundlePath = Bundle.main.path(forResource: "SCCloudModelsEndpoint", ofType: "js") {
            candidatePaths.append(bundlePath)
        }
        if let resourceURL = Bundle.main.resourceURL {
            candidatePaths.append(resourceURL.appendingPathComponent(fileName).path)
        }

        let cwd = FileManager.default.currentDirectoryPath
        candidatePaths.append("\(cwd)/\(fileName)")

        let homeDir = NSHomeDirectory()
        candidatePaths.append("\(homeDir)/SwiftCode-Mac/\(fileName)")

        if let execURL = Bundle.main.executableURL {
            var dir = execURL.deletingLastPathComponent()
            for _ in 0..<8 {
                candidatePaths.append(dir.appendingPathComponent(fileName).path)
                let parent = dir.deletingLastPathComponent()
                if parent == dir { break }
                dir = parent
            }
        }

        for path in candidatePaths {
            guard FileManager.default.fileExists(atPath: path),
                  let content = try? String(contentsOfFile: path, encoding: .utf8) else {
                continue
            }
            let regexPatterns = [
                #"endpoint\s*[:=]\s*["']([^"']+)["']"#,
                #"["']endpoint["']\s*:\s*["']([^"']+)["']"#
            ]
            for pattern in regexPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                   let match = regex.firstMatch(in: content, options: [], range: NSRange(location: 0, length: (content as NSString).length)),
                   match.numberOfRanges > 1 {
                    let range = match.range(at: 1)
                    let foundURL = (content as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !foundURL.isEmpty {
                        return foundURL
                    }
                }
            }
        }
        return nil
    }

    public static var baseURLString: String {
        if let custom = UserDefaults.standard.string(forKey: "swiftcode_cloud_endpoint_url")?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return custom
        }
        if let jsEndpoint = readEndpointFromJSFile(), !jsEndpoint.isEmpty {
            return jsEndpoint
        }
        return defaultBaseURLString
    }

    public enum WireFormat: Sendable {
        case openAICompatible
        case ollamaNative
    }
    public static let wireFormat: WireFormat = .openAICompatible

    public static let chatCompletionsPath = "/v1/chat/completions"
    public static let modelsListPath = "/v1/models"
    public static let ollamaChatPath = "/api/chat"
    public static let ollamaTagsPath = "/api/tags"

    public static let defaultModelIdentifier = ""

    public static let modelIDPrefix = "swiftcode-cloud"

    public static let displayName = "SwiftCode Cloud Model"
    public static let providerID = "swiftcode-cloud"
    public static let providerName = "SwiftCode Cloud"

    public static let fingerprintHeaderName = "X-SwiftCode-Device-Fingerprint"

    public static let dailyRequestLimit = 10
    public static let rateLimitWindow: TimeInterval = 24 * 60 * 60

    public static let requestTimeout: TimeInterval = 180
    public static let resourceTimeout: TimeInterval = 300

    public static func isCloudModelID(_ id: String) -> Bool {
        id == modelIDPrefix || id.hasPrefix(modelIDPrefix + ":")
    }

    public static func endpointName(forInternalID id: String) -> String? {
        guard isCloudModelID(id), id != modelIDPrefix else { return nil }
        return canonicalModelName(String(id.dropFirst(modelIDPrefix.count + 1)))
    }

    public static func internalID(forEndpointName name: String) -> String {
        "\(modelIDPrefix):\(name)"
    }

    public static func canonicalModelName(_ discoveredID: String) -> String {
        let trimmed = discoveredID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix(":latest") {
            return String(trimmed.dropLast(":latest".count))
        }
        return trimmed
    }

    public static let modelBlurbs: [String: String] = [
        "swiftcode-cloud": "Custom Swift assistant — Swift/SwiftUI code generation",
        "qwen2.5-coder:1.5b": "Ultra-fast coding — instant inline completions",
        "qwen2.5-coder:7b": "Flagship coding model — deep multi-file refactoring",
        "qwen2.5:3b": "Fast general reasoning and logic",
        "gemini": "Google-based assistant — general chat and code",
        "gemma2:2b": "Google Gemma 2 foundation model",
        "gpt-oss": "Open-weight reasoning and code engine",
        "deepseek-coder:6.7b": "DeepSeek Coder — complex algorithms",
        "phi3:mini": "Microsoft Phi-3 Mini — math and reasoning",
        "starcoder2:3b": "StarCoder 2 — syntax, translation, lint fixes",
        "llama3.2": "Meta Llama 3.2 3B — concise instructions",
        "llama3.2:1b": "Meta Llama 3.2 1B — ultra-lightweight chat",
    ]

    public static func blurb(forEndpointName name: String) -> String? {
        modelBlurbs[name]
    }

    public static var chatURL: URL? {
        let path: String
        switch wireFormat {
        case .openAICompatible: path = chatCompletionsPath
        case .ollamaNative: path = ollamaChatPath
        }
        return URL(string: baseURLString)?.appendingPathComponent(path)
    }

    public static var modelsListURL: URL? {
        let path: String
        switch wireFormat {
        case .openAICompatible: path = modelsListPath
        case .ollamaNative: path = ollamaTagsPath
        }
        return URL(string: baseURLString)?.appendingPathComponent(path)
    }

    public static var isConfigured: Bool {
        guard !baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: baseURLString),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            return false
        }
        return true
    }

    @MainActor
    public static var isEnabledAndSelected: Bool {
        AppSettings.shared.useSwiftCodeCloudModel
            && isCloudModelID(AppSettings.shared.selectedAssistModelID)
    }

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
        request.timeoutInterval = SCCloudConfiguration.requestTimeout

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

public struct SCCloudModelInfo: Codable, Sendable, Hashable {
    public let endpointName: String
    public let ownedBy: String?
    public let contextWindow: Int?

    public init(endpointName: String, ownedBy: String? = nil, contextWindow: Int? = nil) {
        self.endpointName = endpointName
        self.ownedBy = ownedBy
        self.contextWindow = contextWindow
    }

    public var internalID: String {
        SCCloudConfiguration.internalID(forEndpointName: endpointName)
    }

    public var displayName: String { endpointName }

    public var blurb: String? {
        SCCloudConfiguration.blurb(forEndpointName: endpointName)
    }
}

public final class SCCloudModelDiscovery: @unchecked Sendable {
    public static let shared = SCCloudModelDiscovery()

    public static let cacheTTL: TimeInterval = 60 * 60

    private let lock = NSLock()
    private var cachedModels: [SCCloudModelInfo]?
    private var cachedUpdatedAt: Date?
    private var cachedEndpointURL: String?

    private init() {}

    public var models: [SCCloudModelInfo] {
        lock.lock()
        let currentURL = SCCloudConfiguration.baseURLString
        if let lastURL = cachedEndpointURL, lastURL != currentURL {
            cachedModels = nil
            cachedUpdatedAt = nil
            cachedEndpointURL = currentURL
            lock.unlock()
            Task { await self.refresh() }
            return []
        }
        cachedEndpointURL = currentURL
        if let cached = cachedModels {
            lock.unlock()
            return cached
        }
        let (persisted, updatedAt, savedURL) = loadPersistedLocked()
        if let savedURL = savedURL, savedURL != currentURL {
            cachedModels = nil
            cachedUpdatedAt = nil
            lock.unlock()
            Task { await self.refresh() }
            return []
        }
        cachedModels = persisted
        cachedUpdatedAt = updatedAt
        lock.unlock()
        return persisted
    }

    public var lastUpdated: Date? {
        lock.lock()
        defer { lock.unlock() }
        if cachedUpdatedAt != nil { return cachedUpdatedAt }
        let (_, updatedAt, _) = loadPersistedLocked()
        cachedUpdatedAt = updatedAt
        return updatedAt
    }

    public var isStale: Bool {
        lock.lock()
        let currentURL = SCCloudConfiguration.baseURLString
        let urlChanged = (cachedEndpointURL != nil && cachedEndpointURL != currentURL)
        lock.unlock()
        if urlChanged { return true }
        guard let updatedAt = lastUpdated else { return true }
        return Date().timeIntervalSince(updatedAt) > Self.cacheTTL
    }

    @discardableResult
    public func refreshIfStale(force: Bool = false) async -> [SCCloudModelInfo] {
        if !force, !isStale { return models }
        return await refresh()
    }

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
            let now = Date()
            let currentURL = SCCloudConfiguration.baseURLString
            lock.withLock {
                cachedModels = unique
                cachedUpdatedAt = now
                cachedEndpointURL = currentURL
            }
            persistLocked(models: unique, updatedAt: now, endpointURL: currentURL)
            logger.info("[SCCloud] Discovered \(unique.count) cloud models from \(currentURL, privacy: .public).")
            return unique
        } catch {
            logger.warning("[SCCloud] Model discovery failed: \(error.localizedDescription, privacy: .public) — keeping previous cache.")
            return models
        }
    }

    private func fetchFromServer() async throws -> [SCCloudModelInfo] {
        guard SCCloudConfiguration.isConfigured,
              let url = SCCloudConfiguration.modelsListURL else {
            throw SCCloudError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
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

    private func parseOpenAIModels(_ data: Data) -> [SCCloudModelInfo] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else {
            return []
        }
        return items.compactMap { item in
            guard let rawID = item["id"] as? String else { return nil }
            let id = SCCloudConfiguration.canonicalModelName(rawID)
            guard !id.isEmpty else { return nil }
            let ownedBy = item["owned_by"] as? String
            return SCCloudModelInfo(endpointName: id, ownedBy: ownedBy)
        }
    }

    private func parseOllamaTags(_ data: Data) -> [SCCloudModelInfo] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["models"] as? [[String: Any]] else {
            return []
        }
        return items.compactMap { item in
            guard let rawName = (item["name"] as? String) ?? (item["model"] as? String) else { return nil }
            let name = SCCloudConfiguration.canonicalModelName(rawName)
            guard !name.isEmpty else { return nil }
            var contextWindow: Int? = nil
            if let details = item["details"] as? [String: Any],
               let ctx = details["context_length"] as? Int, ctx > 0 {
                contextWindow = ctx
            }
            return SCCloudModelInfo(endpointName: name, contextWindow: contextWindow)
        }
    }

    private struct Snapshot: Codable {
        let updatedAt: Double
        let models: [SCCloudModelInfo]
        let endpointURL: String?
    }

    private var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("com.swiftcode.app", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sccloud-models.json")
    }

    private func persistLocked(models: [SCCloudModelInfo], updatedAt: Date, endpointURL: String?) {
        let snapshot = Snapshot(updatedAt: updatedAt.timeIntervalSince1970, models: models, endpointURL: endpointURL)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    private func loadPersistedLocked() -> (models: [SCCloudModelInfo], updatedAt: Date?, endpointURL: String?) {
        guard let data = try? Data(contentsOf: storeURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return ([], nil, nil)
        }
        return (snapshot.models, Date(timeIntervalSince1970: snapshot.updatedAt), snapshot.endpointURL)
    }
}

enum SCCloudDeviceFingerprint {
    private static let keychainKey = "com.swiftcode.sccloud.deviceFingerprint"
    private static let prefix = "ssc_"

    static var current: String? {
        KeychainService.shared.get(forKey: keychainKey)
    }

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

    private static func generate() -> String {
        var components: [String] = []

        #if os(macOS)
        var hostUUID: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        if gethostuuid(&hostUUID, nil) == 0 {
            let hex = withUnsafeBytes(of: hostUUID) { bytes in
                bytes.map { String(format: "%02x", $0) }.joined()
            }
            components.append("hostuuid=\(hex)")
        }

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
        #else
        components.append("random=\(UUID().uuidString)")
        #endif

        for ip in ipAddresses() {
            components.append("ip=\(ip)")
        }

        let material = components.joined(separator: "|")
        let digest = SHA256.hash(data: Data(material.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return prefix + hex
    }

    #if os(macOS)
    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let value = String(cString: buffer).trimmingCharacters(in: .controlCharacters)
        return value.isEmpty ? nil : value
    }
    #endif

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
                if !ip.hasPrefix("fe80") && !ip.hasPrefix("169.254") {
                    result.append(ip)
                }
            }
        }
        return Array(Set(result)).sorted()
    }
}

public final class SCCloudRateLimiter: @unchecked Sendable {
    public static let shared = SCCloudRateLimiter()

    public struct Gate: Sendable {
        public let allowed: Bool
        public let remaining: Int
        public let retryAfter: TimeInterval?
    }

    private let lock = NSLock()
    private var cachedTimestamps: [Date]?

    private init() {}

    private var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("com.swiftcode.app", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sccloud-usage.json")
    }

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

    public func recordRequest() {
        lock.lock()
        defer { lock.unlock() }
        var stamps = loadLocked()
        stamps.append(Date())
        let cutoff = Date().addingTimeInterval(-SCCloudConfiguration.rateLimitWindow * 2)
        stamps = stamps.filter { $0 > cutoff }
        saveLocked(stamps)
    }

    public var remainingToday: Int {
        checkGate().remaining
    }

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

public enum SCCloudError: LocalizedError, Sendable {
    case notConfigured
    case fingerprintUnavailable
    case rateLimited(retryAfter: TimeInterval?)
    case network(underlying: Error)
    case server(statusCode: Int, message: String)
    case invalidResponse
    case noModelAvailable

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
            let nsError = underlying as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut {
                return "The request timed out after \(Int(SCCloudConfiguration.requestTimeout))s without a response. The model may still be loading on the server (cold start takes a while on small machines) — try again, or pick a smaller model."
            }
            return "Couldn't reach the SwiftCode Cloud endpoint: \(underlying.localizedDescription)"
        case .server(let statusCode, let message):
            if statusCode == 530 || message.contains("Cloudflare Tunnel error") || message.contains("1033") || message.contains("<!doctype html>") || message.contains("<html") {
                return "The SwiftCode Cloud model server is currently offline or unreachable (Cloudflare Tunnel Error 530/1033). Please try again later or select another model in Assist Settings."
            }
            let preview = message.count > 300 ? String(message.prefix(300)) + "…" : message
            return "SwiftCode Cloud returned an error (HTTP \(statusCode)): \(preview)"
        case .invalidResponse:
            return "The SwiftCode Cloud endpoint returned a response SwiftCode couldn't understand."
        case .noModelAvailable:
            return "SwiftCode couldn't find any models on the cloud server. Open Assist settings and tap Refresh Models, then try again."
        }
    }

    public var errorDescription: String? { userFacingMessage }

    public var httpStatusCode: Int? {
        if case .server(let statusCode, _) = self { return statusCode }
        return nil
    }

    public var rawResponseBody: String? {
        switch self {
        case .server(_, let body): return body
        case .network(let underlying): return underlying.localizedDescription
        default: return nil
        }
    }
}

public final class SCCloudModelClient: Sendable {
    public static let shared = SCCloudModelClient()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = SCCloudConfiguration.requestTimeout
        config.timeoutIntervalForResource = SCCloudConfiguration.resourceTimeout
        self.session = URLSession(configuration: config)
    }

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

        await SCCloudModelDiscovery.shared.refreshIfStale()
        let selectedID = await MainActor.run { AppSettings.shared.selectedAssistModelID }
        let resolvedModel = try resolveModelIdentifier(explicit: modelIdentifier, selectedID: selectedID)

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
                message = String(text.prefix(8000))
            } else {
                message = "No response body."
            }
            throw SCCloudError.server(statusCode: http.statusCode, message: message)
        }
    }

    private func resolveModelIdentifier(explicit: String?, selectedID: String) throws -> String {
        if let explicit, !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicit
        }
        if let endpointName = SCCloudConfiguration.endpointName(forInternalID: selectedID) {
            return endpointName
        }
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
