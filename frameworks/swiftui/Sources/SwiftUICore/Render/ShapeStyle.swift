import Foundation
import OVRender

public protocol ShapeStyle: Sendable {
    associatedtype Resolved: ShapeStyle = Never
    func resolve(in environment: EnvironmentValues) -> Resolved
}

extension Never: ShapeStyle {
    public typealias Resolved = Never
}

extension ShapeStyle where Resolved == Never {
    public func resolve(in environment: EnvironmentValues) -> Never {
        fatalError("\(Self.self) is resolved by the renderer")
    }
}

package protocol PaintableShapeStyle {
    func _paint(bounds: CGRect, environment: EnvironmentValues) -> RenderPaint?
}

package func resolvePaint(_ style: any ShapeStyle, bounds: CGRect, environment: EnvironmentValues, depth: Int = 0) -> RenderPaint? {
    if let p = style as? PaintableShapeStyle { return p._paint(bounds: bounds, environment: environment) }
    guard depth < 16 else { return nil }
    func open<S: ShapeStyle>(_ s: S) -> (any ShapeStyle)? { S.Resolved.self == Never.self ? nil : s.resolve(in: environment) }
    guard let r = open(style) else { return nil }
    return resolvePaint(r, bounds: bounds, environment: environment, depth: depth + 1)
}

extension Color.Resolved {
    package var renderColor: RenderColor {
        RenderColor(red: Double(red), green: Double(green), blue: Double(blue), alpha: Double(opacity))
    }
}

extension Color: ShapeStyle, PaintableShapeStyle {
    package func _paint(bounds: CGRect, environment: EnvironmentValues) -> RenderPaint? {
        .color(resolve(in: environment).renderColor)
    }
}

extension Color.Resolved: ShapeStyle, PaintableShapeStyle {
    public func resolve(in environment: EnvironmentValues) -> Never { fatalError("Color.Resolved is resolved") }
    package func _paint(bounds: CGRect, environment: EnvironmentValues) -> RenderPaint? { .color(renderColor) }
}

extension ShapeStyle where Self == Color {
    public static var red: Color { Color.red }
    public static var orange: Color { Color.orange }
    public static var yellow: Color { Color.yellow }
    public static var green: Color { Color.green }
    public static var mint: Color { Color.mint }
    public static var teal: Color { Color.teal }
    public static var cyan: Color { Color.cyan }
    public static var blue: Color { Color.blue }
    public static var indigo: Color { Color.indigo }
    public static var purple: Color { Color.purple }
    public static var pink: Color { Color.pink }
    public static var brown: Color { Color.brown }
    public static var white: Color { Color.white }
    public static var gray: Color { Color.gray }
    public static var black: Color { Color.black }
    public static var clear: Color { Color.clear }
}

public struct AnyShapeStyle: ShapeStyle, PaintableShapeStyle {
    package let base: any ShapeStyle
    public init<S: ShapeStyle>(_ style: S) { base = (style as? AnyShapeStyle)?.base ?? style }
    package func _paint(bounds: CGRect, environment: EnvironmentValues) -> RenderPaint? {
        resolvePaint(base, bounds: bounds, environment: environment)
    }
}

public struct ForegroundStyle: ShapeStyle, PaintableShapeStyle {
    public init() {}
    package func _paint(bounds: CGRect, environment: EnvironmentValues) -> RenderPaint? {
        environment.foregroundPaint(bounds: bounds, level: 0)
    }
}

public struct HierarchicalShapeStyle: ShapeStyle, PaintableShapeStyle {
    package let level: Int
    public static let primary = HierarchicalShapeStyle(level: 0)
    public static let secondary = HierarchicalShapeStyle(level: 1)
    public static let tertiary = HierarchicalShapeStyle(level: 2)
    public static let quaternary = HierarchicalShapeStyle(level: 3)
    public static let quinary = HierarchicalShapeStyle(level: 4)
    package func _paint(bounds: CGRect, environment: EnvironmentValues) -> RenderPaint? {
        environment.foregroundPaint(bounds: bounds, level: level)
    }
}

package struct RelativeForegroundStyle: ShapeStyle, PaintableShapeStyle {
    package let level: Int
    package let outer: AnyShapeStyle?
    package func _paint(bounds: CGRect, environment: EnvironmentValues) -> RenderPaint? {
        var env = environment
        env.foregroundStyle = outer
        return env.foregroundPaint(bounds: bounds, level: level)
    }
}

public struct TintShapeStyle: ShapeStyle, PaintableShapeStyle {
    public init() {}
    package func _paint(bounds: CGRect, environment: EnvironmentValues) -> RenderPaint? {
        if let t = environment.tintStyle { return resolvePaint(t, bounds: bounds, environment: environment) }
        return .color(Color.accentColor.resolve(in: environment).renderColor)
    }
}

public struct BackgroundStyle: ShapeStyle, PaintableShapeStyle {
    public init() {}
    package func _paint(bounds: CGRect, environment: EnvironmentValues) -> RenderPaint? {
        .color(environment.colorScheme == .dark ? .black : .white)
    }
}

package struct OpacityShapeStyle: ShapeStyle, PaintableShapeStyle {
    let base: any ShapeStyle
    let opacity: Double
    package func _paint(bounds: CGRect, environment: EnvironmentValues) -> RenderPaint? {
        resolvePaint(base, bounds: bounds, environment: environment)?.multiplyingOpacity(opacity)
    }
}

extension ShapeStyle where Self == ForegroundStyle {
    public static var foreground: ForegroundStyle { ForegroundStyle() }
}

extension ShapeStyle where Self == HierarchicalShapeStyle {
    public static var primary: HierarchicalShapeStyle { .primary }
    public static var secondary: HierarchicalShapeStyle { .secondary }
    public static var tertiary: HierarchicalShapeStyle { .tertiary }
    public static var quaternary: HierarchicalShapeStyle { .quaternary }
    public static var quinary: HierarchicalShapeStyle { .quinary }
}

extension ShapeStyle where Self == TintShapeStyle {
    public static var tint: TintShapeStyle { TintShapeStyle() }
}

extension ShapeStyle where Self == BackgroundStyle {
    public static var background: BackgroundStyle { BackgroundStyle() }
}

extension ShapeStyle {
    public func opacity(_ opacity: Double) -> some ShapeStyle { AnyShapeStyle(OpacityShapeStyle(base: self, opacity: opacity)) }
}

private enum ForegroundStyleKey: EnvironmentKey { static let defaultValue: AnyShapeStyle? = nil }
private enum TintStyleKey: EnvironmentKey { static let defaultValue: AnyShapeStyle? = nil }

extension EnvironmentValues {
    package var foregroundStyle: AnyShapeStyle? {
        get { self[ForegroundStyleKey.self] }
        set { self[ForegroundStyleKey.self] = newValue }
    }

    package var tintStyle: AnyShapeStyle? {
        get { self[TintStyleKey.self] }
        set { self[TintStyleKey.self] = newValue }
    }

    package static let hierarchyOpacity: [Double] = [1, 0.6, 0.3, 0.18, 0.08]

    package func foregroundPaint(bounds: CGRect, level: Int) -> RenderPaint? {
        let l = max(0, min(level, Self.hierarchyOpacity.count - 1))
        if let s = foregroundStyle {
            if let h = s.base as? HierarchicalShapeStyle {
                var outer = self
                outer.foregroundStyle = nil
                return outer.foregroundPaint(bounds: bounds, level: l + h.level)
            }
            if let r = s.base as? RelativeForegroundStyle {
                var outer = self
                outer.foregroundStyle = r.outer
                return outer.foregroundPaint(bounds: bounds, level: l + r.level)
            }
            return resolvePaint(s.base, bounds: bounds, environment: self)?.multiplyingOpacity(Self.hierarchyOpacity[l])
        }
        switch l {
        case 0: return .color(Color.primary.resolve(in: self).renderColor)
        case 1: return .color(Color.secondary.resolve(in: self).renderColor)
        default:
            return .color(Color.secondary.resolve(in: self).renderColor.withAlpha(Self.hierarchyOpacity[l] / 0.6))
        }
    }
}

extension View {
    public func foregroundStyle<S: ShapeStyle>(_ style: S) -> some View {
        let any = AnyShapeStyle(style)
        return transformEnvironment(\.foregroundStyle) { current in
            if let h = any.base as? HierarchicalShapeStyle, let outer = current {
                current = AnyShapeStyle(RelativeForegroundStyle(level: h.level, outer: outer))
            } else {
                current = any
            }
        }
    }

    public func foregroundStyle<S1: ShapeStyle, S2: ShapeStyle>(_ primary: S1, _ secondary: S2) -> some View {
        environment(\.foregroundStyle, AnyShapeStyle(primary))
    }

    public func foregroundColor(_ color: Color?) -> some View {
        environment(\.foregroundStyle, color.map { AnyShapeStyle($0) })
    }

    public func tint<S: ShapeStyle>(_ tint: S?) -> some View {
        environment(\.tintStyle, tint.map { AnyShapeStyle($0) })
    }

    public func tint(_ tint: Color?) -> some View {
        environment(\.tintStyle, tint.map { AnyShapeStyle($0) })
    }
}

public struct Gradient: Equatable, Hashable, Sendable {
    public struct Stop: Equatable, Hashable, Sendable {
        public var color: Color
        public var location: CGFloat
        public init(color: Color, location: CGFloat) {
            self.color = color
            self.location = location
        }
    }
    public var stops: [Stop]
    public init(stops: [Stop]) { self.stops = stops }
    public init(colors: [Color]) {
        let n = colors.count
        stops = colors.enumerated().map { Stop(color: $0.element, location: n > 1 ? CGFloat($0.offset) / CGFloat(n - 1) : 0) }
    }

    package func renderStops(_ env: EnvironmentValues) -> [RenderGradientStop] {
        stops.map { RenderGradientStop(color: $0.color.resolve(in: env).renderColor, location: Double($0.location)) }
    }
}

extension UnitPoint {
    package func point(in rect: CGRect) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
}

public struct LinearGradient: ShapeStyle, PaintableShapeStyle, View, Sendable {
    nonisolated package let gradient: Gradient
    nonisolated package let startPoint: UnitPoint
    nonisolated package let endPoint: UnitPoint
    nonisolated public init(gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) {
        self.gradient = gradient
        self.startPoint = startPoint
        self.endPoint = endPoint
    }
    nonisolated public init(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(gradient: Gradient(colors: colors), startPoint: startPoint, endPoint: endPoint)
    }
    nonisolated public init(stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(gradient: Gradient(stops: stops), startPoint: startPoint, endPoint: endPoint)
    }
    nonisolated package func _paint(bounds: CGRect, environment: EnvironmentValues) -> RenderPaint? {
        .linearGradient(stops: gradient.renderStops(environment), start: startPoint.point(in: bounds), end: endPoint.point(in: bounds), spread: .pad)
    }
    public var body: some View { Rectangle().fill(self) }
}

public struct RadialGradient: ShapeStyle, PaintableShapeStyle, View, Sendable {
    nonisolated package let gradient: Gradient
    nonisolated package let center: UnitPoint
    nonisolated package let startRadius: CGFloat
    nonisolated package let endRadius: CGFloat
    nonisolated public init(gradient: Gradient, center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) {
        self.gradient = gradient
        self.center = center
        self.startRadius = startRadius
        self.endRadius = endRadius
    }
    nonisolated public init(colors: [Color], center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) {
        self.init(gradient: Gradient(colors: colors), center: center, startRadius: startRadius, endRadius: endRadius)
    }
    nonisolated public init(stops: [Gradient.Stop], center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) {
        self.init(gradient: Gradient(stops: stops), center: center, startRadius: startRadius, endRadius: endRadius)
    }
    nonisolated package func _paint(bounds: CGRect, environment: EnvironmentValues) -> RenderPaint? {
        .radialGradient(stops: gradient.renderStops(environment), center: center.point(in: bounds),
                        startRadius: Double(startRadius), endRadius: Double(endRadius), spread: .pad)
    }
    public var body: some View { Rectangle().fill(self) }
}

public struct EllipticalGradient: ShapeStyle, PaintableShapeStyle, View, Sendable {
    nonisolated package let gradient: Gradient
    nonisolated package let center: UnitPoint
    nonisolated package let startRadiusFraction: CGFloat
    nonisolated package let endRadiusFraction: CGFloat
    nonisolated public init(gradient: Gradient, center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) {
        self.gradient = gradient
        self.center = center
        self.startRadiusFraction = startRadiusFraction
        self.endRadiusFraction = endRadiusFraction
    }
    nonisolated public init(colors: [Color], center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) {
        self.init(gradient: Gradient(colors: colors), center: center, startRadiusFraction: startRadiusFraction, endRadiusFraction: endRadiusFraction)
    }
    nonisolated package func _paint(bounds: CGRect, environment: EnvironmentValues) -> RenderPaint? {
        let m = Double(min(bounds.width, bounds.height))
        return .radialGradient(stops: gradient.renderStops(environment), center: center.point(in: bounds),
                               startRadius: Double(startRadiusFraction) * m, endRadius: Double(endRadiusFraction) * m, spread: .pad)
    }
    public var body: some View { Rectangle().fill(self) }
}

public struct AngularGradient: ShapeStyle, PaintableShapeStyle, View, Sendable {
    nonisolated package let gradient: Gradient
    nonisolated package let center: UnitPoint
    nonisolated package let startAngle: Angle
    nonisolated package let endAngle: Angle
    nonisolated public init(gradient: Gradient, center: UnitPoint, startAngle: Angle = .zero, endAngle: Angle = .zero) {
        self.gradient = gradient
        self.center = center
        self.startAngle = startAngle
        self.endAngle = endAngle == startAngle ? .radians(startAngle.radians + 2 * .pi) : endAngle
    }
    nonisolated public init(colors: [Color], center: UnitPoint, startAngle: Angle, endAngle: Angle) {
        self.init(gradient: Gradient(colors: colors), center: center, startAngle: startAngle, endAngle: endAngle)
    }
    nonisolated public init(stops: [Gradient.Stop], center: UnitPoint, startAngle: Angle, endAngle: Angle) {
        self.init(gradient: Gradient(stops: stops), center: center, startAngle: startAngle, endAngle: endAngle)
    }
    nonisolated public init(gradient: Gradient, center: UnitPoint, angle: Angle = .zero) {
        self.init(gradient: gradient, center: center, startAngle: angle, endAngle: .radians(angle.radians + 2 * .pi))
    }
    nonisolated public init(colors: [Color], center: UnitPoint, angle: Angle = .zero) {
        self.init(gradient: Gradient(colors: colors), center: center, angle: angle)
    }
    nonisolated package func _paint(bounds: CGRect, environment: EnvironmentValues) -> RenderPaint? {
        .conicGradient(stops: gradient.renderStops(environment), center: center.point(in: bounds),
                       startAngle: startAngle.radians, endAngle: endAngle.radians)
    }
    public var body: some View { Rectangle().fill(self) }
}

extension ShapeStyle where Self == LinearGradient {
    public static func linearGradient(_ gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) -> LinearGradient {
        LinearGradient(gradient: gradient, startPoint: startPoint, endPoint: endPoint)
    }
    public static func linearGradient(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: startPoint, endPoint: endPoint)
    }
    public static func linearGradient(stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint) -> LinearGradient {
        LinearGradient(stops: stops, startPoint: startPoint, endPoint: endPoint)
    }
}

extension ShapeStyle where Self == RadialGradient {
    public static func radialGradient(_ gradient: Gradient, center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) -> RadialGradient {
        RadialGradient(gradient: gradient, center: center, startRadius: startRadius, endRadius: endRadius)
    }
    public static func radialGradient(colors: [Color], center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) -> RadialGradient {
        RadialGradient(colors: colors, center: center, startRadius: startRadius, endRadius: endRadius)
    }
}

extension ShapeStyle where Self == AngularGradient {
    public static func angularGradient(_ gradient: Gradient, center: UnitPoint, startAngle: Angle, endAngle: Angle) -> AngularGradient {
        AngularGradient(gradient: gradient, center: center, startAngle: startAngle, endAngle: endAngle)
    }
    public static func angularGradient(colors: [Color], center: UnitPoint, startAngle: Angle, endAngle: Angle) -> AngularGradient {
        AngularGradient(colors: colors, center: center, startAngle: startAngle, endAngle: endAngle)
    }
    public static func conicGradient(_ gradient: Gradient, center: UnitPoint, angle: Angle = .zero) -> AngularGradient {
        AngularGradient(gradient: gradient, center: center, angle: angle)
    }
    public static func conicGradient(colors: [Color], center: UnitPoint, angle: Angle = .zero) -> AngularGradient {
        AngularGradient(colors: colors, center: center, angle: angle)
    }
}

extension ShapeStyle where Self == EllipticalGradient {
    public static func ellipticalGradient(_ gradient: Gradient, center: UnitPoint = .center, startRadiusFraction: CGFloat = 0,
                                          endRadiusFraction: CGFloat = 0.5) -> EllipticalGradient {
        EllipticalGradient(gradient: gradient, center: center, startRadiusFraction: startRadiusFraction, endRadiusFraction: endRadiusFraction)
    }
}
