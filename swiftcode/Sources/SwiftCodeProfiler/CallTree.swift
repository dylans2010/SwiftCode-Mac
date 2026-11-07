import Foundation

public struct SampleFilter: Sendable, Equatable {
    public var range: Range<UInt64>?
    public var threads: Set<UInt64>?
    public var allStates: Bool

    public init(range: Range<UInt64>? = nil, threads: Set<UInt64>? = nil, allStates: Bool = false) {
        self.range = range
        self.threads = threads
        self.allStates = allStates
    }

    public func includes(_ t: GaugeTrace, _ i: Int) -> Bool {
        if !allStates && !t.samples.state[i].isCPU { return false }
        if let r = range, !r.contains(t.samples.time[i]) { return false }
        if let th = threads, !th.contains(t.samples.thread[i]) { return false }
        return true
    }
}

public struct FunctionRef: Sendable, Hashable {
    public var image: Int
    public var start: UInt64
    public init(image: Int, start: UInt64) {
        self.image = image
        self.start = start
    }
}

public struct CallTreeOptions: Sendable, Equatable {
    public var invert = false
    public var separateByThread = false
    public var hideSystemLibraries = false
    public var flattenRecursion = false
    public var chargedImages: Set<Int> = []
    public var chargedFunctions: Set<FunctionRef> = []
    public init(invert: Bool = false, separateByThread: Bool = false, hideSystemLibraries: Bool = false, flattenRecursion: Bool = false,
                chargedImages: Set<Int> = [], chargedFunctions: Set<FunctionRef> = []) {
        self.invert = invert
        self.separateByThread = separateByThread
        self.hideSystemLibraries = hideSystemLibraries
        self.flattenRecursion = flattenRecursion
        self.chargedImages = chargedImages
        self.chargedFunctions = chargedFunctions
    }
}

public final class CallTreeNode: @unchecked Sendable {
    public enum Key: Hashable, Sendable {
        case root
        case thread(UInt64)
        case function(FunctionRef)
        case system
    }

    public let key: Key
    public let name: String
    public let imageName: String
    public let imageKind: GaugeTrace.ImageKind
    public internal(set) var total = 0
    public internal(set) var selfCount = 0
    public internal(set) var children: [CallTreeNode] = []
    public private(set) weak var parent: CallTreeNode?
    var childIndex: [Key: Int] = [:]

    init(key: Key, name: String, imageName: String, imageKind: GaugeTrace.ImageKind, parent: CallTreeNode?) {
        self.key = key
        self.name = name
        self.imageName = imageName
        self.imageKind = imageKind
        self.parent = parent
    }

    public var function: FunctionRef? { if case .function(let f) = key { f } else { nil } }

    public var path: [Key] {
        var out: [Key] = []
        var n: CallTreeNode? = self
        while let c = n, c.key != .root { out.append(c.key); n = c.parent }
        return out.reversed()
    }

    public var heaviestPath: [CallTreeNode] {
        var out: [CallTreeNode] = [self]
        var n = self
        while let next = n.children.max(by: { $0.total < $1.total || ($0.total == $1.total && $0.name > $1.name) }) {
            out.append(next)
            n = next
        }
        return out
    }

    public func allNodes() -> [CallTreeNode] {
        var out: [CallTreeNode] = []
        var stack: [CallTreeNode] = [self]
        while let n = stack.popLast() {
            out.append(n)
            stack.append(contentsOf: n.children.reversed())
        }
        return out
    }

    public func find(_ text: String) -> CallTreeNode? {
        allNodes().first { $0.name.localizedCaseInsensitiveContains(text) }
    }
}

public struct CallTree: Sendable {
    public let root: CallTreeNode
    public var sampleCount: Int { root.total }
    public let intervalNs: UInt64

    public func milliseconds(_ samples: Int) -> Double { Double(samples) * Double(intervalNs) / 1e6 }

    public init(trace t: GaugeTrace, filter: SampleFilter = SampleFilter(), options o: CallTreeOptions = CallTreeOptions()) {
        let names = SymbolNames(trace: t)
        let root = CallTreeNode(key: .root, name: "All", imageName: "", imageKind: .unknown, parent: nil)
        intervalNs = t.recording.sampleIntervalNs
        var counts: [Pair: Int] = [:]
        for i in 0..<t.samples.count where filter.includes(t, i) {
            counts[Pair(thread: o.separateByThread ? t.samples.thread[i] : 0, stack: t.samples.stack[i]), default: 0] += 1
        }
        var pathCache: [Int: [FunctionRef?]] = [:]
        for (pair, n) in counts.sorted(by: { ($0.key.thread, $0.key.stack) < ($1.key.thread, $1.key.stack) }) {
            let fns: [FunctionRef?]
            if let c = pathCache[pair.stack] { fns = c } else {
                fns = Self.functions(t, names, stack: pair.stack, options: o)
                pathCache[pair.stack] = fns
            }
            var node = root
            root.total += n
            if o.separateByThread {
                node = Self.child(of: node, key: .thread(pair.thread), name: t.threadTitle(pair.thread), image: "", kind: .unknown)
                node.total += n
            }
            let ordered = o.invert ? Array(fns.reversed()) : fns
            if ordered.isEmpty {
                node.selfCount += n
                continue
            }
            for (depth, f) in ordered.enumerated() {
                let key: CallTreeNode.Key = f.map { .function($0) } ?? .system
                let (name, image, kind) = f.map { names.describe($0) } ?? ("<system>", "", .system)
                node = Self.child(of: node, key: key, name: name, image: image, kind: kind)
                node.total += n
                if (!o.invert && depth == ordered.count - 1) || (o.invert && depth == 0) { node.selfCount += n }
            }
        }
        Self.sort(root)
        self.root = root
    }

    struct Pair: Hashable { var thread: UInt64; var stack: Int }

    static func child(of node: CallTreeNode, key: CallTreeNode.Key, name: String, image: String, kind: GaugeTrace.ImageKind) -> CallTreeNode {
        if let i = node.childIndex[key] { return node.children[i] }
        let c = CallTreeNode(key: key, name: name, imageName: image, imageKind: kind, parent: node)
        node.childIndex[key] = node.children.count
        node.children.append(c)
        return c
    }

    static func sort(_ n: CallTreeNode) {
        n.children.sort { $0.total != $1.total ? $0.total > $1.total : $0.name < $1.name }
        n.childIndex = Dictionary(uniqueKeysWithValues: n.children.enumerated().map { ($1.key, $0) })
        for c in n.children { sort(c) }
    }

    static func functions(_ t: GaugeTrace, _ names: SymbolNames, stack: Int, options o: CallTreeOptions) -> [FunctionRef?] {
        var out: [FunctionRef?] = []
        var seen: Set<FunctionRef> = []
        var hidSomething = false
        for fid in t.frameIDs(ofStack: stack) {
            let f = names.function(ofFrame: fid)
            let kind = names.kind(f.image)
            if o.chargedImages.contains(f.image) || o.chargedFunctions.contains(f) { continue }
            if o.hideSystemLibraries && kind.isSystem { hidSomething = true; continue }
            if o.flattenRecursion {
                if seen.contains(f) { continue }
                seen.insert(f)
            }
            out.append(f)
        }
        if out.isEmpty && hidSomething { return [nil] }
        return out
    }

    public static func topFunctions(trace t: GaugeTrace, filter: SampleFilter = SampleFilter(),
                                    options o: CallTreeOptions = CallTreeOptions()) -> [(function: FunctionRef, name: String, image: String, selfCount: Int, total: Int)] {
        let names = SymbolNames(trace: t)
        var selfCounts: [FunctionRef: Int] = [:], totals: [FunctionRef: Int] = [:]
        var stackCounts: [Int: Int] = [:]
        for i in 0..<t.samples.count where filter.includes(t, i) { stackCounts[t.samples.stack[i], default: 0] += 1 }
        for (stack, n) in stackCounts {
            let fns = functions(t, names, stack: stack, options: o).compactMap { $0 }
            if let leaf = fns.last { selfCounts[leaf, default: 0] += n }
            for f in Set(fns) { totals[f, default: 0] += n }
        }
        return totals.map { f, total in
            let d = names.describe(f)
            return (f, d.name, d.image, selfCounts[f] ?? 0, total)
        }.sorted { $0.selfCount != $1.selfCount ? $0.selfCount > $1.selfCount : ($0.total != $1.total ? $0.total > $1.total : $0.name < $1.name) }
    }
}

public struct SymbolNames: Sendable {
    let trace: GaugeTrace
    let imageIndex: [Int: Int]

    public init(trace: GaugeTrace) {
        self.trace = trace
        var m: [Int: Int] = [:]
        for (i, img) in trace.images.enumerated() { m[img.id] = i }
        imageIndex = m
    }

    public func image(_ id: Int) -> GaugeTrace.Image? { imageIndex[id].map { trace.images[$0] } }

    public func kind(_ image: Int) -> GaugeTrace.ImageKind { self.image(image)?.kind ?? .unknown }

    public func function(ofFrame id: Int) -> FunctionRef {
        let f = trace.frames[id]
        guard let img = image(f.image) else { return FunctionRef(image: f.image, start: f.offset) }
        if let s = img.symbol(at: f.offset) { return FunctionRef(image: f.image, start: s.start) }
        return FunctionRef(image: f.image, start: f.offset)
    }

    public func describe(_ f: FunctionRef) -> (name: String, image: String, kind: GaugeTrace.ImageKind) {
        guard let img = image(f.image) else { return ("0x" + String(f.start, radix: 16), "?", .unknown) }
        if let i = img.symbolIndex(at: f.start), img.symbols[i].start == f.start { return (img.symbols[i].name, img.name, img.kind) }
        return ("0x" + String(f.start, radix: 16), img.name, img.kind)
    }

    public func describeFrame(_ id: Int) -> String {
        let f = trace.frames[id]
        guard let img = image(f.image) else { return "0x" + String(f.offset, radix: 16) }
        if let s = img.symbol(at: f.offset) {
            let delta = f.offset - s.start
            return delta == 0 ? "\(s.name) (\(img.name))" : "\(s.name) + \(delta) (\(img.name))"
        }
        return "\(img.name) + 0x\(String(f.offset, radix: 16))"
    }
}
