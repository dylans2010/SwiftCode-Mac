import Foundation
import USDCore

public protocol LayerResolver: AnyObject {
    func identifier(for assetPath: String, anchor: String) -> String
    func layer(for identifier: String) throws -> Layer
}

public enum AssetPaths {
    public static func join(_ directory: String, _ relative: String) -> String {
        if relative.hasPrefix("/") { return normalize(relative) }
        return normalize(directory.isEmpty ? relative : directory + "/" + relative)
    }

    public static func normalize(_ path: String) -> String {
        let absolute = path.hasPrefix("/")
        var parts: [Substring] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == "..", let last = parts.last, last != ".." {
                parts.removeLast()
                continue
            }
            parts.append(part)
        }
        return (absolute ? "/" : "") + parts.joined(separator: "/")
    }

    public static func directory(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }

    public static func splitPackage(_ identifier: String) -> (package: String, inner: String)? {
        guard identifier.hasSuffix("]"), let open = identifier.firstIndex(of: "[") else { return nil }
        let package = String(identifier[..<open])
        let inner = String(identifier[identifier.index(after: open)..<identifier.index(before: identifier.endIndex)])
        return (package, inner)
    }
}

public final class FileLayerResolver: LayerResolver {
    private var cache: [String: Layer] = [:]
    private var packages: [String: USDZArchive] = [:]

    public init() {}

    public func identifier(for assetPath: String, anchor: String) -> String {
        if let (package, inner) = AssetPaths.splitPackage(anchor), !assetPath.hasPrefix("/") {
            let candidate = AssetPaths.join(AssetPaths.directory(of: inner), assetPath)
            if let archive = try? archive(package), archive.entry(named: candidate) != nil {
                return package + "[" + candidate + "]"
            }
            return AssetPaths.join(AssetPaths.directory(of: package), assetPath)
        }
        return AssetPaths.join(AssetPaths.directory(of: anchor), assetPath)
    }

    func archive(_ path: String) throws -> USDZArchive {
        if let a = packages[path] { return a }
        guard let data = FileManager.default.contents(atPath: path) else { throw USDError("cannot read \(path)") }
        let a = try USDZArchive.read([UInt8](data))
        packages[path] = a
        return a
    }

    public func layer(for identifier: String) throws -> Layer {
        if let layer = cache[identifier] { return layer }
        let layer: Layer
        if let (package, inner) = AssetPaths.splitPackage(identifier) {
            guard let entry = try archive(package).entry(named: inner) else { throw USDError("no \(inner) in \(package)") }
            layer = try LayerIO.read(entry.data, identifier: identifier)
        } else if identifier.fileExtension == "usdz" {
            let archive = try archive(identifier)
            guard let root = archive.rootLayer else { throw USDError("\(identifier): no root layer") }
            layer = try LayerIO.read(root.data, identifier: identifier + "[" + root.name + "]")
        } else {
            layer = try LayerIO.read(contentsOf: identifier)
        }
        cache[identifier] = layer
        return layer
    }

    public func setLayer(_ layer: Layer, for identifier: String) { cache[identifier] = layer }
}

public final class MemoryLayerResolver: LayerResolver {
    public var layers: [String: Layer]
    public var fallback: LayerResolver?

    public init(layers: [Layer] = [], fallback: LayerResolver? = nil) {
        self.layers = Dictionary(layers.map { ($0.identifier, $0) }, uniquingKeysWith: { _, b in b })
        self.fallback = fallback
    }

    public func identifier(for assetPath: String, anchor: String) -> String {
        AssetPaths.join(AssetPaths.directory(of: anchor), assetPath)
    }

    public func layer(for identifier: String) throws -> Layer {
        if let l = layers[identifier] { return l }
        if let fallback { return try fallback.layer(for: identifier) }
        throw USDError("no layer \(identifier)")
    }
}

extension String {
    var fileExtension: String {
        let last = split(separator: "/").last.map(String.init) ?? self
        guard let dot = last.lastIndex(of: ".") else { return "" }
        return String(last[last.index(after: dot)...]).lowercased()
    }
}
