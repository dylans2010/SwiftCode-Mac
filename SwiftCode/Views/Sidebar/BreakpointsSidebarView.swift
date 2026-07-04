import SwiftUI

struct BreakpointsSidebarView: View {
    @State private var store = BreakpointStore.shared
    @State private var allExceptions = false

    var body: some View {
        VStack(spacing: 0) {
            List {
                if store.breakpoints.isEmpty {
                    ContentUnavailableView("No Breakpoints", systemImage: "breakpoint", description: Text("Set breakpoints to pause execution during debugging."))
                } else {
                    ForEach(store.breakpoints) { bp in
                        HStack {
                            Image(systemName: bp.isEnabled ? "breakpoint.fill" : "breakpoint")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text(bp.fileName).font(.headline)
                                Text("Line \(bp.lineNumber)").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { bp.isEnabled },
                                set: { _ in store.toggle(id: bp.id) }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                store.remove(id: bp.id)
                            }
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
    }
}
