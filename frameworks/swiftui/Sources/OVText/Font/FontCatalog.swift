import Foundation
import Synchronization

public enum FontDesignClass: Hashable, Sendable {
    case `default`, serif, rounded, monospaced
}

public struct FontRequest: Hashable, Sendable {
    public var family: String?
    public var design: FontDesignClass
    public var traits: FontTraits

    public init(family: String? = nil, design: FontDesignClass = .default, traits: FontTraits = FontTraits()) {
        self.family = family
        self.design = design
        self.traits = traits
    }
}

struct FaceDescriptor: Sendable {
    let url: URL
    let index: Int
    let family: String
    let style: String
    let traits: FontTraits
}

public final class FontCatalog: @unchecked Sendable {
    public static let defaultFamilies: [FontDesignClass: [String]] = [
        .default: ["Noto Sans"],
        .rounded: ["Nunito", "Noto Sans"],
        .serif: ["Noto Serif", "DejaVu Serif", "Liberation Serif", "Noto Sans"],
        .monospaced: ["Noto Sans Mono", "DejaVu Sans Mono", "Liberation Mono", "Noto Sans"],
    ]

    public static let refusedFamilyPrefixes = ["SF Pro", "SF Compact", "SF Mono", "SF Arabic", "SF Hebrew",
                                              "SF Armenian", "SF Georgian", "New York", "San Francisco",
                                              "System Font", "AppleSystemUI"]

    public static func isRefused(family: String) -> Bool {
        family.hasPrefix(".") || refusedFamilyPrefixes.contains { family.lowercased().hasPrefix($0.lowercased()) }
    }

    private struct State {
        var faces: [any FontFace] = []
        var pendingDirectories: [URL] = []
        var descriptors: [FaceDescriptor] = []
        var loaded: [String: any FontFace] = [:]
        var matchCache: [FontRequest: any FontFace] = [:]
        var fallbackCache: [UInt32: (any FontFace)?] = [:]
    }
    private let state = Mutex(State())
    private let familyTable: Mutex<[FontDesignClass: [String]]>
    public var families: [FontDesignClass: [String]] { familyTable.withLock { $0 } }

    public init(families: [FontDesignClass: [String]] = FontCatalog.defaultFamilies) {
        familyTable = Mutex(families)
    }

    public func setFamilies(_ names: [String], for design: FontDesignClass) {
        familyTable.withLock { $0[design] = names }
        state.withLock { $0.matchCache = [:] }
    }

    public static let shared: FontCatalog = {
        let c = FontCatalog()
        c.addBundledFonts()
        #if os(Linux)
        c.addSystemFontDirectories()
        #endif
        return c
    }()

    public static let bundled: FontCatalog = {
        let c = FontCatalog()
        c.addBundledFonts()
        return c
    }()

    public func add(_ face: any FontFace) {
        guard !FontCatalog.isRefused(family: face.familyName) else { return }
        state.withLock {
            $0.faces.append(face)
            $0.matchCache = [:]
            $0.fallbackCache = [:]
        }
    }

    public func addFont(at url: URL) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let count = data.count >= 12 && String(decoding: data.prefix(4), as: UTF8.self) == "ttcf"
            ? Int(FontBytes(data).u32(8)) : 1
        for i in 0..<count { add(try OpenTypeFace(data: data, index: i)) }
    }

    public func addDirectory(_ url: URL) {
        state.withLock {
            $0.pendingDirectories.append(url)
            $0.matchCache = [:]
            $0.fallbackCache = [:]
        }
    }

    public func addBundledFonts() {
        guard let dir = Bundle.module.url(forResource: "Fonts", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        func key(_ u: URL) -> String { (u.lastPathComponent.hasPrefix("Inter") ? "1" : "0") + u.lastPathComponent }
        for f in files.sorted(by: { key($0) < key($1) })
        where ["ttf", "otf", "ttc"].contains(f.pathExtension.lowercased()) {
            try? addFont(at: f)
        }
    }

    public func addSystemFontDirectories() {
        let env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        var dirs: [URL] = []
        if let x = env["XDG_DATA_HOME"] { dirs.append(URL(fileURLWithPath: x).appendingPathComponent("fonts")) }
        dirs.append(home.appendingPathComponent(".local/share/fonts"))
        dirs.append(home.appendingPathComponent(".fonts"))
        dirs.append(URL(fileURLWithPath: "/usr/local/share/fonts"))
        dirs.append(URL(fileURLWithPath: "/usr/share/fonts"))
        for d in dirs { addDirectory(d) }
    }

    public var registeredFaces: [any FontFace] { state.withLock { $0.faces } }

    public func face(for request: FontRequest) -> (any FontFace)? {
        if let f = state.withLock({ $0.matchCache[request] }) { return f }
        let names = request.family.map { [$0] } ?? (families[request.design] ?? families[.default] ?? [])
        var result: (any FontFace)?
        for name in names {
            if let f = match(family: name, traits: request.traits) { result = f; break }
        }
        if result == nil, request.family != nil {
            result = face(for: FontRequest(design: request.design, traits: request.traits))
        }
        if result == nil { result = registeredFaces.first }
        if let r = result { state.withLock { $0.matchCache[request] = r } }
        return result
    }

    public func fallback(for scalar: Unicode.Scalar, near traits: FontTraits) -> (any FontFace)? {
        if let cached = state.withLock({ $0.fallbackCache[scalar.value] }) { return cached }
        var found = registeredFaces.first { $0.glyph(for: scalar) != nil }
        if found == nil {
            scanPendingDirectories()
            var undrawable: (any FontFace)?
            for d in state.withLock({ $0.descriptors }) {
                guard let f = load(d), f.glyph(for: scalar) != nil else { continue }
                if (f as? OpenTypeFace)?.glyfTable == nil {
                    undrawable = undrawable ?? f
                    continue
                }
                found = f
                break
            }
            found = found ?? undrawable
        }
        state.withLock { $0.fallbackCache[scalar.value] = found }
        return found
    }

    private func match(family: String, traits: FontTraits) -> (any FontFace)? {
        let key = family.lowercased()
        var candidates: [(traits: FontTraits, load: () -> (any FontFace)?)] =
            registeredFaces.filter { $0.familyName.lowercased() == key }.map { f in (f.traits, { f }) }
        if candidates.isEmpty {
            scanPendingDirectories()
            candidates = state.withLock { $0.descriptors }.filter { $0.family.lowercased() == key }
                .map { d in (d.traits, { [unowned self] in self.load(d) }) }
        }
        guard !candidates.isEmpty else { return nil }
        let best = FontCatalog.bestMatch(candidates.map(\.traits), for: traits)
        return candidates[best].load()
    }

    public static func bestMatch(_ candidates: [FontTraits], for want: FontTraits) -> Int {
        var idx = Array(candidates.indices)
        let widths = Set(idx.map { candidates[$0].width })
        let w: Int
        if widths.contains(want.width) {
            w = want.width
        } else if want.width <= 5 {
            w = widths.filter { $0 < want.width }.max() ?? widths.min()!
        } else {
            w = widths.filter { $0 > want.width }.min() ?? widths.max()!
        }
        idx = idx.filter { candidates[$0].width == w }
        let italic = idx.filter { candidates[$0].isItalic == want.isItalic }
        if !italic.isEmpty { idx = italic }
        let weights = Set(idx.map { candidates[$0].weight })
        let d = want.weight
        let chosen: Int
        if weights.contains(d) {
            chosen = d
        } else if d >= 400 && d <= 500 {
            chosen = weights.filter { $0 > d && $0 <= 500 }.min()
                ?? weights.filter { $0 < d }.max()
                ?? weights.filter { $0 > 500 }.min()!
        } else if d < 400 {
            chosen = weights.filter { $0 < d }.max() ?? weights.filter { $0 > d }.min()!
        } else {
            chosen = weights.filter { $0 > d }.min() ?? weights.filter { $0 < d }.max()!
        }
        return idx.first { candidates[$0].weight == chosen }!
    }

    private func scanPendingDirectories() {
        let dirs: [URL] = state.withLock {
            let d = $0.pendingDirectories
            $0.pendingDirectories = []
            return d
        }
        guard !dirs.isEmpty else { return }
        var found: [FaceDescriptor] = []
        for dir in dirs {
            guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in e where ["ttf", "otf", "ttc"].contains(url.pathExtension.lowercased()) {
                found.append(contentsOf: FontCatalog.describe(url))
            }
        }
        found.sort { $0.url.path < $1.url.path || ($0.url.path == $1.url.path && $0.index < $1.index) }
        state.withLock { $0.descriptors.append(contentsOf: found) }
    }

    private func load(_ d: FaceDescriptor) -> (any FontFace)? {
        let key = d.url.path + "#\(d.index)"
        if let f = state.withLock({ $0.loaded[key] }) { return f }
        guard let f = try? OpenTypeFace(contentsOf: d.url, index: d.index) else { return nil }
        state.withLock { $0.loaded[key] = f }
        return f
    }

    static func describe(_ url: URL) -> [FaceDescriptor] {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return [] }
        let d = FontBytes(data)
        var bases = [0]
        if d.tag(0) == "ttcf" { bases = (0..<Int(min(d.u32(8), 64))).map { Int(d.u32(12 + 4 * $0)) } }
        var out: [FaceDescriptor] = []
        for (i, base) in bases.enumerated() {
            var tables: [String: Int] = [:]
            for t in 0..<Int(d.u16(base + 4)) {
                let r = base + 12 + 16 * t
                tables[d.tag(r)] = Int(d.u32(r + 8))
            }
            guard let name = tables["name"] else { continue }
            let names = NameTable(d, at: name)
            guard let family = names.string(16) ?? names.string(1), !isRefused(family: family) else { continue }
            var traits = FontTraits()
            if let os2 = tables["OS/2"] {
                traits.weight = Int(d.u16(os2 + 4))
                traits.width = Int(d.u16(os2 + 6))
                traits.isItalic = d.u16(os2 + 62) & 1 != 0
            }
            if let post = tables["post"] { traits.isMonospaced = d.u32(post + 12) != 0 }
            out.append(FaceDescriptor(url: url, index: i, family: family,
                                      style: names.string(17) ?? names.string(2) ?? "Regular", traits: traits))
        }
        return out
    }
}
