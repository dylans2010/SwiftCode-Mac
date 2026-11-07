import Foundation

public enum ShortcutNotation: Sendable {
    case mac, linux

    public static var host: ShortcutNotation {
        #if os(Linux)
        .linux
        #else
        .mac
        #endif
    }

    public func text(key: String, modifiers: MenuCommand.Modifiers) -> String {
        guard !key.isEmpty else { return "" }
        switch self {
        case .mac: return Shortcut.text(key: key, modifiers: modifiers)
        case .linux:
            var k = key, m = modifiers
            if let base = Key.shiftedBase[k] { k = base; m.insert(.shift) }
            if k.count == 1, let ch = k.first, ch.isLetter, ch.isUppercase { k = k.lowercased(); m.insert(.shift) }
            var parts: [String] = []
            if m.contains(.command) && m.contains(.control) { parts.append("Super") }
            if m.contains(.command) || m.contains(.control) { parts.append("Ctrl") }
            if m.contains(.option) { parts.append("Alt") }
            if m.contains(.shift) { parts.append("Shift") }
            parts.append(Self.linuxKeyNames[k] ?? Key.names[k] ?? k.uppercased())
            return parts.joined(separator: "+")
        }
    }

    public func text(_ c: MenuCommand) -> String { text(key: c.key, modifiers: c.modifiers) }

    func canonical(key: String, modifiers: MenuCommand.Modifiers) -> String {
        guard !key.isEmpty else { return "" }
        return self == .mac ? Shortcut.canonical(key: key, modifiers: modifiers) : text(key: key, modifiers: modifiers)
    }

    static let linuxKeyNames: [String: String] = [
        Key.up: "Up", Key.down: "Down", Key.left: "Left", Key.right: "Right", Key.return: "Enter", Key.space: "Space",
        Key.delete: "Backspace", Key.tab: "Tab",
    ]
}

extension KeyBindings {
    public static func parse(_ text: String) -> (key: String, modifiers: MenuCommand.Modifiers)? {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return ("", []) }
        let words = t.count > 1 && t.contains("+") && t.contains(where: \.isLetter) && !t.contains(where: { "⌃⌥⇧⌘".contains($0) })
        var mods: MenuCommand.Modifiers = []
        var rest: String
        if words {
            var parts = t.split(separator: "+", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            if t.hasSuffix("++") { parts.removeLast(2); parts.append("+") }
            rest = parts.removeLast()
            for p in parts {
                switch p.lowercased() {
                case "ctrl", "cmd", "command": mods.insert(.command)
                case "super", "control", "meta": mods.insert(.control)
                case "alt", "option", "opt": mods.insert(.option)
                case "shift": mods.insert(.shift)
                default: return nil
                }
            }
        } else {
            var s = Substring(t)
            while let c = s.first, let m = Shortcut.modifier(c) {
                mods.insert(m)
                s = s.dropFirst()
            }
            rest = String(s)
        }
        guard let key = keyName(rest) else { return nil }
        return (key, mods)
    }

    static func keyName(_ name: String) -> String? {
        if name.isEmpty { return nil }
        if let (k, _) = Key.names.first(where: { $0.value == name }) { return k }
        if let (k, _) = ShortcutNotation.linuxKeyNames.first(where: { $0.value.lowercased() == name.lowercased() }) { return k }
        let aliases = ["return": Key.return, "delete": Key.delete, "del": Key.delete]
        if let a = aliases[name.lowercased()] { return a }
        if name.count > 1, name.first == "F" || name.first == "f", let n = Int(name.dropFirst()), (1...12).contains(n) { return Key.function(n) }
        guard name.count == 1 else { return nil }
        return name.lowercased()
    }

    public static func conflicts(key: String, modifiers: MenuCommand.Modifiers, excluding id: String, in notation: ShortcutNotation,
                                 _ prefs: Preferences = .shared) -> [Entry] {
        guard !key.isEmpty else { return [] }
        let wanted = notation.canonical(key: key, modifiers: modifiers)
        var seen = Set<String>()
        return entries(prefs, includingUnavailable: true).filter {
            $0.id != id && notation.canonical(key: $0.command.key, modifiers: $0.command.modifiers) == wanted && seen.insert($0.id).inserted
        }
    }

    @discardableResult
    public static func set(_ id: String, key: String, modifiers: MenuCommand.Modifiers, in notation: ShortcutNotation,
                           _ prefs: Preferences = .shared) -> [Entry] {
        let c = conflicts(key: key, modifiers: modifiers, excluding: id, in: notation, prefs)
        guard c.isEmpty else { return c }
        var o = prefs.keyBindingOverrides
        o[id] = Preferences.Shortcut(key: key, modifiers: key.isEmpty ? [] : modifiers)
        prefs.keyBindingOverrides = o
        return []
    }

    public static func conflictMessage(_ conflicts: [Entry]) -> String {
        guard !conflicts.isEmpty else { return "" }
        return "Already used by " + conflicts.map { "\($0.title) (\($0.menu))" }.joined(separator: ", ")
    }
}

extension Preferences.Behavior {
    public static func addableActions() -> [String] {
        CommandTable.navigators.map { "Navigator: \($0)" } + [Preferences.showDebuggerAction, Preferences.hideDebuggerAction,
            Preferences.hideDebuggerIfNoOutputAction, Preferences.notifyAction] + soundNames.map { "Play Sound: \($0)" }
    }

    public static let soundNames = ["Glass", "Basso", "Hero"]

    public mutating func add(action: String) {
        if action.hasPrefix("Navigator: ") { showNavigator = CommandTable.navigators.firstIndex(of: String(action.dropFirst(11))) }
        else if action == Preferences.showDebuggerAction { showDebugArea = true }
        else if action == Preferences.hideDebuggerAction { showDebugArea = false }
        else if action == Preferences.hideDebuggerIfNoOutputAction { hideDebugAreaIfNoOutput = true }
        else if action == Preferences.notifyAction { notify = true }
        else if action.hasPrefix("Play Sound: ") { sound = String(action.dropFirst(12)) }
    }

    public mutating func remove(action: String) {
        if action.hasPrefix("Navigator: ") { showNavigator = nil }
        else if action == Preferences.hideDebuggerIfNoOutputAction { hideDebugAreaIfNoOutput = false }
        else if action.hasPrefix("Debugger: ") { showDebugArea = nil }
        else if action == Preferences.notifyAction { notify = false }
        else if action.hasPrefix("Play Sound: ") { sound = nil }
    }
}

extension Preferences.Event {
    public var notificationTitle: String {
        let s = rawValue.replacingOccurrences(of: "When ", with: "")
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}

extension Preferences {
    @discardableResult
    public func editSelectedTheme(_ f: (inout EditorTheme) -> Void) -> Bool {
        var t = theme
        guard !EditorTheme.builtIns.contains(where: { $0.name == t.name }) else { return false }
        f(&t)
        return (try? save(t)) != nil
    }
}

public enum GitGlobalConfig {
    public static func value(_ key: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git", "config", "--global", "--get", key]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let d = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let s = String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return p.terminationStatus == 0 && !s.isEmpty ? s : nil
    }
}
