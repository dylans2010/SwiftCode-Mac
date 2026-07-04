import SwiftUI

struct TestsSidebarView: View {
    var body: some View {
        VStack {
            List {
                Section("Unit Tests") {
                    Text("No tests found")
                        .foregroundStyle(.secondary)
                }
                Section("UI Tests") {
                    Text("No tests found")
                        .foregroundStyle(.secondary)
                }
            }

            Button("Run All Tests") {
                // Run tests
            }
            .buttonStyle(.bordered)
            .padding()
        }
    }
}
