import Foundation
import SwiftUI
import SwiftCodeIDEShell
#if !os(Linux)
import AppKit
#endif

@MainActor
enum ShellClipboard {
    static func copy(_ s: String) {
        #if os(Linux)
        OpenViewsClipboard.copy(s)
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        #endif
    }

    static var string: String? {
        #if os(Linux)
        OpenViewsClipboard.string
        #else
        NSPasteboard.general.string(forType: .string)
        #endif
    }
}

struct CopyButton: View {
    var text: String
    var title = "Copy"
    var target: String

    var body: some View {
        Button(title) { ShellPasteboard.copy(text) }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(text)
            .shellTarget(target)
    }
}
