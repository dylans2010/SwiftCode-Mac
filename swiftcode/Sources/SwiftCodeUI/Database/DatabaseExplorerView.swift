// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Views/Utilities/Database/DatabaseExplorerView.swift
//   (Legacy main ab03f681)
//
// Destination: SwiftCodeUI/Database/DatabaseExplorerView.swift.
//
// Adaptations (behaviour preserved):
// * `DatabaseSection` is NOT redeclared here: the batch-2 port of
//   `DatabaseExplorerSidebarViewController.swift` (same target, staged
//   alongside this file) already declares it, with a header noting it
//   lived in this Legacy file. Redeclaring it would collide.
// * `openWorkspace()` calls `SQLiteExplorerWindowManager.shared.showWindow()`
//   instead of Legacy's `DatabaseExplorerWindowManager.shared.showWindow()`:
//   the destination renamed the manager (SQLiteExplorerWindowController.swift
//   in this target, `showWindow()` with the same idempotent contract).
//   `DatabaseExplorerView` itself is the invisible SwiftUI trigger that
//   launches the AppKit workspace window and dismisses — unchanged.
//
// Wiring hook: this is the entry-point view for the Database Explorer.
// Present it wherever the explorer is launched from (workspace tool,
// command palette, toolbar) and it opens the three-pane workspace
// (`DatabaseExplorerSplitViewController`, staged alongside).

import SwiftUI

/// Main entry point for the Database Explorer.
/// Functions as an invisible background trigger that natively launches the AppKit workspace window.
public struct DatabaseExplorerView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                openWorkspace()
            }
    }

    private func openWorkspace() {
        SQLiteExplorerWindowManager.shared.showWindow()
        dismiss()
    }
}
