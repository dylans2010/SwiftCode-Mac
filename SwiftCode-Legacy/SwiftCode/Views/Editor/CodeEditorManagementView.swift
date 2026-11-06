import SwiftUI
import Combine

@MainActor
final class CodeEditorManagementView: ObservableObject {

    // MARK: - Published State

    @Published var content: String = "" {
        didSet { onContentChanged() }
    }
    @Published var cursorPosition: Int = 0
    @Published var selectedRange: NSRange = NSRange(location: 0, length: 0)
    @Published var currentLine: Int = 1
    @Published var currentColumn: Int = 1
    @Published var isDirty: Bool = false
    @Published var symbols: [CodeSymbol] = []
    @Published var theme: CodeColoringTheme = .dark
    @Published var fontSize: CGFloat = 14
    @Published var showMinimap: Bool = false
    @Published var wordWrap: Bool = false

    // MARK: - Services

    let suggestionEngine = AISuggestionEngine.shared
    let structureAnalyzer = CodeStructureAnalyzer.shared
    let executionManager  = CodeExecutionManager.shared

    private var analysisTask: Task<Void, Never>?
    private var lastSavedContent: String = ""

    // MARK: - Init

    init() {
        let settings = AppSettings.shared
        theme = CodeColoringTheme.theme(for: settings.selectedThemeID)
        fontSize = CGFloat(settings.editorFontSize)
    }

    // MARK: - Load File

    func load(content: String, fileName: String = "") {
        self.content = content
        lastSavedContent = content
        isDirty = false
        cursorPosition = 0
        currentLine = 1
        currentColumn = 1
        analyzeStructure()
        refreshTheme()
    }

    // MARK: - Content Change Handler

    private func onContentChanged() {
        isDirty = content != lastSavedContent
        updateCursorInfo()
        scheduleAnalysis()
    }

    // MARK: - Cursor Info

    func updateCursorInfo() {
        let head = content.prefix(cursorPosition)
        let lines = head.components(separatedBy: "\n")
        currentLine = lines.count
        currentColumn = (lines.last?.count ?? 0) + 1
    }

    // MARK: - Structure Analysis

    private func scheduleAnalysis() {
        analysisTask?.cancel()
        analysisTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            analyzeStructure()
        }
    }

    func analyzeStructure() {
        symbols = structureAnalyzer.analyze(content)
    }

    // MARK: - AI Suggestions

    func requestAISuggestion(fileName: String) {
        guard cursorPosition <= content.count else { return }
        let prefix = String(content.prefix(cursorPosition))
        let suffix = String(content.suffix(content.count - cursorPosition))
        suggestionEngine.requestCompletion(
            prefix: prefix,
            suffix: suffix,
            fileName: fileName
        )
    }

    func acceptSuggestion() {
        let accepted = suggestionEngine.acceptSuggestion()
        guard !accepted.isEmpty, cursorPosition <= content.count else { return }
        let idx = content.index(content.startIndex, offsetBy: cursorPosition)
        content.insert(contentsOf: accepted, at: idx)
        cursorPosition += accepted.count
    }

    // MARK: - Theme

    func refreshTheme() {
        theme = CodeColoringTheme.theme(for: AppSettings.shared.selectedThemeID)
        fontSize = CGFloat(AppSettings.shared.editorFontSize)
    }

    // MARK: - Mark Saved

    func markSaved() {
        lastSavedContent = content
        isDirty = false
    }

    // MARK: - Statistics

    var statistics: CodeStatistics {
        structureAnalyzer.statistics(for: content)
    }

    // MARK: - Go To Line

    func cursorOffset(forLine line: Int) -> Int {
        let lines = content.components(separatedBy: "\n")
        guard line > 0, line <= lines.count else { return 0 }
        let before = lines.prefix(line - 1).joined(separator: "\n")
        return min(before.count + (line > 1 ? 1 : 0), content.count)
    }

    func goToLine(_ line: Int) {
        cursorPosition = cursorOffset(forLine: line)
        updateCursorInfo()
    }

    // MARK: - Format

    func formatDocument() {
        let lines = content.components(separatedBy: "\n")
        let trimmed = lines.map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
        content = trimmed.joined(separator: "\n")
    }
}
