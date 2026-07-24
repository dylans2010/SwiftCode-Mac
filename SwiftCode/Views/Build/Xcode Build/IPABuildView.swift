import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
public struct IPABuildView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss

    // IPABuildService reference
    private var buildService: IPABuildService {
        IPABuildService.shared
    }

    // UI state
    @State private var selectedApp: SelectedApp? = nil
    @State private var outputDirectory = "~/Desktop"
    @State private var customIPAName = ""
    @State private var showSavePanel = false
    @State private var autoScrollLogs = true

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Title info card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("iOS Application Packaging", systemImage: "shippingbox.fill")
                                    .font(.headline)
                                    .foregroundColor(.purple)
                                Spacer()
                            }
                            Text("Package compiled .app binaries into standard production .ipa containers cleanly and safely without opening Xcode.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Workflow Triggers
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Workflows Selection", systemImage: "play.circle")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }

                            HStack(spacing: 12) {
                                // Workflow 1: Open Temporary Managed Builds Folder
                                Button {
                                    revealTemporaryBuildsFolder()
                                } label: {
                                    Label("Reveal Builds Folder", systemImage: "folder.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)

                                // Workflow 2: Choose Existing .app bundle
                                Button {
                                    selectExistingAppBundle()
                                } label: {
                                    Label("Select .app Bundle...", systemImage: "doc.badge.gearshape")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // App Metadata Dashboard
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("App Metadata Dashboard", systemImage: "info.circle")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()
                            }

                            if let app = selectedApp {
                                HStack(spacing: 12) {
                                    Image(systemName: "app.fill")
                                        .font(.title)
                                        .foregroundStyle(.orange)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(app.name)
                                            .font(.subheadline.bold())
                                        Text(app.bundleID)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }

                                Divider()

                                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                                    GridRow {
                                        Text("Version").font(.caption).foregroundColor(.secondary)
                                        Text(app.version).font(.caption.bold())

                                        Text("Build").font(.caption).foregroundColor(.secondary)
                                        Text(app.build).font(.caption.bold())
                                    }

                                    GridRow {
                                        Text("Minimum iOS").font(.caption).foregroundColor(.secondary)
                                        Text(app.minOS).font(.caption.bold())

                                        Text("File Size").font(.caption).foregroundColor(.secondary)
                                        Text(app.fileSize).font(.caption.bold())
                                    }

                                    GridRow {
                                        Text("Signing").font(.caption).foregroundColor(.secondary)
                                        Text(app.signingStatus).font(.caption.bold()).foregroundColor(.green)

                                        Text("Modified").font(.caption).foregroundColor(.secondary)
                                        Text(app.lastModified).font(.caption.bold())
                                    }
                                }
                            } else {
                                VStack(spacing: 8) {
                                    Image(systemName: "doc.text.magnifyingglass")
                                        .font(.system(size: 30))
                                        .foregroundStyle(.secondary)
                                    Text("No application bundle selected. Please select an existing .app bundle to package.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Output specs
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Output Specifications", systemImage: "gearshape")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Output Destination Folder")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                HStack {
                                    TextField("Destination path...", text: $outputDirectory)
                                        .textFieldStyle(.roundedBorder)

                                    Button("Browse...") {
                                        selectOutputDestination()
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Optional Custom IPA Filename (including .ipa)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                TextField("e.g. MyApp.ipa", text: $customIPAName)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Action box
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Action", systemImage: "shippingbox.fill")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                Spacer()
                            }

                            HStack(spacing: 16) {
                                Button {
                                    Task {
                                        await buildIPAContainer()
                                    }
                                } label: {
                                    HStack {
                                        if buildService.buildState == .packaging {
                                            ProgressView().scaleEffect(0.8).padding(.trailing, 8)
                                        } else {
                                            Image(systemName: "shippingbox.fill")
                                        }
                                        Text(buildService.buildState == .packaging ? "Packaging..." : "Create IPA Package")
                                            .fontWeight(.semibold)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.purple)
                                .controlSize(.large)
                                .disabled(selectedApp == nil || buildService.buildState == .packaging)

                                if buildService.buildState == .packaging {
                                    Button("Abort") {
                                        buildService.cancelPackaging()
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.red)
                                    .controlSize(.large)
                                }
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Logs box
                    if !buildService.logs.isEmpty || buildService.buildState == .packaging {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label("Live Streams & Packaging Logs", systemImage: "terminal.fill")
                                        .font(.headline)
                                        .foregroundColor(.gray)
                                    Spacer()

                                    Toggle("Auto-scroll", isOn: $autoScrollLogs)
                                        .toggleStyle(.checkbox)
                                        .controlSize(.small)
                                }

                                // Progress bar
                                if buildService.buildState == .packaging {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ProgressView(value: buildService.currentProgress, total: 1.0)
                                            .progressViewStyle(.linear)
                                        Text(buildService.progressDescription)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                // Monospaced output logs
                                ScrollViewReader { proxy in
                                    ScrollView {
                                        LazyVStack(alignment: .leading, spacing: 4) {
                                            ForEach(Array(buildService.logs.enumerated()), id: \.offset) { index, log in
                                                HStack(alignment: .top, spacing: 6) {
                                                    Text(log.timestamp.formatted(date: .omitted, time: .standard))
                                                        .font(.system(size: 8, design: .monospaced))
                                                        .foregroundColor(.secondary.opacity(0.6))

                                                    Text(log.message)
                                                        .font(.system(size: 9, design: .monospaced))
                                                        .foregroundColor(log.isError ? .red : .green)
                                                        .textSelection(.enabled)
                                                }
                                                .id(index)
                                            }
                                        }
                                        .padding()
                                    }
                                    .frame(height: 250)
                                    .background(Color.black.opacity(0.3))
                                    .cornerRadius(12)
                                    .onChange(of: buildService.logs.count) { _, newCount in
                                        if autoScrollLogs && newCount > 0 {
                                            withAnimation {
                                                proxy.scrollTo(newCount - 1, anchor: .bottom)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }
                }
                .padding(24)
            }
            .navigationTitle("Production IPA Builder")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Workflows Operations

    private func revealTemporaryBuildsFolder() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

        let projectName = sessionStore.activeProject?.name ?? "Untitled"
        let buildsDir = appSupport.appendingPathComponent("SwiftCode/Builds/\(projectName)")

        // Ensure directory exists
        try? fm.createDirectory(at: buildsDir, withIntermediateDirectories: true, attributes: nil)

        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: buildsDir.path)
    }

    private func selectExistingAppBundle() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType("com.apple.application-and-system-extension") ?? .directory]
        panel.title = "Select Compiled iOS .app Bundle"

        if panel.runModal() == .OK, let url = panel.url {
            // Runs on the view's MainActor while allowing plist reads to await the process runner actor.
            Task { await parseSelectedAppBundle(url: url) }
        }
    }

    private func selectOutputDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Select Output IPA Folder"

        if panel.runModal() == .OK, let url = panel.url {
            self.outputDirectory = url.path
        }
    }

    private func parseSelectedAppBundle(url: URL) async {
        let plistURL = url.appendingPathComponent("Info.plist")
        let fm = FileManager.default
        guard fm.fileExists(atPath: plistURL.path) else {
            let alert = NSAlert()
            alert.messageText = "Invalid App Bundle"
            alert.informativeText = "Info.plist is missing inside the selected bundle."
            alert.runModal()
            return
        }

        let path = url.path
        let bundleID = await readPlistValue(at: plistURL, key: "CFBundleIdentifier") ?? "Unknown"
        let name = await readPlistValue(at: plistURL, key: "CFBundleDisplayName") ?? url.deletingPathExtension().lastPathComponent
        let version = await readPlistValue(at: plistURL, key: "CFBundleShortVersionString") ?? "1.0"
        let build = await readPlistValue(at: plistURL, key: "CFBundleVersion") ?? "1"
        let minOS = await readPlistValue(at: plistURL, key: "MinimumOSVersion") ?? "iOS 17.0"

        // File size
        let attr = try? fm.attributesOfItem(atPath: path)
        let sizeInBytes = attr?[.size] as? Int64 ?? 0
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        let sizeStr = formatter.string(fromByteCount: sizeInBytes)

        // Last modified
        let modDate = attr?[.modificationDate] as? Date ?? Date()
        let dateStr = modDate.formatted(date: .abbreviated, time: .shortened)

        let app = SelectedApp(
            path: path,
            name: name,
            bundleID: bundleID,
            version: version,
            build: build,
            minOS: minOS,
            fileSize: sizeStr,
            buildConfiguration: "Debug/Release",
            lastModified: dateStr,
            signingStatus: "Detached/Validated"
        )

        self.selectedApp = app
    }


    private func readPlistValue(at plistURL: URL, key: String) async -> String? {
        let result = try? await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/defaults"),
            arguments: ["read", plistURL.path, key]
        )
        return result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildIPAContainer() async {
        guard let app = selectedApp else { return }

        let outDir = (outputDirectory as NSString).expandingTildeInPath
        let result = await buildService.packageAppIntoIPA(
            appPath: app.path,
            outputDirectory: outDir,
            customIPAName: customIPAName.isEmpty ? nil : customIPAName
        )

        if result.success, let finalPath = result.ipaPath {
            let alert = NSAlert()
            alert.messageText = "IPA Packaging Succeeded!"
            alert.informativeText = "Successfully compiled production IPA container package:\n\(finalPath)"
            alert.addButton(withTitle: "Reveal in Finder")
            alert.addButton(withTitle: "OK")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.selectFile(finalPath, inFileViewerRootedAtPath: outDir)
            }
        } else {
            let alert = NSAlert()
            alert.messageText = "IPA Packaging Failed"
            alert.informativeText = result.errorMessage ?? "An unknown pipeline error occurred."
            alert.runModal()
        }
    }

    private func statusColor(_ state: IPABuildState) -> Color {
        switch state {
        case .idle: return .secondary
        case .packaging: return .blue
        case .succeeded: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }
}
