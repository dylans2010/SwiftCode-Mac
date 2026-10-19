import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
public struct IPABuildView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss

    private var buildService: IPABuildService {
        IPABuildService.shared
    }

    // UI state
    @State private var selectedApp: SelectedApp? = nil
    @State private var outputDirectory = UserDefaults.standard.string(forKey: "com.swiftcode.ipa.outputDirectory") ?? "~/Desktop"
    @State private var customIPAName = ""
    @State private var autoScrollLogs = true

    public init() {}

    public var body: some View {
        @Bindable var service = buildService
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    latestArchiveCard(service: service)

                    // Build & package workflows — no manual Builds-folder / .app hunting.
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Build & Package", systemImage: "hammer")
                                    .font(.headline)
                                Spacer()
                            }

                            Text("Compile the active project with xcodebuild and package the resulting .app into a production .ipa — no need to locate build folders or bundles yourself.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button {
                                Task { await buildWithXcodebuildAndPackage() }
                            } label: {
                                HStack {
                                    if service.buildState == .compiling {
                                        ProgressView().scaleEffect(0.8).padding(.trailing, 8)
                                    } else {
                                        Image(systemName: "hammer.fill")
                                    }
                                    Text(service.buildState == .compiling ? "Compiling..." : "Build with xcodebuild & Package")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(service.isBusy || activeProjectURL == nil)

                            if activeProjectURL == nil {
                                Text("Open a project to enable xcodebuild compilation.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Button("Choose existing .app…") {
                                    selectExistingAppBundle()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(service.isBusy)

                                Spacer()

                                Toggle("Always Build Archive", isOn: $service.alwaysBuildArchive)
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                                    .help("When on, every successful xcodebuild automatically packages the most up-to-date .app into an .ipa.")
                            }

                            if service.alwaysBuildArchive {
                                Text("Always Build Archive is on: the freshest compiled .app is turned into an .ipa after every successful build.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // App Metadata Dashboard
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("App Metadata", systemImage: "info.circle")
                                    .font(.headline)
                                Spacer()
                            }

                            if let app = selectedApp {
                                HStack(spacing: 12) {
                                    Image(systemName: "app.fill")
                                        .font(.title)
                                        .foregroundStyle(.secondary)

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
                                        Text("Modified").font(.caption).foregroundColor(.secondary)
                                        Text(app.lastModified).font(.caption.bold())
                                    }
                                }
                            } else {
                                VStack(spacing: 8) {
                                    Image(systemName: "doc.text.magnifyingglass")
                                        .font(.system(size: 30))
                                        .foregroundStyle(.secondary)
                                    Text("No application bundle selected yet. Use “Build with xcodebuild & Package” or choose an existing .app.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
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
                                Label("Output", systemImage: "folder")
                                    .font(.headline)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Output Destination Folder")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                HStack {
                                    TextField("Destination path...", text: $outputDirectory)
                                        .textFieldStyle(.roundedBorder)
                                        .onChange(of: outputDirectory) { _, newValue in
                                            UserDefaults.standard.set(newValue, forKey: "com.swiftcode.ipa.outputDirectory")
                                        }

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
                                Label("Package Selected .app", systemImage: "shippingbox")
                                    .font(.headline)
                                Spacer()
                            }

                            HStack(spacing: 16) {
                                Button {
                                    Task {
                                        await buildIPAContainer()
                                    }
                                } label: {
                                    HStack {
                                        if service.buildState == .packaging {
                                            ProgressView().scaleEffect(0.8).padding(.trailing, 8)
                                        } else {
                                            Image(systemName: "shippingbox.fill")
                                        }
                                        Text(service.buildState == .packaging ? "Packaging..." : "Create IPA Package")
                                            .fontWeight(.semibold)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(selectedApp == nil || service.isBusy)

                                if service.isBusy {
                                    Button("Abort") {
                                        service.cancelPackaging()
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
                    if !service.logs.isEmpty || service.isBusy {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label("Build & Packaging Logs", systemImage: "terminal.fill")
                                        .font(.headline)
                                    Spacer()

                                    Toggle("Auto-scroll", isOn: $autoScrollLogs)
                                        .toggleStyle(.checkbox)
                                        .controlSize(.small)
                                }

                                if service.isBusy {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ProgressView(value: service.currentProgress, total: 1.0)
                                            .progressViewStyle(.linear)
                                        Text(service.progressDescription)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                ScrollViewReader { proxy in
                                    ScrollView {
                                        LazyVStack(alignment: .leading, spacing: 4) {
                                            ForEach(Array(service.logs.enumerated()), id: \.offset) { index, log in
                                                HStack(alignment: .top, spacing: 6) {
                                                    Text(log.timestamp.formatted(date: .omitted, time: .standard))
                                                        .font(.system(size: 8, design: .monospaced))
                                                        .foregroundColor(.secondary.opacity(0.6))

                                                    Text(log.message)
                                                        .font(.system(size: 9, design: .monospaced))
                                                        .foregroundColor(log.isError ? .red : .primary)
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
                                    .onChange(of: service.logs.count) { _, newCount in
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
            .onAppear {
                buildService.validateLatestArchive()
            }
        }
    }

    // MARK: - Latest Archive card

    @ViewBuilder
    private func latestArchiveCard(service: IPABuildService) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Latest Archive:", systemImage: "archivebox.fill")
                        .font(.headline)
                    Spacer()
                }

                if let ipaPath = service.latestArchivePath {
                    HStack(spacing: 12) {
                        Image(systemName: "shippingbox.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text((ipaPath as NSString).lastPathComponent)
                                .font(.subheadline.bold())
                                .lineLimit(1)
                                .truncationMode(.middle)
                            HStack(spacing: 8) {
                                if let date = service.latestArchiveDate {
                                    Text(date.formatted(date: .abbreviated, time: .shortened))
                                }
                                if let size = service.latestArchiveSize {
                                    Text("· \(size)")
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Button {
                            downloadLatestArchive()
                        } label: {
                            Label("Download", systemImage: "arrow.down.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)

                        Button {
                            NSWorkspace.shared.selectFile(ipaPath, inFileViewerRootedAtPath: (ipaPath as NSString).deletingLastPathComponent)
                        } label: {
                            Label("Reveal in Finder", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                } else {
                    Text("No archive yet. Build with xcodebuild or package an .app to produce your first .ipa — it will appear here ready to download.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    // MARK: - Project resolution

    private var activeProjectURL: URL? {
        if let url = DocumentCoordinator.shared.projectURL { return url }
        return ProjectSessionStore.shared.activeProject?.directoryURL
    }

    private var activeProjectName: String? {
        activeProjectURL?.deletingPathExtension().lastPathComponent
    }

    // MARK: - Operations

    /// Compile the active project with xcodebuild, grab the fresh .app, and package it.
    private func buildWithXcodebuildAndPackage() async {
        guard let projectURL = activeProjectURL else { return }
        let scheme = XcodeBuildManager.shared.selectedScheme ?? projectURL.deletingPathExtension().lastPathComponent
        let configuration = XcodeBuildManager.shared.selectedConfiguration
        let destination = XcodeBuildManager.shared.selectedDestination

        let (appURL, compileError) = await buildService.compileAppBundle(
            projectURL: projectURL,
            scheme: scheme,
            configuration: configuration,
            destination: destination
        )

        guard let appURL else {
            showAlert(title: "Compilation Failed", message: compileError ?? "xcodebuild failed.")
            return
        }

        await parseSelectedAppBundle(url: appURL)

        let outDir = (outputDirectory as NSString).expandingTildeInPath
        let result = await buildService.packageAppIntoIPA(
            appPath: appURL.path,
            outputDirectory: outDir,
            customIPAName: customIPAName.isEmpty ? nil : customIPAName
        )

        if result.success, let finalPath = result.ipaPath {
            showAlert(
                title: "IPA Build Succeeded!",
                message: "Compiled and packaged production .ipa:\n\(finalPath)",
                revealPath: finalPath,
                revealDir: outDir
            )
        } else {
            showAlert(title: "IPA Packaging Failed", message: result.errorMessage ?? "An unknown pipeline error occurred.")
        }
    }

    private func showAlert(title: String, message: String, revealPath: String? = nil, revealDir: String? = nil) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        if revealPath != nil {
            alert.addButton(withTitle: "Reveal in Finder")
            alert.addButton(withTitle: "OK")
            if alert.runModal() == .alertFirstButtonReturn, let revealPath, let revealDir {
                NSWorkspace.shared.selectFile(revealPath, inFileViewerRootedAtPath: revealDir)
            }
        } else {
            alert.runModal()
        }
    }

    private func downloadLatestArchive() {
        guard let ipaPath = buildService.latestArchivePath else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (ipaPath as NSString).lastPathComponent
        if let ipaType = UTType(filenameExtension: "ipa") {
            panel.allowedContentTypes = [ipaType]
        }
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)
                    }
                    try FileManager.default.copyItem(atPath: ipaPath, toPath: url.path)
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "Download Failed"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    private func selectExistingAppBundle() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType("com.apple.application-and-system-extension") ?? .directory]
        panel.title = "Select Compiled .app Bundle"

        if panel.runModal() == .OK, let url = panel.url {
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
            UserDefaults.standard.set(url.path, forKey: "com.swiftcode.ipa.outputDirectory")
        }
    }

    private func parseSelectedAppBundle(url: URL) async {
        let plistURL = url.appendingPathComponent("Info.plist")
        let fm = FileManager.default
        guard fm.fileExists(atPath: plistURL.path) else {
            showAlert(title: "Invalid App Bundle", message: "Info.plist is missing inside the selected bundle.")
            return
        }

        let path = url.path
        let bundleID = await readPlistValue(at: plistURL, key: "CFBundleIdentifier") ?? "Unknown"
        let name = await readPlistValue(at: plistURL, key: "CFBundleDisplayName") ?? url.deletingPathExtension().lastPathComponent
        let version = await readPlistValue(at: plistURL, key: "CFBundleShortVersionString") ?? "1.0"
        let build = await readPlistValue(at: plistURL, key: "CFBundleVersion") ?? "1"
        let minOS = await readPlistValue(at: plistURL, key: "MinimumOSVersion") ?? "Unknown"

        let attr = try? fm.attributesOfItem(atPath: path)
        let sizeInBytes = attr?[.size] as? Int64 ?? 0
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        let sizeStr = formatter.string(fromByteCount: sizeInBytes)

        let modDate = attr?[.modificationDate] as? Date ?? Date()
        let dateStr = modDate.formatted(date: .abbreviated, time: .shortened)

        self.selectedApp = SelectedApp(
            path: path,
            name: name,
            bundleID: bundleID,
            version: version,
            build: build,
            minOS: minOS,
            fileSize: sizeStr,
            buildConfiguration: "Device",
            lastModified: dateStr,
            signingStatus: "Unknown"
        )
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
            showAlert(
                title: "IPA Packaging Succeeded!",
                message: "Successfully packaged production .ipa:\n\(finalPath)",
                revealPath: finalPath,
                revealDir: outDir
            )
        } else {
            showAlert(title: "IPA Packaging Failed", message: result.errorMessage ?? "An unknown pipeline error occurred.")
        }
    }
}
