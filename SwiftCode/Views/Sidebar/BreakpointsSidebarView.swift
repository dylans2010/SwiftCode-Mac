import SwiftUI

struct BreakpointsSidebarView: View {
    @State private var breakpoints: [Breakpoint] = []
    @State private var allExceptions = false

    var body: some View {
        VStack(spacing: 0) {
            List {
                if breakpoints.isEmpty {
                    Text("No breakpoints set")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    ForEach(breakpoints) { bp in
                        HStack {
                            Image(systemName: bp.isEnabled ? "breakpoint.fill" : "breakpoint")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text(bp.fileName).font(.headline)
                                Text("Line \(bp.lineNumber)").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: .constant(bp.isEnabled))
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Toggle("All Exceptions", isOn: $allExceptions)
                    .font(.caption)
                Spacer()
            }
            .padding()
        }
        .onAppear {
            loadBreakpoints()
        }
    }

    private func loadBreakpoints() {
        // Logic to load real breakpoints from DebuggerService
        breakpoints = []
    }
}

struct Breakpoint: Identifiable {
    let id = UUID()
    let fileName: String
    let lineNumber: Int
    let isEnabled: Bool
}
