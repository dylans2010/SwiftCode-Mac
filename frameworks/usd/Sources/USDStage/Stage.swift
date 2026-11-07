import Foundation
import USDCore

public enum ArcType: Int, Comparable, Sendable {
    case root = 0, inherit, variant, reference, payload, specialize

    public static func < (a: ArcType, b: ArcType) -> Bool { a.rawValue < b.rawValue }
}

public final class LayerStack {
    public let identifier: String
    public let layers: [(layer: Layer, offset: LayerOffset)]

    init(identifier: String, layers: [(layer: Layer, offset: LayerOffset)]) {
        self.identifier = identifier
        self.layers = layers
    }

    public var rootLayer: Layer { layers[0].layer }

    func hasSpec(at path: Path) -> Bool { layers.contains { $0.layer.hasSpec(at: path) } }
}

public final class IndexNode {
    public let stack: LayerStack
    public internal(set) var path: Path
    public let arc: ArcType
    public let namespaceDepth: Int
    public let offset: LayerOffset
    let mappings: [(from: Path, to: Path)]
    public internal(set) var children: [IndexNode] = []
    let order: Int

    init(stack: LayerStack, path: Path, arc: ArcType, namespaceDepth: Int, offset: LayerOffset,
         mappings: [(from: Path, to: Path)], order: Int) {
        self.stack = stack
        self.path = path
        self.arc = arc
        self.namespaceDepth = namespaceDepth
        self.offset = offset
        self.mappings = mappings
        self.order = order
    }

    func copy(appending name: String) -> IndexNode {
        let n = IndexNode(stack: stack, path: path.appendingChild(name), arc: arc, namespaceDepth: namespaceDepth,
                          offset: offset, mappings: mappings, order: order)
        n.children = children.map { $0.copy(appending: name) }
        return n
    }

    public var strengthOrdered: [IndexNode] {
        var out: [IndexNode] = [self]
        for c in children { out += c.strengthOrdered }
        return out
    }

    public func mapToStage(_ p: Path) -> Path {
        var p = p
        for m in mappings where p.hasPrefix(m.from) { p = p.replacingPrefix(m.from, with: m.to) }
        return p
    }

    func sortChildren() {
        children.sort { a, b in
            if a.arc != b.arc { return a.arc < b.arc }
            if a.namespaceDepth != b.namespaceDepth { return a.namespaceDepth > b.namespaceDepth }
            return a.order < b.order
        }
    }
}

public final class Stage {
    public private(set) var rootLayer: Layer
    public let resolver: LayerResolver
    public var variantFallbacks: [String: [String]] = [:] { didSet { invalidate() } }
    public var loadPayloads = true { didSet { invalidate() } }
    public private(set) var errors: [String] = []

    private var stacks: [String: LayerStack] = [:]
    private var indexes: [Path: IndexNode?] = [:]
    private var rootStack: LayerStack!
    private var nodeCounter = 0

    public init(rootLayer: Layer, resolver: LayerResolver? = nil) {
        self.rootLayer = rootLayer
        self.resolver = resolver ?? FileLayerResolver()
        invalidate()
    }

    public static func open(_ path: String, resolver: LayerResolver? = nil) throws -> Stage {
        let resolver = resolver ?? FileLayerResolver()
        let layer = try resolver.layer(for: path)
        return Stage(rootLayer: layer, resolver: resolver)
    }

    public func setRootLayer(_ layer: Layer) {
        rootLayer = layer
        invalidate()
    }

    public func invalidate() {
        stacks = [:]
        indexes = [:]
        errors = []
        nodeCounter = 0
        rootStack = buildStack(rootLayer, visited: [])
    }

    private func buildStack(_ layer: Layer, visited: Set<String>) -> LayerStack {
        if let s = stacks[layer.identifier] { return s }
        var entries: [(layer: Layer, offset: LayerOffset)] = []
        func add(_ l: Layer, offset: LayerOffset, chain: Set<String>) {
            entries.append((l, offset))
            let offsets = l.subLayerOffsets
            for (i, sub) in l.subLayers.enumerated() {
                let id = resolver.identifier(for: sub, anchor: l.identifier)
                guard !chain.contains(id) else {
                    errors.append("sublayer cycle at \(id)")
                    continue
                }
                do {
                    let subLayer = try resolver.layer(for: id)
                    let o = i < offsets.count ? offsets[i] : .identity
                    add(subLayer, offset: offset.concatenating(o), chain: chain.union([id]))
                } catch {
                    errors.append("cannot open sublayer @\(sub)@ of \(l.identifier): \(error)")
                }
            }
        }
        add(layer, offset: .identity, chain: visited.union([layer.identifier]))
        let stack = LayerStack(identifier: layer.identifier, layers: entries)
        stacks[layer.identifier] = stack
        return stack
    }

    private func stack(for identifier: String) throws -> LayerStack {
        if let s = stacks[identifier] { return s }
        return buildStack(try resolver.layer(for: identifier), visited: [])
    }

    public func primIndex(_ path: Path) -> IndexNode? {
        if let cached = indexes[path] { return cached }
        let result = buildIndex(path)
        indexes[path] = result
        return result
    }

    private func buildIndex(_ path: Path) -> IndexNode? {
        guard path.isAbsolute, !path.containsVariantSelection else { return nil }
        let root: IndexNode
        if path.isRoot {
            nodeCounter += 1
            root = IndexNode(stack: rootStack, path: .root, arc: .root, namespaceDepth: 0, offset: .identity, mappings: [], order: nodeCounter)
            return root
        }
        guard case .prim(let name) = path.last, let parent = primIndex(path.parent) else { return nil }
        root = parent.copy(appending: name)
        expandExisting(root, root: root, depth: path.primNames.count)
        guard root.strengthOrdered.contains(where: { $0.stack.hasSpec(at: $0.path) }) else { return nil }
        return root
    }

    private func expandExisting(_ node: IndexNode, root: IndexNode, depth: Int) {
        let existing = node.children
        for c in existing { expandExisting(c, root: root, depth: depth) }
        addArcs(to: node, root: root, depth: depth, chain: [])
        node.sortChildren()
    }

    private func siteSpecs(_ node: IndexNode, at path: Path? = nil) -> [(layer: Layer, spec: Spec)] {
        let p = path ?? node.path
        return node.stack.layers.compactMap { entry in entry.layer.spec(at: p).map { (entry.layer, $0) } }
    }

    private func composedList<T>(_ node: IndexNode, field: String, extract: (Value) -> ListOp<T>?) -> [(item: T, layer: Layer)] {
        var items: [T] = []
        var source: [T: Layer] = [:]
        for (layer, spec) in siteSpecs(node).reversed() {
            guard let value = spec.fields[field], let op = extract(value) else { continue }
            items = op.applied(to: items)
            for i in op.allItems { source[i] = layer }
        }
        return items.map { ($0, source[$0] ?? node.stack.rootLayer) }
    }

    private func addArcs(to node: IndexNode, root: IndexNode, depth: Int, chain: [String]) {
        let key = node.stack.identifier + "|" + node.path.description
        guard chain.count < 48, !chain.contains(key) else {
            errors.append("composition cycle at \(node.path)")
            return
        }
        let specs = siteSpecs(node)
        guard !specs.isEmpty else { return }
        let chain = chain + [key]
        let anchorPath = node.path.strippingVariantSelections
        var added: [IndexNode] = []
        func make(_ stack: LayerStack, _ target: Path, _ arc: ArcType, _ offset: LayerOffset, mapFrom: Path) -> IndexNode {
            nodeCounter += 1
            let mapping = mapFrom == anchorPath ? node.mappings : [(mapFrom, anchorPath)] + node.mappings
            let n = IndexNode(stack: stack, path: target, arc: arc, namespaceDepth: depth, offset: node.offset.concatenating(offset),
                              mappings: mapping, order: nodeCounter)
            node.children.append(n)
            added.append(n)
            return n
        }

        for (target, _) in composedList(node, field: FieldKey.inheritPaths, extract: { if case .pathListOp(let op) = $0 { return op }; return nil }) {
            _ = make(node.stack, target, .inherit, .identity, mapFrom: target)
        }
        let sets = composedList(node, field: FieldKey.variantSetNames) { v -> ListOp<String>? in
            if case .stringListOp(let op) = v { return op }
            return nil
        }
        for (set, _) in sets {
            guard let selection = variantSelection(set, root: root, node: node), !selection.isEmpty else { continue }
            let vPath = node.path.appendingVariantSelection(set: set, variant: selection)
            guard node.stack.hasSpec(at: vPath) else { continue }
            _ = make(node.stack, vPath, .variant, .identity, mapFrom: anchorPath)
        }
        let refs = composedList(node, field: FieldKey.references) { v -> ListOp<Reference>? in
            if case .referenceListOp(let op) = v { return op }
            return nil
        }
        for (ref, layer) in refs {
            if let (stack, target) = arcTarget(asset: ref.assetPath, prim: ref.primPath, node: node, layer: layer) {
                _ = make(stack, target, .reference, ref.layerOffset, mapFrom: target)
            }
        }
        if loadPayloads {
            let payloads = composedList(node, field: FieldKey.payload) { v -> ListOp<Payload>? in
                if case .payloadListOp(let op) = v { return op }
                return nil
            }
            for (payload, layer) in payloads {
                if let (stack, target) = arcTarget(asset: payload.assetPath, prim: payload.primPath, node: node, layer: layer) {
                    _ = make(stack, target, .payload, payload.layerOffset, mapFrom: target)
                }
            }
        }
        for (target, _) in composedList(node, field: FieldKey.specializes, extract: { if case .pathListOp(let op) = $0 { return op }; return nil }) {
            _ = make(node.stack, target, .specialize, .identity, mapFrom: target)
        }
        for n in added { addArcs(to: n, root: root, depth: depth, chain: chain) }
        node.sortChildren()
    }

    private func arcTarget(asset: String, prim: Path, node: IndexNode, layer: Layer) -> (LayerStack, Path)? {
        let stack: LayerStack
        if asset.isEmpty {
            stack = node.stack
        } else {
            let id = resolver.identifier(for: asset, anchor: layer.identifier)
            do {
                stack = try self.stack(for: id)
            } catch {
                errors.append("\(node.path): cannot open @\(asset)@: \(error)")
                return nil
            }
        }
        var target = prim
        if target.isEmpty {
            guard let def = stack.rootLayer.defaultPrim, !def.isEmpty else {
                errors.append("\(node.path): @\(asset)@ has no defaultPrim")
                return nil
            }
            target = Path.root.appendingChild(def)
        }
        if target.kind == .relative { target = target.makingAbsolute(anchor: node.path.strippingVariantSelections) }
        guard stack.hasSpec(at: target) else {
            errors.append("\(node.path): unresolved target <\(target)> in @\(asset.isEmpty ? stack.identifier : asset)@")
            return nil
        }
        return (stack, target)
    }

    private func variantSelection(_ set: String, root: IndexNode, node: IndexNode) -> String? {
        for n in root.strengthOrdered {
            for (_, spec) in siteSpecs(n) {
                if case .variantSelectionMap(let map)? = spec.fields[FieldKey.variantSelection], let v = map[set] { return v }
            }
        }
        if let fallbacks = variantFallbacks[set] {
            for f in fallbacks where node.stack.hasSpec(at: node.path.appendingVariantSelection(set: set, variant: f)) { return f }
        }
        return nil
    }

    public func opinions(_ path: Path) -> [(node: IndexNode, layer: Layer, spec: Spec, offset: LayerOffset)] {
        let primPath = path.primPath
        guard let index = primIndex(primPath) else { return [] }
        var out: [(node: IndexNode, layer: Layer, spec: Spec, offset: LayerOffset)] = []
        for node in index.strengthOrdered {
            let p: Path
            switch path.last {
            case .property(let name)?: p = node.path.appendingProperty(name)
            default: p = node.path
            }
            for entry in node.stack.layers {
                if let spec = entry.layer.spec(at: p) {
                    out.append((node, entry.layer, spec, node.offset.concatenating(entry.offset)))
                }
            }
        }
        return out
    }

    public func resolvedField(_ field: String, at path: Path) -> Value? {
        var merged: [String: Value]?
        for o in opinions(path) {
            guard let v = o.spec.fields[field] else { continue }
            if case .dictionary(let d) = v {
                merged = Stage.mergeDictionary(stronger: merged ?? [:], weaker: d)
                continue
            }
            return merged.map { .dictionary($0) } ?? v
        }
        return merged.map { .dictionary($0) }
    }

    static func mergeDictionary(stronger: [String: Value], weaker: [String: Value]) -> [String: Value] {
        var out = weaker
        for (k, v) in stronger {
            if case .dictionary(let s) = v, case .dictionary(let w)? = out[k] {
                out[k] = .dictionary(mergeDictionary(stronger: s, weaker: w))
            } else {
                out[k] = v
            }
        }
        return out
    }

    private func composedNames(_ path: Path, list: String, order: String) -> [String] {
        guard let index = primIndex(path) else { return [] }
        var names: [String] = []
        var seen: Set<String> = []
        var reorder: [String]?
        for node in index.strengthOrdered.reversed() {
            for entry in node.stack.layers.reversed() {
                guard let spec = entry.layer.spec(at: node.path) else { continue }
                for n in spec.fields[list]?.stringArray ?? [] where !seen.contains(n) {
                    names.append(n)
                    seen.insert(n)
                }
                if let o = spec.fields[order]?.stringArray { reorder = o }
            }
        }
        if let reorder { names = ListOp(orderedItems: reorder).applied(to: names) }
        return names
    }

    public func prim(at path: Path) -> Prim? {
        guard path.isRoot || primIndex(path) != nil else { return nil }
        return Prim(stage: self, path: path)
    }

    public var pseudoRoot: Prim { Prim(stage: self, path: .root) }

    public var defaultPrim: Prim? {
        guard let name = rootLayer.defaultPrim else { return nil }
        return prim(at: Path.root.appendingChild(name))
    }

    public func childNames(of path: Path) -> [String] {
        composedNames(path, list: FieldKey.primChildren, order: FieldKey.primOrder).filter {
            primIndex(path.appendingChild($0)) != nil
        }
    }

    public func propertyNames(of path: Path) -> [String] {
        composedNames(path, list: FieldKey.properties, order: FieldKey.propertyOrder)
    }

    public struct TraversalOptions: Sendable {
        public var includeInactive = false
        public var includeUndefined = false
        public var includeAbstract = false

        public init(includeInactive: Bool = false, includeUndefined: Bool = false, includeAbstract: Bool = false) {
            self.includeInactive = includeInactive
            self.includeUndefined = includeUndefined
            self.includeAbstract = includeAbstract
        }

        public static let all = TraversalOptions(includeInactive: true, includeUndefined: true, includeAbstract: true)
    }

    public func traverse(_ options: TraversalOptions = TraversalOptions(), from start: Path = .root) -> [Prim] {
        var out: [Prim] = []
        func visit(_ path: Path) {
            for name in childNames(of: path) {
                let p = path.appendingChild(name)
                let prim = Prim(stage: self, path: p)
                if !options.includeInactive && !prim.isActive { continue }
                if !options.includeAbstract && prim.specifier == .class { continue }
                if !options.includeUndefined && !prim.isDefined { continue }
                out.append(prim)
                visit(p)
            }
        }
        visit(start)
        return out
    }

    public var upAxis: String { rootLayer.upAxis ?? "Y" }
    public var metersPerUnit: Double { rootLayer.metersPerUnit ?? 0.01 }
}
