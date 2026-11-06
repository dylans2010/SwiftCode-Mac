import AppKit
import YcodeMCP

/// The review UI for SDK extension writes (gap closure, specs/ide/
/// gap-closure-windows-artboards.md §4).
///
/// Agent-mode writes are proposed into their conversation
/// (`CodingAssistantModel.proposeAgentChange`); extension writes
/// have no conversation, so this presenter asks in a sheet on the
/// workspace window instead. It is the only thing standing between
/// a granted extension write and the disk: the grant check in
/// `MCPServer.run` runs first (an ungranted tool never reaches
/// this presenter), and a granted write still asks exactly as a
/// host write would. No bypass, no auto-allow.
///
/// The sheet names the extension (the change already carries its
/// caller identity — `MCPServer.run` stamps it via `settingCaller`),
/// shows the change's summary + path + a short excerpt of what
/// changes, and offers Accept / Reject. Closing the sheet rejects.
/// With no visible window to ask in, the answer is refuse — never
/// queue silently, never auto-allow.
@MainActor
public final class ExtensionChangeReviewPresenter {
    /// Answers instead of showing UI (tests): the reviewer's answer.
    public var reviewer: ((MCPChange) async -> Bool)?

    /// The window the sheet attaches to (nil: no window).
    public var windowProvider: () -> NSWindow? = { NSApp.keyWindow ?? NSApp.mainWindow }

    public init() {}

    /// Asks the user about one extension change. `true` means "write it".
    public func review(_ change: MCPChange) async -> Bool {
        if let reviewer { return await reviewer(change) }
        guard let window = windowProvider(), window.isVisible else { return false }
        let alert = NSAlert()
        if let caller = change.caller {
            alert.messageText = "Extension “\(caller.extensionID)” wants to change a file"
        } else {
            alert.messageText = "An extension wants to make a change"
        }
        var info = change.summary
        if !change.relativePath.isEmpty {
            info += "\n\nFile: \(change.relativePath)"
        }
        let excerpt = Self.excerpt(of: change)
        if !excerpt.isEmpty { info += "\n\n\(excerpt)" }
        alert.informativeText = info
        alert.addButton(withTitle: "Accept")
        alert.addButton(withTitle: "Reject")
        let response = await alert.beginSheetModal(for: window)
        return response == .alertFirstButtonReturn
    }

    /// The first lines of what changes, trimmed so the sheet stays
    /// readable. A new file shows the start of its content; an
    /// edit shows the proposed text's start.
    static func excerpt(of change: MCPChange) -> String {
        let proposed = change.proposed
        guard !proposed.isEmpty else { return "" }
        let lines = proposed.components(separatedBy: .newlines)
        let shown = lines.prefix(8).joined(separator: "\n")
        var text = change.original == nil ? "New content:\n\(shown)" : "Proposed:\n\(shown)"
        if lines.count > 8 { text += "\n… (\(lines.count - 8) more lines)" }
        if text.count > 2000 { text = String(text.prefix(2000)) + "\n…" }
        return text
    }
}
