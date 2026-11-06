import SwiftUI
import YcodeIDECore

/// Project Inspector — Legacy's `ProjectInspectorView` +
/// `ProjectArchitectureGraph`, rebuilt in Ycode style on top of
/// `InspectorProjectScanner`.
///
/// Tabs: Overview (counts + health), Project (targets, schemes, signing
/// summary, build settings, dependencies), Analytics (file/folder metrics),
/// File Detail (per-file metadata), Graph (folders / targets / packages),
/// AI Review (needs a text provider — the view takes one as a closure; with
/// none it says so), Actions (export the Markdown report and JSON metrics
/// into the project directory).
public struct ProjectInspectorView: View {
    public var rootURL: URL
    /// Text generation for AI Review. Wire the coding assistant's provider
    /// here; nil shows an honest "not configured" state instead of a fake
    /// review.
    public var textProvider: ((String) async throws -> String)?

    @State private var scanner = InspectorProjectScanner()
    @State private var selectedTab = 0
    @State private var selectedFile: FileMetrics?
    @State private var fileMetadata: InspectorFileMetadata?
    @State private var graphType: InspectorGraphType = .files
    @State private var aiReview: String?
    @State private var aiRunning = false
    @State private var exportMessage: String?

    public init(rootURL: URL, textProvider: ((String) async throws -> String)? = nil) {
        self.rootURL = rootURL
        self.textProvider = textProvider
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $selectedTab) {
                Text("Overview").tag(0)
                Text("Project").tag(1)
                Text("Analytics").tag(2)
                Text("File Detail").tag(3)
                Text("Graph").tag(4)
                Text("AI Review").tag(5)
                Text("Actions").tag(6)
            }
            .pickerStyle(.segmented)
            .padding()
            Divider()
            Group {
                switch selectedTab {
                case 0: overviewTab
                case 1: projectTab
                case 2: analyticsTab
                case 3: fileDetailTab
                case 4: graphTab
                case 5: aiReviewTab
                default: actionsTab
                }
            }
        }
        .navigationTitle("Project Inspector — \(scanner.projectName)")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Rescan") { Task { await scanner.scan(rootURL: rootURL) } }
                    .disabled(scanner.isScanning)
            }
        }
        .task { await scanner.scan(rootURL: rootURL) }
    }

    private var overviewTab: some View {
        List {
            Section("Health") {
                LabeledContent("Health score", value: "\(scanner.projectHealthScore)/100")
                LabeledContent("Scanning", value: scanner.isScanning ? "Running…" : "Idle")
            }
            Section("Counts") {
                LabeledContent("Files", value: "\(scanner.totalFiles)")
                LabeledContent("Swift files", value: "\(scanner.totalSwiftFiles)")
                LabeledContent("Folders", value: "\(scanner.totalFolders)")
                LabeledContent("Packages", value: "\(scanner.packageCount)")
                LabeledContent("Images", value: "\(scanner.imageCount)")
                LabeledContent("Localizations", value: "\(scanner.localizationCount)")
                LabeledContent("Average file size", value: ByteCountFormatter.string(fromByteCount: Int64(scanner.averageFileSize), countStyle: .file))
            }
            Section("Framework usage") {
                LabeledContent("SwiftUI files", value: "\(scanner.swiftUIUsageCount)")
                LabeledContent("AppKit files", value: "\(scanner.appkitUsageCount)")
                LabeledContent("UIKit files", value: "\(scanner.uikitUsageCount)")
                LabeledContent("@Observable files", value: "\(scanner.observationUsageCount)")
                LabeledContent("async/await files", value: "\(scanner.asyncUsageCount)")
                LabeledContent("Actor files", value: "\(scanner.actorUsageCount)")
            }
            Section("Recommendations") {
                ForEach(scanner.aiRecommendations, id: \.self) { Text($0).font(.caption) }
            }
        }
    }

    private var projectTab: some View {
        List {
            Section("Identity") {
                LabeledContent("Bundle ID", value: scanner.bundleIdentifier.isEmpty ? "—" : scanner.bundleIdentifier)
                LabeledContent("Version", value: scanner.version.isEmpty ? "—" : scanner.version)
                LabeledContent("Build", value: scanner.buildNumber.isEmpty ? "—" : scanner.buildNumber)
                LabeledContent("Configurations", value: scanner.buildConfigurationSummary.isEmpty ? "—" : scanner.buildConfigurationSummary)
            }
            Section("Targets") {
                if scanner.xcodeTargets.isEmpty {
                    Text(scanner.xcodeProjectFound ? "No targets found in the project file." : "No .xcodeproj at the project root.").foregroundStyle(.secondary)
                } else {
                    ForEach(scanner.xcodeTargets) { target in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(target.name).font(.headline)
                            Text(target.productType).font(.caption).foregroundStyle(.secondary)
                            Text("Configurations: \(target.configurationNames.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            Section("Schemes") {
                if scanner.xcodeSchemes.isEmpty {
                    Text("No shared schemes found.").foregroundStyle(.secondary)
                } else {
                    ForEach(scanner.xcodeSchemes) { Text($0.name) }
                }
            }
            Section("Package dependencies") {
                if scanner.packageDependencies.isEmpty {
                    Text("No package dependencies in the project file.").foregroundStyle(.secondary)
                } else {
                    ForEach(scanner.packageDependencies) { pkg in
                        VStack(alignment: .leading) {
                            Text(pkg.name).font(.headline)
                            Text(pkg.url).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Build settings (first target)") {
                if let target = scanner.xcodeTargets.first {
                    ForEach(target.buildSettings.sorted(by: { $0.key < $1.key }), id: \.key) { config, settings in
                        DisclosureGroup(config) {
                            ForEach(settings.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                HStack {
                                    Text(key).font(.caption).lineLimit(1)
                                    Spacer()
                                    Text(value).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }
                } else {
                    Text("No targets to show settings for.").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var analyticsTab: some View {
        List {
            Section("Largest files") {
                ForEach(scanner.largestFiles.prefix(15)) { file in
                    Button { selectFile(file) } label: {
                        HStack {
                            Text(file.name).font(.headline)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Section("Longest Swift files") {
                ForEach(scanner.longestSwiftFiles.prefix(15)) { file in
                    Button { selectFile(file) } label: {
                        HStack {
                            Text(file.name).font(.headline)
                            Spacer()
                            Text("\(file.lineCount) lines").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Section("Largest folders") {
                ForEach(scanner.largestFolders.prefix(15)) { folder in
                    HStack {
                        Text(folder.name).font(.headline)
                        Spacer()
                        Text("\(folder.fileCount) files · \(ByteCountFormatter.string(fromByteCount: folder.totalSize, countStyle: .file))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var fileDetailTab: some View {
        Group {
            if let file = selectedFile, let meta = fileMetadata {
                List {
                    Section("File") {
                        LabeledContent("Path", value: file.path)
                        LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: meta.size, countStyle: .file))
                        LabeledContent("Lines", value: "\(meta.lineCount)")
                        LabeledContent("Git status", value: meta.gitStatus)
                    }
                    Section("Imports") {
                        if meta.imports.isEmpty {
                            Text("No imports.").foregroundStyle(.secondary)
                        } else {
                            ForEach(meta.imports, id: \.self) { Text($0).font(.system(.body, design: .monospaced)) }
                        }
                    }
                    Section("Localizations") {
                        if meta.localizations.isEmpty {
                            Text("No localizations for this file.").foregroundStyle(.secondary)
                        } else {
                            ForEach(meta.localizations, id: \.self) { Text($0) }
                        }
                    }
                }
            } else {
                ContentUnavailableView("Select a file", systemImage: "doc.text", description: Text("Pick a file in the Analytics tab to inspect it."))
            }
        }
    }

    private func selectFile(_ file: FileMetrics) {
        selectedFile = file
        fileMetadata = InspectorFileMetadata.load(from: URL(fileURLWithPath: file.path), root: rootURL)
        selectedTab = 3
    }

    private var graphTab: some View {
        VStack {
            Picker("Graph", selection: $graphType) {
                ForEach(InspectorGraphType.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            List(scanner.graphNodes(for: graphType)) { node in
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name).font(.headline)
                    Text("\(node.kind) · \(node.detail)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var aiReviewTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let provider = textProvider {
                Button(aiRunning ? "Reviewing…" : "Run AI review") {
                    aiRunning = true
                    Task {
                        do {
                            let prompt = "Review this project summary and give concrete, prioritized recommendations:\n\(scanner.markdownReport())"
                            aiReview = try await provider(prompt)
                        } catch {
                            aiReview = "AI review failed: \(error.localizedDescription)"
                        }
                        aiRunning = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(aiRunning)
            } else {
                Text("AI review needs a text provider. Connect a Coding Assistant provider and wire it into this view — the local health recommendations on the Overview tab are available without one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let aiReview {
                ScrollView { Text(aiReview).textSelection(.enabled).padding() }
            }
            Spacer()
        }
        .padding()
    }

    private var actionsTab: some View {
        List {
            Section("Export") {
                Button("Export Markdown report") {
                    let url = rootURL.appendingPathComponent("ProjectInspectorReport.md")
                    do {
                        try scanner.markdownReport().write(to: url, atomically: true, encoding: .utf8)
                        exportMessage = "Wrote \(url.path)."
                    } catch {
                        exportMessage = "Export failed: \(error.localizedDescription)"
                    }
                }
                Button("Export JSON metrics") {
                    let url = rootURL.appendingPathComponent("ProjectInspectorMetrics.json")
                    let metrics: [String: Any] = [
                        "project": scanner.projectName,
                        "healthScore": scanner.projectHealthScore,
                        "totalFiles": scanner.totalFiles,
                        "totalSwiftFiles": scanner.totalSwiftFiles,
                        "totalFolders": scanner.totalFolders,
                        "packageCount": scanner.packageCount,
                        "recommendations": scanner.aiRecommendations,
                    ]
                    do {
                        let data = try JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys])
                        try data.write(to: url, options: .atomic)
                        exportMessage = "Wrote \(url.path)."
                    } catch {
                        exportMessage = "Export failed: \(error.localizedDescription)"
                    }
                }
                if let exportMessage {
                    Text(exportMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
