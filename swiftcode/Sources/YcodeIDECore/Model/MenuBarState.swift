import Foundation

public struct MenuContext: Equatable, Sendable {
    public var containerKind: WorkspaceModel.ContainerKind = .project
    public var workspaceName = ""
    public var fileName: String?
    public var caretLine: Int?
    public var editorTabCount = 1
    public var editorPaneCount = 1
    public var windowTabCount = 1
    public var isWindowTabBarVisible = false
    public var isFullScreen = false
    public var sourceEditorFocused = false
    public var editorKind: EditorKind = .source
    public var inlineIssuesShown = true
    public var repositoryHasRemote = false
    public var integrationVerb = ""
    public var hasConflicts = false
    public var isDebugging = false
    public var isPaused = false
    public var breakpointsActive = true
    public var caretLineBreakpointsEnabled: Bool?
    public var navigatorShown = true
    public var codingAssistantShown = false
    public var inspectorShown = true
    public var debugAreaShown = false
    public var editorTabBarShown = false
    public var editorTabPinned = false
    public var hasNavigatorFileSelection = false
    public var selectedFileIsUntracked = false
    public var pasteboardHasText = false
    public var projectSelection: ProjectSelection?
    public var projectSelectionInFolder = false
    public var hasItemToMove = false

    public enum ProjectSelection: Equatable, Sendable { case file, group }

    public init() {}

    public var scopeName: String {
        switch containerKind {
        case .project: "Project"
        case .workspace: "Workspace"
        case .package: "Package"
        }
    }
}

public enum MenuTitles {
    static func quoted(_ s: String) -> String { "\u{201C}\(s)\u{201D}" }

    public static func title(for c: MenuCommand, in ctx: MenuContext?) -> String {
        title(generic: c.title, in: ctx)
    }

    public static func title(generic g: String, in ctx: MenuContext?) -> String {
        guard let ctx else { return g }
        let file = ctx.fileName
        switch g {
        case "Add Files…": return "Add Files to \(quoted(ctx.workspaceName))…"
        case "Close Tab, Editor Pane, Window Tab, or Window": return CloseShortcutRule.commandWTitle(tabCount: ctx.editorTabCount)
        case "Close Document": return EditorCloseCommand.document.title(fileName: file, isPackage: false)
        case "Close Window": return ctx.windowTabCount > 1 ? "Close Window Tab" : "Close Window"
        case "Close Workspace": return "Close \(ctx.scopeName)"
        case "Workspace Settings…": return "\(ctx.scopeName) Settings…"
        case "File from Clipboard": return ctx.pasteboardHasText ? "New File from Clipboard" : g
        case "Bookmark Line":
            if let file, let n = ctx.caretLine { return "Bookmark \(quoted(file)) Line \(n)" }
        case "Bookmark Line With Dialog":
            if let file, let n = ctx.caretLine { return "Bookmark \(quoted(file)) Line \(n)…" }
        case "Bookmark File":
            if let file { return "Bookmark \(quoted(file))" }
        case "Bookmark File With Dialog":
            if let file { return "Bookmark \(quoted(file))…" }
        case "Show Editor Tab Bar": return ctx.editorTabBarShown ? "Hide Editor Tab Bar" : g
        case "Pin Editor Tab": return ctx.editorTabPinned ? "Unpin Editor Tab" : g
        case "Show Navigator": return ctx.navigatorShown ? "Hide Navigator" : g
        case "Show Coding Assistant": return ctx.codingAssistantShown ? "Hide Coding Assistant" : g
        case "Show Inspector": return ctx.inspectorShown ? "Hide Inspector" : g
        case "Show Debug Area": return ctx.debugAreaShown ? "Hide Debug Area" : g
        case "Show Window Tab Bar": return ctx.isWindowTabBarVisible ? "Hide Window Tab Bar" : g
        case "Enter Full Screen": return ctx.isFullScreen ? "Exit Full Screen" : g
        case "Show All Issues": return ctx.inlineIssuesShown ? "Hide All Issues" : g
        case "Format Selection", "Format File":
            if let file, file.hasSuffix(".swift") { return g + " with \u{2018}swift-format\u{2019}" }
        case "Find in Selected Groups…": return ctx.projectSelection == .file ? "Find in Selected File…" : g
        case "Jump to Line…":
            if let file { return "Jump to Line in \(quoted(file))…" }
        case "Compile File", "Analyze File", "Preprocess File", "Assemble File":
            if let file { return g.replacingOccurrences(of: "File", with: quoted(file)) }
        case "Pause": return ctx.isPaused ? "Continue" : g
        case "Deactivate Breakpoints": return ctx.breakpointsActive ? g : "Activate Breakpoints"
        case "Enable Breakpoints at Current Line": return ctx.caretLineBreakpointsEnabled == true ? "Disable Breakpoints at Current Line" : g
        case "Stage Selected Files":
            if !ctx.hasNavigatorFileSelection, let file { return "Stage Changes in \(quoted(file))" }
            return "Stage Changes in Selected Files"
        case "Unstage Selected Files": return "Unstage Changes in Selected Files"
        case "Mark as Resolved": return "Mark Selected Files as Resolved"
        case "Continue", "Abort": return ctx.integrationVerb.isEmpty ? g : "\(g) \(ctx.integrationVerb)"
        case "Add": return "Add Selected Files"
        case "Discard Changes in Selected Files…":
            if ctx.hasNavigatorFileSelection && ctx.selectedFileIsUntracked { return "Move Selected Files to Trash…" }
            if !ctx.hasNavigatorFileSelection, let file { return "Discard Changes in \(quoted(file))…" }
        default:
            if g.hasPrefix("Find"), g.contains(" in Workspace") {
                return g.replacingOccurrences(of: " in Workspace", with: " in \(ctx.scopeName)")
            }
        }
        return g
    }
}

public enum MenuConditions {
    public static func isShown(_ c: MenuCondition?, in ctx: MenuContext?) -> Bool {
        guard let c else { return true }
        switch c {
        case .sourceEditorFocused: return ctx?.sourceEditorFocused ?? false
        case .repositoryHasRemote: return ctx?.repositoryHasRemote ?? false
        case .integrationInProgress: return ctx.map { !$0.integrationVerb.isEmpty || $0.hasConflicts } ?? false
        case .debugging: return ctx?.isDebugging ?? false
        case .separateCloseWindow: return ctx.map { CloseShortcutRule.showsSeparateCloseWindow(tabCount: $0.editorTabCount) } ?? true
        case .groupsAllowed: return !(ctx?.projectSelectionInFolder ?? false)
        case .itemToMove: return ctx?.hasItemToMove ?? false
        }
    }

    public static func visibleSeparators(isSeparator: [Bool], isVisible: [Bool]) -> [Bool] {
        var out = Array(repeating: false, count: isSeparator.count)
        var sawItem = false
        var pending: Int?
        for i in isSeparator.indices {
            if isSeparator[i] {
                if sawItem && pending == nil { pending = i }
            } else if isVisible[i] {
                if let p = pending { out[p] = true }
                pending = nil
                sawItem = true
            }
        }
        return out
    }
}
