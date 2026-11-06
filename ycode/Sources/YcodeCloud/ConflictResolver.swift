import Foundation

/// Resolves record conflicts with Last Write Wins, ported verbatim
/// from Legacy's `ConflictResolver.swift`: the higher version wins;
/// on equal versions the newer `updatedAt` wins (a tie goes to the
/// local record, because the comparison is `>=`).
public final class ConflictResolver: Sendable {
    public static let shared = ConflictResolver()

    private init() {}

    /// Resolves conflicts using Last Write Wins (LWW) based on
    /// timestamps and version number.
    public func resolve(local: CloudRecord, remote: CloudRecord) -> CloudRecord {
        // 1. Compare version numbers
        if local.version > remote.version {
            return local
        } else if remote.version > local.version {
            return remote
        }

        // 2. Compare updated timestamps if versions are equal
        if local.updatedAt >= remote.updatedAt {
            return local
        } else {
            return remote
        }
    }
}
