import Foundation

public enum PrefValue: Equatable, Sendable, CustomStringConvertible {
    case bool(Bool)
    case int(Int)
    case real(Double)
    case string(String)

    public var plistObject: Any {
        switch self {
        case .bool(let b): b
        case .int(let i): i
        case .real(let d): d
        case .string(let s): s
        }
    }

    public init?(plistObject o: Any) {
        if let s = o as? String { self = .string(s); return }
        #if canImport(Darwin)
        if let n = o as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue); return }
            if CFNumberIsFloatType(n) { self = .real(n.doubleValue); return }
            self = .int(n.intValue)
            return
        }
        #else
        if let b = o as? Bool, type(of: o) == Bool.self { self = .bool(b); return }
        if let i = o as? Int { self = .int(i); return }
        if let d = o as? Double { self = .real(d); return }
        if let b = o as? Bool { self = .bool(b); return }
        #endif
        return nil
    }

    public var intValue: Int? {
        switch self {
        case .bool(let b): b ? 1 : 0
        case .int(let i): i
        case .real(let d): Int(d)
        case .string(let s): Int(s)
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .bool(let b): b ? 1 : 0
        case .int(let i): Double(i)
        case .real(let d): d
        case .string(let s): Double(s)
        }
    }

    public var description: String {
        switch self {
        case .bool(let b): b ? "true" : "false"
        case .int(let i): String(i)
        case .real(let d): String(d)
        case .string(let s): "\"\(s)\""
        }
    }
}

public struct PreferenceWrite: Equatable, Sendable, CustomStringConvertible {
    public var domain: String
    public var key: String
    public var value: PrefValue?

    public init(_ domain: String, _ key: String, _ value: PrefValue?) {
        self.domain = domain
        self.key = key
        self.value = value
    }

    public var description: String { "\(domain) \(key) = \(value?.description ?? "(removed)")" }
}

public struct PreferenceRead: Hashable, Sendable {
    public var domain: String
    public var key: String
    public init(_ domain: String, _ key: String) {
        self.domain = domain
        self.key = key
    }
    public var tag: String { domain + "|" + key }
}

public struct SettingsPlan: Equatable, Sendable {
    public var writes: [PreferenceWrite] = []
    public var notifications: [String] = []
    public var waitForVoiceOver: Bool?
    public var startServices: [String] = []

    public init(writes: [PreferenceWrite] = [], notifications: [String] = [], waitForVoiceOver: Bool? = nil,
                startServices: [String] = []) {
        self.writes = writes
        self.notifications = notifications
        self.waitForVoiceOver = waitForVoiceOver
        self.startServices = startServices
    }

    public mutating func append(_ other: SettingsPlan) {
        writes += other.writes
        for n in other.notifications where !notifications.contains(n) { notifications.append(n) }
        if let w = other.waitForVoiceOver { waitForVoiceOver = w }
        startServices += other.startServices
    }
}

public enum SimPrefs {
    public static let styleDomain = "com.apple.uikitservices.userInterfaceStyleMode"
    public static let styleKey = "UserInterfaceStyleMode"
    public static let uikit = "com.apple.UIKit"
    public static let glassTint = "UIViewGlassTintAmount"
    public static let glassLegibility = "UIViewGlassLegibilitySetting"
    public static let contentSize = "UIPreferredContentSizeCategoryName"
    public static let preferencesFramework = "com.apple.preferences-framework"
    public static let extendedRange = "largeTextUsesExtendedRange"
    public static let accessibility = "com.apple.Accessibility"
    public static let mediaAccessibility = "com.apple.mediaaccessibility"
    public static let filterEnabled = "__Color__.MADisplayFilterCategoryEnabled"
    public static let filterType = "__Color__.MADisplayFilterType"
    public static let grayscale = "GrayscaleDisplay"
    public static let grayscaleChecked = "DidCheckGrayscaleValue-v2"
    public static let reduceMotion = "ReduceMotionEnabled"
    public static let pointerScaling = "PointerEffectScalingEnabled"
    public static let darkenColors = "DarkenSystemColors"
    public static let pointerContrast = "PointerIncreasedContrastEnabled"
    public static let buttonShapes = "ButtonShapesEnabled"
    public static let backgroundContrast = "EnhancedBackgroundContrastEnabled"
    public static let voiceOverTouch = "VoiceOverTouchEnabled"
    public static let accessibilityEnabled = "AccessibilityEnabled"
    public static let applicationAccessibility = "ApplicationAccessibilityEnabled"
    public static let voiceOverRunning = "VOTIsRunningKey"
    public static let voiceOverDomain = "com.apple.VoiceOverTouch"
    public static let voiceOverService = "com.apple.VoiceOverTouch"
}

public enum SimNotifications {
    public static let styleChanged = "com.apple.UIKit.SystemUIServiceUserInterfaceStyleNotification"
    public static let glassTint = "UIViewGlassTintAmountUpdateNotification"
    public static let glassLegibility = "UIViewGlassLegibilityUpdateNotification"
    public static let contentSize = "ApplePreferredContentSizeCategoryChangedNotification"
    public static let filterChanged = "com.apple.mediaaccessibility.displayFilterSettingsChanged"
    public static let filterForceUpdate = "com.apple.accessibility.displayFilterForceUpdate"
    public static let axCache = "com.apple.accessibility.cache.ax"
    public static let appAXCache = "com.apple.accessibility.cache.app.ax"
    public static let axStatus = "com.apple.accessibility.status"
    public static let appStatus = "com.apple.accessibility.application.status"
    public static let reduceMotion = "com.apple.accessibility.reduce.motion.status"
    public static let darkenColors = "com.apple.accessibility.darken.system.colors"
    public static let buttonShapes = "com.apple.accessibility.button.shapes"
    public static let backgroundContrast = "com.apple.accessibility.enhance.background.contrast.status"
    public static let volume = "com.apple.springboard.volumestate"
    public static let audioDevices = "com.apple.CoreSimulator.audio.devices_changed"
    public static let watched = [
        styleChanged, contentSize, "UIViewGlassLegibilityDidChangeNotification",
        "com.apple.accessibility.cache.button.shapes.enabled", "com.apple.accessibility.voiceovertouch.status",
        "com.apple.accessibility.grayscale", "com.apple.accessibility.red-color-filter",
        "com.apple.accessibility.green-color-filter", "com.apple.accessibility.blue-color-filter",
        "com.apple.accessibility.cache.reduce.motion", "com.apple.accessibility.cache.darken.system.colors.enabled",
        "com.apple.accessibility.cache.enhance.background.contrast",
    ]
}

public enum Appearance: String, CaseIterable, Sendable {
    case light, dark
    public var mode: Int { self == .light ? 1 : 2 }
    public init?(mode: Int) {
        switch mode {
        case 1: self = .light
        case 2: self = .dark
        default: return nil
        }
    }
    public var title: String { self == .light ? "Light" : "Dark" }
}

public enum ContentSize: String, CaseIterable, Sendable {
    case extraSmall = "extra-small", small, medium, large, extraLarge = "extra-large"
    case extraExtraLarge = "extra-extra-large", extraExtraExtraLarge = "extra-extra-extra-large"
    case accessibilityMedium = "accessibility-medium", accessibilityLarge = "accessibility-large"
    case accessibilityExtraLarge = "accessibility-extra-large"
    case accessibilityExtraExtraLarge = "accessibility-extra-extra-large"
    case accessibilityExtraExtraExtraLarge = "accessibility-extra-extra-extra-large"

    static let suffixes = ["XS", "S", "M", "L", "XL", "XXL", "XXXL",
                           "AccessibilityM", "AccessibilityL", "AccessibilityXL", "AccessibilityXXL", "AccessibilityXXXL"]
    public var index: Int { Self.allCases.firstIndex(of: self)! }
    public var categoryName: String { "UICTContentSizeCategory" + Self.suffixes[index] }
    public init?(categoryName: String) {
        guard categoryName.hasPrefix("UICTContentSizeCategory"),
              let i = Self.suffixes.firstIndex(of: String(categoryName.dropFirst("UICTContentSizeCategory".count))) else { return nil }
        self = Self.allCases[i]
    }
    public var isAccessibility: Bool { index >= 7 }
    public func stepped(by delta: Int) -> ContentSize { Self.allCases[min(Self.allCases.count - 1, max(0, index + delta))] }
    public var title: String {
        ["Extra Small", "Small", "Medium", "Large (Default)", "Extra Large", "Extra Extra Large",
         "Extra Extra Extra Large", "Accessibility Medium", "Accessibility Large", "Accessibility Extra Large",
         "Accessibility Extra Extra Large", "Accessibility Extra Extra Extra Large"][index]
    }
    public init?(argument: String) {
        if let s = ContentSize(rawValue: argument.lowercased().replacingOccurrences(of: "_", with: "-")) { self = s; return }
        if let s = ContentSize(categoryName: argument) { self = s; return }
        return nil
    }
}

public enum ColorFilter: String, CaseIterable, Sendable {
    case none, protanopia, deuteranopia, tritanopia, grayscale

    public var typeCode: Int? {
        switch self {
        case .none: nil
        case .grayscale: 1
        case .protanopia: 2
        case .deuteranopia: 4
        case .tritanopia: 8
        }
    }
    public init?(typeCode: Int) {
        guard let f = Self.allCases.first(where: { $0.typeCode == typeCode }) else { return nil }
        self = f
    }
    public var intensityKey: String? {
        switch self {
        case .protanopia: "MADisplayFilterRedColorCorrectionIntensity"
        case .deuteranopia: "MADisplayFilterGreenColorCorrectionIntensity"
        case .tritanopia: "MADisplayFilterBlueColorCorrectionIntensity"
        default: nil
        }
    }
    public var notification: String? {
        switch self {
        case .protanopia: "com.apple.accessibility.red-color-filter"
        case .deuteranopia: "com.apple.accessibility.green-color-filter"
        case .tritanopia: "com.apple.accessibility.blue-color-filter"
        default: nil
        }
    }
    public var title: String {
        switch self {
        case .none: "None"
        case .protanopia: "Red/Green (Protanopia)"
        case .deuteranopia: "Green/Red (Deuteranopia)"
        case .tritanopia: "Blue/Yellow (Tritanopia)"
        case .grayscale: "Grayscale"
        }
    }
    public static let intensityRange = 0.25...1.0
    public static let defaultIntensity = 1.0
    public init?(argument: String) {
        switch argument.lowercased() {
        case "none", "off": self = .none
        case "protanopia", "red-green", "red/green": self = .protanopia
        case "deuteranopia", "green-red", "green/red": self = .deuteranopia
        case "tritanopia", "blue-yellow", "blue/yellow": self = .tritanopia
        case "grayscale", "greyscale": self = .grayscale
        default: return nil
        }
    }
}

public enum GlassLook: String, CaseIterable, Sendable {
    case clear, tinted
}

public enum AccessibilitySwitch: String, CaseIterable, Sendable {
    case reduceMotion = "reduce-motion"
    case increaseContrast = "increase-contrast"
    case showBorders = "show-borders"
    case reduceTransparency = "reduce-transparency"
    case voiceOver = "voiceover"

    public var title: String {
        switch self {
        case .reduceMotion: "Reduce Motion"
        case .increaseContrast: "Increase Contrast"
        case .showBorders: "Show Borders"
        case .reduceTransparency: "Reduce Transparency"
        case .voiceOver: "VoiceOver"
        }
    }
    public init?(argument: String) {
        let a = argument.lowercased().replacingOccurrences(of: "_", with: "-")
        switch a {
        case "voice-over": self = .voiceOver
        case "button-shapes": self = .showBorders
        default:
            guard let s = AccessibilitySwitch(rawValue: a) else { return nil }
            self = s
        }
    }
    public var key: String {
        switch self {
        case .reduceMotion: SimPrefs.reduceMotion
        case .increaseContrast: SimPrefs.darkenColors
        case .showBorders: SimPrefs.buttonShapes
        case .reduceTransparency: SimPrefs.backgroundContrast
        case .voiceOver: SimPrefs.voiceOverTouch
        }
    }
}

public enum SimSetting: Equatable, Sendable {
    case appearance(Appearance)
    case liquidGlass(opacity: Double?, look: GlassLook?)
    case colorFilter(ColorFilter, intensity: Double?)
    case contentSize(ContentSize)
    case largerAccessibilitySizes(Bool)
    case accessibility(AccessibilitySwitch, Bool)
}

public enum SimFeatureMapping {
    private static func ax(_ key: String, _ on: Bool) -> PreferenceWrite {
        PreferenceWrite(SimPrefs.accessibility, key, .int(on ? 1 : 0))
    }

    public static func plan(for setting: SimSetting) -> SettingsPlan {
        switch setting {
        case .appearance(let a):
            return SettingsPlan(writes: [PreferenceWrite(SimPrefs.styleDomain, SimPrefs.styleKey, .int(a.mode))])
        case .liquidGlass(let opacity, let look):
            var p = SettingsPlan()
            if let opacity {
                p.writes.append(PreferenceWrite(SimPrefs.uikit, SimPrefs.glassTint, .real(min(1, max(0, opacity)))))
                p.notifications.append(SimNotifications.glassTint)
            }
            if let look {
                p.writes.append(PreferenceWrite(SimPrefs.uikit, SimPrefs.glassLegibility, look == .tinted ? .int(1) : nil))
                p.notifications.append(SimNotifications.glassLegibility)
            }
            return p
        case .colorFilter(let filter, let intensity):
            var p = SettingsPlan()
            let ma = SimPrefs.mediaAccessibility
            if let code = filter.typeCode {
                p.writes.append(PreferenceWrite(ma, SimPrefs.filterEnabled, .int(1)))
                p.writes.append(PreferenceWrite(ma, SimPrefs.filterType, .int(code)))
                if let key = filter.intensityKey {
                    let v = min(ColorFilter.intensityRange.upperBound, max(ColorFilter.intensityRange.lowerBound,
                                                                           intensity ?? ColorFilter.defaultIntensity))
                    p.writes.append(PreferenceWrite(ma, key, .real(v)))
                }
            } else {
                p.writes.append(PreferenceWrite(ma, SimPrefs.filterEnabled, .int(0)))
            }
            p.writes.append(ax(SimPrefs.grayscale, filter == .grayscale))
            p.writes.append(ax(SimPrefs.grayscaleChecked, true))
            p.notifications = [SimNotifications.filterChanged, SimNotifications.filterForceUpdate]
            if let n = filter.notification {
                p.notifications.append(n)
            } else if filter == .none {
                p.notifications += [ColorFilter.protanopia, .deuteranopia, .tritanopia].compactMap(\.notification)
            }
            return p
        case .contentSize(let size):
            var p = SettingsPlan(writes: [PreferenceWrite(SimPrefs.uikit, SimPrefs.contentSize, .string(size.categoryName))],
                                 notifications: [SimNotifications.contentSize])
            if size.isAccessibility {
                p.writes.append(PreferenceWrite(SimPrefs.preferencesFramework, SimPrefs.extendedRange, .bool(true)))
            }
            return p
        case .largerAccessibilitySizes(let on):
            return SettingsPlan(writes: [PreferenceWrite(SimPrefs.preferencesFramework, SimPrefs.extendedRange, .bool(on))],
                                notifications: [SimNotifications.contentSize])
        case .accessibility(let s, let on):
            switch s {
            case .reduceMotion:
                return SettingsPlan(writes: [ax(SimPrefs.reduceMotion, on),
                                             PreferenceWrite(SimPrefs.accessibility, SimPrefs.pointerScaling, on ? .int(0) : nil)],
                                    notifications: [SimNotifications.axCache, SimNotifications.reduceMotion])
            case .increaseContrast:
                return SettingsPlan(writes: [ax(SimPrefs.darkenColors, on), ax(SimPrefs.pointerContrast, on)],
                                    notifications: [SimNotifications.axCache, SimNotifications.axStatus, SimNotifications.darkenColors])
            case .showBorders:
                return SettingsPlan(writes: [ax(SimPrefs.buttonShapes, on)], notifications: [SimNotifications.buttonShapes])
            case .reduceTransparency:
                return SettingsPlan(writes: [ax(SimPrefs.backgroundContrast, on)], notifications: [SimNotifications.backgroundContrast])
            case .voiceOver:
                return SettingsPlan(writes: [ax(SimPrefs.voiceOverTouch, on),
                                             PreferenceWrite(SimPrefs.accessibility, SimPrefs.accessibilityEnabled, .bool(on)),
                                             ax(SimPrefs.applicationAccessibility, on)],
                                    notifications: [SimNotifications.axCache, SimNotifications.appAXCache, SimNotifications.appStatus],
                                    waitForVoiceOver: on,
                                    startServices: on ? [SimPrefs.voiceOverService] : [])
            }
        }
    }

    public static func persists(_ setting: SimSetting) -> Bool {
        if case .colorFilter = setting { return false }
        return true
    }

    public static func bootPlan(_ state: SimSettingsState) -> SettingsPlan? {
        if state.isOn(.voiceOver) { return SettingsPlan(startServices: [SimPrefs.voiceOverService]) }
        guard state.voiceOverRunning else { return nil }
        return SettingsPlan(writes: [PreferenceWrite(SimPrefs.accessibility, SimPrefs.voiceOverRunning, nil),
                                     PreferenceWrite(SimPrefs.voiceOverDomain, SimPrefs.voiceOverRunning, nil)])
    }

    public static let stateReads: [PreferenceRead] = [
        PreferenceRead(SimPrefs.styleDomain, SimPrefs.styleKey),
        PreferenceRead(SimPrefs.uikit, SimPrefs.glassTint),
        PreferenceRead(SimPrefs.uikit, SimPrefs.glassLegibility),
        PreferenceRead(SimPrefs.uikit, SimPrefs.contentSize),
        PreferenceRead(SimPrefs.preferencesFramework, SimPrefs.extendedRange),
        PreferenceRead(SimPrefs.mediaAccessibility, SimPrefs.filterEnabled),
        PreferenceRead(SimPrefs.mediaAccessibility, SimPrefs.filterType),
        PreferenceRead(SimPrefs.accessibility, SimPrefs.grayscale),
    ] + ColorFilter.allCases.compactMap { $0.intensityKey.map { PreferenceRead(SimPrefs.mediaAccessibility, $0) } }
      + AccessibilitySwitch.allCases.map { PreferenceRead(SimPrefs.accessibility, $0.key) }
      + [PreferenceRead(SimPrefs.accessibility, SimPrefs.voiceOverRunning),
         PreferenceRead(SimPrefs.voiceOverDomain, SimPrefs.voiceOverRunning)]
}

public struct SimSettingsState: Equatable, Sendable {
    public var appearance: Appearance = .light
    public var glassOpacity: Double?
    public var glassLook: GlassLook = .clear
    public var contentSize: ContentSize = .large
    public var largerAccessibilitySizes = false
    public var colorFilter: ColorFilter = .none
    public var colorFilterIntensity: Double?
    public var switches: [AccessibilitySwitch: Bool] = Dictionary(uniqueKeysWithValues: AccessibilitySwitch.allCases.map { ($0, false) })
    public var voiceOverRunning = false

    public init() {}

    public init(values: [String: PrefValue]) {
        func v(_ d: String, _ k: String) -> PrefValue? { values[PreferenceRead(d, k).tag] }
        if let m = v(SimPrefs.styleDomain, SimPrefs.styleKey)?.intValue, let a = Appearance(mode: m) { appearance = a }
        glassOpacity = v(SimPrefs.uikit, SimPrefs.glassTint)?.doubleValue
        if v(SimPrefs.uikit, SimPrefs.glassLegibility)?.intValue == 1 { glassLook = .tinted }
        if case .string(let s)? = v(SimPrefs.uikit, SimPrefs.contentSize), let c = ContentSize(categoryName: s) { contentSize = c }
        largerAccessibilitySizes = (v(SimPrefs.preferencesFramework, SimPrefs.extendedRange)?.intValue ?? 0) != 0
        if v(SimPrefs.mediaAccessibility, SimPrefs.filterEnabled)?.intValue == 1,
           let code = v(SimPrefs.mediaAccessibility, SimPrefs.filterType)?.intValue, let f = ColorFilter(typeCode: code) {
            colorFilter = f
            colorFilterIntensity = f.intensityKey.flatMap { v(SimPrefs.mediaAccessibility, $0)?.doubleValue }
        } else if v(SimPrefs.accessibility, SimPrefs.grayscale)?.intValue == 1 {
            colorFilter = .grayscale
        }
        for s in AccessibilitySwitch.allCases { switches[s] = (v(SimPrefs.accessibility, s.key)?.intValue ?? 0) != 0 }
        voiceOverRunning = (v(SimPrefs.accessibility, SimPrefs.voiceOverRunning)?.intValue ?? 0) != 0
            || (v(SimPrefs.voiceOverDomain, SimPrefs.voiceOverRunning)?.intValue ?? 0) != 0
    }

    public func isOn(_ s: AccessibilitySwitch) -> Bool { switches[s] ?? false }

    public var lines: [String] {
        var out = ["appearance \(appearance.rawValue)",
                   "liquid-glass \(glassOpacity.map { String(format: "%.2f", $0) } ?? "default") \(glassLook.rawValue)",
                   "content-size \(contentSize.rawValue)",
                   "larger-accessibility-sizes \(largerAccessibilitySizes ? "on" : "off")",
                   "color-filter \(colorFilter.rawValue)" + (colorFilterIntensity.map { String(format: " %.2f", $0) } ?? "")]
        for s in AccessibilitySwitch.allCases { out.append("\(s.rawValue) \(isOn(s) ? "on" : "off")") }
        out.append("voiceover-running \(voiceOverRunning ? "yes" : "no")")
        return out
    }

    public init(lines: [String]) {
        self.init()
        for line in lines {
            let w = line.split(separator: " ").map(String.init)
            guard w.count >= 2 else { continue }
            switch w[0] {
            case "appearance": appearance = Appearance(rawValue: w[1]) ?? .light
            case "liquid-glass":
                glassOpacity = Double(w[1])
                if w.count > 2 { glassLook = GlassLook(rawValue: w[2]) ?? .clear }
            case "content-size": contentSize = ContentSize(rawValue: w[1]) ?? .large
            case "larger-accessibility-sizes": largerAccessibilitySizes = w[1] == "on"
            case "color-filter":
                colorFilter = ColorFilter(rawValue: w[1]) ?? .none
                colorFilterIntensity = w.count > 2 ? Double(w[2]) : nil
            case "voiceover-running": voiceOverRunning = w[1] == "yes"
            default:
                if let s = AccessibilitySwitch(rawValue: w[0]) { switches[s] = w[1] == "on" }
            }
        }
    }
}
