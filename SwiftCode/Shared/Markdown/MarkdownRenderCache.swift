import Foundation
import SwiftUI

public actor MarkdownRenderCache {
    public static let shared = MarkdownRenderCache()

    public struct RenderedDocument: Sendable {
        public let attributedContent: AttributedString
        public let blocks: [MarkdownBlock]
        public let wordCount: Int
        public let readingTimeSeconds: Int
    }

    private struct CacheKey: Hashable, Sendable {
        let contentHash: Int
        let options: MarkdownRenderOptions
    }

    private var cache: [CacheKey: RenderedDocument] = [:]
    private var keysOrder: [CacheKey] = []
    private let maxCapacity = 50

    private init() {}

    public func get(for content: String, options: MarkdownRenderOptions) -> RenderedDocument? {
        let key = CacheKey(contentHash: content.hashValue, options: options)
        guard let value = cache[key] else { return nil }

        if let index = keysOrder.firstIndex(of: key) {
            keysOrder.remove(at: index)
        }
        keysOrder.append(key)
        return value
    }

    public func set(_ document: RenderedDocument, for content: String, options: MarkdownRenderOptions) {
        let key = CacheKey(contentHash: content.hashValue, options: options)

        if cache[key] != nil, let index = keysOrder.firstIndex(of: key) {
            keysOrder.remove(at: index)
        }

        cache[key] = document
        keysOrder.append(key)

        if keysOrder.count > maxCapacity {
            let oldestKey = keysOrder.removeFirst()
            cache.removeValue(forKey: oldestKey)
        }
    }

    public func clear() {
        cache.removeAll()
        keysOrder.removeAll()
    }
}
