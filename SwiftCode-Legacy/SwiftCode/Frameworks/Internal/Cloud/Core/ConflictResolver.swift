import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.Cloud", category: "ConflictResolver")

public final class ConflictResolver: Sendable {
    public static let shared = ConflictResolver()

    private init() {}

    /// Resolves conflicts using Last Write Wins (LWW) based on timestamps and version number.
    public func resolve(local: CloudRecord, remote: CloudRecord) -> CloudRecord {
        logger.info("Resolving conflict for record \(local.recordKey, privacy: .public)")

        // 1. Compare version numbers
        if local.version > remote.version {
            logger.info("Local record has higher version. Choosing Local.")
            return local
        } else if remote.version > local.version {
            logger.info("Remote record has higher version. Choosing Remote.")
            return remote
        }

        // 2. Compare updated timestamps if versions are equal
        if local.updatedAt >= remote.updatedAt {
            logger.info("Local record has newer timestamp. Choosing Local.")
            return local
        } else {
            logger.info("Remote record has newer timestamp. Choosing Remote.")
            return remote
        }
    }
}
