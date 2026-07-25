import Foundation
import CryptoKit

public final class BackupEncryption: Sendable {
    public static let shared = BackupEncryption()

    private init() {}

    public func encrypt(data: Data, key: String) throws -> Data {
        let keyData = SHA256.hash(data: Data(key.utf8))
        let symmetricKey = SymmetricKey(data: keyData)
        let sealedBox = try AES.GCM.seal(data, using: symmetricKey)
        guard let combined = sealedBox.combined else {
            throw NSError(domain: "BackupEncryption", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to compile sealed box"])
        }
        return combined
    }

    public func decrypt(data: Data, key: String) throws -> Data {
        let keyData = SHA256.hash(data: Data(key.utf8))
        let symmetricKey = SymmetricKey(data: keyData)
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: symmetricKey)
    }
}
