import SwiftUI

struct DebugInspectorSidebarView: View {
    var body: some View {
        VStack {
            List {
                Section("Variables") {
                    Text("No active debug session")
                        .foregroundStyle(.secondary)
                }

                Section("Call Stack") {
                    Text("Not debugging")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
