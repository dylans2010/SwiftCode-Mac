import Foundation
import StoreKitConfiguration
import StoreKitEngine
import StoreKitSigning

public final class SwiftCodeStoreKit: @unchecked Sendable {
    public let device: StoreDevice
    public let bundleID: String
    public let vendorID: UUID
    public let applicationVersion: String
    public let jwsIdentity: SigningIdentity
    public let receiptIdentity: SigningIdentity
    public let receiptURL: URL?
    public var callbackQueue: DispatchQueue = .main

    public var confirmPurchase: @Sendable (PurchaseConfirmation) async -> Bool = { _ in true }
    public var presentAlert: @Sendable (StoreAlert) async -> Void = { _ in }

    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<VerificationResult<Transaction>>.Continuation] = [:]
    private var observerToken: UUID?
    private var ticker: Task<Void, Never>?
    private var receiptData: Data?
    private var alertLog: [StoreAlert] = []

    public init(
        device: StoreDevice, bundleID: String, vendorID: UUID = UUID(), applicationVersion: String = "1",
        receiptURL: URL? = nil
    ) throws {
        self.device = device
        self.bundleID = bundleID
        self.vendorID = vendorID
        self.applicationVersion = applicationVersion
        self.receiptURL = receiptURL
        let identities = device.directory?.appendingPathComponent("_signing", isDirectory: true)
        let now = device.clock.now()
        jwsIdentity = try SigningIdentity.deviceJWSIdentity(directory: identities, now: now)
        receiptIdentity = try SigningIdentity.deviceReceiptIdentity(directory: identities, now: now)
    }

    private static let sharedLock = NSLock()
    nonisolated(unsafe) private static var current: SwiftCodeStoreKit?

    public static var shared: SwiftCodeStoreKit {
        sharedLock.withLock {
            if let current { return current }
            let made = makeFromEnvironment()
            current = made
            return made
        }
    }

    public static func configure(_ runtime: SwiftCodeStoreKit) {
        sharedLock.withLock {
            current?.stop()
            current = runtime
        }
    }

    static func makeFromEnvironment() -> SwiftCodeStoreKit {
        let env = ProcessInfo.processInfo.environment
        let dir = env["SWIFTCODE_STOREKIT_DIRECTORY"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        let bundleID = env["SWIFTCODE_STOREKIT_BUNDLE_ID"] ?? Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        let version = env["SWIFTCODE_STOREKIT_APP_VERSION"]
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "1"
        var vendor = UUID()
        if let dir {
            let url = dir.appendingPathComponent("_vendor").appendingPathComponent(bundleID)
            if let text = try? String(contentsOf: url, encoding: .utf8), let v = UUID(uuidString: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                vendor = v
            } else {
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? vendor.uuidString.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        let device = StoreDevice(directory: dir)
        let receipt = dir?.appendingPathComponent(bundleID).appendingPathComponent("StoreKit/receipt")
        if let made = try? SwiftCodeStoreKit(device: device, bundleID: bundleID, vendorID: vendor, applicationVersion: version, receiptURL: receipt) {
            return made
        }
        return try! SwiftCodeStoreKit(device: StoreDevice(), bundleID: bundleID, vendorID: vendor, applicationVersion: version)
    }

    public var store: AppTestStore { device.store(for: bundleID) }

    var signer: StoreSigner { StoreSigner(identity: jwsIdentity, bundleID: bundleID, vendorID: vendorID) }

    var now: Date { device.clock.now() }

    public var alerts: [StoreAlert] { lock.withLock { alertLog } }

    func show(_ alert: StoreAlert) async {
        lock.withLock { alertLog.append(alert) }
        await presentAlert(alert)
    }

    func verifier() -> JWSVerifier { JWSVerifier(requiredPayloadKeys: []) }

    func verificationResults(_ records: [TransactionRecord]) -> [VerificationResult<Transaction>] {
        let simulated = store.simulatedError(for: .verification)
        guard let signed = try? signer.sign(records, at: now, simulated: simulated) else { return [] }
        return signed.map { verify($0, simulated: simulated, make: Transaction.init(jws:payload:)) }
    }

    func verificationResult(_ record: TransactionRecord) -> VerificationResult<Transaction>? { verificationResults([record]).first }

    func verify<T>(_ jws: String, simulated: SimulatedFailure?, make: (String, JSONValue) -> T) -> VerificationResult<T> {
        do {
            let d = try verifier().verify(jws)
            let value = make(jws, d.payload)
            if case .verification(let reason)? = simulated,
               [.invalidCertificateChain, .invalidEncoding, .missingRequiredProperties].contains(reason),
               let e = VerificationResult<T>.VerificationError(reason) {
                return .unverified(value, e)
            }
            return .verified(value)
        } catch {
            let payload = (try? JWS.decode(jws).payload) ?? .object([:])
            return .unverified(make(jws, payload), VerificationResult<T>.VerificationError(error.reason) ?? .invalidSignature)
        }
    }

    func updatesStream() -> AsyncStream<VerificationResult<Transaction>> {
        let (stream, continuation) = AsyncStream<VerificationResult<Transaction>>.makeStream()
        let id = UUID()
        let replay = verificationResults(store.unfinishedTransactions().reversed())
        for r in replay { continuation.yield(r) }
        lock.withLock {
            continuations[id] = continuation
            if observerToken == nil {
                observerToken = store.addObserver { [weak self] event in self?.deliver(event) }
            }
            startTickerLocked()
        }
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            self.lock.withLock { self.continuations[id] = nil }
        }
        return stream
    }

    private func deliver(_ event: StoreEvent) {
        guard case .transaction(let record) = event, let result = verificationResult(record) else { return }
        let targets = lock.withLock { Array(continuations.values) }
        for c in targets { c.yield(result) }
    }

    private func startTickerLocked() {
        guard ticker == nil, device.clock is SystemClock else { return }
        let store = self.store
        ticker = Task.detached { [weak self] in
            while !Task.isCancelled, self != nil {
                let wait = store.nextEventDate().map { max(0.05, min(1.0, $0.timeIntervalSinceNow)) } ?? 1.0
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                store.advance()
            }
        }
    }

    func stop() {
        lock.withLock {
            ticker?.cancel()
            ticker = nil
            if let t = observerToken { store.removeObserver(t) }
            observerToken = nil
            for c in continuations.values { c.finish() }
            continuations = [:]
        }
    }

    public var receipt: Data? {
        lock.withLock {
            if let receiptData { return receiptData }
            if let receiptURL { return try? Data(contentsOf: receiptURL) }
            return nil
        }
    }

    @discardableResult
    func writeReceipt() throws -> Data {
        var opaque = [UInt8](repeating: 0, count: 8)
        for i in opaque.indices { opaque[i] = UInt8.random(in: 0...255) }
        let data = try Receipt.build(
            bundleID: bundleID, appVersion: applicationVersion, vendorID: vendorID, opaque: opaque, creationDate: now,
            purchases: store.allTransactions(), identity: receiptIdentity)
        try lock.withLock {
            receiptData = data
            if let receiptURL {
                try FileManager.default.createDirectory(at: receiptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: receiptURL, options: .atomic)
            }
        }
        return data
    }
}

public struct PurchaseConfirmation: Sendable {
    public let product: Product
    public let quantity: Int
    public let buttonTitle: String
    public let environmentNote: String
}

public enum SwiftCodeStoreSystemError: Error, Hashable, Sendable {
    case noAccount
    case unknown
}
