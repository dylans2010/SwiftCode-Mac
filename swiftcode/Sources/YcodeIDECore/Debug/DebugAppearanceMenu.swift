import Foundation
import YcodeSimFeatures

public enum DebugAppearanceMenu {
    public static let titles = ["System Appearance", "Light", "Dark", "High Contrast Light", "High Contrast Dark"]
    public static let actions = ["debugAppearanceSystem:", "debugAppearanceLight:", "debugAppearanceDark:",
                                 "debugAppearanceHighContrastLight:", "debugAppearanceHighContrastDark:"]

    public static func apply(_ index: Int, to overrides: EnvironmentOverrides) -> EnvironmentOverrides {
        var o = overrides
        switch index {
        case 1, 3: o.values[.appearance] = "light"
        case 2, 4: o.values[.appearance] = "dark"
        default: o.values[.appearance] = nil
        }
        o.values[.increaseContrast] = index >= 3 ? "on" : nil
        return o
    }

    public static func checkedIndex(_ overrides: EnvironmentOverrides) -> Int {
        let contrast = overrides.values[.increaseContrast] == "on"
        switch overrides.values[.appearance] {
        case "light": return contrast ? 3 : 1
        case "dark": return contrast ? 4 : 2
        default: return 0
        }
    }
}
