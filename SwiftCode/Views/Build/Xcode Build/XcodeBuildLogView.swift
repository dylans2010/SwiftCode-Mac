import SwiftUI
import AppKit

@MainActor
struct StructuredBuildLog: Identifiable, Sendable {
    let id = UUID()
    let timestamp = Date()
    let message: String
    let severity: Severity

    enum Severity: String, Sendable, CaseIterable, Identifiable {
        case error = "Error"
        case warning = "Warning"
        case system = "System"
        case info = "Info"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .error: return "exclamationmark.octagon"
            case .warning: return "exclamationmark.triangle"
            case .system: return "cpu"
            case .info: return "info.circle"
            }
        }
    }
}

@MainActor
struct XcodeBuildLogView: View {
    @AppStorage("com.swiftcode.build.searchLogQuery") private var searchLogQuery = ""
    @AppStorage("com.swiftcode.build.autoScrollToBottom") private var autoScrollToBottom = true
    @AppStorage("com.swiftcode.build.filterMode") private var filterMode: LogFilterMode = .all

    // Segmented View Mode
    @State private var activeSection: SectionTab = .console

    // Switch sheets
    @State private var showingIPABuilder = false
    @State private var showPlatformPickerSheet = false
    @State private var showSDKErrorDetailSheet = false
    @State private var platformSearchText = ""

    @Environment(\.dismiss) private var dismiss

    private var buildManager: XcodeBuildManager {
        XcodeBuildManager.shared
    }

    enum SectionTab: String, CaseIterable, Identifiable {
        case console = "Console"
        case diagnostics = "Diagnostics"
        case settings = "Settings"
        case packaging = "Packaging"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .console: return "terminal"
            case .diagnostics: return "stethoscope"
            case .settings: return "gearshape"
            case .packaging: return "shippingbox"
            }
        }
    }

    enum LogFilterMode: String, CaseIterable, Identifiable {
        case all = "All Logs"
        case errors = "Errors"
        case warnings = "Warnings"
        case system = "System"

        var id: String { rawValue }
    }

    private var structuredLogs: [StructuredBuildLog] {
        buildManager.buildLogs.map { line in
            let lower = line.lowercased()
            let severity: StructuredBuildLog.Severity
            if lower.contains("error:") || lower.hasPrefix("error:") || lower.hasPrefix("[error]") {
                severity = .error
            } else if lower.contains("warning:") || lower.hasPrefix("warning:") {
                severity = .warning
            } else if lower.hasPrefix("[system]") {
                severity = .system
            } else {
                severity = .info
            }
            return StructuredBuildLog(message: line, severity: severity)
        }
    }

    private var filteredStructuredLogs: [StructuredBuildLog] {
        var logs = structuredLogs

        if !searchLogQuery.isEmpty {
            logs = logs.filter { $0.message.localizedCaseInsensitiveContains(searchLogQuery) }
        }

        switch filterMode {
        case .all:
            return logs
        case .errors:
            return logs.filter { $0.severity == .error }
        case .warnings:
            return logs.filter { $0.severity == .warning }
        case .system:
            return logs.filter { $0.severity == .system }
        }
    }

    private var errorLogs: [StructuredBuildLog] {
        structuredLogs.filter { $0.severity == .error }
    }

    private var warningLogs: [StructuredBuildLog] {
        structuredLogs.filter { $0.severity == .warning }
    }

    var body: some View {
        @Bindable var buildManager = self.buildManager
        NavigationStack {
            VStack(spacing: 0) {
                // Top Clean Toolbar
                topToolbar

                Divider()

                // Main Content by Segment
                switch activeSection {
                case .console:
                    consoleSection
                case .diagnostics:
                    diagnosticsSection
                case .settings:
                    settingsSection
                case .packaging:
                    packagingSection
                }
            }
            .navigationTitle("Xcode Build Center")
            .onAppear {
                Task {
                    await buildManager.detectAvailableSDKs()
                }
            }
            .sheet(isPresented: $showingIPABuilder) {
                AdaptiveSheet {
                    NavigationStack {
                        IPABuildView()
                    }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingIPABuilder = false }
                        }
                    }
                }
            }
            .sheet(isPresented: $showPlatformPickerSheet) {
                platformPickerSheet
            }
            .sheet(isPresented: $showSDKErrorDetailSheet) {
                sdkErrorDetailSheet
            }
        }
    }

    // MARK: - Top Toolbar
    private var topToolbar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                // Segmented section picker
                Picker("", selection: $activeSection) {
                    ForEach(SectionTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 440)

                Spacer()

                // Status Badge
                statusBadge

                // Action Buttons
                if buildManager.isBuilding {
                    Button(role: .destructive) {
                        buildManager.cancelBuild()
                    } label: {
                        Label("Cancel", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        Task {
                            await buildManager.runBuild()
                        }
                    } label: {
                        Label("Build", systemImage: "hammer")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Menu {
                    Button {
                        Task {
                            buildManager.cleanBuild()
                        }
                    } label: {
                        Label("Clean Build Folder", systemImage: "trash")
                    }

                    Button {
                        copyBuildCommand()
                    } label: {
                        Label("Copy Build Command", systemImage: "terminal")
                    }

                    Button {
                        let text = buildManager.buildLogs.joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    } label: {
                        Label("Copy All Logs", systemImage: "doc.on.doc")
                    }

                    Button {
                        exportLogsToFile()
                    } label: {
                        Label("Export Logs...", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        Task {
                            await buildManager.detectAvailableSDKs(forceRefresh: true)
                        }
                    } label: {
                        Label("Re-detect SDKs", systemImage: "arrow.triangle.2.circlepath")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderedButton)
                .fixedSize()
            }

            // Sub-metrics row
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Duration: \(String(format: "%.1fs", buildManager.buildDuration))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.octagon")
                        .font(.caption2)
                        .foregroundStyle(buildManager.errorsCount > 0 ? .primary : .secondary)
                    Text("Errors: \(buildManager.errorsCount)")
                        .font(.caption.bold())
                }

                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(buildManager.warningsCount > 0 ? .primary : .secondary)
                    Text("Warnings: \(buildManager.warningsCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if buildManager.isAssistFixRunning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(buildManager.assistFixStatus.isEmpty ? "Fixing with Assist…" : buildManager.assistFixStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Button("Stop") {
                            buildManager.stopAssistFixLoop()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else if !errorLogs.isEmpty || buildManager.currentStatus == .failed {
                    Button {
                        buildManager.startAssistFixLoop()
                    } label: {
                        Label("Fix Build with Assist", systemImage: "wand.and.stars")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Capture all logs and project context, then let Assist iteratively fix the build until xcodebuild reports BUILD SUCCEEDED.")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            if buildManager.isBuilding {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: statusIcon(buildManager.currentStatus))
                    .font(.caption)
            }
            Text(buildManager.currentStatus.rawValue)
                .font(.caption.bold())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    // MARK: - Section 1: Console
    private var consoleSection: some View {
        VStack(spacing: 0) {
            // Filter Bar
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Filter build logs...", text: $searchLogQuery)
                        .textFieldStyle(.plain)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

                Picker("", selection: $filterMode) {
                    ForEach(LogFilterMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                Toggle("Auto-scroll", isOn: $autoScrollToBottom)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Console output area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        if filteredStructuredLogs.isEmpty {
                            VStack(spacing: 10) {
                                Spacer()
                                Image(systemName: "terminal")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.secondary)
                                Text("No build logs to display")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, minHeight: 350)
                        } else {
                            ForEach(Array(filteredStructuredLogs.enumerated()), id: \.offset) { index, log in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(log.timestamp.formatted(date: .omitted, time: .standard))
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.secondary.opacity(0.7))
                                        .frame(width: 65, alignment: .leading)

                                    Image(systemName: log.severity.icon)
                                        .font(.system(size: 10))
                                        .foregroundStyle(log.severity == .error ? .primary : .secondary)

                                    Text(log.message)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(log.severity == .error ? .primary : .secondary)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .id(index)
                            }
                        }
                    }
                    .padding(12)
                }
                .background(Color(NSColor.textBackgroundColor))
                .onChange(of: filteredStructuredLogs.count) { _, newCount in
                    if autoScrollToBottom && newCount > 0 {
                        withAnimation {
                            proxy.scrollTo(newCount - 1, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Section 2: Diagnostics
    private var diagnosticsSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if errorLogs.isEmpty && warningLogs.isEmpty {
                    ContentUnavailableView {
                        Label("Clean Build Log", systemImage: "checkmark.shield")
                    } description: {
                        Text("No compiler errors or warnings detected in the active build output.")
                    }
                    .padding(40)
                } else {
                    if !errorLogs.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Label("Errors (\(errorLogs.count))", systemImage: "exclamationmark.octagon")
                                        .font(.headline)
                                    Spacer()
                                    if buildManager.isAssistFixRunning {
                                        HStack(spacing: 6) {
                                            ProgressView().controlSize(.small)
                                            Text(buildManager.assistFixStatus.isEmpty ? "Waiting for Assist…" : buildManager.assistFixStatus)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Button("Stop") {
                                                buildManager.stopAssistFixLoop()
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                    } else {
                                        Button {
                                            buildManager.startAssistFixLoop()
                                        } label: {
                                            Label("Fix Build with Assist", systemImage: "wand.and.stars")
                                                .font(.caption)
                                        }
                                        .buttonStyle(.bordered)
                                        .help("Capture all logs and project context, then let Assist iteratively fix the build until xcodebuild reports BUILD SUCCEEDED.")
                                    }
                                }

                                Divider()

                                ForEach(errorLogs) { log in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "exclamationmark.circle")
                                            .font(.caption)
                                        Text(log.message)
                                            .font(.system(size: 11, design: .monospaced))
                                            .textSelection(.enabled)
                                    }
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                                }
                            }
                            .padding(8)
                        }
                    }

                    if !warningLogs.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Label("Warnings (\(warningLogs.count))", systemImage: "exclamationmark.triangle")
                                        .font(.headline)
                                    Spacer()
                                }

                                Divider()

                                ForEach(warningLogs) { log in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(log.message)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                                }
                            }
                            .padding(8)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Section 3: Settings
    private var settingsSection: some View {
        @Bindable var buildManager = self.buildManager
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Build Configuration", systemImage: "gearshape")
                            .font(.headline)

                        Divider()

                        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 14) {
                            GridRow {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label("Configuration", systemImage: "slider.horizontal.3")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Picker("", selection: $buildManager.selectedConfiguration) {
                                        ForEach(buildManager.availableConfigurations, id: \.self) { config in
                                            Text(config).tag(config)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(width: 220)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Label("Active Scheme", systemImage: "target")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(buildManager.selectedScheme ?? "Automatic")
                                        .font(.body.bold())
                                }
                            }

                            GridRow {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label("Target SDK Platform", systemImage: "apple.logo")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Button {
                                        platformSearchText = ""
                                        showPlatformPickerSheet = true
                                    } label: {
                                        HStack {
                                            Text(buildManager.selectedSDKType)
                                                .font(.body)
                                            Spacer()
                                            Image(systemName: "chevron.up.chevron.down")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                                    }
                                    .buttonStyle(.plain)
                                    .frame(width: 220)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Label("Destination", systemImage: "iphone")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(buildManager.selectedDestination)
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(1)
                                }
                            }

                            GridRow {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label("Active Developer Xcode Path", systemImage: "folder")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(buildManager.activeXcodePath.isEmpty ? "/usr/bin/xcodebuild" : buildManager.activeXcodePath)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Label("SDK Detection Status", systemImage: "info.circle")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: 6) {
                                        Text("\(buildManager.detectedSDKs.count) SDKs Available")
                                            .font(.caption)
                                        Button("Refresh") {
                                            Task {
                                                await buildManager.detectAvailableSDKs(forceRefresh: true)
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("CLI Build Command", systemImage: "terminal")
                            .font(.headline)

                        Divider()

                        Text(buildCommandString())
                            .font(.system(.caption, design: .monospaced))
                            .padding(10)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                            .textSelection(.enabled)

                        HStack {
                            Spacer()
                            Button {
                                copyBuildCommand()
                            } label: {
                                Label("Copy Command", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(12)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Section 4: Packaging
    private var packagingSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Package Binary & IPA", systemImage: "shippingbox")
                            .font(.headline)

                        Divider()

                        Text("Produce production, ad-hoc, or enterprise .ipa archives and export binaries directly to your build products directory.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button {
                                showingIPABuilder = true
                            } label: {
                                Label("Open IPA Packaging Wizard...", systemImage: "shippingbox.fill")
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                if let derived = URL(string: "file:///Users/dylan/SwiftCode-Mac/build/DerivedData") {
                                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: derived.path)
                                }
                            } label: {
                                Label("Reveal Build Products in Finder", systemImage: "folder")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(12)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Sheets & Helpers
    private var platformPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search platform...", text: $platformSearchText)
                        .textFieldStyle(.plain)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.08))

                List {
                    let filtered = buildManager.availableSDKTypes.filter {
                        platformSearchText.isEmpty || $0.localizedCaseInsensitiveContains(platformSearchText)
                    }

                    if filtered.isEmpty {
                        Text("No platforms match your search")
                            .foregroundStyle(.secondary)
                            .italic()
                            .padding()
                    } else {
                        ForEach(filtered, id: \.self) { platform in
                            Button {
                                buildManager.selectedSDKType = platform
                                showPlatformPickerSheet = false
                            } label: {
                                HStack {
                                    Image(systemName: platform == "Default" ? "command" : "apple.logo")
                                        .foregroundStyle(.secondary)
                                    Text(platform)
                                    Spacer()
                                    if platform == buildManager.selectedSDKType {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Target Platform")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showPlatformPickerSheet = false }
                }
            }
        }
        .frame(width: 320, height: 380)
    }

    private var sdkErrorDetailSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Label("SDK Diagnostics", systemImage: "info.circle")
                        .font(.headline)

                    if let err = buildManager.sdkDetectionError {
                        Text(err)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding()
            }
            .navigationTitle("Diagnostic Log")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Dismiss") { showSDKErrorDetailSheet = false }
                }
            }
        }
        .frame(width: 500, height: 350)
    }

    private func buildCommandString() -> String {
        let path = buildManager.getXcodeBuildPath()
        let scheme = buildManager.selectedScheme ?? "DefaultScheme"
        let config = buildManager.selectedConfiguration
        let dest = buildManager.selectedDestination
        return "\(path) -scheme \(scheme) -configuration \(config) -destination \"\(dest)\" build"
    }

    private func copyBuildCommand() {
        let cmd = buildCommandString()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
    }

    private func exportLogsToFile() {
        let text = buildManager.buildLogs.joined(separator: "\n")
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "XcodeBuildLogs.txt"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? text.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    private func statusIcon(_ status: XcodeBuildManager.BuildStatus) -> String {
        switch status {
        case .idle: return "circle"
        case .building: return "arrow.triangle.2.circlepath"
        case .succeeded: return "checkmark.circle"
        case .failed: return "xmark.circle"
        case .cancelled: return "minus.circle"
        default: return "circle"
        }
    }
}
