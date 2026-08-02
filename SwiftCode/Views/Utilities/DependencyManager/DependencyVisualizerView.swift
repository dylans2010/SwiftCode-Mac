import SwiftUI

struct DependencyVisualizerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ProjectSessionStore.self) private var sessionStore

    @State private var platformManager = DependencyPlatformManager.shared
    @State private var dependencies: [ParsedDependency] = []
    @State private var selectedNode: DependencyVisualNode?

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("[", modifiers: .command)

                Text("Interactive Dependency Graph Visualizer")
                    .font(.title2.bold())

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            HSplitView {
                InteractiveVectorCanvasView(
                    dependencies: dependencies,
                    sessionStore: sessionStore,
                    platformManager: platformManager,
                    selectedNode: $selectedNode
                )
                DetailsInspectorPanel(selectedNode: selectedNode)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadDependencies()
        }
    }

    private func loadDependencies() {
        guard let project = sessionStore.activeProject else { return }
        let packageURL = project.directoryURL.appendingPathComponent("Package.swift")
        guard let content = try? String(contentsOf: packageURL, encoding: .utf8) else { return }

        let pathPattern = #"\.package\(path:\s*"([^"]+)"\)"#
        let urlPattern = #"\.package\(url:\s*"([^"]+)",\s*(from|branch|revision|exact):\s*"([^"]+)"\)"#

        var parsedList: [ParsedDependency] = []
        let nsContent = content as NSString

        if let pathRegex = try? NSRegularExpression(pattern: pathPattern) {
            let matches = pathRegex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
            for match in matches {
                let path = nsContent.substring(with: match.range(at: 1))
                parsedList.append(ParsedDependency(url: path, requirementType: .exact, value: "local", isLocal: true))
            }
        }

        if let urlRegex = try? NSRegularExpression(pattern: urlPattern) {
            let matches = urlRegex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
            for match in matches {
                let url = nsContent.substring(with: match.range(at: 1))
                let reqTypeRaw = nsContent.substring(with: match.range(at: 2))
                let val = nsContent.substring(with: match.range(at: 3))

                let reqType = DependencyRequirementType(rawValue: reqTypeRaw) ?? .from
                parsedList.append(ParsedDependency(url: url, requirementType: reqType, value: val, isLocal: false))
            }
        }

        self.dependencies = parsedList
    }
}

// MARK: - Private Subviews to Prevent Compiler Type-Checking Timeout
private struct InteractiveVectorCanvasView: View {
    let dependencies: [ParsedDependency]
    let sessionStore: ProjectSessionStore
    var platformManager: DependencyPlatformManager
    @Binding var selectedNode: DependencyVisualNode?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Dependency Relations Map", systemImage: "network")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if dependencies.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No active packages detected in Package.swift.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
            } else {
                ScrollView([.horizontal, .vertical]) {
                    VStack(spacing: 40) {
                        // Root Node (Active Project)
                        VStack(spacing: 8) {
                            Image(systemName: "folder.badge.gearshape")
                                .font(.title)
                                .foregroundStyle(.blue)
                            Text(sessionStore.activeProject?.name ?? "Active Project")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("v1.0.0 (Root)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(width: 160)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                        // Connector lines & child nodes
                        let graphNodes = platformManager.buildDependencyGraph(dependencies: dependencies)

                        HStack(alignment: .top, spacing: 30) {
                            ForEach(graphNodes) { node in
                                Button {
                                    selectedNode = node
                                } label: {
                                    VStack(spacing: 10) {
                                        Image(systemName: node.isLocal ? "folder.fill" : "puzzlepiece.extension.fill")
                                            .font(.title2)
                                            .foregroundStyle(node.hasConflict ? .red : (node.isLocal ? .orange : .blue))

                                        Text(node.name)
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.primary)

                                        Text(node.version)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)

                                        if node.hasConflict {
                                            Label("Risk", systemImage: "exclamationmark.triangle.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.red)
                                        }
                                    }
                                    .padding()
                                    .frame(width: 140)
                                    .background(
                                        selectedNode?.id == node.id
                                        ? Color.accentColor.opacity(0.12)
                                        : Color.secondary.opacity(0.04),
                                        in: RoundedRectangle(cornerRadius: 12)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(selectedNode?.id == node.id ? Color.accentColor : Color.clear, lineWidth: 2)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(40)
                    .frame(minWidth: 800, minHeight: 400)
                }
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DetailsInspectorPanel: View {
    let selectedNode: DependencyVisualNode?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Dependency Details")
                .font(.headline)
                .foregroundStyle(.secondary)

            if let node = selectedNode {
                VStack(alignment: .leading, spacing: 14) {
                    Text(node.name)
                        .font(.title3.bold())

                    Label("Version: \(node.version)", systemImage: "tag")
                        .font(.subheadline)

                    Label("Type: \(node.isLocal ? "Local Directory" : "Remote SPM URL")", systemImage: node.isLocal ? "folder" : "link")
                        .font(.subheadline)

                    Divider()

                    if node.hasConflict {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Security Vulnerability", systemImage: "exclamationmark.shield.fill")
                                    .font(.caption.bold())
                                    .foregroundStyle(.red)
                                Text("This package contains severe known advisories. Open Security Center for details.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(6)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }

                    Text("Sub-dependencies:")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    if node.dependencies.isEmpty {
                        Text("No secondary sub-dependencies.")
                            .font(.caption)
                            .italic()
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(node.dependencies, id: \.self) { sub in
                            Label(sub, systemImage: "arrow.turn.down.right")
                                .font(.caption.monospaced())
                        }
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("No Node Selected", systemImage: "hand.tap")
                } description: {
                    Text("Select a dependency block on the left canvas to inspect nested relationships.")
                }
            }
            Spacer()
        }
        .padding(20)
        .frame(width: 260, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
