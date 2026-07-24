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
            case .error: return "exclamationmark.octagon.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .system: return "cpu.fill"
            case .info: return "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .error: return .red
            case .warning: return .yellow
            case .system: return .cyan
            case .info: return .secondary
            }
        }
    }
}

@MainActor
struct XcodeBuildLogView: View {
    @AppStorage("com.swiftcode.build.searchLogQuery") private var searchLogQuery = ""
    @AppStorage("com.swiftcode.build.autoScrollToBottom") private var autoScrollToBottom = true
    @AppStorage("com.swiftcode.build.filterMode") private var filterMode: LogFilterMode = .all

    // Collapsible section states
    @AppStorage("com.swiftcode.build.showErrorsGroup") private var showErrorsGroup = true
    @AppStorage("com.swiftcode.build.showWarningsGroup") private var showWarningsGroup = true
    @AppStorage("com.swiftcode.build.showFullConsole") private var showFullConsole = true

    // Switch sheets
    @State private var showingIPABuilder = false

    // SDK Search and detail sheets
    @State private var platformSearchText = ""
    @State private var showPlatformPickerSheet = false
    @State private var showSDKErrorDetailSheet = false

    @Environment(\.dismiss) private var dismiss

    private var buildManager: XcodeBuildManager {
        XcodeBuildManager.shared
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
            ScrollView {
                VStack(spacing: 24) {
                    // Title info card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Xcode Build Center", systemImage: "hammer.fill")
                                    .font(.headline)
                                    .foregroundColor(.purple)
                                Spacer()
                            }
                            Text("Monitor compiling workloads, diagnose syntax or architecture issues, and package deployment binaries.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 1: Build Status Metrics
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Build Status Details", systemImage: "play.circle")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }

                            buildStatusHeader
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 2: Build Specifications (Fully Dynamic & Modernized Layout)
                    GroupBox {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack {
                                Label("Build Specifications", systemImage: "gearshape.fill")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()

                                // Dynamic Sync status/Trigger
                                sdkDetectionStatusView
                            }

                            Divider()

                            if buildManager.sdkDetectionState == .failure {
                                errorStateSpecificationView
                            } else {
                                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 16) {
                                    GridRow {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Label("Active Build Scheme", systemImage: "scheme")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text(buildManager.selectedScheme ?? "Automatic")
                                                .font(.body.bold())
                                        }

                                        VStack(alignment: .leading, spacing: 4) {
                                            Label("Build SDK Destination", systemImage: "target")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text(buildManager.selectedDestination)
                                                .font(.body.bold())
                                        }
                                    }

                                    GridRow {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Label("Optimization Level", systemImage: "speedometer")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text("\(buildManager.selectedConfiguration)")
                                                .font(.body.bold())
                                        }

                                        VStack(alignment: .leading, spacing: 4) {
                                            Label("Active Developer Xcode Path", systemImage: "folder.fill")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text(buildManager.activeXcodePath.isEmpty ? "Not Detected" : buildManager.activeXcodePath)
                                                .font(.system(.body, design: .monospaced))
                                                .lineLimit(1)
                                                .help(buildManager.activeXcodePath)
                                        }
                                    }

                                    GridRow {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Label("Target SDK Platform", systemImage: "apple.logo")
                                                .font(.caption)
                                                .foregroundColor(.secondary)

                                            Button {
                                                platformSearchText = ""
                                                showPlatformPickerSheet = true
                                            } label: {
                                                HStack {
                                                    Text(buildManager.selectedSDKType)
                                                        .font(.body.bold())
                                                    Spacer()
                                                    Image(systemName: "chevron.up.chevron.down")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                                            }
                                            .buttonStyle(.plain)
                                            .frame(maxWidth: 240)
                                        }

                                        VStack(alignment: .leading, spacing: 4) {
                                            Label("Target SDK Version", systemImage: "number")
                                                .font(.caption)
                                                .foregroundColor(.secondary)

                                            Picker("", selection: $buildManager.selectedSDKVersion) {
                                                ForEach(buildManager.availableSDKVersions, id: \.self) { version in
                                                    Text(version).tag(version)
                                                }
                                            }
                                            .pickerStyle(.menu)
                                            .labelsHidden()
                                            .controlSize(.regular)
                                            .frame(maxWidth: 240)
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 3: Action Buttons Box
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Actions", systemImage: "bolt.fill")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                Spacer()
                            }

                            HStack(spacing: 12) {
                                Button(action: {
                                    let text = buildManager.buildLogs.joined(separator: "\n")
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(text, forType: .string)
                                }) {
                                    Label("Copy Logs", systemImage: "doc.on.doc")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.large)

                                Button {
                                    showingIPABuilder = true
                                } label: {
                                    Label("Package IPA Bundle...", systemImage: "shippingbox.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.purple)
                                .controlSize(.large)

                                if buildManager.isBuilding {
                                    Button("Cancel Build") {
                                        buildManager.cancelBuild()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)
                                    .controlSize(.large)
                                }
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 4: Collapsible Errors Group
                    if !errorLogs.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                Button {
                                    withAnimation { showErrorsGroup.toggle() }
                                } label: {
                                    HStack {
                                        Label("Errors Detected (\(errorLogs.count))", systemImage: "exclamationmark.octagon.fill")
                                            .font(.headline)
                                            .foregroundColor(.red)
                                        Spacer()
                                        Image(systemName: showErrorsGroup ? "chevron.up" : "chevron.down")
                                            .foregroundStyle(.red)
                                    }
                                }
                                .buttonStyle(.plain)

                                if showErrorsGroup {
                                    Divider()
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(errorLogs) { log in
                                            HStack(alignment: .top, spacing: 8) {
                                                Text(log.timestamp.formatted(date: .omitted, time: .standard))
                                                    .font(.system(.caption2, design: .monospaced))
                                                    .foregroundColor(.secondary)

                                                Text(log.message)
                                                    .font(.system(.caption, design: .monospaced))
                                                    .foregroundColor(.red)
                                                    .textSelection(.enabled)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                            .padding(6)
                                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                                        }
                                    }
                                }
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }

                    // Card 5: Collapsible Warnings Group
                    if !warningLogs.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                Button {
                                    withAnimation { showWarningsGroup.toggle() }
                                } label: {
                                    HStack {
                                        Label("Warnings Detected (\(warningLogs.count))", systemImage: "exclamationmark.triangle.fill")
                                            .font(.headline)
                                            .foregroundColor(.yellow)
                                        Spacer()
                                        Image(systemName: showWarningsGroup ? "chevron.up" : "chevron.down")
                                            .foregroundStyle(.yellow)
                                    }
                                }
                                .buttonStyle(.plain)

                                if showWarningsGroup {
                                    Divider()
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(warningLogs) { log in
                                            HStack(alignment: .top, spacing: 8) {
                                                Text(log.timestamp.formatted(date: .omitted, time: .standard))
                                                    .font(.system(.caption2, design: .monospaced))
                                                    .foregroundColor(.secondary)

                                                Text(log.message)
                                                    .font(.system(.caption, design: .monospaced))
                                                    .foregroundColor(.yellow)
                                                    .textSelection(.enabled)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                            .padding(6)
                                            .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                                        }
                                    }
                                }
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }

                    // Card 6: Console Outputs Group
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Menu {
                                    Button {
                                        let text = buildManager.buildLogs.joined(separator: "\n")
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(text, forType: .string)
                                    } label: {
                                        Label("Copy Logs", systemImage: "doc.on.doc")
                                    }

                                    Button {
                                        exportLogsToFile()
                                    } label: {
                                        Label("Export Logs...", systemImage: "square.and.arrow.up")
                                    }
                                } label: {
                                    Label("Console Outputs Log Trace", systemImage: "terminal.fill")
                                        .font(.headline)
                                        .foregroundColor(.blue)
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()

                                Spacer()

                                Toggle("Auto-scroll", isOn: $autoScrollToBottom)
                                    .toggleStyle(.checkbox)
                                    .controlSize(.small)
                            }

                            HStack(spacing: 12) {
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    TextField("Search logs...", text: $searchLogQuery)
                                        .textFieldStyle(.plain)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                                .frame(maxWidth: .infinity)

                                Picker("", selection: $filterMode) {
                                    ForEach(LogFilterMode.allCases) { mode in
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .controlSize(.small)
                                .frame(width: 260)
                            }

                            Divider()

                            ScrollViewReader { proxy in
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 4) {
                                        if filteredStructuredLogs.isEmpty {
                                            VStack(spacing: 10) {
                                                Spacer()
                                                Image(systemName: "doc.text.magnifyingglass")
                                                    .font(.system(size: 24))
                                                    .foregroundStyle(.secondary)
                                                Text("No matching build logs")
                                                    .font(.subheadline.bold())
                                                    .foregroundStyle(.secondary)
                                                Spacer()
                                            }
                                            .frame(maxWidth: .infinity, minHeight: 250)
                                        } else {
                                            ForEach(Array(filteredStructuredLogs.enumerated()), id: \.offset) { index, log in
                                                HStack(alignment: .top, spacing: 6) {
                                                    Text(log.timestamp.formatted(date: .omitted, time: .standard))
                                                        .font(.system(size: 9, design: .monospaced))
                                                        .foregroundColor(.secondary.opacity(0.6))

                                                    Circle()
                                                        .fill(log.severity.color)
                                                        .frame(width: 5, height: 5)
                                                        .padding(.top, 5)

                                                    Text(log.message)
                                                        .font(.system(size: 10, design: .monospaced))
                                                        .foregroundStyle(log.severity.color)
                                                        .textSelection(.enabled)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                }
                                                .id(index)
                                            }
                                        }
                                    }
                                    .padding()
                                }
                                .frame(height: 350)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(12)
                                .onChange(of: filteredStructuredLogs.count) { _, newCount in
                                    if autoScrollToBottom && newCount > 0 {
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
                .padding(24)
            }
            .navigationTitle("Xcode Build Center")
            .onAppear {
                // Asynchronously detect available SDKs on load to pre-populate selection
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
            // Dynamic platform picker sheet with real-time searching
            .sheet(isPresented: $showPlatformPickerSheet) {
                NavigationStack {
                    VStack(spacing: 0) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("Search platform...", text: $platformSearchText)
                                .textFieldStyle(.plain)
                        }
                        .padding()
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
                                                .foregroundColor(platform == buildManager.selectedSDKType ? .accentColor : .secondary)
                                            Text(platform)
                                                .font(.body)
                                            Spacer()
                                            if platform == buildManager.selectedSDKType {
                                                Image(systemName: "checkmark")
                                                    .foregroundColor(.accentColor)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .navigationTitle("Select Target SDK Platform")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showPlatformPickerSheet = false
                            }
                        }
                    }
                }
                .frame(width: 350, height: 400)
            }
            // SDK detection error detailed report
            .sheet(isPresented: $showSDKErrorDetailSheet) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Label("SDK Detection Diagnostic Report", systemImage: "info.circle.fill")
                                .font(.headline)
                                .foregroundColor(.red)

                            if let err = buildManager.sdkDetectionError {
                                Text("Error:")
                                    .font(.subheadline.bold())
                                Text(err)
                                    .foregroundStyle(.red)
                                    .padding()
                                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            }

                            if let code = buildManager.sdkDetectionExitCode {
                                Text("Process Exit Code:")
                                    .font(.subheadline.bold())
                                Text("\(code)")
                                    .font(.system(.body, design: .monospaced))
                            }

                            if !buildManager.sdkDetectionStdout.isEmpty {
                                Text("Standard Output:")
                                    .font(.subheadline.bold())
                                Text(buildManager.sdkDetectionStdout)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding()
                                    .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                                    .textSelection(.enabled)
                            }

                            if !buildManager.sdkDetectionStderr.isEmpty {
                                Text("Standard Error:")
                                    .font(.subheadline.bold())
                                Text(buildManager.sdkDetectionStderr)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.red)
                                    .padding()
                                    .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                                    .textSelection(.enabled)
                            }
                        }
                        .padding()
                    }
                    .navigationTitle("Diagnostic Log")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Dismiss") {
                                showSDKErrorDetailSheet = false
                            }
                        }
                    }
                }
                .frame(width: 600, height: 450)
            }
        }
    }

    private var buildStatusHeader: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(statusColor(buildManager.currentStatus).opacity(0.12))
                        .frame(width: 32, height: 32)

                    if buildManager.isBuilding {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: statusIcon(buildManager.currentStatus))
                            .font(.headline)
                            .foregroundStyle(statusColor(buildManager.currentStatus))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("BUILD STATUS")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(buildManager.currentStatus.rawValue)
                        .font(.subheadline.bold())
                        .foregroundStyle(statusColor(buildManager.currentStatus))
                }
            }
            .frame(width: 160, alignment: .leading)

            Divider().frame(height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("DURATION")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f s", buildManager.buildDuration))
                    .font(.subheadline.bold())
            }
            .frame(width: 80, alignment: .leading)

            Divider().frame(height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("ERRORS")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("\(buildManager.errorsCount)")
                    .font(.subheadline.bold())
                    .foregroundStyle(buildManager.errorsCount > 0 ? .red : .primary)
            }
            .frame(width: 60, alignment: .leading)

            Divider().frame(height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("WARNINGS")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("\(buildManager.warningsCount)")
                    .font(.subheadline.bold())
                    .foregroundStyle(buildManager.warningsCount > 0 ? .yellow : .primary)
            }
            .frame(width: 60, alignment: .leading)
        }
    }

    // Dynamic SDK detection header status component
    private var sdkDetectionStatusView: some View {
        HStack(spacing: 8) {
            switch buildManager.sdkDetectionState {
            case .idle:
                Button {
                    Task {
                        await buildManager.detectAvailableSDKs(forceRefresh: true)
                    }
                } label: {
                    Label("Check Available SDKs", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

            case .detecting:
                ProgressView()
                    .controlSize(.small)
                Text("Detecting SDKs...")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .success:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("\(buildManager.detectedSDKs.count) SDKs Found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task {
                        await buildManager.detectAvailableSDKs(forceRefresh: true)
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Refresh Available SDKs")

            case .failure:
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("Detection Failed")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button("Details") {
                    showSDKErrorDetailSheet = true
                }
                .buttonStyle(.link)
                .font(.caption)

                Button {
                    Task {
                        await buildManager.detectAvailableSDKs(forceRefresh: true)
                    }
                } label: {
                    Label("Retry", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // Detailed layout when detection completely fails
    private var errorStateSpecificationView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 32))
                .foregroundColor(.red)

            Text("No Apple SDKs found or command failed")
                .font(.headline)

            Text("Please verify Xcode is installed correctly, or configure the correct path in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack(spacing: 12) {
                Button("View Error Details") {
                    showSDKErrorDetailSheet = true
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button("Retry Verification") {
                    Task {
                        await buildManager.detectAvailableSDKs(forceRefresh: true)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.red.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
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
        case .idle: return "play.circle"
        case .building: return "arrow.triangle.2.circlepath"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "multiply.circle.fill"
        default: return "exclamationmark.circle.fill"
        }
    }

    private func statusColor(_ status: XcodeBuildManager.BuildStatus) -> Color {
        switch status {
        case .idle: return .secondary
        case .building: return .blue
        case .succeeded: return .green
        case .failed: return .red
        case .cancelled: return .orange
        default: return .red
        }
    }
}
