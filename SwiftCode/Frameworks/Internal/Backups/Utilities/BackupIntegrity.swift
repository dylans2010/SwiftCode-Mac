import Foundation
import CryptoKit

public final class BackupIntegrity: Sendable {
    public static let shared = BackupIntegrity()

    private init() {}

    public func generateChecksum(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public func verifyBackup(data: Data, expectedChecksum: String) -> Bool {
        let actual = generateChecksum(for: data)
        return actual.lowercased() == expectedChecksum.lowercased()
    }

    public func repairMetadata(_ metadata: BackupMetadata) -> BackupMetadata {
        return BackupMetadata(
            id: metadata.id,
            name: metadata.name,
            sizeBytes: metadata.sizeBytes,
            createdAt: metadata.createdAt,
            providerType: metadata.providerType,
            deviceName: metadata.deviceName,
            integrityStatus: "verified",
            isEncrypted: metadata.isEncrypted,
            isCompressed: metadata.isCompressed
        )
    }
}
