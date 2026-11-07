import SwiftUI

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
