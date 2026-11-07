import Crypto
import Foundation

public struct SigningIdentity: @unchecked Sendable {
    public let privateKey: P256.Signing.PrivateKey
    public let certificates: [Certificate]

    public var certificate: Certificate { certificates[0] }

    public init(privateKey: P256.Signing.PrivateKey, certificates: [Certificate]) {
        precondition(!certificates.isEmpty)
        self.privateKey = privateKey
        self.certificates = certificates
    }

    public static func generate(
        subject: DistinguishedName = .storeKitTesting, now: Date, validityYears: Int = 1, notAfter: Date? = nil,
        issuer: SigningIdentity? = nil, isCA: Bool = false
    ) throws -> SigningIdentity {
        let key = P256.Signing.PrivateKey()
        let start = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let end = notAfter ?? cal.date(byAdding: .year, value: validityYears, to: start)!
        let signer: Certificate.Signer = issuer.map { .issuer($0.certificate, $0.privateKey) } ?? .selfSigned(key)
        let cert = try Certificate.make(
            subject: subject, publicKey: key.publicKey, notBefore: start, notAfter: end, isCA: isCA, signer: signer)
        let chain = [cert] + (issuer.map { [$0.certificate] } ?? [])
        return SigningIdentity(privateKey: key, certificates: chain)
    }

    public static func deviceJWSIdentity(directory: URL?, now: Date) throws -> SigningIdentity {
        try loadOrCreate(directory: directory, name: "jws", now: now) {
            try generate(subject: .storeKitTesting, now: now)
        }
    }

    public static func deviceReceiptIdentity(directory: URL?, now: Date) throws -> SigningIdentity {
        try loadOrCreate(directory: directory, name: "receipt", now: now) {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC")!
            let start = cal.date(from: DateComponents(year: 2020, month: 4, day: 1))!
            let end = cal.date(from: DateComponents(year: 2040, month: 3, day: 27))!
            return try generate(subject: .receiptSigner, now: start, notAfter: end)
        }
    }

    static func loadOrCreate(directory: URL?, name: String, now: Date, make: () throws -> SigningIdentity) throws -> SigningIdentity {
        guard let directory else { return try make() }
        let certURL = directory.appendingPathComponent("\(name)-certificate.der")
        let keyURL = directory.appendingPathComponent("\(name)-key.raw")
        if let certData = try? Data(contentsOf: certURL), let keyData = try? Data(contentsOf: keyURL),
           let key = try? P256.Signing.PrivateKey(rawRepresentation: keyData), let cert = try? Certificate(der: certData),
           cert.publicKeyDER == Array(key.publicKey.derRepresentation) {
            return SigningIdentity(privateKey: key, certificates: [cert])
        }
        let identity = try make()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(identity.certificate.der).write(to: certURL, options: .atomic)
        try identity.privateKey.rawRepresentation.write(to: keyURL, options: .atomic)
        return identity
    }
}
