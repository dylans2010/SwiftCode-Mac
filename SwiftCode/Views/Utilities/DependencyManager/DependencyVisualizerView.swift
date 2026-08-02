import SwiftUI

struct DependencyVisualizerView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore

    @State private var platformManager = DependencyPlatformManager.shared
    @State private var dependencies: [ParsedDependency] = []
    @State private var selectedNode: DependencyVisualNode?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Info Header Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Interactive Dependency Graph Visualizer", systemImage: "network")
                                .font(.title2.bold())
                                .foregroundColor(.cyan)
                            Spacer()
                        }

                        Text("Interactive structural map showing direct, nested, and conflicting targets.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Graph Map Canvas Card
                GroupBox {
                    VStack(spacing: 12) {
                        HStack {
                            Label("Dependency Relations Map", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                                .font(.headline)
                                .foregroundColor(.blue)
                            Spacer()
                        }

                        Divider()

                        if dependencies.isEmpty {
                            ContentUnavailableView(
                                "No Active Packages",
                                systemImage: "puzzlepiece.extension",
                                description: Text("No active packages detected in Package.swift.")
                            )
                            .padding(.vertical, 32)
                        } else {
                            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                                VStack(spacing: 32) {
                                    // Root Node (Active Project)
                                    VStack(spacing: 6) {
                                        Image(systemName: "folder.badge.gearshape")
                                            .font(.title2)
                                            .foregroundStyle(.blue)
                                        Text(sessionStore.activeProject?.name ?? "Active Project")
                                            .font(.headline)
                                        Text("v1.0.0 (Root)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding()
                                    .frame(width: 150)
                                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                                    let graphNodes = platformManager.buildDependencyGraph(dependencies: dependencies)

                                    HStack(alignment: .top, spacing: 20) {
                                        ForEach(graphNodes) { node in
                                            Button {
                                                selectedNode = node
                                            } label: {
                                                VStack(spacing: 8) {
                                                    Image(systemName: node.isLocal ? "folder.fill" : "puzzlepiece.extension.fill")
                                                        .font(.title3)
                                                        .foregroundStyle(node.hasConflict ? .red : (node.isLocal ? .orange : .blue))

                                                    Text(node.name)
                                                        .font(.subheadline.bold())
                                                        .lineLimit(1)

                                                    Text(node.version)
                                                        .font(.system(size: 9, design: .monospaced))
                                                        .foregroundStyle(.secondary)

                                                    if node.hasConflict {
                                                        Label("Risk", systemImage: "exclamationmark.triangle.fill")
                                                            .font(.system(size: 8))
                                                            .foregroundStyle(.red)
                                                    }
                                                }
                                                .padding()
                                                .frame(width: 130)
                                                .background(
                                                    selectedNode?.id == node.id
                                                    ? Color.accentColor.opacity(0.12)
                                                    : Color.secondary.opacity(0.04),
                                                    in: RoundedRectangle(cornerRadius: 10)
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 10)
                                                        .stroke(selectedNode?.id == node.id ? Color.accentColor : Color.clear, lineWidth: 2)
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(24)
                            }
                            .frame(height: 280)
                            .background(Color.black.opacity(0.1))
                            .cornerRadius(10)
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Details Inspector Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Dependency Details", systemImage: "doc.text.magnifyingglass")
                            .font(.headline)
                            .foregroundColor(.orange)

                        Divider()

                        if let node = selectedNode {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(node.name)
                                    .font(.title3.bold())

                                HStack(spacing: 16) {
                                    Label("Version: \(node.version)", systemImage: "tag")
                                        .font(.subheadline)

                                    Label("Type: \(node.isLocal ? "Local Directory" : "Remote SPM URL")", systemImage: node.isLocal ? "folder" : "link")
                                        .font(.subheadline)
                                }

                                if node.hasConflict {
                                    HStack {
                                        Image(systemName: "exclamationmark.shield.fill")
                                            .foregroundColor(.red)
                                        Text("This package contains severe known advisories. Open Security Center for details.")
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    }
                                    .padding(10)
                                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], alignment: .leading, spacing: 8) {
                                        ForEach(node.dependencies, id: \.self) { sub in
                                            Label(sub, systemImage: "arrow.turn.down.right")
                                                .font(.system(size: 11, design: .monospaced))
                                        }
                                    }
                                }
                            }
                        } else {
                            ContentUnavailableView(
                                "No Selection",
                                systemImage: "hand.tap",
                                description: Text("Select a dependency block on the relations map above to inspect details.")
                            )
                            .padding(.vertical, 16)
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(24)
        }
        .navigationTitle("Graph Visualizer")
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
