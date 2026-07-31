import SwiftUI

public enum GraphType: String, CaseIterable, Sendable, Identifiable {
    case folders = "Folder Hierarchy"
    case dependencies = "Dependencies"
    case frameworks = "Frameworks & SDKs"
    case services = "Architecture Layers"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .folders: return "folder.fill"
        case .dependencies: return "puzzlepiece.extension.fill"
        case .frameworks: return "shippingbox.fill"
        case .services: return "square.stack.3d.up.fill"
        }
    }
}

public struct GraphNode: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let type: String // "layer", "file", "service", "framework", "package", "folder"
    public let details: String
    public let connections: [String] // IDs of connected nodes
}

public struct ProjectArchitectureGraph: View {
    @State private var scanner = InspectorProjectScanner.shared
    @State private var selectedGraphType: GraphType = .services
    @State private var selectedNode: GraphNode? = nil
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var searchNodeQuery = ""

    // Nodes definitions dynamically generated from InspectorProjectScanner
    private func getNodes(for type: GraphType) -> [GraphNode] {
        switch type {
        case .folders:
            var nodes = [
                GraphNode(id: "root", label: scanner.projectName, type: "folder", details: "Project Root folder containing \(scanner.totalFiles) files and \(scanner.totalFolders) directories.", connections: [])
            ]
            // Map largest folders scanned dynamically
            let folders = scanner.largestFolders
            for f in folders {
                nodes.append(GraphNode(
                    id: f.path,
                    label: f.name,
                    type: "folder",
                    details: "Directory path: \(f.path) | File count: \(f.fileCount) | Total size: \(formatBytes(f.totalSize))",
                    connections: ["root"]
                ))
            }
            return nodes

        case .dependencies:
            var nodes: [GraphNode] = []
            if scanner.packageCount > 0 {
                nodes.append(GraphNode(id: "spm", label: "Swift Packages", type: "package", details: "Detected \(scanner.packageCount) packages inside the active project workspace.", connections: []))
            } else {
                nodes.append(GraphNode(id: "spm", label: "Swift Packages (None)", type: "package", details: "No local Package.swift files resolved.", connections: []))
            }
            // Dynamic check for integrations
            if scanner.sqlCount > 0 {
                nodes.append(GraphNode(id: "sqlite", label: "SQLite DB Service", type: "package", details: "Detected \(scanner.sqlCount) local SQLite migrations or templates.", connections: ["spm"]))
            }
            if scanner.jsonCount > 0 {
                nodes.append(GraphNode(id: "json", label: "JSON Encoder/Decoder", type: "package", details: "Detected \(scanner.jsonCount) data contracts or raw payload templates.", connections: ["spm"]))
            }
            return nodes

        case .frameworks:
            var nodes: [GraphNode] = []
            if scanner.swiftUIUsageCount > 0 {
                nodes.append(GraphNode(id: "swiftui", label: "SwiftUI Framework", type: "framework", details: "Integrated across \(scanner.swiftUIUsageCount) active layout views.", connections: ["foundation"]))
            }
            if scanner.uikitUsageCount > 0 {
                nodes.append(GraphNode(id: "uikit", label: "UIKit SDK", type: "framework", details: "Detected \(scanner.uikitUsageCount) controller dependencies or interfaces.", connections: ["foundation"]))
            }
            if scanner.appkitUsageCount > 0 {
                nodes.append(GraphNode(id: "appkit", label: "AppKit SDK", type: "framework", details: "Detected \(scanner.appkitUsageCount) native macOS window/split view actions.", connections: ["foundation"]))
            }
            nodes.append(GraphNode(id: "foundation", label: "Foundation Standard Library", type: "framework", details: "Implicit core runtime resolved across all \(scanner.totalSwiftFiles) Swift components.", connections: []))
            return nodes

        case .services:
            return [
                GraphNode(id: "views_layer", label: "Presentation Layer", type: "layer", details: "Renders visual themes. SwiftUI Usage: \(scanner.swiftUIUsageCount) view templates.", connections: ["logic_layer"]),
                GraphNode(id: "logic_layer", label: "State & Logic Layer", type: "layer", details: "Coordinating operations. Modern Observations: \(scanner.observationUsageCount) variables.", connections: ["concurrency_layer"]),
                GraphNode(id: "concurrency_layer", label: "Isolation & Concurrency Layer", type: "layer", details: "Protects shared variables. Actors: \(scanner.actorUsageCount) declarations | Async Tasks: \(scanner.asyncUsageCount).", connections: ["data_layer"]),
                GraphNode(id: "data_layer", label: "Persistence & Data Store", type: "layer", details: "Raw project schemas. JSON files: \(scanner.jsonCount) | SQL queries: \(scanner.sqlCount).", connections: [])
            ]
        }
    }

    private var filteredNodes: [GraphNode] {
        let all = getNodes(for: selectedGraphType)
        if searchNodeQuery.isEmpty { return all }
        return all.filter { $0.label.localizedCaseInsensitiveContains(searchNodeQuery) || $0.details.localizedCaseInsensitiveContains(searchNodeQuery) }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header configuration
            HStack {
                Picker("Graph View Type", selection: $selectedGraphType) {
                    ForEach(GraphType.allCases) { type in
                        Label(type.rawValue, systemImage: type.icon).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 550)

                Spacer()

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Filter nodes...", text: $searchNodeQuery)
                        .textFieldStyle(.plain)
                        .frame(width: 180)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            HSplitView {
                // Left side: Zoomable and pannable Graph Canvas
                ZStack {
                    Color(NSColor.controlBackgroundColor)

                    // Node canvas wrapper
                    ScrollView([.horizontal, .vertical]) {
                        VStack(spacing: 40) {
                            ForEach(filteredNodes) { node in
                                let isSelected = selectedNode?.id == node.id
                                Button {
                                    withAnimation {
                                        selectedNode = node
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Image(systemName: nodeIcon(for: node.type))
                                                .foregroundStyle(nodeColor(for: node.type))
                                            Text(node.label)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            Spacer()
                                        }

                                        Text(node.details)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)

                                        if !node.connections.isEmpty {
                                            HStack {
                                                Image(systemName: "arrow.right.circle.fill")
                                                    .font(.caption2)
                                                Text("Outputs to: " + node.connections.joined(separator: ", "))
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundStyle(.secondary)
                                            }
                                            .padding(.top, 4)
                                        }
                                    }
                                    .padding()
                                    .frame(width: 280)
                                    .background(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.05))
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.15), lineWidth: isSelected ? 2 : 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(40)
                        .scaleEffect(scale)
                    }

                    // Canvas controls overlay
                    VStack {
                        Spacer()
                        HStack {
                            Button { scale = max(0.5, scale - 0.1) } label: { Image(systemName: "minus.magnifyingglass") }
                            Button { scale = 1.0; offset = .zero } label: { Image(systemName: "gobackward") }
                            Button { scale = min(2.0, scale + 0.1) } label: { Image(systemName: "plus.magnifyingglass") }
                        }
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Right side: Detail connection inspector
                VStack(alignment: .leading, spacing: 16) {
                    if let node = selectedNode {
                        Text("Node Inspector")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Divider()

                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(nodeColor(for: node.type).opacity(0.15))
                                    .frame(width: 40, height: 40)
                                Image(systemName: nodeIcon(for: node.type))
                                    .font(.title3)
                                    .foregroundStyle(nodeColor(for: node.type))
                            }

                            VStack(alignment: .leading) {
                                Text(node.label)
                                    .font(.title3.bold())
                                Text(node.type.uppercased())
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("DESCRIPTION")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                            Text(node.details)
                                .font(.subheadline)
                        }

                        Divider()

                        // Connected outputs
                        Text("CONNECTIONS & DEPENDENTS")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)

                        let inputs = getNodes(for: selectedGraphType).filter { $0.connections.contains(node.id) }
                        let outputs = getNodes(for: selectedGraphType).filter { node.connections.contains($0.id) }

                        if inputs.isEmpty && outputs.isEmpty {
                            Text("No internal connections detected.")
                                .font(.caption)
                                .italic()
                                .foregroundStyle(.secondary)
                        } else {
                            if !inputs.isEmpty {
                                Text("Inbound (Accessed by):")
                                    .font(.caption.bold())
                                ForEach(inputs) { inp in
                                    HStack {
                                        Image(systemName: nodeIcon(for: inp.type))
                                            .font(.caption)
                                            .foregroundStyle(nodeColor(for: inp.type))
                                        Text(inp.label)
                                            .font(.caption)
                                    }
                                    .padding(.leading, 10)
                                }
                            }

                            if !outputs.isEmpty {
                                Text("Outbound (Outputs to):")
                                    .font(.caption.bold())
                                    .padding(.top, 4)
                                ForEach(outputs) { out in
                                    HStack {
                                        Image(systemName: nodeIcon(for: out.type))
                                            .font(.caption)
                                            .foregroundStyle(nodeColor(for: out.type))
                                        Text(out.label)
                                            .font(.caption)
                                    }
                                    .padding(.leading, 10)
                                }
                            }
                        }
                    } else {
                        ContentUnavailableView("Select a node", systemImage: "hand.tap")
                    }
                    Spacer()
                }
                .padding()
                .frame(width: 280)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
    }

    private func nodeIcon(for type: String) -> String {
        switch type {
        case "folder": return "folder.fill"
        case "package": return "puzzlepiece.extension.fill"
        case "framework": return "shippingbox.fill"
        case "layer": return "square.stack.3d.up.fill"
        default: return "circle.fill"
        }
    }

    private func nodeColor(for type: String) -> Color {
        switch type {
        case "folder": return .blue
        case "package": return .orange
        case "framework": return .green
        case "layer": return .purple
        default: return .secondary
        }
    }

    private func formatBytes(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}
