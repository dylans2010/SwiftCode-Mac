import AppKit

@MainActor
enum EditorScrollerStyle {
    static let defaultsKey = "SwiftCodeEditorScrollerStyle"
    static let settleTime: TimeInterval = 3
    private static var settled = false
    private static var observer: NSObjectProtocol?
    private static var firstUse: Date?

    static var initial: NSScroller.Style {
        watch()
        let preferred = NSScroller.preferredScrollerStyle
        if settled { return preferred }
        guard let raw = UserDefaults.standard.object(forKey: defaultsKey) as? Int, let remembered = NSScroller.Style(rawValue: raw) else {
            return preferred
        }
        return remembered
    }

    private static let followers = NSHashTable<NSScrollView>.weakObjects()

    static func noteSettled(_ style: NSScroller.Style) {
        settled = true
        UserDefaults.standard.set(style.rawValue, forKey: defaultsKey)
        for scrollView in followers.allObjects where scrollView.scrollerStyle != style {
            scrollView.scrollerStyle = style
            scrollView.superview?.needsLayout = true
        }
        followers.removeAllObjects()
    }

    static func follow(_ scrollView: NSScrollView) {
        guard !settled else { return }
        followers.add(scrollView)
    }

    private static func watch() {
        guard firstUse == nil else { return }
        firstUse = Date()
        observer = NotificationCenter.default.addObserver(forName: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil,
                                                          queue: .main) { _ in
            MainActor.assumeIsolated { noteSettled(NSScroller.preferredScrollerStyle) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + settleTime) {
            MainActor.assumeIsolated {
                guard !settled else { return }
                noteSettled(NSScroller.preferredScrollerStyle)
            }
        }
    }
}
