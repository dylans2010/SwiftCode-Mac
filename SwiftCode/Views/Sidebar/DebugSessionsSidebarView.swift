import SwiftUI

struct DebugSessionsSidebarView: View {
    @Bindable var viewModel: DebugSessionViewModel

    var body: some View {
        VStack(spacing: 0) {
            List {
                if let session = viewModel.activeSession {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(session.executableURL.lastPathComponent)
                                .font(.headline)
                            Text("PID: \(session.pid)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        StatusIndicator(state: session.state)
                    }
                    .contextMenu {
                        Button("Terminate", role: .destructive) {
                            viewModel.stop()
                        }
                    }
                } else {
                    ContentUnavailableView("No Active Sessions", systemImage: "play.square", description: Text("Start a new debug session to see it here."))
                }
            }

            Divider()

            HStack {
                Button(action: {
                    // In a real app, this would show a target picker
                }) {
                    Label("New Session", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            .padding()
        }
    }
}
