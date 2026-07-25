import Foundation

public final class BackupCompression: Sendable {
    public static let shared = BackupCompression()

    private init() {}

    public func compress(data: Data) throws -> Data {
        let nsData = data as NSData
        let compressed = try nsData.compressed(using: .zlib)
        return compressed as Data
    }

    public func decompress(data: Data) throws -> Data {
        let nsData = data as NSData
        let decompressed = try nsData.decompressed(using: .zlib)
        return decompressed as Data
    }
}
