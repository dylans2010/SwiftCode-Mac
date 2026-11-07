import Foundation

public final class CacheImageFiles: @unchecked Sendable {
    public static let cryptexPrefix = "/System/Cryptexes/OS"
    public static let excludedPrefix = "/usr/lib/system/"

    public static let enabledByEnvironment: Bool =
        getenv("SWIFTCODE_CACHE_IMAGE_FILES").map { String(cString: $0) != "0" } ?? true

    public let runtimeRoot: String
    private let loadImagePaths: () -> [String]
    private let lock = NSLockLike(name: "cache image files")
    private var imagePaths: Set<String>?

    public init(runtimeRoot: String, imagePaths: @escaping () -> [String]) {
        var root = runtimeRoot
        while root.count > 1 && root.hasSuffix("/") { root.removeLast() }
        self.runtimeRoot = root
        self.loadImagePaths = imagePaths
    }

    private func paths() -> Set<String> {
        lock.withLock {
            if let p = imagePaths { return p }
            let p = Set(loadImagePaths())
            imagePaths = p
            return p
        }
    }

    public func imagePath(forGuestPath guestPath: String) -> String? {
        guard guestPath.hasPrefix(runtimeRoot + "/") else { return nil }
        let inner = String(guestPath.dropFirst(runtimeRoot.count))
        guard !inner.hasPrefix(Self.excludedPrefix) else { return nil }
        let set = paths()
        if set.contains(inner) { return inner }
        if inner.hasPrefix(Self.cryptexPrefix + "/") {
            let bare = String(inner.dropFirst(Self.cryptexPrefix.count))
            if !bare.hasPrefix(Self.excludedPrefix) && set.contains(bare) { return bare }
        } else if set.contains(Self.cryptexPrefix + inner) {
            return Self.cryptexPrefix + inner
        }
        return nil
    }

    public func stat(forGuestPath guestPath: String, dev: UInt32) -> DarwinStat? {
        guard let image = imagePath(forGuestPath: guestPath) else { return nil }
        return DarwinStat(dev: dev, mode: DarwinStat.S_IFREG | 0o555, nlink: 1, ino: Self.inode(image),
                          uid: 0, gid: 0, size: 0, blksize: 4096)
    }

    static func inode(_ image: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in image.utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
        return 0x7963_0000_0000_0000 | (h & 0xFFFF_FFFF)
    }
}
