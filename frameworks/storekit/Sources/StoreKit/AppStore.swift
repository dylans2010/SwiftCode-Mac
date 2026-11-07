import Foundation
import StoreKitConfiguration
import StoreKitEngine
import StoreKitSigning

public enum AppStore {
    public static var canMakePayments: Bool { true }

    public static var deviceVerificationID: UUID? { SwiftCodeStoreKit.shared.vendorID }

    public static func sync() async throws {
        do { try SwiftCodeStoreKit.shared.store.sync() } catch { throw StoreKitError(error.kind) }
    }

    public struct Environment: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let production = Environment(rawValue: "Production")
        public static let sandbox = Environment(rawValue: "Sandbox")
        public static let xcode = Environment(rawValue: "Xcode")
    }

    public struct Platform: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let iOS = Platform(rawValue: "iOS")
        public static let macOS = Platform(rawValue: "macOS")
        public static let tvOS = Platform(rawValue: "tvOS")
        public static let visionOS = Platform(rawValue: "visionOS")
    }
}

public struct AppTransaction: Hashable, Sendable, SwiftCodeSignedValue {
    let jws: String
    let payload: JSONValue

    public var swiftcodeJWS: String { jws }

    init(jws: String, payload: JSONValue) {
        self.jws = jws
        self.payload = payload
    }

    private func string(_ k: String) -> String? { payload[k]?.stringValue }
    private func date(_ k: String) -> Date? { payload[k]?.numberValue?.intValue.map { Date(storeMilliseconds: StoreMilliseconds($0)) } }

    public var jsonRepresentation: Data { (try? JWS.decode(jws).payloadData) ?? Data() }
    public var bundleID: String { string("bundleId") ?? "" }
    public var appVersion: String { string("applicationVersion") ?? "" }
    public var originalAppVersion: String { string("originalApplicationVersion") ?? "" }
    public var originalPurchaseDate: Date { date("originalPurchaseDate") ?? Date(timeIntervalSince1970: 0) }
    public var environment: AppStore.Environment { AppStore.Environment(rawValue: string("receiptType") ?? "") }
    public var originalPlatform: AppStore.Platform { AppStore.Platform(rawValue: string("originalPlatform") ?? "") }
    public var originalPlatformStringRepresentation: String { string("originalPlatform") ?? "" }
    public var appTransactionID: String { string("appTransactionId") ?? "" }
    public var appID: UInt64? { nil }
    public var appVersionID: UInt64? { nil }
    public var signedDate: Date { date("receiptCreationDate") ?? .distantPast }
    public var deviceVerification: Data { string("deviceVerification").flatMap { Data(base64Encoded: $0) } ?? Data() }
    public var deviceVerificationNonce: UUID { string("deviceVerificationNonce").flatMap(UUID.init(uuidString:)) ?? UUID() }

    public static var shared: VerificationResult<AppTransaction> {
        get async throws {
            let rt = SwiftCodeStoreKit.shared
            do { try rt.store.checkAppTransaction() } catch { throw StoreKitError(error.kind) }
            let jws = try rt.signer.signAppTransaction(applicationVersion: rt.applicationVersion, at: rt.now)
            return rt.verify(jws, simulated: rt.store.simulatedError(for: .verification), make: AppTransaction.init(jws:payload:))
        }
    }

    public static func refresh() async throws -> VerificationResult<AppTransaction> { try await shared }

    public static func == (a: AppTransaction, b: AppTransaction) -> Bool { a.jws == b.jws }
    public func hash(into h: inout Hasher) { h.combine(jws) }
}

public struct Storefront: Identifiable, Hashable, Sendable {
    public typealias ID = String
    public let countryCode: String
    public let id: String
    public let currencyCode: String?

    public static var current: Storefront? {
        get async {
            let s = SwiftCodeStoreKit.shared.store.settings.storefront
            return Storefront(countryCode: s.countryCode, id: s.id, currencyCode: s.currency)
        }
    }
}

extension Transaction {
    public func swiftcodeRequestRefund(developerIssue: Bool = false) async throws -> RefundRequestStatus {
        let rt = SwiftCodeStoreKit.shared
        do { try rt.store.checkSimulatedError(for: .refundRequest) } catch {
            if case .refundRequest(let r)? = error.simulated {
                throw r == .duplicateRequest ? RefundRequestError.duplicateRequest : RefundRequestError.failed
            }
            throw StoreKitError(error.kind)
        }
        do { try rt.store.refundTransaction(id, reason: developerIssue ? 1 : 0) } catch { throw RefundRequestError.failed }
        return .success
    }
}
