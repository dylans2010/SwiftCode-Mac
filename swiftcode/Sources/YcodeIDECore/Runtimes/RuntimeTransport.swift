import Foundation

public enum RuntimeDownloadError: Error, Equatable, Sendable, CustomStringConvertible {
    case badIndex(String)
    case noRuntime(String)
    case needsSignIn(String)
    case network(String)
    case refused(String)
    case noAsset(String)
    case untrusted(String)
    case sizeMismatch(expected: Int64, actual: Int64)
    case verificationFailed(String)
    case notEnoughSpace(String)
    case decryptor(String)
    case expansion(String)
    case image(String)
    case install(String)
    case cancelled
    case tool(String)

    public var description: String {
        switch self {
        case .badIndex(let s): "Apple's runtime index could not be read: \(s)."
        case .noRuntime(let s): s
        case .needsSignIn(let s): "\(s) is only offered behind an Apple developer sign-in, which SwiftCode does not automate. Use Xcode on a Mac, or a runtime you have."
        case .network(let s): s
        case .refused(let s): "Apple's asset service did not answer this computer: \(s). Get the runtime with Xcode on a Mac instead (xcodebuild -downloadPlatform with -exportPath), then add it here."
        case .noAsset(let s): "Apple's asset service has no download for \(s)."
        case .untrusted(let s): "The asset service's answer could not be trusted: \(s)."
        case .sizeMismatch(let e, let a): "The download is \(a) bytes; Apple said \(e). It was removed; download it again."
        case .verificationFailed(let s): "The download did not match Apple's checksum (\(s)). It was removed; download it again."
        case .notEnoughSpace(let s): s
        case .decryptor(let s): s
        case .expansion(let s): "The archive could not be unpacked: \(s)."
        case .image(let s): "The runtime disk image could not be read: \(s)."
        case .install(let s): "The runtime could not be put in place: \(s)."
        case .cancelled: "Cancelled. What was downloaded is kept; download again to resume."
        case .tool(let s): s
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .noRuntime, .needsSignIn, .refused, .noAsset, .decryptor: false
        default: true
        }
    }
}

public struct RuntimeArchiveKey: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let bytes: [UInt8]

    public init?(base64: String) {
        guard let d = Data(base64Encoded: base64), !d.isEmpty else { return nil }
        bytes = Array(d)
    }

    public init(bytes: [UInt8]) { self.bytes = bytes }

    public var description: String { "<redacted>" }
    public var debugDescription: String { "<redacted>" }
    public var customMirror: Mirror { Mirror(self, children: [:]) }

    var textForms: [String] {
        let b64 = Data(bytes).base64EncodedString()
        let url = b64.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        var forms = [b64, url, hex, hex.uppercased()]
        for f in [b64, url] {
            let bare = f.replacingOccurrences(of: "=", with: "")
            if bare != f { forms.append(bare) }
        }
        if b64.contains("/") { forms.append(b64.replacingOccurrences(of: "/", with: "\\/")) }
        return forms
    }

    var hexForStandardInput: String { bytes.map { String(format: "%02x", $0) }.joined() }
}

public enum RuntimeSecrets {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var keys: [RuntimeArchiveKey] = []

    public static func register(_ k: RuntimeArchiveKey) { lock.withLock { if !keys.contains(k) { keys.append(k) } } }
    public static func forget(_ k: RuntimeArchiveKey) { lock.withLock { keys.removeAll { $0 == k } } }

    public static func scrub(_ text: String, extra: [RuntimeArchiveKey] = []) -> String {
        var out = text
        for k in lock.withLock({ keys }) + extra {
            for form in k.textForms.sorted(by: { $0.count > $1.count }) where !form.isEmpty {
                out = out.replacingOccurrences(of: form, with: "<redacted>")
            }
        }
        out = out.replacingOccurrences(of: #"("?ArchiveDecryptionKey"?\s*[:=]\s*"?)[^",\s<}]+"#, with: "$1<redacted>", options: .regularExpression)
        return out
    }
}

public struct RuntimeHTTPResponse: Sendable {
    public var status: Int
    public var body: Data
    public var etag: String?
    public init(status: Int, body: Data, etag: String? = nil) {
        self.status = status
        self.body = body
        self.etag = etag
    }
}

public final class RuntimeCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var handlers: [UUID: @Sendable () -> Void] = [:]
    public init() {}

    public var isCancelled: Bool { lock.withLock { cancelled } }

    public func cancel() {
        let hs: [@Sendable () -> Void] = lock.withLock {
            cancelled = true
            return Array(handlers.values)
        }
        for h in hs { h() }
    }

    @discardableResult
    func onCancel(_ h: @escaping @Sendable () -> Void) -> UUID {
        let id = UUID()
        let now: Bool = lock.withLock {
            if cancelled { return true }
            handlers[id] = h
            return false
        }
        if now { h() }
        return id
    }

    func remove(_ id: UUID) { _ = lock.withLock { handlers.removeValue(forKey: id) } }

    func check() throws { if isCancelled { throw RuntimeDownloadError.cancelled } }
}

public protocol RuntimeTransport: Sendable {
    func get(_ url: URL, etag: String?) async throws -> RuntimeHTTPResponse
    func post(_ url: URL, json: Data, headers: [String: String], caFile: String?) async throws -> RuntimeHTTPResponse
    func download(_ url: URL, to file: String, from offset: Int64, cancel: RuntimeCancellation) async throws
}

public struct CurlTransport: RuntimeTransport {
    public var curl: String
    public var userAgent: String

    public init(curl: String = CurlTransport.defaultPath, userAgent: String = RuntimeHostDescription.current().userAgent) {
        self.curl = curl
        self.userAgent = userAgent
    }

    public static var defaultPath: String {
        if let c = ProcessInfo.processInfo.environment["SWIFTCODE_CURL"], !c.isEmpty { return c }
        return FileManager.default.isExecutableFile(atPath: "/usr/bin/curl") ? "/usr/bin/curl" : "curl"
    }

    func tempFile(_ name: String) -> String {
        NSTemporaryDirectory() + "swiftcode-\(name)-\(UUID().uuidString)"
    }

    public func get(_ url: URL, etag: String?) async throws -> RuntimeHTTPResponse {
        let headers = tempFile("h"), body = tempFile("b")
        defer { try? FileManager.default.removeItem(atPath: headers); try? FileManager.default.removeItem(atPath: body) }
        var args = [curl, "-sS", "-L", "--max-time", "120", "-A", userAgent, "-D", headers, "-o", body, "-w", "%{http_code}"]
        if let etag { args += ["-H", "If-None-Match: \(etag)"] }
        args.append(url.absoluteString)
        let p = SetupProcess(args)
        let status = await p.run()
        guard status == 0, let code = Int(p.text.trimmed.suffix(3)) else {
            throw RuntimeDownloadError.network("Could not reach \(url.host ?? "the server"): \(RuntimeSecrets.scrub(p.text.trimmed)) (curl \(status)).")
        }
        let head = (try? String(contentsOfFile: headers, encoding: .utf8)) ?? ""
        return RuntimeHTTPResponse(status: code, body: FileManager.default.contents(atPath: body) ?? Data(), etag: Self.header("etag", in: head))
    }

    public func post(_ url: URL, json: Data, headers h: [String: String], caFile: String?) async throws -> RuntimeHTTPResponse {
        let body = tempFile("b")
        defer { try? FileManager.default.removeItem(atPath: body) }
        var args = [curl, "-sS", "--max-time", "60", "-A", userAgent, "-X", "POST", "-H", "Content-Type: application/json", "--data-binary", "@-",
                    "-o", body, "-w", "%{http_code}"]
        for (k, v) in h.sorted(by: { $0.key < $1.key }) { args += ["-H", "\(k): \(v)"] }
        if let caFile { args += ["--cacert", caFile] }
        args.append(url.absoluteString)
        let p = SetupProcess(args, stdin: String(decoding: json, as: UTF8.self))
        let status = await p.run()
        guard status == 0, let code = Int(p.text.trimmed.suffix(3)) else {
            if status == 60 || status == 35 {
                throw RuntimeDownloadError.untrusted("\(url.host ?? "the server") did not present a certificate from Apple's root (curl \(status))")
            }
            throw RuntimeDownloadError.network("Could not reach \(url.host ?? "the server"): \(RuntimeSecrets.scrub(p.text.trimmed)) (curl \(status)).")
        }
        return RuntimeHTTPResponse(status: code, body: FileManager.default.contents(atPath: body) ?? Data())
    }

    public func download(_ url: URL, to file: String, from offset: Int64, cancel: RuntimeCancellation) async throws {
        try cancel.check()
        if offset == 0 { FileManager.default.createFile(atPath: file, contents: nil) }
        let args = [curl, "-sS", "-f", "-L", "-A", userAgent, "--retry", "2", "--speed-limit", "1024", "--speed-time", "60",
                    "-C", String(offset), "-o", file, url.absoluteString]
        let p = SetupProcess(args)
        let token = cancel.onCancel { p.terminate() }
        defer { cancel.remove(token) }
        let status = await p.run()
        try cancel.check()
        guard status == 0 else {
            if status == 33 { throw RuntimeDownloadError.network("The server would not resume the download (no byte ranges).") }
            throw RuntimeDownloadError.network("The download from \(url.host ?? "the server") stopped: \(RuntimeSecrets.scrub(p.text.trimmed)) (curl \(status)). Download again to resume.")
        }
    }

    static func header(_ name: String, in dump: String) -> String? {
        var found: String?
        for line in dump.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].lowercased() == name else { continue }
            found = parts[1].trimmingCharacters(in: .whitespaces)
        }
        return found
    }
}
