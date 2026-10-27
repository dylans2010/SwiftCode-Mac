import SwiftUI

public struct ModernGroupBoxStyle: GroupBoxStyle {
    public var cornerRadius: CGFloat
    public var style: LiquidGlassStyle
    public var tint: Color?

    public init(cornerRadius: CGFloat = 12, style: LiquidGlassStyle = .standard, tint: Color? = nil) {
        self.cornerRadius = cornerRadius
        self.style = style
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.label
                .font(.headline)
            configuration.content
        }
        .padding()
        .liquidGlass(style: style, cornerRadius: cornerRadius, tint: tint)
    }
}
