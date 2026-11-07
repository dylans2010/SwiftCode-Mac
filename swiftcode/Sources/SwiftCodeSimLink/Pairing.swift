import Crypto
import Foundation

public enum Pairing {
    public static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    public static let window: TimeInterval = 300

    public static func newCode() -> String {
        var rng = SystemRandomNumberGenerator()
        let chars = (0..<12).map { _ in alphabet[Int(rng.next(upperBound: UInt32(alphabet.count)))] }
        return stride(from: 0, to: 12, by: 4).map { String(chars[$0..<($0 + 4)]) }.joined(separator: "-")
    }

    public static func normalize(_ code: String) -> String {
        String(code.uppercased().compactMap { c -> Character? in
            switch c {
            case "-", " ": return nil
            case "O": return "0"
            case "I", "L": return "1"
            default: return c
            }
        })
    }

    public static func psk(code: String) -> [UInt8] {
        Array(SHA256.hash(data: Array("swiftcode-sim-link pairing code ".utf8) + Array(normalize(code).utf8)))
    }

    struct WindowFile: Codable {
        var psk: String
        var expires: Double
    }

    static func url(_ store: LinkStore) -> URL { store.directory.appendingPathComponent("pairing.json") }

    public static func open(code: String, store: LinkStore, now: Date = Date()) throws {
        _ = try store.identity()
        let w = WindowFile(psk: Data(psk(code: code)).base64EncodedString(), expires: now.timeIntervalSince1970 + window)
        let path = url(store).path
        unlink(path)
        guard FileManager.default.createFile(atPath: path, contents: try JSONEncoder().encode(w), attributes: [.posixPermissions: 0o600]) else {
            throw LinkStoreError.corrupt(path)
        }
    }

    public static func take(store: LinkStore, now: Date = Date()) -> [UInt8]? {
        let path = url(store).path
        guard let d = FileManager.default.contents(atPath: path) else { return nil }
        unlink(path)
        guard let w = try? JSONDecoder().decode(WindowFile.self, from: d), w.expires > now.timeIntervalSince1970,
              let k = Data(base64Encoded: w.psk) else { return nil }
        return Array(k)
    }

    public static func isOpen(store: LinkStore, now: Date = Date()) -> Bool {
        guard let d = FileManager.default.contents(atPath: url(store).path),
              let w = try? JSONDecoder().decode(WindowFile.self, from: d) else { return false }
        return w.expires > now.timeIntervalSince1970
    }

    public static func close(store: LinkStore) { unlink(url(store).path) }
}

public struct PairingFile: Codable, Sendable, Equatable {
    public var name: String
    public var publicKey: String
    public var role: String
    public var address: String?
    public var mediaPort: Int?

    public init(name: String, identity: LinkIdentity, role: String, address: String? = nil, mediaPort: Int? = nil) {
        self.name = name
        publicKey = Data(identity.publicKey).base64EncodedString()
        self.role = role
        self.address = address
        self.mediaPort = mediaPort
    }
}
