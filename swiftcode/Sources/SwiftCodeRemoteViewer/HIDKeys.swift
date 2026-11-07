import Foundation

public enum HIDKeys {
    public static let keyboardPage: UInt16 = 7
    public static let leftShift: UInt16 = 0xE1

    public static func usage(sdlScancode s: Int32) -> UInt16? {
        (4...0xE7).contains(s) ? UInt16(s) : nil
    }

    public static func isModifier(_ usage: UInt16) -> Bool { (0xE0...0xE7).contains(usage) }

    public static func usage(for ch: Character) -> (usage: UInt16, shift: Bool)? {
        guard let a = ch.asciiValue else { return nil }
        switch a {
        case 0x61...0x7A: return (UInt16(a - 0x61) + 0x04, false)
        case 0x41...0x5A: return (UInt16(a - 0x41) + 0x04, true)
        case 0x31...0x39: return (UInt16(a - 0x31) + 0x1E, false)
        case 0x30: return (0x27, false)
        default: break
        }
        let plain: [Character: UInt16] = [
            "\n": 0x28, "\t": 0x2B, " ": 0x2C, "-": 0x2D, "=": 0x2E, "[": 0x2F, "]": 0x30, "\\": 0x31,
            ";": 0x33, "'": 0x34, "`": 0x35, ",": 0x36, ".": 0x37, "/": 0x38,
        ]
        if let u = plain[ch] { return (u, false) }
        let shifted: [Character: UInt16] = [
            "!": 0x1E, "@": 0x1F, "#": 0x20, "$": 0x21, "%": 0x22, "^": 0x23, "&": 0x24, "*": 0x25, "(": 0x26, ")": 0x27,
            "_": 0x2D, "+": 0x2E, "{": 0x2F, "}": 0x30, "|": 0x31, ":": 0x33, "\"": 0x34, "~": 0x35, "<": 0x36,
            ">": 0x37, "?": 0x38,
        ]
        if let u = shifted[ch] { return (u, true) }
        return nil
    }

    public static func events(typing text: String) -> [(usage: UInt16, down: Bool)] {
        var out: [(UInt16, Bool)] = []
        for ch in text {
            guard let (u, shift) = usage(for: ch) else { continue }
            if shift { out.append((leftShift, true)) }
            out.append((u, true))
            out.append((u, false))
            if shift { out.append((leftShift, false)) }
        }
        return out
    }
}
