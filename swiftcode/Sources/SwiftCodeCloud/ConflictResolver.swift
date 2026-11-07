import Foundation

public final class ConflictResolver: Sendable {
    public static let shared = ConflictResolver()

    private init() {}

    public func resolve(local: CloudRecord, remote: CloudRecord) -> CloudRecord {
        if local.version > remote.version {
            return local
        } else if remote.version > local.version {
            return remote
        }

        if local.updatedAt >= remote.updatedAt {
            return local
        } else {
            return remote
        }
    }
}
