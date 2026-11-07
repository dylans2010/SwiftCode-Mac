import Foundation
import OVPlatform
#if OPENVIEWS_RENAMED
import OpenViewsCore
#else
import SwiftUICore
#endif

@MainActor
public enum OpenViewsClipboard {
    private static let fallback = MemoryClipboard()

    static var platform: any PlatformClipboard { (AppHost.current ?? AppHost.lastLaunched)?.backend.clipboard ?? fallback }

    public static var string: String? {
        get { platform.text }
        set { platform.text = newValue }
    }

    public static var hasString: Bool { platform.hasText }

    public static func copy(_ text: String) { platform.text = text }
}
