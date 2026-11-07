import Foundation
import Synchronization

private let environmentRevisionCounter = Atomic<UInt64>(0)

public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

public struct EnvironmentValues: CustomStringConvertible {
    private var storage: [ObjectIdentifier: Any] = [:]
    package private(set) var revision: UInt64 = 0

    public init() {}

    public subscript<K: EnvironmentKey>(key: K.Type) -> K.Value {
        get {
            guard let v = storage[ObjectIdentifier(key)] else { return K.defaultValue }
            return v as! K.Value
        }
        set {
            storage[ObjectIdentifier(key)] = newValue
            revision = environmentRevisionCounter.add(1, ordering: .relaxed).newValue
        }
    }

    public var description: String { "EnvironmentValues(\(storage.count) values set)" }
}

public enum ColorScheme: CaseIterable, Sendable, Equatable, Hashable {
    case light
    case dark
}

public enum ColorSchemeContrast: CaseIterable, Sendable, Equatable, Hashable {
    case standard
    case increased
}

public enum DynamicTypeSize: Hashable, Comparable, CaseIterable, Sendable {
    case xSmall, small, medium, large, xLarge, xxLarge, xxxLarge
    case accessibility1, accessibility2, accessibility3, accessibility4, accessibility5

    public var isAccessibilitySize: Bool { self >= .accessibility1 }
}

private enum ColorSchemeKey: EnvironmentKey { static let defaultValue = ColorScheme.light }
private enum ColorSchemeContrastKey: EnvironmentKey { static let defaultValue = ColorSchemeContrast.standard }
private enum LayoutDirectionKey: EnvironmentKey { static let defaultValue = LayoutDirection.leftToRight }
private enum DisplayScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 3 }
private enum DynamicTypeSizeKey: EnvironmentKey { static let defaultValue = DynamicTypeSize.large }

extension EnvironmentValues {
    public var colorScheme: ColorScheme {
        get { self[ColorSchemeKey.self] }
        set { self[ColorSchemeKey.self] = newValue }
    }

    public var colorSchemeContrast: ColorSchemeContrast {
        get { self[ColorSchemeContrastKey.self] }
        set { self[ColorSchemeContrastKey.self] = newValue }
    }

    public var layoutDirection: LayoutDirection {
        get { self[LayoutDirectionKey.self] }
        set { self[LayoutDirectionKey.self] = newValue }
    }

    public var displayScale: CGFloat {
        get { self[DisplayScaleKey.self] }
        set { self[DisplayScaleKey.self] = newValue }
    }

    public var pixelLength: CGFloat { 1 / displayScale }

    public var dynamicTypeSize: DynamicTypeSize {
        get { self[DynamicTypeSizeKey.self] }
        set { self[DynamicTypeSizeKey.self] = newValue }
    }
}
