import Foundation

@MainActor
public final class Preferences {
    public static let didChange = Notification.Name("SwiftCodePreferencesDidChange")
    public static var shared = Preferences()

    public let defaults: UserDefaults
    public let themesDirectory: URL

    public init(defaults: UserDefaults = .standard, themesDirectory: URL? = nil) {
        self.defaults = defaults
        self.themesDirectory = themesDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SwiftCode/Themes")
        registerFactoryDefaults()
    }

    package func changed() { NotificationCenter.default.post(name: Self.didChange, object: self) }

    public static let factoryDefaults: [String: Any] = ["minimap": true]

    public func registerFactoryDefaults() {
        defaults.register(defaults: Dictionary(uniqueKeysWithValues: Self.factoryDefaults.map { ("SwiftCode.\($0.key)", $0.value) }))
    }

    func get<T>(_ key: String, _ fallback: T) -> T { defaults.object(forKey: "SwiftCode.\(key)") as? T ?? fallback }
    func set(_ key: String, _ value: Any?) { defaults.set(value, forKey: "SwiftCode.\(key)"); changed() }

    public enum Appearance: String, CaseIterable, Sendable { case system = "System", light = "Light", dark = "Dark" }
    public var appearance: Appearance {
        get { Appearance(rawValue: get("appearance", "System")) ?? .system }
        set { set("appearance", newValue.rawValue) }
    }
    public enum FileExtensions: String, CaseIterable, Sendable { case hide = "Hide All", show = "Show All" }
    public var fileExtensions: FileExtensions {
        get { FileExtensions(rawValue: get("fileExtensions", FileExtensions.hide.rawValue)) ?? .hide }
        set { set("fileExtensions", newValue.rawValue) }
    }
    public var showLiveIssues: Bool { get { get("showLiveIssues", true) } set { set("showLiveIssues", newValue) } }

    public enum Event: String, CaseIterable, Sendable {
        case buildStarts = "When build starts", buildErrors = "When build generates errors"
        case buildWarnings = "When build generates warnings", buildSucceeds = "When build succeeds", buildFails = "When build fails"
        case runStarts = "When running starts", runPauses = "When running pauses", runOutput = "When running generates output"
        case runEnds = "When running completes", runExitsUnexpectedly = "When running exits unexpectedly"
        case testSucceeds = "When testing succeeds", testFails = "When testing fails"

        public var category: String { rawValue.contains("build") ? "Build" : (rawValue.contains("testing") ? "Testing" : "Running") }
    }

    public static let behaviorCategories = ["Build", "Testing", "Running", "Search", "Localization Import / Export", "File",
                                            "Intelligence", "Playgrounds"]

    nonisolated public static let showDebuggerAction = "Debugger: Show Current Views"
    nonisolated public static let hideDebuggerAction = "Debugger: Hide Debugger"
    nonisolated public static let hideDebuggerIfNoOutputAction = "Debugger: Hide Debugger If No Output"
    nonisolated public static let notifyAction = "Notify with bezel or system notification"

    public struct Behavior: Codable, Equatable, Sendable {
        public var showNavigator: Int?
        public var showDebugArea: Bool?
        public var sound: String?
        public var notify = false
        public var hideDebugAreaIfNoOutput = false
        public init(showNavigator: Int? = nil, showDebugArea: Bool? = nil, sound: String? = nil, notify: Bool = false,
                    hideDebugAreaIfNoOutput: Bool = false) {
            self.showNavigator = showNavigator
            self.showDebugArea = showDebugArea
            self.sound = sound
            self.notify = notify
            self.hideDebugAreaIfNoOutput = hideDebugAreaIfNoOutput
        }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            showNavigator = try c.decodeIfPresent(Int.self, forKey: .showNavigator)
            showDebugArea = try c.decodeIfPresent(Bool.self, forKey: .showDebugArea)
            sound = try c.decodeIfPresent(String.self, forKey: .sound)
            notify = try c.decodeIfPresent(Bool.self, forKey: .notify) ?? false
            hideDebugAreaIfNoOutput = try c.decodeIfPresent(Bool.self, forKey: .hideDebugAreaIfNoOutput) ?? false
        }

        public var actionTitles: [String] {
            var a: [String] = []
            if let n = showNavigator, CommandTable.navigators.indices.contains(n) { a.append("Navigator: \(CommandTable.navigators[n])") }
            if let d = showDebugArea { a.append(d ? Preferences.showDebuggerAction : Preferences.hideDebuggerAction) }
            if hideDebugAreaIfNoOutput { a.append(Preferences.hideDebuggerIfNoOutputAction) }
            if let s = sound { a.append("Play Sound: \(s)") }
            if notify { a.append(Preferences.notifyAction) }
            return a
        }
    }

    public static let defaultBehaviors: [Event: Behavior] = [
        .buildErrors: Behavior(showNavigator: 4), .buildSucceeds: Behavior(notify: true), .buildFails: Behavior(notify: true),
        .runPauses: Behavior(showNavigator: 6, showDebugArea: true), .runOutput: Behavior(showDebugArea: true),
        .runEnds: Behavior(hideDebugAreaIfNoOutput: true),
        .testSucceeds: Behavior(notify: true), .testFails: Behavior(notify: true),
    ]

    public func behavior(_ e: Event) -> Behavior {
        if let data = defaults.data(forKey: "SwiftCode.behavior.\(e)"), let b = try? JSONDecoder().decode(Behavior.self, from: data) { return b }
        return Self.defaultBehaviors[e] ?? Behavior()
    }

    public func setBehavior(_ b: Behavior, for e: Event) {
        defaults.set(try? JSONEncoder().encode(b), forKey: "SwiftCode.behavior.\(e)")
        changed()
    }

    public var showLineNumbers: Bool { get { get("lineNumbers", true) } set { set("lineNumbers", newValue) } }
    public var showFoldingRibbon: Bool { get { get("foldingRibbon", false) } set { set("foldingRibbon", newValue) } }
    public var showMinimap: Bool { get { get("minimap", Self.factoryDefaults["minimap"] as? Bool ?? true) } set { set("minimap", newValue) } }
    public var showPageGuide: Bool { get { get("pageGuide", false) } set { set("pageGuide", newValue) } }
    public var pageGuideColumn: Int { get { get("pageGuideColumn", 80) } set { set("pageGuideColumn", max(1, newValue)) } }
    public var indentWithTabs: Bool { get { get("indentWithTabs", false) } set { set("indentWithTabs", newValue) } }
    public var tabWidth: Int { get { get("tabWidth", 4) } set { set("tabWidth", max(1, min(16, newValue))) } }
    public var indentWidth: Int { get { get("indentWidth", 4) } set { set("indentWidth", max(1, min(16, newValue))) } }
    public var trimTrailingWhitespace: Bool { get { get("trimWhitespace", true) } set { set("trimWhitespace", newValue) } }
    public var wrapLines: Bool { get { get("wrapLines", true) } set { set("wrapLines", newValue) } }
    public var wrappedLineIndent: Int { get { get("wrappedLineIndent", 4) } set { set("wrappedLineIndent", max(0, min(16, newValue))) } }
    public var highlightSelectedSymbol: Bool { get { get("highlightSelectedSymbol", true) } set { set("highlightSelectedSymbol", newValue) } }
    public var highlightDelay: Double { get { get("highlightDelay", 0.25) } set { set("highlightDelay", max(0, min(5, newValue))) } }
    public var showInvisibles: Bool { get { get("showInvisibles", false) } set { set("showInvisibles", newValue) } }
    public var showCodeCoverage: Bool { get { get("showCodeCoverage", false) } set { set("showCodeCoverage", newValue) } }
    public var trimWhitespaceOnlyLines: Bool { get { get("trimWhitespaceOnlyLines", false) } set { set("trimWhitespaceOnlyLines", newValue) } }

    public var sourceFontSize: Double? {
        get { (defaults.object(forKey: "SwiftCode.sourceFontSize") as? NSNumber)?.doubleValue }
        set { set("sourceFontSize", newValue.map { max(Self.fontSizeRange.lowerBound, min(Self.fontSizeRange.upperBound, $0)) }) }
    }
    public static let fontSizeRange: ClosedRange<Double> = 6...48

    public var indentUnit: String { indentWithTabs ? "\t" : String(repeating: " ", count: indentWidth) }

    public var autoIndent: Bool { get { get("autoIndent", true) } set { set("autoIndent", newValue) } }
    public var autoInsertClosers: Bool { get { get("autoInsertClosers", true) } set { set("autoInsertClosers", newValue) } }
    public var encloseSelection: Bool { get { get("encloseSelection", true) } set { set("encloseSelection", newValue) } }
    public var tabKeyBehavior: TabKeyBehavior {
        get { TabKeyBehavior(rawValue: get("tabKey", TabKeyBehavior.indentsInLeadingWhitespace.rawValue)) ?? .indentsInLeadingWhitespace }
        set { set("tabKey", newValue.rawValue) }
    }
    public var typingOptions: TypingOptions {
        TypingOptions(indent: IndentOptions(usesTabs: indentWithTabs, tabWidth: tabWidth, indentWidth: indentWithTabs ? tabWidth : indentWidth),
                      autoIndent: autoIndent, autoClose: autoInsertClosers, encloseSelection: encloseSelection, tabKey: tabKeyBehavior)
    }

    public var sourceControlEnabled: Bool { get { get("sourceControl", true) } set { set("sourceControl", newValue) } }

    public var showRegisters: Bool { get { get("showRegisters", false) } set { set("showRegisters", newValue) } }

    public var themeName: String {
        get { get("theme", EditorTheme.builtIns[0].name) }
        set { set("theme", newValue) }
    }

    public var themes: [EditorTheme] {
        let user = ((try? FileManager.default.contentsOfDirectory(at: themesDirectory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "swiftcodetheme" }
            .compactMap { try? EditorTheme.read($0) }
            .sorted { $0.name < $1.name }
        return EditorTheme.builtIns + user.filter { u in !EditorTheme.builtIns.contains { $0.name == u.name } }
    }

    public var theme: EditorTheme { themes.first { $0.name == themeName } ?? EditorTheme.builtIns[0] }

    public func save(_ t: EditorTheme) throws {
        guard !EditorTheme.builtIns.contains(where: { $0.name == t.name }) else { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.createDirectory(at: themesDirectory, withIntermediateDirectories: true)
        try t.write(to: themesDirectory.appendingPathComponent(t.fileName))
        themeName = t.name
    }

    @discardableResult
    public func duplicate(_ t: EditorTheme) throws -> EditorTheme {
        var copy = t
        var n = "\(t.name) Copy", i = 2
        while themes.contains(where: { $0.name == n }) { n = "\(t.name) Copy \(i)"; i += 1 }
        copy.name = n
        try save(copy)
        return copy
    }

    public func deleteTheme(named name: String) {
        guard let t = themes.first(where: { $0.name == name }), !EditorTheme.builtIns.contains(where: { $0.name == name }) else { return }
        try? FileManager.default.removeItem(at: themesDirectory.appendingPathComponent(t.fileName))
        if themeName == name { themeName = EditorTheme.builtIns[0].name } else { changed() }
    }

    @discardableResult
    public func importTheme(from url: URL) throws -> EditorTheme {
        let t = try EditorTheme.read(url)
        try save(t)
        return t
    }

    public func exportTheme(_ t: EditorTheme, to url: URL) throws { try t.write(to: url) }

    public struct Shortcut: Codable, Equatable, Hashable, Sendable {
        public var key: String
        public var modifiers: Int
        public init(key: String, modifiers: MenuCommand.Modifiers) {
            self.key = key.lowercased()
            self.modifiers = modifiers.rawValue
        }
        public var mods: MenuCommand.Modifiers { MenuCommand.Modifiers(rawValue: modifiers) }
    }

    public var keyBindingOverrides: [String: Shortcut] {
        get {
            guard let d = defaults.data(forKey: "SwiftCode.keyBindings"), let m = try? JSONDecoder().decode([String: Shortcut].self, from: d) else { return [:] }
            return m
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "SwiftCode.keyBindings"); changed() }
    }
}

public struct EditorTheme: Codable, Equatable, Sendable {
    public var name: String
    public var fontName: String
    public var fontSize: Double
    public var background: String?
    public var foreground: String?
    public var selection: String?
    public var currentLine: String?
    public var tokens: [String: String]
    public var consoleFontName: String
    public var consoleFontSize: Double
    public var consoleBackground: String?
    public var consoleText: String?
    public var tokenFonts: [String: FontSpec]?

    public struct FontSpec: Codable, Equatable, Sendable {
        public var name: String
        public var size: Double
        public init(name: String, size: Double) {
            self.name = name
            self.size = size
        }
    }

    public var fontSpec: FontSpec { FontSpec(name: fontName, size: fontSize) }
    public var consoleFontSpec: FontSpec { FontSpec(name: consoleFontName, size: consoleFontSize) }

    public var fileName: String { name.replacingOccurrences(of: "/", with: "-") + ".swiftcodetheme" }

    public static func read(_ url: URL) throws -> EditorTheme {
        try JSONDecoder().decode(EditorTheme.self, from: Data(contentsOf: url))
    }

    public func write(to url: URL) throws {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(self).write(to: url, options: .atomic)
    }

    public static func themeColor(_ hex: String?) -> ThemeColor? { ThemeColor(hex: hex) }

    public static let builtIns: [EditorTheme] = [
        EditorTheme(name: "SwiftCode Default", fontName: "", fontSize: 13, background: nil, foreground: nil, selection: nil, currentLine: nil,
                    tokens: [:], consoleFontName: "", consoleFontSize: 11, consoleBackground: nil, consoleText: nil),
        EditorTheme(name: "SwiftCode Paper", fontName: "", fontSize: 13, background: "#FBF8F1", foreground: "#2B2A27", selection: "#E3DCC8", currentLine: "#F2ECDD",
                    tokens: ["keyword": "#8A2D5E", "comment": "#8C8778", "docComment": "#5E7A3A", "string": "#A3471B", "number": "#2F5E9E",
                             "preprocessor": "#9A5B12", "attribute": "#6E5A2E", "typeName": "#4E3F94"],
                    consoleFontName: "", consoleFontSize: 11, consoleBackground: "#FBF8F1", consoleText: "#2B2A27"),
        EditorTheme(name: "SwiftCode Dusk", fontName: "", fontSize: 12, background: "#1E2128", foreground: "#D8DCE3", selection: "#3A4252", currentLine: "#262A33",
                    tokens: ["keyword": "#E58AB8", "comment": "#7A8291", "docComment": "#93B87A", "string": "#E9A37A", "number": "#8DB4F0",
                             "preprocessor": "#E2B86B", "attribute": "#C9A97A", "typeName": "#B9A6F2"],
                    consoleFontName: "", consoleFontSize: 11, consoleBackground: "#1A1C22", consoleText: "#D8DCE3"),
        EditorTheme(name: "SwiftCode High Contrast", fontName: "", fontSize: 13, background: "#000000", foreground: "#FFFFFF", selection: "#264F9E", currentLine: "#1A1A1A",
                    tokens: ["keyword": "#FF6FB5", "comment": "#B0B0B0", "docComment": "#7CFC7C", "string": "#FFB070", "number": "#7FD4FF",
                             "preprocessor": "#FFD75E", "attribute": "#E8C890", "typeName": "#C8A8FF"],
                    consoleFontName: "", consoleFontSize: 12, consoleBackground: "#000000", consoleText: "#FFFFFF"),
    ]
}

@MainActor
public enum KeyBindings {
    public struct Entry: Equatable, Sendable {
        public var id: String
        public var title: String
        public var menu: String
        public var command: MenuCommand
        public var customized: Bool
    }

    static func id(_ c: MenuCommand) -> String { "\(c.action)#\(c.tag)" }

    public static func entries(_ prefs: Preferences = .shared, includingUnavailable: Bool = false) -> [Entry] {
        let overrides = prefs.keyBindingOverrides
        var out: [Entry] = []
        func walk(_ items: [MenuItemSpec], _ path: String) {
            for i in items {
                switch i {
                case .separator, .label: break
                case .submenu(let t, let sub): walk(sub, path + " ▸ " + t)
                case .command(var c) where c.isAvailable || includingUnavailable:
                    let id = id(c)
                    if let o = overrides[id] { c.key = o.key; c.modifiers = o.key.isEmpty ? [] : o.mods }
                    out.append(Entry(id: id, title: c.title, menu: path, command: c, customized: overrides[id] != nil))
                case .command: break
                }
            }
        }
        for (menu, items) in CommandTable.menus { walk(items, menu) }
        return out
    }

    public static func search(_ q: String, _ prefs: Preferences = .shared) -> [Entry] {
        let t = q.lowercased()
        return entries(prefs).filter { t.isEmpty || $0.title.lowercased().contains(t) || $0.menu.lowercased().contains(t) || $0.command.shortcutText.lowercased().contains(t) }
    }

    public static func conflicts(key: String, modifiers: MenuCommand.Modifiers, excluding id: String, _ prefs: Preferences = .shared) -> [Entry] {
        guard !key.isEmpty else { return [] }
        let wanted = Shortcut.canonical(key: key, modifiers: modifiers)
        var seen = Set<String>()
        return entries(prefs, includingUnavailable: true).filter {
            $0.id != id && $0.command.canonicalShortcut == wanted && seen.insert($0.id).inserted
        }
    }

    @discardableResult
    public static func set(_ id: String, key: String, modifiers: MenuCommand.Modifiers, _ prefs: Preferences = .shared) -> [Entry] {
        let c = conflicts(key: key, modifiers: modifiers, excluding: id, prefs)
        guard c.isEmpty else { return c }
        var o = prefs.keyBindingOverrides
        o[id] = Preferences.Shortcut(key: key, modifiers: key.isEmpty ? [] : modifiers)
        prefs.keyBindingOverrides = o
        return []
    }

    public static func reset(_ id: String, _ prefs: Preferences = .shared) {
        var o = prefs.keyBindingOverrides
        o[id] = nil
        prefs.keyBindingOverrides = o
    }

    public static func effective(_ c: MenuCommand, _ prefs: Preferences = .shared) -> MenuCommand {
        guard let o = prefs.keyBindingOverrides[id(c)] else { return c }
        var c = c
        c.key = o.key
        c.modifiers = o.key.isEmpty ? [] : o.mods
        return c
    }
}

public struct ThemeColor: Equatable, Hashable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init?(hex: String?) {
        guard var h = hex?.trimmingCharacters(in: .whitespaces), !h.isEmpty else { return nil }
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(red: UInt8(v >> 16 & 0xFF), green: UInt8(v >> 8 & 0xFF), blue: UInt8(v & 0xFF))
    }

    public var hex: String { String(format: "#%02X%02X%02X", Int(red), Int(green), Int(blue)) }

    public var redFraction: Double { Double(red) / 255 }
    public var greenFraction: Double { Double(green) / 255 }
    public var blueFraction: Double { Double(blue) / 255 }
}
