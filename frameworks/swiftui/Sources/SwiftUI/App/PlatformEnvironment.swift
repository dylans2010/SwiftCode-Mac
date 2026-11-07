import Foundation
import OVPlatform
#if OPENVIEWS_RENAMED
import OpenViewsCore
#else
import SwiftUICore
#endif

@MainActor
package enum PlatformEnvironment {
    static let rightToLeftLanguages: Set<String> = ["ar", "arc", "ckb", "dv", "fa", "he", "iw", "ks", "ku", "ps", "sd", "ug",
                                                     "ur", "yi"]

    package static func layoutDirection(forLocale id: String) -> LayoutDirection {
        let lang = String(id.split(whereSeparator: { $0 == "_" || $0 == "-" }).first ?? "").lowercased()
        return rightToLeftLanguages.contains(lang) ? .rightToLeft : .leftToRight
    }

    package static func dynamicTypeSize(_ index: Int) -> DynamicTypeSize {
        let all = DynamicTypeSize.allCases
        return all[max(0, min(all.count - 1, index))]
    }

    package static func apply(_ s: PlatformSettings, to env: inout EnvironmentValues) {
        set(&env, \.colorScheme, s.darkAppearance ? .dark : .light)
        set(&env, \.colorSchemeContrast, s.increasedContrast ? .increased : .standard)
        let size = dynamicTypeSize(s.contentSizeIndex)
        set(&env, \.dynamicTypeSize, size)
        set(&env, \.defaultMinListRowHeight, size >= .accessibility2 ? 59 : 52)
        set(&env, \.legibilityWeight, s.boldText ? .bold : .regular)
        set(&env, \.accessibilityReduceMotion, s.reduceMotion)
        set(&env, \.accessibilityReduceTransparency, s.reduceTransparency)
        set(&env, \.accessibilityDifferentiateWithoutColor, s.differentiateWithoutColor)
        set(&env, \.accessibilityInvertColors, s.invertColors)
        set(&env, \.accessibilityShowButtonShapes, s.showButtonShapes)
        if env.locale.identifier != s.localeIdentifier {
            let locale = Locale(identifier: s.localeIdentifier)
            env.locale = locale
            env.calendar = locale.calendar
        }
        set(&env, \.layoutDirection, layoutDirection(forLocale: s.localeIdentifier))
        if let tz = s.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)), env.timeZone != tz { env.timeZone = tz }
    }

    private static func set<V: Equatable>(_ env: inout EnvironmentValues, _ kp: WritableKeyPath<EnvironmentValues, V>, _ v: V) {
        if env[keyPath: kp] != v { env[keyPath: kp] = v }
    }
}
