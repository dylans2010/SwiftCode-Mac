import SwiftUI

struct DebugSessionsSidebarView: View {
    @State private var sessions: [DebugSession] = []

    var body: some View {
        VStack(spacing: 0) {
            List {
                if sessions.isEmpty {
                    Text("No active sessions")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    ForEach(sessions) { session in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(session.executableURL.lastPathComponent)
                                    .font(.headline)
                                Text("PID: \(session.pid) • \(session.startedAt.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            StatusIndicator(state: session.state)
                        }
                        .contextMenu {
                            Button("Terminate", role: .destructive) {
                                // Logic to terminate
                            }
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button(action: { /* Logic for new session */ }) {
                    Label("New Session", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            .padding()
        }
    }
}

struct StatusIndicator: View {
    let state: DebugSession.State

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    var color: Color {
        switch state {
        case .launching: return .yellow
        case .running: return .green
        case .terminated: return .gray
        }
    }
}
