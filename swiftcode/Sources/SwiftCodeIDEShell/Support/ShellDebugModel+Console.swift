import Foundation
import SwiftCodeIDECore

@MainActor
public enum ShellPasteboard {
    public static var writer: ((String) -> Void)?
    public private(set) static var lastCopied: String?

    public static func copy(_ text: String) {
        lastCopied = text
        writer?(text)
    }
}

extension ShellDebugModel {
    public enum ConsoleRowCopy: Sendable {
        case visibleMetadata, allMetadata, withoutMetadata
    }

    public var consoleRows: [ConsoleRow] {
        ConsoleRows.rows(session.consoleEntries.filter { consoleFilter.includes($0.kind) })
    }

    public var selectedConsoleRowValue: ConsoleRow? {
        guard let i = selectedConsoleRow else { return nil }
        let rows = consoleRows
        return rows.indices.contains(i) ? rows[i] : nil
    }

    public func consoleRowCopyText(_ kind: ConsoleRowCopy) -> String? {
        guard let row = selectedConsoleRowValue else { return nil }
        switch kind {
        case .visibleMetadata, .withoutMetadata: return ConsoleRows.copyText(row, metadata: nil)
        case .allMetadata: return ConsoleRows.copyText(row, metadata: ConsoleRows.allMetadata)
        }
    }

    @discardableResult
    public func copyConsoleRow(_ kind: ConsoleRowCopy) -> Bool {
        guard let text = consoleRowCopyText(kind) else { return false }
        ShellPasteboard.copy(text)
        return true
    }

    static func copyKind(_ c: ShellCommand) -> ConsoleRowCopy? {
        switch c {
        case .copyConsoleRowWithVisibleMetadata: .visibleMetadata
        case .copyConsoleRowWithAllMetadata: .allMetadata
        case .copyConsoleRowWithoutMetadata: .withoutMetadata
        default: nil
        }
    }
}
