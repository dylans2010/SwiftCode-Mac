import Foundation

public enum Axis: Int8, CaseIterable, CustomStringConvertible, Sendable {
    case horizontal = 0
    case vertical = 1

    public var otherAxis: Axis { self == .horizontal ? .vertical : .horizontal }

    public var perpendicularEdges: Edge.Set {
        self == .horizontal ? [.leading, .trailing] : [.top, .bottom]
    }

    public var description: String { self == .horizontal ? "horizontal" : "vertical" }

    public struct Set: OptionSet, Sendable, Hashable {
        public typealias Element = Axis.Set
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public static let horizontal = Axis.Set(rawValue: 1 << 0)
        public static let vertical = Axis.Set(rawValue: 1 << 1)

        package init(_ axis: Axis) { self = axis == .horizontal ? .horizontal : .vertical }
    }
}

public enum Edge: Int8, CaseIterable, Sendable, Hashable {
    case top = 0, leading = 1, bottom = 2, trailing = 3

    public struct Set: OptionSet, Sendable, Hashable {
        public typealias Element = Edge.Set
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public static let top = Edge.Set(rawValue: 1 << 0)
        public static let leading = Edge.Set(rawValue: 1 << 1)
        public static let bottom = Edge.Set(rawValue: 1 << 2)
        public static let trailing = Edge.Set(rawValue: 1 << 3)
        public static let all: Edge.Set = [.top, .leading, .bottom, .trailing]
        public static let horizontal: Edge.Set = [.leading, .trailing]
        public static let vertical: Edge.Set = [.top, .bottom]

        public init(_ edge: Edge) { self.init(rawValue: 1 << edge.rawValue) }
    }
}

public enum VerticalEdge: Int8, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case top = 0, bottom = 1

    public struct Set: OptionSet, Sendable, Hashable {
        public typealias Element = VerticalEdge.Set
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public static let top = Set(rawValue: 1 << 0)
        public static let bottom = Set(rawValue: 1 << 1)
        public static let all: Set = [.top, .bottom]
        public init(_ e: VerticalEdge) { self.init(rawValue: 1 << e.rawValue) }
    }
}

public enum HorizontalEdge: Int8, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case leading = 0, trailing = 1

    public struct Set: OptionSet, Sendable, Hashable {
        public typealias Element = HorizontalEdge.Set
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public static let leading = Set(rawValue: 1 << 0)
        public static let trailing = Set(rawValue: 1 << 1)
        public static let all: Set = [.leading, .trailing]
        public init(_ e: HorizontalEdge) { self.init(rawValue: 1 << e.rawValue) }
    }
}

public enum LayoutDirection: Hashable, CaseIterable, Sendable {
    case leftToRight
    case rightToLeft
}

public enum ContentMode: Hashable, CaseIterable, Sendable {
    case fit
    case fill
}
