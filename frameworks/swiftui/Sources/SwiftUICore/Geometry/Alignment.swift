import Foundation

public protocol AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat
}

package protocol ExplicitCombiningAlignmentID: AlignmentID {
    static func combine(_ values: [CGFloat]) -> CGFloat?
}

public struct AlignmentKey: Hashable, Comparable, Sendable {
    package let index: Int
    package let axis: Axis

    package init(id: any AlignmentID.Type, axis: Axis) {
        self.index = AlignmentRegistry.shared.index(of: id)
        self.axis = axis
    }

    package var id: any AlignmentID.Type { AlignmentRegistry.shared.type(at: index) }

    public static func < (lhs: AlignmentKey, rhs: AlignmentKey) -> Bool {
        (lhs.index, lhs.axis.rawValue) < (rhs.index, rhs.axis.rawValue)
    }

    package func defaultValue(for size: CGSize) -> CGFloat {
        id.defaultValue(in: ViewDimensions(size: size))
    }

    package func defaultValue(in d: ViewDimensions) -> CGFloat { id.defaultValue(in: d) }

    package func combine(_ values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else { return nil }
        if let c = id as? any ExplicitCombiningAlignmentID.Type { return c.combine(values) }
        return values.reduce(0, +) / CGFloat(values.count)
    }
}

package final class AlignmentRegistry: @unchecked Sendable {
    package static let shared = AlignmentRegistry()
    private let lock = NSLock()
    private var indices: [ObjectIdentifier: Int] = [:]
    private var types: [any AlignmentID.Type] = []

    func index(of id: any AlignmentID.Type) -> Int {
        lock.lock(); defer { lock.unlock() }
        let oid = ObjectIdentifier(id)
        if let i = indices[oid] { return i }
        types.append(id)
        indices[oid] = types.count - 1
        return types.count - 1
    }

    func type(at index: Int) -> any AlignmentID.Type {
        lock.lock(); defer { lock.unlock() }
        return types[index]
    }
}

public struct HorizontalAlignment: Equatable, Sendable {
    public let key: AlignmentKey

    public init(_ id: any AlignmentID.Type) { key = AlignmentKey(id: id, axis: .horizontal) }

    public func combineExplicit(_ values: some Sequence<CGFloat>) -> CGFloat? {
        key.combine(Array(values))
    }

    private enum Leading: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { 0 }
    }
    private enum Center: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d.width / 2 }
    }
    private enum Trailing: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d.width }
    }

    public static let leading = HorizontalAlignment(Leading.self)
    public static let center = HorizontalAlignment(Center.self)
    public static let trailing = HorizontalAlignment(Trailing.self)
}

public struct VerticalAlignment: Equatable, Sendable {
    public let key: AlignmentKey

    public init(_ id: any AlignmentID.Type) { key = AlignmentKey(id: id, axis: .vertical) }

    public func combineExplicit(_ values: some Sequence<CGFloat>) -> CGFloat? {
        key.combine(Array(values))
    }

    private enum Top: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { 0 }
    }
    private enum Center: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d.height / 2 }
    }
    private enum Bottom: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d.height }
    }
    private enum FirstTextBaseline: ExplicitCombiningAlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d.height }
        static func combine(_ values: [CGFloat]) -> CGFloat? { values.min() }
    }
    private enum LastTextBaseline: ExplicitCombiningAlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d.height }
        static func combine(_ values: [CGFloat]) -> CGFloat? { values.max() }
    }

    public static let top = VerticalAlignment(Top.self)
    public static let center = VerticalAlignment(Center.self)
    public static let bottom = VerticalAlignment(Bottom.self)
    public static let firstTextBaseline = VerticalAlignment(FirstTextBaseline.self)
    public static let lastTextBaseline = VerticalAlignment(LastTextBaseline.self)
}

public struct Alignment: Equatable, Sendable {
    public var horizontal: HorizontalAlignment
    public var vertical: VerticalAlignment

    public init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    public static let center = Alignment(horizontal: .center, vertical: .center)
    public static let leading = Alignment(horizontal: .leading, vertical: .center)
    public static let trailing = Alignment(horizontal: .trailing, vertical: .center)
    public static let top = Alignment(horizontal: .center, vertical: .top)
    public static let bottom = Alignment(horizontal: .center, vertical: .bottom)
    public static let topLeading = Alignment(horizontal: .leading, vertical: .top)
    public static let topTrailing = Alignment(horizontal: .trailing, vertical: .top)
    public static let bottomLeading = Alignment(horizontal: .leading, vertical: .bottom)
    public static let bottomTrailing = Alignment(horizontal: .trailing, vertical: .bottom)
    public static let centerFirstTextBaseline = Alignment(horizontal: .center, vertical: .firstTextBaseline)
    public static let centerLastTextBaseline = Alignment(horizontal: .center, vertical: .lastTextBaseline)
    public static let leadingFirstTextBaseline = Alignment(horizontal: .leading, vertical: .firstTextBaseline)
    public static let leadingLastTextBaseline = Alignment(horizontal: .leading, vertical: .lastTextBaseline)
    public static let trailingFirstTextBaseline = Alignment(horizontal: .trailing, vertical: .firstTextBaseline)
    public static let trailingLastTextBaseline = Alignment(horizontal: .trailing, vertical: .lastTextBaseline)
}

package final class ExplicitGuides {
    private let lookup: (AlignmentKey) -> CGFloat?
    private var memo: [AlignmentKey: CGFloat?] = [:]

    package init(_ lookup: @escaping (AlignmentKey) -> CGFloat?) { self.lookup = lookup }

    package func value(_ key: AlignmentKey) -> CGFloat? {
        if let v = memo[key] { return v }
        let v = lookup(key)
        memo[key] = .some(v)
        return v
    }
}

public struct ViewDimensions: Equatable {
    package let size: CGSize
    package let guides: ExplicitGuides?

    package init(size: CGSize, guides: ExplicitGuides? = nil) {
        self.size = size
        self.guides = guides
    }

    public var width: CGFloat { size.width }
    public var height: CGFloat { size.height }

    public subscript(guide: HorizontalAlignment) -> CGFloat { self[key: guide.key] }
    public subscript(guide: VerticalAlignment) -> CGFloat { self[key: guide.key] }
    public subscript(explicit guide: HorizontalAlignment) -> CGFloat? { explicitValue(guide.key) }
    public subscript(explicit guide: VerticalAlignment) -> CGFloat? { explicitValue(guide.key) }

    package subscript(key key: AlignmentKey) -> CGFloat {
        explicitValue(key) ?? key.defaultValue(in: ViewDimensions(size: size))
    }

    package func explicitValue(_ key: AlignmentKey) -> CGFloat? { guides?.value(key) }

    public static func == (lhs: ViewDimensions, rhs: ViewDimensions) -> Bool {
        lhs.size == rhs.size && lhs.guides === rhs.guides
    }
}
