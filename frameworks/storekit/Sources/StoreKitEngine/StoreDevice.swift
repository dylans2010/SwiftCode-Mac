import Foundation
import StoreKitConfiguration

public struct PromotionalOfferContext: Hashable, Sendable {
    public var bundleID: String
    public var productID: String
    public var appAccountToken: UUID?

    public init(bundleID: String, productID: String, appAccountToken: UUID?) {
        self.bundleID = bundleID
        self.productID = productID
        self.appAccountToken = appAccountToken
    }
}

public typealias PromotionalOfferVerifier = @Sendable (SignedPromotionalOffer, PromotionalOfferContext) -> Bool

public final class StoreDevice: @unchecked Sendable {
    public let clock: any StoreClock
    public let timeZone: TimeZone
    public let directory: URL?
    public let quirks: EngineQuirks

    private let lock = NSLock()
    private var stores: [String: AppTestStore] = [:]
    private var verifier: PromotionalOfferVerifier = { _, _ in false }

    public init(
        clock: any StoreClock = SystemClock(), timeZone: TimeZone = .current, directory: URL? = nil,
        quirks: EngineQuirks = .reference
    ) {
        self.clock = clock
        self.timeZone = timeZone
        self.directory = directory
        self.quirks = quirks
    }

    public var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }

    public var promotionalOfferVerifier: PromotionalOfferVerifier {
        get { lock.withLock { verifier } }
        set { lock.withLock { verifier = newValue } }
    }

    public func store(for bundleID: String) -> AppTestStore {
        lock.withLock {
            if let s = stores[bundleID] { return s }
            let s = AppTestStore(bundleID: bundleID, device: self)
            stores[bundleID] = s
            return s
        }
    }

    func appDirectory(_ bundleID: String) -> URL? {
        guard let directory else { return nil }
        let safe = bundleID.unicodeScalars.map { c -> String in
            let ok = CharacterSet.alphanumerics.contains(c) || c == "." || c == "-" || c == "_"
            return ok && c.isASCII ? String(c) : String(format: "%%%02X", c.value)
        }.joined()
        return directory.appendingPathComponent(safe.isEmpty || safe == "." || safe == ".." ? "_" : safe, isDirectory: true)
    }
}
