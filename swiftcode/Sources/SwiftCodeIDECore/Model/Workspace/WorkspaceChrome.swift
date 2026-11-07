import Foundation

public enum WorkspaceChrome {

    public static let windowWidth: Double = 1400
    public static let windowHeight: Double = 900
    public static let navigatorWidth: Double = 290
    public static let inspectorWidth: Double = 260
    public static let toolbarHeight: Double = 52
    public static let toolbarItemHeight: Double = 36
    public static let toolbarItemTop: Double = 8
    public static let debugAreaHeight: Double = 135

    public static let selectorHeight: Double = 30
    public static let selectorInset: Double = 6
    public static let selectorPillSize = (width: 30.0, height: 24.0)
    public static let rowHeight: Double = 22
    public static let firstRowGap: Double = 7
    public static let indentationPerLevel: Double = 12
    public static let disclosureX: Double = 12
    public static let filterBarHeight: Double = 30
    public static let filterBarBottomInset: Double = 7
    public static let plusCircleWidth: Double = 31
    public static let plusToFilter: Double = 5

    public static let navigatorSymbols = [
        "folder", "arrow.triangle.branch", "bookmark", "magnifyingglass", "exclamationmark.triangle",
        "checkmark.diamond", "gauge.with.dots.needle.33percent", "tag", "list.bullet.rectangle",
    ]

    public static let jumpBarBandHeight: Double = EditorMetrics.jumpBarBand
    public static var jumpBarHeight: Double { jumpBarBandHeight + EditorMetrics.jumpBarSeparator }
    public static let gutterWidth: Double = 48
    public static let foldingRibbonWidth: Double = 12
    public static let textInset: Double = 9
    public static let minimapFraction: Double = 112.0 / 845.0
    public static let debugBarHeight: Double = 36
    public static let bottomBarHeight: Double = 28
    public static let bottomBarSideInset: Double = 6

    public static let inspectorSymbols = ["doc", "clock", "questionmark.circle"]
    public static let inspectorTabPillSize = (width: 78.0, height: 24.0)
    public static let inspectorContentInset: Double = 12
    public static let inspectorContentTopInset: Double = 10
    public static let inspectorKeyColumnWidth: Double = 80
    public static let inspectorKeyToValue: Double = 8

    public struct ToolbarItem: Equatable, Sendable {
        public var id: String
        public var symbols: [String]
        public var toolTips: [String]
    }

    public static let leftPanes = ToolbarItem(id: "leftPanes", symbols: ["sidebar.left", "text.bubble"],
                                              toolTips: ["Navigators", "Coding Assistant"])
    public static let runStop = ToolbarItem(id: "run", symbols: ["play.fill", "stop.fill"],
                                            toolTips: ["Build and then run the current scheme", "Stop the running scheme or application"])
    public static let history = ToolbarItem(id: "history", symbols: ["chevron.left", "chevron.right"],
                                            toolTips: ["Show Previous Location in History", "Show Next Location in History"])
    public static let newConversation = ToolbarItem(id: "newConversation", symbols: ["plus.bubble"], toolTips: ["New Conversation"])
    public static let addEditor = ToolbarItem(id: "addEditor", symbols: ["plus.rectangle.on.rectangle"],
                                              toolTips: ["Add Editor Tabs or Editor Panes"])
    public static let editorOptions = ToolbarItem(id: "editorOptions", symbols: ["line.3.horizontal"], toolTips: ["Adjust Editor Options"])
    public static let editorModes = ToolbarItem(id: "editorModes",
                                                symbols: ["rectangle.righthalf.inset.filled", "rectangle.split.2x1", "arrow.left.arrow.right"],
                                                toolTips: ["Canvas", "Assistant", "Code Review"])
    public static let inspectorToggle = ToolbarItem(id: "inspectorToggle", symbols: ["sidebar.right"], toolTips: ["Hide Inspector"])

    public static func symbol(for node: NavigatorNode) -> String {
        symbol(kind: node.kind, name: node.name, path: node.path)
    }

    public static func symbol(kind: NavigatorNode.Kind, name: String, path: String?) -> String {
        switch kind {
        case .container:
            if path?.hasSuffix(".xcworkspace") == true { return "square.stack.3d.up" }
            return path?.hasSuffix(".xcodeproj") == true ? "folder.badge.gearshape" : "shippingbox"
        case .group, .folder: return "folder.fill"
        case .file: return fileSymbol(name)
        }
    }

    public static func fileSymbol(_ name: String) -> String {
        switch URL(fileURLWithPath: name).pathExtension {
        case "swift": "chevron.left.forwardslash.chevron.right"
        case "h", "m", "c", "mm", "cpp": "c.square"
        case "xcassets": "photo.on.rectangle"
        case "xcstrings": "character.book.closed"
        case "plist", "json": "list.bullet.rectangle"
        case "storyboard", "xib": "rectangle.on.rectangle"
        case "xcconfig": "gearshape"
        case "app", "framework", "xctest", "a", "dylib": "shippingbox"
        case "png", "jpg", "jpeg", "gif", "tif", "tiff", "heic", "bmp", "webp": "photo"
        default: "doc.text"
        }
    }

    public enum IconTint: Equatable, Sendable { case orange, lightBlue, blue, grey, accent }

    public static func iconTint(kind: NavigatorNode.Kind, name: String) -> IconTint {
        switch kind {
        case .container: return .blue
        case .group: return .grey
        case .folder: return .lightBlue
        case .file:
            switch URL(fileURLWithPath: name).pathExtension {
            case "swift": return .orange
            case "png", "jpg", "jpeg", "gif", "tif", "tiff", "heic", "bmp", "webp", "xcassets": return .blue
            default: return .accent
            }
        }
    }

    public static func jumpBarFileTitle(_ name: String, hideExtension: Bool) -> String {
        guard hideExtension else { return name }
        let bare = (name as NSString).deletingPathExtension
        return bare.isEmpty ? name : bare
    }

    public static func jumpPath(for url: URL, root: NavigatorNode, workspaceName: String, hideExtension: Bool) -> [(String, String)] {
        var trail: [NavigatorNode] = []
        func search(_ n: NavigatorNode, _ path: [NavigatorNode]) -> Bool {
            if n.path == url.path && n.kind == .file { trail = path + [n]; return true }
            return n.children.contains { search($0, path + [n]) }
        }
        _ = search(root, [])
        if trail.isEmpty {
            return [(workspaceName, "folder.badge.gearshape"), (jumpBarFileTitle(url.lastPathComponent, hideExtension: hideExtension), "doc.text")]
        }
        return trail.map { ($0.kind == .file ? jumpBarFileTitle($0.name, hideExtension: hideExtension) : $0.name, symbol(for: $0)) }
    }

    public static let jumpBarNoSymbol = "No Selection"

    public static func fileTypeName(for url: URL) -> String {
        switch url.pathExtension {
        case "swift": "Swift Source"
        case "m": "Objective-C Source"
        case "h": "C Header"
        case "c": "C Source"
        case "plist": "Property List"
        case "xcconfig": "Configuration Settings File"
        case "png": "PNG Image"
        case "jpg", "jpeg": "JPEG Image"
        case "gif": "GIF Image"
        case "tif", "tiff": "TIFF Image"
        case "heic": "HEIC Image"
        default: "Default"
        }
    }

    public static func activityFinishedText(_ result: String, at date: Date) -> String {
        "\(result) \u{2022} Today at \(DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short))"
    }

    public static let textEncodingItems = ["No Explicit Encoding", "Unicode (UTF-8)"]
    public static let lineEndingItems = ["No Explicit Line Endings", "macOS / Unix (LF)"]
}

extension WorkspaceChrome {
    public struct DefaultThemeColors: Equatable, Sendable {
        public var background: ThemeColor
        public var foreground: ThemeColor
        public var currentLine: ThemeColor
        public var lineNumber: ThemeColor
        public var selection: ThemeColor
        public var tokens: [String: ThemeColor]
    }

    public static func defaultThemeColors(dark: Bool) -> DefaultThemeColors {
        func c(_ hex: String) -> ThemeColor { ThemeColor(hex: hex)! }
        if dark {
            return DefaultThemeColors(
                background: c("#1E1E1E"), foreground: c("#FFFFFF"), currentLine: c("#292929"), lineNumber: c("#9A9A9A"),
                selection: c("#3F638B"),
                tokens: ["keyword": c("#EB4B63"), "comment": c("#8C8C8C"), "docComment": c("#68CE67"), "string": c("#EB534E"),
                         "number": c("#0A84FF"), "preprocessor": c("#FF9F0A"), "attribute": c("#AC8E68"), "typeName": c("#CA43EA")])
        }
        return DefaultThemeColors(
            background: c("#FFFFFF"), foreground: c("#000000"), currentLine: c("#F2F2F2"), lineNumber: c("#A6A6A6"),
            selection: c("#B3D7FF"),
            tokens: ["keyword": c("#EB445A"), "comment": c("#808080"), "docComment": c("#67C468"), "string": c("#EB4C46"),
                     "number": c("#007AFF"), "preprocessor": c("#FF9500"), "attribute": c("#A2845E"), "typeName": c("#BB3ED9")])
    }
}
