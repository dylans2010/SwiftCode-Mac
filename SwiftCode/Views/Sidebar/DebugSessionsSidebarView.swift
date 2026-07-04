import SwiftUI

struct DebugSessionsSidebarView: View {
    var body: some View {
        VStack {
            List {
                Text("No active sessions")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(action: {}) {
                    Label("New Session", systemImage: "plus")
                }
                Spacer()
            }
            .padding()
        }
    }
}
