import Foundation
import SwiftCodeIDECore

public enum ShellCommand: String, CaseIterable, Sendable {
    case open, closeWorkspace, newProject, closeDocument, save, saveAll, revertToSaved
    case find, findAndReplace, findNext, findPrevious, useSelectionForFind
    case commentSelection, shiftLeft, shiftRight, moveLineUp, moveLineDown
    case showProjectNavigator, showFindNavigator, showIssueNavigator, showDebugNavigator, showBreakpointNavigator
    case toggleNavigator, toggleInspector, toggleDebugArea, activateConsole
    case findInWorkspace
    case revealInProjectNavigator, goBack, goForward, nextIssue, previousIssue, jumpToLine
    case run, test, stop, build, clean
    case pauseOrContinue, stepOver, stepInto, stepOut, toggleBreakpointsActive, toggleBreakpointAtCurrentLine,
         toggleBreakpointsEnabledAtCurrentLine, deleteAllBreakpoints, clearConsole
    case copyConsoleRowWithVisibleMetadata, copyConsoleRowWithAllMetadata, copyConsoleRowWithoutMetadata
    case createSwiftErrorBreakpoint, createExceptionBreakpoint, createSymbolicBreakpoint
    case toggleNavigateToSourceOnPause, toggleAlwaysShowDisassembly, viewMemory
    case jumpToDefinition, jumpToOriginalSource, renameSymbol, showQuickHelp, findSelectedSymbol, showCallHierarchy
    case showSymbolNavigator, showFileInspector, showQuickHelpInspector
    case welcome, downloads, organizer
    case about, help, releaseNotes, reportBug, swiftBook, clone
    case scmCommit, scmPush, scmPull, scmFetch, scmRefresh, scmStageAll, scmStageSelected, scmUnstageAll, scmUnstageSelected
    case scmMarkResolved, scmAddSelected, scmCherryPick, scmStash, scmDiscardAll, scmDiscardSelected
    case scmNewRepository
    case scmMerge
    case scmResolveConflicts, scmContinueIntegration, scmAbortIntegration
    case showSourceControlNavigator, showTestNavigator, showReportNavigator
    case testAgain
    case showCodingAssistant, newConversation, jumpToNextActiveConversation
    case codingToolExplain, codingToolDocument, codingToolGeneratePlayground, codingToolGeneratePreview
    case toggleCanvas, canvasLayoutAutomatic, canvasLayoutRight, canvasLayoutBottom

    public var action: (selector: String, tag: Int) {
        switch self {
        case .open: ("openDocument:", 0)
        case .newProject: ("newProject:", 0)
        case .closeWorkspace: ("closeWorkspace:", 0)
        case .closeDocument: ("closeDocument:", 0)
        case .save: ("saveDocument:", 0)
        case .saveAll: ("swiftcodeUnavailableSaveAll:", 0)
        case .revertToSaved: ("revertDocumentToSaved:", 0)
        case .find: ("performFindPanelAction:", 1)
        case .findAndReplace: ("performFindPanelAction:", 12)
        case .findNext: ("performFindPanelAction:", 2)
        case .findPrevious: ("performFindPanelAction:", 3)
        case .useSelectionForFind: ("performFindPanelAction:", 7)
        case .commentSelection: ("commentSelection:", 0)
        case .shiftLeft: ("shiftLeft:", 0)
        case .shiftRight: ("shiftRight:", 0)
        case .moveLineUp: ("moveLineUp:", 0)
        case .moveLineDown: ("moveLineDown:", 0)
        case .jumpToLine: ("jumpToLine:", 0)
        case .showProjectNavigator: ("showNavigator:", ShellNavigator.project.selectorIndex)
        case .showFindNavigator: ("showNavigator:", ShellNavigator.find.selectorIndex)
        case .showIssueNavigator: ("showNavigator:", ShellNavigator.issues.selectorIndex)
        case .showDebugNavigator: ("showNavigator:", ShellNavigator.debug.selectorIndex)
        case .showBreakpointNavigator: ("showNavigator:", ShellNavigator.breakpoints.selectorIndex)
        case .toggleNavigator: ("toggleNavigator:", 0)
        case .toggleInspector: ("toggleInspector:", 0)
        case .toggleDebugArea: ("toggleDebugArea:", 0)
        case .activateConsole: ("activateConsole:", 0)
        case .findInWorkspace: ("findInWorkspace:", 0)
        case .revealInProjectNavigator: ("revealInProjectNavigator:", 0)
        case .goBack: ("goBack:", 0)
        case .goForward: ("goForward:", 0)
        case .nextIssue: ("jumpToNextIssue:", 0)
        case .previousIssue: ("jumpToPreviousIssue:", 0)
        case .run: ("runProduct:", 0)
        case .test: ("testProduct:", 0)
        case .stop: ("stopProduct:", 0)
        case .build: ("buildProduct:", 0)
        case .clean: ("cleanProduct:", 0)
        case .pauseOrContinue: ("pauseOrContinue:", 0)
        case .stepOver: ("stepOver:", 0)
        case .stepInto: ("stepInto:", 0)
        case .stepOut: ("stepOut:", 0)
        case .toggleBreakpointsActive: ("toggleBreakpointsActive:", 0)
        case .toggleBreakpointAtCurrentLine: ("toggleBreakpointAtCurrentLine:", 0)
        case .toggleBreakpointsEnabledAtCurrentLine: ("toggleBreakpointsEnabledAtCurrentLine:", 0)
        case .deleteAllBreakpoints: ("deleteAllBreakpoints:", 0)
        case .clearConsole: ("clearConsole:", 0)
        case .copyConsoleRowWithVisibleMetadata: ("copyConsoleRowWithVisibleMetadata:", 0)
        case .copyConsoleRowWithAllMetadata: ("copyConsoleRowWithAllMetadata:", 0)
        case .copyConsoleRowWithoutMetadata: ("copyConsoleRowWithoutMetadata:", 0)
        case .createSwiftErrorBreakpoint: ("createSwiftErrorBreakpoint:", 0)
        case .createExceptionBreakpoint: ("createExceptionBreakpoint:", 0)
        case .createSymbolicBreakpoint: ("createSymbolicBreakpoint:", 0)
        case .toggleNavigateToSourceOnPause: ("toggleNavigateToSourceOnPause:", 0)
        case .toggleAlwaysShowDisassembly: ("toggleAlwaysShowDisassembly:", 0)
        case .viewMemory: ("swiftcodeUnavailableViewMemory:", 0)
        case .welcome: ("showWelcomeWindow:", 0)
        case .downloads: ("showDownloads:", 0)
        case .organizer: ("showOrganizer:", 0)
        case .about: ("showAboutWindow:", 0)
        case .help: ("showSwiftCodeHelp:", 0)
        case .releaseNotes: ("showReleaseNotes:", 0)
        case .reportBug: ("reportBug:", 0)
        case .swiftBook: ("showSwiftBook:", 0)
        case .clone: ("scmClone:", 0)
        case .showSourceControlNavigator: ("showNavigator:", ShellNavigator.sourceControl.selectorIndex)
        case .showTestNavigator: ("showNavigator:", ShellNavigator.tests.selectorIndex)
        case .showReportNavigator: ("showNavigator:", ShellNavigator.reports.selectorIndex)
        case .testAgain: ("testAgain:", 0)
        case .jumpToDefinition: ("jumpToDefinition:", 0)
        case .jumpToOriginalSource: ("jumpToOriginalSource:", 0)
        case .renameSymbol: ("renameSymbol:", 0)
        case .showQuickHelp: ("showQuickHelpForSelection:", 0)
        case .findSelectedSymbol: ("findSelectedSymbol:", 0)
        case .showCallHierarchy: ("showCallHierarchy:", 0)
        case .showSymbolNavigator: ("showNavigator:", ShellNavigator.symbols.selectorIndex)
        case .showFileInspector: ("showInspector:", 0)
        case .showQuickHelpInspector: ("showInspector:", 2)
        case .toggleCanvas: ("toggleCanvas:", 0)
        case .canvasLayoutAutomatic: ("setCanvasLayout:", 0)
        case .canvasLayoutRight: ("setCanvasLayout:", 1)
        case .canvasLayoutBottom: ("setCanvasLayout:", 2)
        default: (Self.integrateSelectors[self] ?? Self.assistantActions[self]?.selector ?? "", 0)
        }
    }

    public var menu: String {
        switch self {
        case .open, .closeWorkspace, .newProject, .closeDocument, .save, .saveAll, .revertToSaved: "File"
        case .find, .findAndReplace, .findNext, .findPrevious, .useSelectionForFind: "Find"
        case .commentSelection, .shiftLeft, .shiftRight, .moveLineUp, .moveLineDown: "Editor"
        case .showProjectNavigator, .showFindNavigator, .showIssueNavigator, .showDebugNavigator, .showBreakpointNavigator,
             .toggleNavigator, .toggleInspector, .toggleDebugArea, .activateConsole: "View"
        case .findInWorkspace: "Find"
        case .revealInProjectNavigator, .goBack, .goForward, .nextIssue, .previousIssue, .jumpToLine: "Navigate"
        case .run, .test, .stop, .build, .clean: "Product"
        case .pauseOrContinue, .stepOver, .stepInto, .stepOut, .toggleBreakpointsActive, .toggleBreakpointAtCurrentLine,
             .toggleBreakpointsEnabledAtCurrentLine, .deleteAllBreakpoints, .clearConsole,
             .copyConsoleRowWithVisibleMetadata, .copyConsoleRowWithAllMetadata, .copyConsoleRowWithoutMetadata: "Debug"
        case .createSwiftErrorBreakpoint, .createExceptionBreakpoint, .createSymbolicBreakpoint, .toggleNavigateToSourceOnPause,
             .toggleAlwaysShowDisassembly, .viewMemory: "Debug"
        case .welcome, .downloads, .organizer: "Window"
        case .about: "SwiftCode"
        case .help, .releaseNotes, .reportBug, .swiftBook: "Help"
        case .clone: "Integrate"
        case .showSourceControlNavigator, .showTestNavigator, .showReportNavigator: "View"
        case .testAgain: "Product"
        case .jumpToDefinition, .jumpToOriginalSource: "Navigate"
        case .renameSymbol: "Editor"
        case .showQuickHelp: "Help"
        case .findSelectedSymbol, .showCallHierarchy: "Find"
        case .showSymbolNavigator, .showFileInspector, .showQuickHelpInspector: "View"
        case .toggleCanvas, .canvasLayoutAutomatic, .canvasLayoutRight, .canvasLayoutBottom: "Editor"
        default: Self.assistantActions[self]?.menu ?? "Integrate"
        }
    }

    static let integrateSelectors: [ShellCommand: String] = [
        .scmCommit: "showCommitSheet:", .scmPush: "scmPush:", .scmPull: "scmPull:", .scmFetch: "scmFetch:", .scmRefresh: "refreshFileStatus:",
        .scmStageAll: "scmStageAll:", .scmStageSelected: "scmStageSelected:", .scmUnstageAll: "scmUnstageAll:",
        .scmUnstageSelected: "scmUnstageSelected:", .scmMarkResolved: "scmMarkResolved:", .scmAddSelected: "scmAddSelected:",
        .scmCherryPick: "scmCherryPick:", .scmStash: "scmStash:",
        .scmDiscardAll: "scmDiscardAll:", .scmDiscardSelected: "scmDiscardSelected:", .scmNewRepository: "scmNewRepository:",
        .scmResolveConflicts: "scmResolveConflicts:", .scmContinueIntegration: "scmContinueIntegration:",
        .scmAbortIntegration: "scmAbortIntegration:", .scmMerge: "scmMerge:",
    ]

    public var isSourceControl: Bool { Self.integrateSelectors[self] != nil }

    public var menuCommand: MenuCommand? {
        let (selector, tag) = action
        return Self.table.first { $0.action == selector && $0.tag == tag && !$0.isAlternate }
    }

    public func title(in context: MenuContext?) -> String {
        guard let c = menuCommand else { return rawValue }
        if self == .findInWorkspace, let ctx = context { return "Find in \(ctx.scopeName)" }
        return MenuTitles.title(for: c, in: context)
    }

    public var shortcut: ShellShortcut? { menuCommand.flatMap(ShellShortcut.init(command:)) }

    static let table: [MenuCommand] = {
        var out: [MenuCommand] = []
        func walk(_ items: [MenuItemSpec]) {
            for i in items {
                switch i {
                case .command(let c): out.append(c)
                case .submenu(_, let sub): walk(sub)
                case .separator, .label: break
                }
            }
        }
        for (_, items) in CommandTable.menus { walk(items) }
        return out
    }()
}

public struct ShellShortcut: Equatable, Hashable, Sendable {
    public var key: String
    public var modifiers: MenuCommand.Modifiers
    public init(key: String, modifiers: MenuCommand.Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    public init?(command c: MenuCommand) {
        guard !c.key.isEmpty else { return nil }
        if let base = Key.shiftedBase[c.key] { self.init(key: base, modifiers: c.modifiers.union(.shift)) } else {
            self.init(key: c.key, modifiers: c.modifiers)
        }
    }

    public var text: String { Shortcut.text(key: key, modifiers: modifiers) }
}

public enum ShellNavigator: String, CaseIterable, Sendable, Identifiable {
    case project, sourceControl, symbols, find, issues, tests, debug, breakpoints, reports

    public var id: String { rawValue }

    public var selectorIndex: Int {
        switch self {
        case .project: 0
        case .sourceControl: 1
        case .symbols: 2
        case .find: 3
        case .issues: 4
        case .tests: 5
        case .debug: 6
        case .breakpoints: 7
        case .reports: 8
        }
    }

    public var title: String { self == .symbols ? "Symbols" : CommandTable.navigators[selectorIndex] }

    public var symbolName: String {
        switch self {
        case .project: "folder"
        case .sourceControl: "arrow.triangle.branch"
        case .symbols: "list.bullet.indent"
        case .find: "magnifyingglass"
        case .issues: "exclamationmark.triangle"
        case .tests: "checkmark.diamond"
        case .reports: "list.bullet.rectangle"
        case .debug, .breakpoints: WorkspaceChrome.navigatorSymbols[selectorIndex]
        }
    }

    public var toolTip: String {
        self == .symbols ? "Show the Symbol navigator" : NavigatorBars.selectorToolTips[selectorIndex]
    }

    public static var selectorButtons: [(symbol: String, toolTip: String, title: String)] {
        WorkspaceChrome.navigatorSymbols.indices.map { i in
            guard let n = allCases.first(where: { $0.selectorIndex == i }) else {
                return (WorkspaceChrome.navigatorSymbols[i], NavigatorBars.selectorToolTips[i], CommandTable.navigators[i])
            }
            return (n == .symbols ? n.symbolName : WorkspaceChrome.navigatorSymbols[i], n.toolTip,
                    n == .symbols ? n.title : CommandTable.navigators[i])
        }
    }

    public var command: ShellCommand {
        switch self {
        case .project: .showProjectNavigator
        case .sourceControl: .showSourceControlNavigator
        case .symbols: .showSymbolNavigator
        case .find: .showFindNavigator
        case .issues: .showIssueNavigator
        case .tests: .showTestNavigator
        case .reports: .showReportNavigator
        case .debug: .showDebugNavigator
        case .breakpoints: .showBreakpointNavigator
        }
    }
}
