import Foundation

extension Preferences {

    public enum RestoreWindows: String, CaseIterable, Sendable {
        case system = "Use System Setting", always = "Always", never = "Never"
    }
    public static let keepWindowsKey = "NSQuitAlwaysKeepsWindows"

    public var restoreWindows: RestoreWindows {
        get { RestoreWindows(rawValue: get("restoreWindows", RestoreWindows.system.rawValue)) ?? .system }
        set {
            switch newValue {
            case .system: defaults.removeObject(forKey: Self.keepWindowsKey)
            case .always: defaults.set(true, forKey: Self.keepWindowsKey)
            case .never: defaults.set(false, forKey: Self.keepWindowsKey)
            }
            set("restoreWindows", newValue.rawValue)
        }
    }

    public enum NavigatorSize: String, CaseIterable, Sendable {
        case system = "Use System Setting", small = "Small", medium = "Medium", large = "Large"
    }
    public var navigatorSize: NavigatorSize {
        get { NavigatorSize(rawValue: get("navigatorSize", NavigatorSize.system.rawValue)) ?? .system }
        set { set("navigatorSize", newValue.rawValue) }
    }

    public static let detailLineChoices = Array(1...5)
    public static func detailTitle(_ n: Int) -> String { n == 1 ? "Up to 1 Line" : "Up to \(n) Lines" }
    public static func detailLines(fromTitle t: String) -> Int? { detailLineChoices.first { detailTitle($0) == t } }

    private func lines(_ key: String) -> Int { min(5, max(1, get(key, 3))) }
    public var bookmarkNavigatorDetail: Int { get { lines("bookmarkNavigatorDetail") } set { set("bookmarkNavigatorDetail", min(5, max(1, newValue))) } }
    public var findNavigatorDetail: Int { get { lines("findNavigatorDetail") } set { set("findNavigatorDetail", min(5, max(1, newValue))) } }
    public var issueNavigatorDetail: Int { get { lines("issueNavigatorDetail") } set { set("issueNavigatorDetail", min(5, max(1, newValue))) } }

    public var independentSidebarWidths: Bool { get { get("independentSidebarWidths", false) } set { set("independentSidebarWidths", newValue) } }
    public var autoUnlockFiles: Bool { get { get("autoUnlockFiles", false) } set { set("autoUnlockFiles", newValue) } }

    public enum IssuePresentation: String, CaseIterable, Sendable { case inline = "Show Inline", minimized = "Show Minimized" }
    public var issuePresentation: IssuePresentation {
        get { IssuePresentation(rawValue: get("issuePresentation", IssuePresentation.inline.rawValue)) ?? .inline }
        set { set("issuePresentation", newValue.rawValue) }
    }
    public var stopBuildOnFirstError: Bool { get { get("stopBuildOnFirstError", true) } set { set("stopBuildOnFirstError", newValue) } }

    public enum TestParallelization: String, CaseIterable, Sendable { case automatic = "Automatic", off = "Off" }
    public var testParallelizationMac: TestParallelization {
        get { TestParallelization(rawValue: get("testParallelizationMac", "Automatic")) ?? .automatic }
        set { set("testParallelizationMac", newValue.rawValue) }
    }
    public var testParallelizationSimulator: TestParallelization {
        get { TestParallelization(rawValue: get("testParallelizationSimulator", "Automatic")) ?? .automatic }
        set { set("testParallelizationSimulator", newValue.rawValue) }
    }

    public static let reportHistoryChoices = [10, 20, 50, 100]
    public static func reportHistoryTitle(_ n: Int) -> String { "Up to \(n) Reports" }
    public var reportHistoryLimit: Int {
        get { let n: Int = get("reportHistoryLimit", 20); return Self.reportHistoryChoices.contains(n) ? n : 20 }
        set { set("reportHistoryLimit", newValue) }
    }

    public var settingsKeys: [String] {
        defaults.dictionaryRepresentation().keys.filter {
            ($0.hasPrefix("SwiftCode.") && $0 != RecentProjects.defaultsKey) || $0 == BuildSystemPreference.defaultsKey
        }.sorted()
    }

    public func exportSettings() throws -> Data {
        var values: [String: Any] = [:]
        for k in settingsKeys { if let v = defaults.object(forKey: k) { values[k] = Self.jsonValue(v) } }
        let doc: [String: Any] = ["format": "swiftcode-settings", "version": 1, "values": values]
        return try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys])
    }

    public func importSettings(_ data: Data) throws {
        guard let doc = try JSONSerialization.jsonObject(with: data) as? [String: Any], doc["format"] as? String == "swiftcode-settings",
              let values = doc["values"] as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        for k in settingsKeys { defaults.removeObject(forKey: k) }
        for (k, v) in values where k.hasPrefix("SwiftCode.") || k == BuildSystemPreference.defaultsKey {
            defaults.set(Self.defaultsValue(v), forKey: k)
        }
        let r = restoreWindows
        restoreWindows = r
        changed()
    }

    public func resetSettings() {
        for k in settingsKeys { defaults.removeObject(forKey: k) }
        defaults.removeObject(forKey: Self.keepWindowsKey)
        changed()
    }

    public static let suppressionPrefix = "SwiftCode.suppress."
    public func isWarningSuppressed(_ id: String) -> Bool { defaults.bool(forKey: Self.suppressionPrefix + id) }
    public func suppressWarning(_ id: String) { defaults.set(true, forKey: Self.suppressionPrefix + id); changed() }
    public func resetSuppressedWarnings() {
        for k in defaults.dictionaryRepresentation().keys where k.hasPrefix(Self.suppressionPrefix) { defaults.removeObject(forKey: k) }
        changed()
    }

    static func jsonValue(_ v: Any) -> Any {
        switch v {
        case let d as Data: return ["data": d.base64EncodedString()]
        case let a as [Any]: return a.map(jsonValue)
        case let m as [String: Any]: return m.mapValues(jsonValue)
        case let date as Date: return ["date": date.timeIntervalSinceReferenceDate]
        default: return v
        }
    }

    static func defaultsValue(_ v: Any) -> Any {
        switch v {
        case let m as [String: Any] where m.count == 1 && m["data"] is String:
            return Data(base64Encoded: m["data"] as? String ?? "") ?? Data()
        case let m as [String: Any] where m.count == 1 && m["date"] is NSNumber:
            return Date(timeIntervalSinceReferenceDate: (m["date"] as? NSNumber)?.doubleValue ?? 0)
        case let m as [String: Any]: return m.mapValues(defaultsValue)
        case let a as [Any]: return a.map(defaultsValue)
        #if canImport(Darwin)
        case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID(): return n.boolValue
        #else
        case let b as Bool: return b
        #endif
        default: return v
        }
    }

    public enum NewEditorContent: String, CaseIterable, Sendable { case startPage = "Start Page", sameDocument = "Same Document" }
    public var newEditorTabsOpenWith: NewEditorContent {
        get { NewEditorContent(rawValue: get("newEditorTabsOpenWith", NewEditorContent.startPage.rawValue)) ?? .startPage }
        set { set("newEditorTabsOpenWith", newValue.rawValue) }
    }
    public var newEditorPanesOpenWith: NewEditorContent {
        get { NewEditorContent(rawValue: get("newEditorPanesOpenWith", NewEditorContent.sameDocument.rawValue)) ?? .sameDocument }
        set { set("newEditorPanesOpenWith", newValue.rawValue) }
    }

    public enum PinEditorTabs: String, CaseIterable, Sendable { case manually = "Manually", automatically = "Automatically" }
    public var pinEditorTabs: PinEditorTabs {
        get { PinEditorTabs(rawValue: get("pinEditorTabs", PinEditorTabs.manually.rawValue)) ?? .manually }
        set { set("pinEditorTabs", newValue.rawValue) }
    }

    public enum CodeClick: String, CaseIterable, Sendable { case quickHelp = "Shows Quick Help", definition = "Jumps to Definition" }
    public var optionClickOnCode: CodeClick {
        get { CodeClick(rawValue: get("clickOnCodeOption", CodeClick.quickHelp.rawValue)) ?? .quickHelp }
        set { set("clickOnCodeOption", newValue.rawValue) }
    }
    public var commandClickOnCode: CodeClick {
        get { CodeClick(rawValue: get("clickOnCodeCommand", CodeClick.definition.rawValue)) ?? .definition }
        set { set("clickOnCodeCommand", newValue.rawValue) }
    }
    public var commandControlClickOnCode: CodeClick {
        get { CodeClick(rawValue: get("clickOnCodeCommandControl", CodeClick.definition.rawValue)) ?? .definition }
        set { set("clickOnCodeCommandControl", newValue.rawValue) }
    }
    public func codeClick(forModifiers flags: MenuCommand.Modifiers) -> CodeClick? {
        switch flags.intersection([.command, .option, .control, .shift]) {
        case .option: optionClickOnCode
        case .command: commandClickOnCode
        case [.command, .control]: commandControlClickOnCode
        default: nil
        }
    }

    public enum NavigationDestination: String, CaseIterable, Sendable { case focusedPane = "Focused Editor Pane" }
    public var navigationDestination: NavigationDestination {
        get { NavigationDestination(rawValue: get("navigationDestination", NavigationDestination.focusedPane.rawValue)) ?? .focusedPane }
        set { set("navigationDestination", newValue.rawValue) }
    }
    public enum NavigationTarget: String, CaseIterable, Sendable {
        case sameAsClick = "Same as Click"
        case focusedPane = "Uses Focused Editor Pane"
        case newUnpinnedTab = "Uses New Unpinned Tab"
        case nextPane = "Uses Next Editor Pane"
    }
    public var navigationWithOption: NavigationTarget {
        get { NavigationTarget(rawValue: get("navigationOption", NavigationTarget.newUnpinnedTab.rawValue)) ?? .newUnpinnedTab }
        set { set("navigationOption", newValue.rawValue) }
    }
    public var navigationWithOptionShift: NavigationTarget {
        get { NavigationTarget(rawValue: get("navigationOptionShift", NavigationTarget.nextPane.rawValue)) ?? .nextPane }
        set { set("navigationOptionShift", newValue.rawValue) }
    }
    public var navigationWithDoubleClick: NavigationTarget {
        get { NavigationTarget(rawValue: get("navigationDoubleClick", NavigationTarget.sameAsClick.rawValue)) ?? .sameAsClick }
        set { set("navigationDoubleClick", newValue.rawValue) }
    }
    public func navigationTarget(keys modifiers: MenuCommand.Modifiers, clickCount: Int = 1) -> NavigationTarget {
        let m = modifiers.intersection([.command, .option, .control, .shift])
        var t: NavigationTarget = .sameAsClick
        if m == [.option, .shift] { t = navigationWithOptionShift } else if m == .option { t = navigationWithOption }
        else if clickCount >= 2 { t = navigationWithDoubleClick }
        return t == .sameAsClick ? .focusedPane : t
    }

    public var useWindowTabsInFullScreen: Bool { get { get("useWindowTabsInFullScreen", true) } set { set("useWindowTabsInFullScreen", newValue) } }
    public var animateOpenQuickly: Bool { get { get("animateOpenQuickly", true) } set { set("animateOpenQuickly", newValue) } }

    public var convertExistingFilesOnSave: Bool { get { get("convertOnSave", false) } set { set("convertOnSave", newValue) } }
    public var generateStringCatalogComments: Bool { get { get("stringCatalogComments", true) } set { set("stringCatalogComments", newValue) } }

    public var showCodeStructureHeaders: Bool { get { get("structureHeaders", true) } set { set("structureHeaders", newValue) } }
    public var showMarkSeparators: Bool { get { get("markSeparators", true) } set { set("markSeparators", newValue) } }
    public var showCoverageCounts: Bool { get { get("coverageCounts", true) } set { set("coverageCounts", newValue) } }
    public var showEndifConditions: Bool { get { get("endifConditions", true) } set { set("endifConditions", newValue) } }
    public enum ScopeGuides: String, CaseIterable, Sendable { case none = "None", lines = "Lines" }
    public var scopeGuides: ScopeGuides {
        get { ScopeGuides(rawValue: get("scopeGuides", "None")) ?? .none }
        set { set("scopeGuides", newValue.rawValue) }
    }
    public var reformatColumn: Int { get { pageGuideColumn } set { pageGuideColumn = newValue } }
    public var showReformattingGuide: Bool { get { showPageGuide } set { showPageGuide = newValue } }
    public var reformatWhenCompleting: Bool { get { get("reformatWhenCompleting", false) } set { set("reformatWhenCompleting", newValue) } }
    public var dimInactiveCode: Bool { get { get("dimInactiveCode", true) } set { set("dimInactiveCode", newValue) } }

    public enum EditorOverscroll: String, CaseIterable, Sendable {
        case none = "None", small = "Small", medium = "Medium", large = "Large"
        public var fraction: CGFloat {
            switch self { case .none: 0; case .small: 0.25; case .medium: 0.5; case .large: 0.75 }
        }
    }
    public var editorOverscroll: EditorOverscroll {
        get { EditorOverscroll(rawValue: get("editorOverscroll", EditorOverscroll.medium.rawValue)) ?? .medium }
        set { set("editorOverscroll", newValue.rawValue) }
    }
    public var fadeDocCommentDelimiters: Bool { get { get("fadeDocDelimiters", true) } set { set("fadeDocDelimiters", newValue) } }
    public var fadeCommentDelimiters: Bool { get { get("fadeCommentDelimiters", true) } set { set("fadeCommentDelimiters", newValue) } }
}
