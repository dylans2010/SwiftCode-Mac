import Foundation

/// Actor-isolated, thread-safe caching layer storing layout calculations, compiled binaries, and environmental profiles.
public actor PreviewCache {
    public static let shared = PreviewCache()

    private var compiledBinaryPaths: [String: URL] = [:]
    private var compiledBinaryPathsByHash: [String: URL] = [:]
    private var renderedStateHashes: [String: Int] = [:]
    private var layoutCache: [String: [String: Double]] = [:]

    private init() {}

    public func getBinary(forSourcePath path: String) -> URL? {
        return compiledBinaryPaths[path]
    }

    public func setBinary(_ url: URL, forSourcePath path: String) {
        compiledBinaryPaths[path] = url
    }

    // Modern Content Hash Caching Interfaces
    public func getBinary(forHash hash: String) -> URL? {
        return compiledBinaryPathsByHash[hash]
    }

    public func setBinary(_ url: URL, forHash hash: String) {
        compiledBinaryPathsByHash[hash] = url
    }

    public func getLayoutValue(forNodeKey key: String, property: String) -> Double? {
        return layoutCache[key]?[property]
    }

    public func cacheLayoutValue(_ value: Double, forNodeKey key: String, property: String) {
        if layoutCache[key] == nil {
            layoutCache[key] = [:]
        }
        layoutCache[key]?[property] = value
    }

    public func registerRenderedHash(key: String, hash: Int) {
        renderedStateHashes[key] = hash
    }

    public func isRenderedHashUpToDate(key: String, hash: Int) -> Bool {
        return renderedStateHashes[key] == hash
    }

    public func clearAll() {
        compiledBinaryPaths.removeAll()
        compiledBinaryPathsByHash.removeAll()
        renderedStateHashes.removeAll()
        layoutCache.removeAll()
    }
}
