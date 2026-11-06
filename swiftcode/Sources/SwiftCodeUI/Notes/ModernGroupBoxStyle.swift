import SwiftUI

// MARK: - Modern group-box style (Wave 19, slice C)
//
// Ported from Legacy `SwiftCode/UI/Styles/ModernGroupBoxStyle.swift`
// (Dylan's own code, ported under MIT), adapted to the destination:
// Legacy drew the box with its own `.liquidGlass(style:cornerRadius:tint:)`
// modifier, which has no destination equivalent — SwiftCode draws no glass
// of its own making (specs/ide/liquid-glass-swiftcode.md) and uses the
// system's materials through public API. This style uses `.thinMaterial`
// in a rounded rectangle with a hairline stroke instead. Legacy's
// `LiquidGlassStyle` / `tint` parameters are dropped; the only parameter
// is the corner radius.
//
// This also repairs the bulk wave's latent break: the DevTools views in
// `swiftcode-ide` call `ModernGroupBoxStyle()` but the type was never
// defined anywhere in the destination (its ledger row claims it was
// SUPERSEDED by `ShellStyle.swift`, which defines no `GroupBoxStyle`).
// See INTEGRATION.md.

public struct ModernGroupBoxStyle: GroupBoxStyle {
    public var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = 12) {
        self.cornerRadius = cornerRadius
    }

    public func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.label
                .font(.headline)
            configuration.content
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }
}
