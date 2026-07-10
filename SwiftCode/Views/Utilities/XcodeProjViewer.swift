import SwiftUI

public struct XcodeProjViewer: View {
    public let model: XcodeProjModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: Tab = .targets
    @State private var searchQuery = ""

    enum Tab: String, CaseIterable, Identifiable {
        case targets = "Targets"
        case files = "Files & References"
        case phases = "Build Phases"
        case configs = "Build Settings"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .targets: return "target"
            case .files: return "doc.text.magnifyingglass"
            case .phases: return "shippingbox"
            case .configs: return "slider.horizontal.3"
            }
        }
    }

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            // Sidebar for tabs & overview metrics
            VStack(alignment: .leading, spacing: 0) {
                // Project Header
                HStack(spacing: 12) {
                    Image(systemName: "hammer.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.projectURL.lastPathComponent)
                            .font(.headline)
                            .lineLimit(1)
                        Text("Xcode Project Document")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()

                Divider()

                // Custom Sidebar Selector
                List(Tab.allCases, selection: $selectedTab) { tab in
                    NavigationLink(value: tab) {
                        Label(tab.rawValue, systemImage: tab.icon)
                            .font(.subheadline)
                    }
                    .tag(tab)
                }
                .listStyle(.sidebar)

                Spacer()

                // Summary / Footer block
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    Text("PROJECT METRICS")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)

                    HStack {
                        Label("\(model.targets.count) Targets", systemImage: "target")
                        Spacer()
                        Label("\(model.fileReferences.count) Files", systemImage: "doc")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            VStack(spacing: 0) {
                // Toolbar/Header in Detail Area
                HStack {
                    Text(selectedTab.rawValue)
                        .font(.title2.bold())
                    Spacer()

                    // Search Bar
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search...", text: $searchQuery)
                            .textFieldStyle(.plain)
                            .frame(width: 180)
                        if !searchQuery.isEmpty {
                            Button { searchQuery = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )

                    Button {
                        dismiss()
                    } label: {
                        Text("Close")
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.2), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(.background.opacity(0.4))

                Divider()

                // Content View based on Selected Tab
                Group {
                    switch selectedTab {
                    case .targets:
                        targetsView
                    case .files:
                        filesView
                    case .phases:
                        phasesView
                    case .configs:
                        configsView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 800, minHeight: 550)
    }

    // MARK: - Subviews

    private var targetsView: some View {
        let filtered = model.targets.filter {
            searchQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(searchQuery)
        }

        return ScrollView {
            LazyVStack(spacing: 12) {
                if filtered.isEmpty {
                    ContentUnavailableView("No Targets Found", systemImage: "target")
                } else {
                    ForEach(filtered) { target in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label(target.name, systemImage: "target")
                                    .font(.headline)
                                    .foregroundStyle(.blue)
                                Spacer()
                                if let type = target.productType {
                                    Text(type.replacingOccurrences(of: "com.apple.product-type.", with: ""))
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.blue.opacity(0.15))
                                        .foregroundStyle(.blue)
                                        .cornerRadius(6)
                                }
                            }

                            Divider().opacity(0.3)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("UUID: \(target.uuid)")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 16) {
                                    Text("Build Phases: \(target.buildPhaseUUIDs.count)")
                                    Text("Dependencies: \(target.dependencies.count)")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                }
            }
            .padding()
        }
    }

    private var filesView: some View {
        let filtered = model.fileReferences.filter {
            searchQuery.isEmpty ||
            ($0.name ?? "").localizedCaseInsensitiveContains(searchQuery) ||
            ($0.path ?? "").localizedCaseInsensitiveContains(searchQuery)
        }

        return List {
            if filtered.isEmpty {
                ContentUnavailableView("No File References Found", systemImage: "doc.text.magnifyingglass")
            } else {
                ForEach(filtered) { file in
                    HStack(spacing: 12) {
                        Image(systemName: fileIcon(file.path ?? ""))
                            .font(.title3)
                            .foregroundStyle(.orange)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name ?? file.path ?? "Unknown File")
                                .font(.subheadline.weight(.semibold))
                            if let path = file.path {
                                Text(path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            if let type = file.lastKnownFileType {
                                Text(type)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(file.uuid)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var phasesView: some View {
        let filtered = model.buildPhases.filter {
            searchQuery.isEmpty || $0.isa.localizedCaseInsensitiveContains(searchQuery)
        }

        return ScrollView {
            LazyVStack(spacing: 12) {
                if filtered.isEmpty {
                    ContentUnavailableView("No Build Phases Found", systemImage: "shippingbox")
                } else {
                    ForEach(filtered) { phase in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(phase.isa.replacingOccurrences(of: "PBX", with: "").replacingOccurrences(of: "BuildPhase", with: " Build Phase"))
                                    .font(.headline)
                                    .foregroundStyle(.orange)
                                Spacer()
                                Text("\(phase.files.count) files")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text("UUID: \(phase.uuid)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                }
            }
            .padding()
        }
    }

    private var configsView: some View {
        let filtered = model.buildConfigurations.filter {
            searchQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(searchQuery)
        }

        return ScrollView {
            LazyVStack(spacing: 16) {
                if filtered.isEmpty {
                    ContentUnavailableView("No Build Settings Found", systemImage: "slider.horizontal.3")
                } else {
                    ForEach(filtered) { config in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(config.name)
                                .font(.headline)
                                .foregroundStyle(.orange)

                            Divider().opacity(0.3)

                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(config.buildSettings.keys).sorted(), id: \.self) { key in
                                    HStack(alignment: .top) {
                                        Text(key)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 250, alignment: .leading)

                                        Spacer()

                                        Text(config.buildSettings[key] ?? "")
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.primary)
                                            .multilineTextAlignment(.trailing)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                }
            }
            .padding()
        }
    }

    private func fileIcon(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "plist": return "list.bullet.rectangle.fill"
        case "json": return "curlybraces.square.fill"
        case "md": return "document.fill"
        default: return "doc.fill"
        }
    }
}
