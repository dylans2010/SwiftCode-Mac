import AppKit
import SwiftCodeMCP

@MainActor
public final class ExtensionChangeReviewPresenter {
    public var reviewer: ((MCPChange) async -> Bool)?

    public var windowProvider: () -> NSWindow? = { NSApp.keyWindow ?? NSApp.mainWindow }

    public init() {}

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
