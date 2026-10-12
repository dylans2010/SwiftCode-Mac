import Combine
import Foundation

// MARK: - SDKCodeEditorError
//
// Typed failures from `SDKCodeEditorState` document operations. `openFile`
// throws instead of silently opening an empty buffer: a file the editor
// claims to show but cannot read is a fake implementation.

public enum SDKCodeEditorError: Error, Sendable {
    /// The file exists but could not be read as text (permissions, I/O
    /// failure, or undecodable bytes). Carries the URL and the underlying
    /// reason for diagnostics.
    case unreadableFile(url: URL, reason: String)
}

// MARK: - SDKCodeEditorState
//
// The single source of truth for the Studio code editor session: open
// tabs, the active tab, the console, and the find query.
//
// `@MainActor` because it is an `ObservableObject` driving SwiftUI; all
// published state mutates on the main actor. The types it stores are
// value types (`Sendable`), so background work (file reads, builds) can
// prepare values off-main and hand them in without data races.

@MainActor
public final class SDKCodeEditorState: ObservableObject {
    /// Maximum console entries retained. Appends beyond the cap drop the
    /// oldest entries first; `consoleEntries` never grows unbounded.
    public static let maxConsoleEntries: Int = 5_000

    /// Open tabs, in tab-bar order.
    @Published public private(set) var tabs: [SDKCodeEditorTab] = []

    /// The active tab's ID, or `nil` when no tabs are open.
    @Published public private(set) var activeTabID: UUID?

    /// Console output, oldest first, capped at `maxConsoleEntries`.
    @Published public private(set) var consoleEntries: [SDKConsoleEntry] = []

    /// Current find-panel query. Published so the editor view and find
    /// bar stay in sync.
    @Published public var findQuery: String = ""

    public init() {}

    /// The active tab, if any.
    public var activeTab: SDKCodeEditorTab? {
        guard let activeTabID else { return nil }
        return tabs.first(where: { $0.id == activeTabID })
    }

    /// The active document, if any.
    public var activeDocument: SDKCodeDocument? {
        activeTab?.document
    }

    // MARK: - Documents & tabs

    /// Opens `url` in a tab, or activates the existing tab when the file
    /// is already open. The language is inferred from the file extension
    /// (`SDKCodeLanguage.infer(fromFileURL:)`).
    ///
    /// - Throws: `SDKCodeEditorError.unreadableFile` when the file cannot
    ///   be read as UTF-8 text. The caller surfaces this as a console
    ///   entry or alert; no tab is created on failure.
    /// - Returns: The tab ID (existing or newly created).
    @discardableResult
    public func openFile(_ url: URL) throws -> UUID {
        if let existing = tabs.first(where: { $0.document.fileURL == url }) {
            activateTab(existing.id)
            return existing.id
        }
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw SDKCodeEditorError.unreadableFile(url: url, reason: error.localizedDescription)
        }
        let document = SDKCodeDocument(
            fileURL: url,
            language: SDKCodeLanguage.infer(fromFileURL: url),
            text: text
        )
        let tab = SDKCodeEditorTab(document: document)
        tabs.append(tab)
        activateTab(tab.id)
        return tab.id
    }

    /// Closes the tab with `id`. When the closed tab was active, the
    /// neighbor to the right (or left, at the end) becomes active; when
    /// no tabs remain, `activeTabID` becomes `nil`. Unknown IDs are
    /// ignored.
    public func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        guard activeTabID == id else { return }
        if tabs.isEmpty {
            activeTabID = nil
        } else {
            let nextIndex = min(index, tabs.count - 1)
            activateTab(tabs[nextIndex].id)
        }
    }

    /// Makes the tab with `id` active. Unknown IDs are ignored.
    public func activateTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
        tabs = tabs.map { $0.withActive($0.id == id) }
    }

    /// Replaces the text of the document in the tab with `tabID`, marking
    /// it dirty. The standard path for applying editor edits. Unknown tab
    /// IDs are ignored.
    public func updateText(_ text: String, for tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index] = tabs[index].withDocument(tabs[index].document.withText(text))
    }

    /// Marks the document in the tab with `tabID` as saved (clears the
    /// dirty flag) after the caller has written it to disk. Unknown tab
    /// IDs are ignored.
    public func markSaved(tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index] = tabs[index].withDocument(tabs[index].document.saved())
    }

    // MARK: - Console

    /// Appends a console entry. Text longer than
    /// `SDKConsoleEntry.maxTextLength` is truncated with an ellipsis
    /// marker; when the buffer exceeds `maxConsoleEntries`, the oldest
    /// entries are dropped. This is the ONLY append path, so the bounds
    /// cannot be bypassed.
    public func appendConsole(_ entry: SDKConsoleEntry) {
        var text = entry.text
        if text.count > SDKConsoleEntry.maxTextLength {
            text = String(text.prefix(SDKConsoleEntry.maxTextLength)) + "… (truncated)"
        }
        let bounded = text == entry.text
            ? entry
            : SDKConsoleEntry(id: entry.id, timestamp: entry.timestamp, stream: entry.stream, text: text)
        consoleEntries.append(bounded)
        let overflow = consoleEntries.count - Self.maxConsoleEntries
        if overflow > 0 {
            consoleEntries.removeFirst(overflow)
        }
    }

    /// Clears all console entries.
    public func clearConsole() {
        consoleEntries.removeAll()
    }
}
