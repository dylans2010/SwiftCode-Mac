import AppKit
import SwiftCodeIDECore
import SwiftCodeSyntax

@MainActor
enum DefaultLightTheme {
    static var applies: Bool {
        let t = Theme.current
        return t.name == EditorTheme.builtIns[0].name && t.tokens.isEmpty && t.foreground == nil
    }

    static let lightHex: [SyntaxTokenKind.Role: String] = [
        .keyword: "#C4246E", .comment: "#6A7084", .string: "#CA2B1C", .number: "#0178B8", .typeName: "#9D31CF",
    ]
    static let plainHex = "#322529"
    static let lineNumberHex = "#B8B3B4"
    static let typeDeclarationHex = "#007D9E"
    static let otherDeclarationHex = "#006178"

    private static var cache: [String: NSColor] = [:]

    static func dynamic(_ hex: String, dark: NSColor) -> NSColor {
        let key = hex + "|" + (dark.colorNameComponentIfAny ?? "\(ObjectIdentifier(dark))")
        if let c = cache[key] { return c }
        let light = EditorTheme.color(hex) ?? dark
        let c = NSColor(name: NSColor.Name("swiftcode.default." + hex)) { a in
            a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
        cache[key] = c
        return c
    }

    static var plain: NSColor { dynamic(plainHex, dark: .textColor) }
    static var lineNumber: NSColor { dynamic(lineNumberHex, dark: .secondaryLabelColor) }
    static var typeDeclaration: NSColor { dynamic(typeDeclarationHex, dark: .textColor) }
    static var otherDeclaration: NSColor { dynamic(otherDeclarationHex, dark: .textColor) }

    static let typeDeclarationKeywords: Set<String> = ["struct", "class", "enum", "protocol", "actor", "typealias", "associatedtype"]
    static let otherDeclarationKeywords: Set<String> = ["let", "var", "func", "case", "macro"]

    static func colorDeclarations(_ tokens: [SyntaxToken], in storage: NSTextStorage, range: NSRange) {
        let ns = storage.string as NSString
        func isName(_ c: unichar, first: Bool) -> Bool {
            (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || (!first && c >= 48 && c <= 57) || c > 127
        }
        for t in tokens where t.kind == .keyword && NSMaxRange(t.range) <= ns.length {
            let k = ns.substring(with: t.range)
            let color: NSColor? = typeDeclarationKeywords.contains(k) ? typeDeclaration
                : (otherDeclarationKeywords.contains(k) ? otherDeclaration : nil)
            guard let color else { continue }
            var i = NSMaxRange(t.range)
            while i < ns.length, [32, 9].contains(ns.character(at: i)) { i += 1 }
            let start = i
            while i < ns.length, isName(ns.character(at: i), first: i == start) { i += 1 }
            let r = NSIntersectionRange(NSRange(location: start, length: i - start), range)
            if i > start, r.length > 0 { storage.addAttribute(.foregroundColor, value: color, range: r) }
        }
    }
}

private extension NSColor {
    var colorNameComponentIfAny: String? { type == .catalog ? catalogNameComponent : nil }
}
