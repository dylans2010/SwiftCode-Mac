import SwiftUI

struct OperationsDependencyManagerView: View {
    @State private var dm = DependencyManager.shared
    @State private var showAddingSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dependencies")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Swift Packages, binary frameworks, and workspace configurations.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    dm.refreshDependencies()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding(16)

            Divider()

            if dm.dependencies.isEmpty {
                ContentUnavailableView {
                    Label("No Dependencies", systemImage: "puzzlepiece")
                } description: {
                    Text("Open an active project containing Swift Packages or custom library frameworks.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(dm.dependencies) { item in
                    GroupBox {
                        HStack(alignment: .center, spacing: 14) {
                            Image(systemName: "puzzlepiece.extension.fill")
                                .font(.title3)
                                .foregroundStyle(.blue)
                                .frame(width: 32, height: 32)
                                .background(Color.blue.opacity(0.12))
                                .cornerRadius(6)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.name)
                                        .font(.headline)
                                    Text(item.version)
                                        .font(.system(.subheadline, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }

                                Text(item.type)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text(item.status)
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(item.status == "Up to date" ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                                    .foregroundStyle(item.status == "Up to date" ? .green : .orange)
                                    .cornerRadius(4)

                                if !item.homepage.isEmpty {
                                    Button("Homepage") {
                                        if let url = URL(string: item.homepage) {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }
                                    .buttonStyle(.link)
                                    .font(.caption2)
                                }
                            }
                        }
                        .padding(4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, 16)
            }
        }
        .onAppear {
            dm.refreshDependencies()
        }
    }
}
