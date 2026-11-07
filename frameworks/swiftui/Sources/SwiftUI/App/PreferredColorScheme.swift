import Foundation
#if OPENVIEWS_RENAMED
import OpenViewsCore
#else
import SwiftUICore
#endif

struct PreferredColorSchemeKey: PreferenceKey {
    static var defaultValue: ColorScheme? { nil }
    static func reduce(value: inout ColorScheme?, nextValue: () -> ColorScheme?) {
        if value == nil { value = nextValue() }
    }
}

extension View {
    public func preferredColorScheme(_ colorScheme: ColorScheme?) -> some View {
        preference(key: PreferredColorSchemeKey.self, value: colorScheme)
    }
}

extension WindowHost {
    var requestedColorScheme: ColorScheme? {
        graph.rootPreferences[PreferredColorSchemeKey.self].flatMap { $0 }
    }
}
