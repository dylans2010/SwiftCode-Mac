// Ported from SwiftCode-Legacy `SwiftCode/Services/Color+Hex.swift` (Dylan's own code; direct port authorised under MIT).
// M-VUB supporting file: Color(hex: String) for the ported VUB files (VisualUIAssetsPanel, VisualUIRenderer).
// The same init already exists in the swiftcode-ide target (swiftcode/Sources/swiftcode-ide/Color+Hex.swift);
// that is a different module, so there is no collision — but if Color+Hex is ever hoisted into SwiftCodeUI
// properly, this file should be removed in favour of the single home.
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif


extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let r, g, b, a: Double
        switch cleaned.count {
        case 3:
            (r, g, b, a) = (
                Double((value >> 8) & 0xF) / 15,
                Double((value >> 4) & 0xF) / 15,
                Double(value & 0xF) / 15,
                1.0
            )
        case 6:
            (r, g, b, a) = (
                Double((value >> 16) & 0xFF) / 255,
                Double((value >> 8) & 0xFF) / 255,
                Double(value & 0xFF) / 255,
                1.0
            )
        case 8:
            (r, g, b, a) = (
                Double((value >> 24) & 0xFF) / 255,
                Double((value >> 16) & 0xFF) / 255,
                Double((value >> 8) & 0xFF) / 255,
                Double(value & 0xFF) / 255
            )
        default:
            (r, g, b, a) = (0.31, 0.53, 1.0, 1.0)
        }

        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

        var toHex: String {
        #if canImport(AppKit)
        let nsColor = NSColor(self)
        guard let rgbColor = nsColor.usingColorSpace(.sRGB) else { return "#4F86FF" }
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        rgbColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        #elseif canImport(UIKit)
        let uiColor = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else { return "#4F86FF" }
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        #else
        return "#4F86FF"
        #endif
    }
}
