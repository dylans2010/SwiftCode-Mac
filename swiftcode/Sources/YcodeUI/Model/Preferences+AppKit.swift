import AppKit
import YcodeIDECore

extension Preferences {
    public var nsAppearance: NSAppearance? {
        switch appearance { case .system: nil; case .light: NSAppearance(named: .aqua); case .dark: NSAppearance(named: .darkAqua) }
    }

    public func codeClick(for flags: NSEvent.ModifierFlags) -> CodeClick? { codeClick(forModifiers: MenuCommand.Modifiers(flags)) }

    public func navigationTarget(modifiers: NSEvent.ModifierFlags, clickCount: Int = 1) -> NavigationTarget {
        navigationTarget(keys: MenuCommand.Modifiers(modifiers), clickCount: clickCount)
    }
}

extension MenuCommand.Modifiers {
    public init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.control) { insert(.control) }
    }
}

extension EditorTheme.FontSpec {
    public var font: NSFont { NSFont.editorFont(self) }
}

extension EditorTheme {
    public var font: NSFont { fontSpec.font }

    public var consoleFont: NSFont { consoleFontSpec.font }

    public static func color(_ hex: String?) -> NSColor? { themeColor(hex).map(NSColor.init(themeColor:)) }

    public static func hex(_ c: NSColor) -> String {
        let s = c.usingColorSpace(.sRGB) ?? c
        return String(format: "#%02X%02X%02X", Int((s.redComponent * 255).rounded()), Int((s.greenComponent * 255).rounded()), Int((s.blueComponent * 255).rounded()))
    }
}

extension NSColor {
    public convenience init(themeColor c: ThemeColor) {
        self.init(srgbRed: CGFloat(c.red) / 255, green: CGFloat(c.green) / 255, blue: CGFloat(c.blue) / 255, alpha: 1)
    }
}

extension NSFont {
    static func editorFont(_ spec: EditorTheme.FontSpec) -> NSFont {
        let s = CGFloat(spec.size)
        return spec.name.isEmpty ? .monospacedSystemFont(ofSize: s, weight: .regular) : (NSFont(name: spec.name, size: s) ?? .monospacedSystemFont(ofSize: s, weight: .regular))
    }
}
