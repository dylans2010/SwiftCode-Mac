import AppKit
import Foundation

public enum CodingDictionaryEntryText {
    public static func attributedString(for result: CodingDictionaryResult) -> NSAttributedString {
        let out = NSMutableAttributedString()
        func heading(_ text: String) {
            out.append(NSAttributedString(
                string: "\n\(text)\n",
                attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                             .foregroundColor: NSColor.labelColor]
            ))
        }
        func body(_ text: String) {
            guard !text.isEmpty else { return }
            out.append(NSAttributedString(
                string: "\(text)\n",
                attributes: [.font: NSFont.systemFont(ofSize: 13),
                             .foregroundColor: NSColor.labelColor]
            ))
        }
        func bullet(_ text: String) {
            guard !text.isEmpty else { return }
            out.append(NSAttributedString(
                string: "•  \(text)\n",
                attributes: [.font: NSFont.systemFont(ofSize: 13),
                             .foregroundColor: NSColor.labelColor]
            ))
        }
        func code(_ text: String) {
            guard !text.isEmpty else { return }
            out.append(NSAttributedString(
                string: "\(text)\n",
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                             .foregroundColor: NSColor.labelColor]
            ))
        }
        func list(_ title: String, _ items: [String]) {
            guard !items.isEmpty else { return }
            heading(title)
            for item in items { bullet(item) }
        }

        out.append(NSAttributedString(
            string: "\(result.title)\n",
            attributes: [.font: NSFont.systemFont(ofSize: 20, weight: .bold),
                         .foregroundColor: NSColor.labelColor]
        ))
        if !result.subtitle.isEmpty {
            out.append(NSAttributedString(
                string: "\(result.subtitle)\n",
                attributes: [.font: NSFont.systemFont(ofSize: 13),
                             .foregroundColor: NSColor.secondaryLabelColor]
            ))
        }
        let meta = [result.kind, result.category, result.difficulty].filter { !$0.isEmpty }.joined(separator: "  ·  ")
        if !meta.isEmpty {
            out.append(NSAttributedString(
                string: "\(meta)\n",
                attributes: [.font: NSFont.systemFont(ofSize: 12),
                             .foregroundColor: NSColor.secondaryLabelColor]
            ))
        }
        if result.confidence < 100 {
            out.append(NSAttributedString(
                string: "Confidence: \(result.confidence)% — the model was unsure about part of this entry.\n",
                attributes: [.font: NSFont.systemFont(ofSize: 12),
                             .foregroundColor: NSColor.secondaryLabelColor]
            ))
        }
        heading("Overview")
        body(result.overview)
        heading("Definition")
        body(result.definition)
        if !result.summary.isEmpty {
            heading("Summary")
            body(result.summary)
        }
        if !result.syntax.isEmpty {
            heading("Syntax")
            code(result.syntax)
        }
        if !result.parameters.isEmpty {
            heading("Parameters")
            for p in result.parameters {
                bullet("\(p.name) (\(p.type)) — \(p.description)")
            }
        }
        if !result.returnValue.type.isEmpty || !result.returnValue.description.isEmpty {
            heading("Return Value")
            body("\(result.returnValue.type) — \(result.returnValue.description)")
        }
        if !result.examples.isEmpty {
            heading("Examples")
            for example in result.examples {
                if !example.title.isEmpty {
                    out.append(NSAttributedString(
                        string: "\(example.title)\n",
                        attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium),
                                     .foregroundColor: NSColor.labelColor]
                    ))
                }
                code(example.code)
            }
        }
        if !result.commonMistakes.isEmpty {
            heading("Common Mistakes")
            for mistake in result.commonMistakes {
                bullet("\(mistake.description) — \(mistake.explanation) Fix: \(mistake.fix)")
            }
        }
        list("Best Practices", result.bestPractices)
        if !result.performanceNotes.isEmpty { heading("Performance"); body(result.performanceNotes) }
        if !result.threadSafety.isEmpty { heading("Thread Safety"); body(result.threadSafety) }
        if !result.securityNotes.isEmpty { heading("Security"); body(result.securityNotes) }
        if !result.complexity.isEmpty { heading("Complexity"); body(result.complexity) }
        if !result.memoryConsiderations.isEmpty { heading("Memory"); body(result.memoryConsiderations) }
        if !result.codeSnippet.isEmpty { heading("Code Snippet"); code(result.codeSnippet) }
        if !result.appleDocsSummary.isEmpty { heading("Apple Documentation"); body(result.appleDocsSummary) }
        if !result.swiftVersion.isEmpty { heading("Swift Version"); body(result.swiftVersion) }
        list("Availability", result.availability)
        list("Alternative APIs", result.alternativeAPIs)
        list("Related Concepts", result.relatedConcepts)
        list("Aliases", result.aliases)
        list("Keywords", result.keywords)
        list("Warnings", result.warnings)
        list("Notes", result.notes)
        list("See Also", result.seeAlso)
        list("References", result.references)
        return out
    }
}

@MainActor
public final class CodingDictionaryWindowManager: NSObject {
    public static let shared = CodingDictionaryWindowManager()
    private var windowController: CodingDictionaryWindowController?

    private override init() {}

    public func showWindow() {
        if let existing = windowController {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = CodingDictionaryWindowController()
        windowController = controller
        controller.window?.delegate = self
        controller.window?.makeKeyAndOrderFront(nil)
    }

    public func closeWindow() {
        windowController?.close()
        windowController = nil
    }
}

extension CodingDictionaryWindowManager: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        windowController = nil
    }
}

@MainActor
public final class CodingDictionaryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    public static let size = NSSize(width: 960, height: 640)

    public let service: CodingDictionaryService

    private let searchField = NSSearchField()
    private let defineButton = NSButton(title: "Define", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let historyTable = NSTableView()
    private let detailTextView = NSTextView()
    private let pinButton = NSButton(title: "Pin", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private let clearButton = NSButton(title: "Clear History", target: nil, action: nil)

    private var currentTask: Task<Void, Never>?
    private var currentResult: CodingDictionaryResult?

    public init(service: CodingDictionaryService = CodingDictionaryService()) {
        self.service = service
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Coding Dictionary"
        window.minSize = NSSize(width: 700, height: 450)
        window.setFrameAutosaveName("SwiftCodeCodingDictionaryWindow")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
        window.center()
        showWelcome()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        guard let content = window?.contentView else { return }
        searchField.placeholderString = "Term, API, or concept (e.g. TaskGroup)"
        searchField.target = self
        searchField.action = #selector(defineClicked)
        defineButton.target = self
        defineButton.action = #selector(defineClicked)
        defineButton.keyEquivalent = "\r"
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        cancelButton.isEnabled = false
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor

        let searchRow = NSStackView(views: [searchField, defineButton, cancelButton])
        searchRow.orientation = .horizontal
        searchRow.spacing = 8

        let historyColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("query"))
        historyTable.addTableColumn(historyColumn)
        historyTable.headerView = nil
        historyTable.rowHeight = 22
        historyTable.dataSource = self
        historyTable.delegate = self
        let historyScroll = NSScrollView()
        historyScroll.documentView = historyTable
        historyScroll.hasVerticalScroller = true

        detailTextView.isEditable = false
        detailTextView.isSelectable = true
        detailTextView.font = .systemFont(ofSize: 13)
        detailTextView.textContainerInset = NSSize(width: 12, height: 12)
        let detailScroll = NSScrollView()
        detailScroll.documentView = detailTextView
        detailScroll.hasVerticalScroller = true
        detailScroll.hasHorizontalScroller = false

        let sep = NSBox()
        sep.boxType = .separator

        pinButton.target = self
        pinButton.action = #selector(pinClicked)
        deleteButton.target = self
        deleteButton.action = #selector(deleteClicked)
        clearButton.target = self
        clearButton.action = #selector(clearClicked)
        let historyBar = NSStackView(views: [pinButton, deleteButton, clearButton])
        historyBar.orientation = .horizontal
        historyBar.spacing = 8

        for view in [searchRow, statusLabel, historyScroll, sep, detailScroll, historyBar] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            searchRow.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            searchRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            searchRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            statusLabel.topAnchor.constraint(equalTo: searchRow.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            historyScroll.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            historyScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            historyScroll.widthAnchor.constraint(equalToConstant: 230),
            historyScroll.bottomAnchor.constraint(equalTo: historyBar.topAnchor, constant: -8),

            sep.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            sep.bottomAnchor.constraint(equalTo: historyBar.topAnchor, constant: -8),
            sep.leadingAnchor.constraint(equalTo: historyScroll.trailingAnchor, constant: 4),
            sep.widthAnchor.constraint(equalToConstant: 1),

            detailScroll.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            detailScroll.leadingAnchor.constraint(equalTo: sep.trailingAnchor, constant: 4),
            detailScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            detailScroll.bottomAnchor.constraint(equalTo: historyBar.topAnchor, constant: -8),

            historyBar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            historyBar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            historyBar.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
        updateHistoryButtons()
    }

    private func showWelcome() {
        statusLabel.stringValue = "Definitions are generated by your configured Coding Assistant provider. Type a term above and press Define."
        detailTextView.string = "The Coding Dictionary explains Swift, Apple frameworks, tools, and programming concepts.\n\nEnter a term above — for example “TaskGroup”, “@MainActor”, or “git rebase” — and the dictionary generates a structured entry: definition, syntax, parameters, examples, common mistakes, and best practices.\n\nPast queries are kept in the history on the left. Select one to define it again."
    }

    @objc func defineClicked() {
        define(query: searchField.stringValue)
    }

    public func define(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        currentTask?.cancel()
        defineButton.isEnabled = false
        cancelButton.isEnabled = true
        statusLabel.stringValue = "Defining “\(trimmed)”…"
        historyTable.reloadData()
        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.service.define(query: trimmed)
                self.currentResult = result
                self.detailTextView.textStorage?.setAttributedString(CodingDictionaryEntryText.attributedString(for: result))
                self.statusLabel.stringValue = "“\(result.title)” — generated by the configured provider."
            } catch is CancellationError {
                self.statusLabel.stringValue = "Cancelled."
            } catch let error as CodingDictionaryError {
                self.statusLabel.stringValue = error.localizedDescription
                if case .invalidJSON(let rawText) = error {
                    self.detailTextView.string = rawText
                }
            } catch {
                self.statusLabel.stringValue = error.localizedDescription
            }
            self.defineButton.isEnabled = true
            self.cancelButton.isEnabled = false
            self.historyTable.reloadData()
            self.updateHistoryButtons()
        }
    }

    @objc func cancelClicked() {
        currentTask?.cancel()
    }

    @objc func pinClicked() {
        let row = historyTable.selectedRow
        guard row >= 0, row < service.history.count else { return }
        service.togglePin(id: service.history[row].id)
        historyTable.reloadData()
        updateHistoryButtons()
    }

    @objc func deleteClicked() {
        let row = historyTable.selectedRow
        guard row >= 0, row < service.history.count else { return }
        service.deleteHistoryItem(id: service.history[row].id)
        historyTable.reloadData()
        updateHistoryButtons()
    }

    @objc func clearClicked() {
        service.clearHistory()
        historyTable.reloadData()
        updateHistoryButtons()
    }

    private func updateHistoryButtons() {
        let hasSelection = historyTable.selectedRow >= 0
        pinButton.isEnabled = hasSelection
        deleteButton.isEnabled = hasSelection
        clearButton.isEnabled = !service.history.isEmpty
    }

    public func numberOfRows(in tableView: NSTableView) -> Int {
        service.history.count
    }

    public func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard row < service.history.count else { return nil }
        let item = service.history[row]
        let field = NSTextField(labelWithString: item.isPinned ? "★ \(item.query)" : item.query)
        field.font = .systemFont(ofSize: 12)
        return field
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        updateHistoryButtons()
        let row = historyTable.selectedRow
        guard row >= 0, row < service.history.count else { return }
        let query = service.history[row].query
        searchField.stringValue = query
        define(query: query)
    }
}
