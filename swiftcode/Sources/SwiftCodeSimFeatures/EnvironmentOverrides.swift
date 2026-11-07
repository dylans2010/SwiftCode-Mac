import Foundation

public struct EnvironmentOverrides: Equatable, Sendable {
    public enum Item: String, CaseIterable, Sendable {
        case appearance
        case dynamicType = "dynamic-type"
        case increaseContrast = "increase-contrast"
        case reduceTransparency = "reduce-transparency"
        case boldText = "bold-text"
        case reduceMotion = "reduce-motion"
        case onOffLabels = "on-off-labels"
        case buttonShapes = "button-shapes"
        case grayscale
        case smartInvert = "smart-invert"
        case differentiateWithoutColor = "differentiate-without-color"

        public var category: String {
            switch self {
            case .appearance: "Appearance"
            case .dynamicType: "Dynamic Type"
            default: "Accessibility"
            }
        }

        public var title: String {
            switch self {
            case .appearance: "Appearance"
            case .dynamicType: "Dynamic Type"
            case .increaseContrast: "Increase Contrast"
            case .reduceTransparency: "Reduce Transparency"
            case .boldText: "Bold Text"
            case .reduceMotion: "Reduce Motion"
            case .onOffLabels: "On/Off Labels"
            case .buttonShapes: "Button Shapes"
            case .grayscale: "Grayscale"
            case .smartInvert: "Smart Invert"
            case .differentiateWithoutColor: "Differentiate Without Color"
            }
        }

        public var choices: [(title: String, value: String)] {
            switch self {
            case .appearance: [("Light", "light"), ("Dark", "dark")]
            case .dynamicType:
                zip(["X Small", "Small", "Medium", "Large (Default)", "X Large", "XX Large", "XXX Large",
                     "Accessibility 1", "Accessibility 2", "Accessibility 3", "Accessibility 4", "Accessibility 5"],
                    ContentSize.allCases.map(\.rawValue)).map { ($0, $1) }
            case .increaseContrast: [("Increased", "on"), ("Default", "off")]
            case .reduceTransparency, .reduceMotion: [("Reduced", "on"), ("Default", "off")]
            default: [("Enabled", "on"), ("Disabled", "off")]
            }
        }

        public var isSwitch: Bool { self != .appearance && self != .dynamicType }
    }

    public static let noOverride = "No Override"
    public static let changedNotification = "dev.swiftcode.environment-overrides.changed"
    public static let directoryVariable = "SWIFTCODE_ENV_OVERRIDES_DIR"
    public static let libraryName = "libSwiftCodeEnvironmentOverrides.dylib"

    public var values: [Item: String] = [:]

    public init(values: [Item: String] = [:]) { self.values = values }

    public var isEmpty: Bool { values.isEmpty }

    public static func validate(_ item: Item, _ value: String) -> Bool {
        item.choices.contains { $0.value == value }
    }

    public var plist: [String: Any] {
        var out: [String: Any] = [:]
        for (item, v) in values {
            if item.isSwitch { out[item.rawValue] = v == "on" } else if item == .dynamicType {
                out[item.rawValue] = ContentSize(rawValue: v)?.categoryName ?? v
            } else {
                out[item.rawValue] = v
            }
        }
        return out
    }

    public init(plist: [String: Any]) {
        for item in Item.allCases {
            guard let o = plist[item.rawValue] else { continue }
            if item.isSwitch {
                if let b = o as? Bool { values[item] = b ? "on" : "off" }
                else if let n = o as? NSNumber { values[item] = n.boolValue ? "on" : "off" }
            } else if let s = o as? String {
                values[item] = item == .dynamicType ? (ContentSize(categoryName: s)?.rawValue ?? s) : s
            }
        }
    }

    public var words: [String] {
        Item.allCases.compactMap { i in values[i].map { "\(i.rawValue)=\($0)" } }
    }

    public enum Request: Equatable, Sendable {
        case show
        case clear
        case set([Item: String?])

        public static func parse(_ w: [String]) throws -> Request {
            if w.isEmpty || w == ["show"] { return .show }
            if w == ["clear"] { return .clear }
            var changes: [Item: String?] = [:]
            for word in w {
                let parts = word.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2, let item = Item(rawValue: parts[0]) else {
                    throw SimSettingsCommand.ParseError("overrides: \(word): expected <item>=<value> with item "
                        + Item.allCases.map(\.rawValue).joined(separator: "|"))
                }
                if parts[1] == "none" { changes[item] = .some(nil); continue }
                guard EnvironmentOverrides.validate(item, parts[1]) else {
                    throw SimSettingsCommand.ParseError("overrides: \(item.rawValue): one of none|"
                        + item.choices.map(\.value).joined(separator: "|"))
                }
                changes[item] = .some(parts[1])
            }
            return .set(changes)
        }
    }

    public struct Sections: Equatable, Sendable {
        public var appearance: Appearance?
        public var dynamicType: ContentSize?
        public var accessibility: [Item: Bool]?
        public init(appearance: Appearance? = nil, dynamicType: ContentSize? = nil, accessibility: [Item: Bool]? = nil) {
            self.appearance = appearance
            self.dynamicType = dynamicType
            self.accessibility = accessibility
        }
    }

    public static let accessibilityItems = Item.allCases.filter(\.isSwitch)

    public init(sections s: Sections) {
        if let a = s.appearance { values[.appearance] = a.rawValue }
        if let d = s.dynamicType { values[.dynamicType] = d.rawValue }
        if let checks = s.accessibility {
            for i in Self.accessibilityItems { values[i] = checks[i] == true ? "on" : "off" }
        }
    }

    public var sections: Sections {
        var s = Sections()
        s.appearance = values[.appearance].flatMap(Appearance.init(rawValue:))
        s.dynamicType = values[.dynamicType].flatMap(ContentSize.init(rawValue:))
        let set = Self.accessibilityItems.filter { values[$0] != nil }
        if !set.isEmpty { s.accessibility = Dictionary(uniqueKeysWithValues: Self.accessibilityItems.map { ($0, values[$0] == "on") }) }
        return s
    }

    public func commandWords(bundleID: String) -> [String] {
        let w = Item.allCases.map { i in "\(i.rawValue)=\(values[i] ?? "none")" }
        return ["overrides", bundleID] + (isEmpty ? ["clear"] : w)
    }

    public mutating func apply(_ request: Request) {
        switch request {
        case .show: break
        case .clear: values = [:]
        case .set(let changes):
            for (item, v) in changes { values[item] = v }
        }
    }
}
