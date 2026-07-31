import SwiftUI
import os

struct ProjectInspectorView: View {
    @State private var scanner = InspectorProjectScanner.shared
    @State private var selectedTab = "Overview"
    @State private var aiReviewPrompt = "Explain this project."
    @State private var aiReviewResult = ""
    @State private var isAIReviewRunning = false
    @State private var alertMessage = ""
    @State private var showingAlert = false

    let tabs = ["Overview", "Structure", "Analytics", "AI Review", "Actions"]

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: "square.text.square")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text("Project Inspector")
                        .font(.title2.bold())
                }

                Spacer()

                HStack(spacing: 12) {
                    // Health Score Indicator
                    HStack(spacing: 6) {
                        Image(systemName: "heart.text.square.fill")
                            .foregroundColor(healthColor)
                        Text("Health Score: \(scanner.projectHealthScore)/100")
                            .font(.subheadline.bold())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(healthColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                    // Scan button
                    Button {
                        Task {
                            await scanner.scan()
                        }
                    } label: {
                        HStack {
                            if scanner.isScanning {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .padding(.trailing, 4)
                                Text("Scanning...")
                            } else {
                                Image(systemName: "arrow.clockwise")
                                Text("Scan Now")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(scanner.isScanning)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Main Tab View
            TabView(selection: $selectedTab) {
                // Overview Tab
                ScrollView {
                    overviewTab()
                }
                .tabItem {
                    Label("Overview", systemImage: "doc.text.fill")
                }
                .tag("Overview")

                // Structure Tab
                ProjectArchitectureGraph()
                    .tabItem {
                        Label("Structure", systemImage: "circle.grid.3x3.fill")
                    }
                    .tag("Structure")

                // Analytics Tab
                ScrollView {
                    analyticsTab()
                }
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar.xaxis")
                }
                .tag("Analytics")

                // AI Review Tab
                aiReviewTab()
                    .tabItem {
                        Label("AI Review", systemImage: "sparkles")
                    }
                    .tag("AI Review")

                // Actions Tab
                ScrollView {
                    actionsTab()
                }
                .tabItem {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
                .tag("Actions")
            }
            .padding(.top, 1)
        }
        .onAppear {
            Task {
                await scanner.scan()
            }
        }
        .alert("Project Inspector", isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private var healthColor: Color {
        if scanner.projectHealthScore >= 85 { return .green }
        if scanner.projectHealthScore >= 65 { return .orange }
        return .red
    }

    // MARK: - Overview Tab View

    @ViewBuilder
    private func overviewTab() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // General Metadata Card
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Project Metadata", systemImage: "info.circle")
                        .font(.headline)
                        .foregroundColor(.blue)

                    Divider()

                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                        GridRow {
                            Text("Project Name:").bold()
                            Text(scanner.projectName)
                            Text("Bundle ID:").bold()
                            Text(scanner.bundleIdentifier)
                        }
                        GridRow {
                            Text("Version:").bold()
                            Text(scanner.version)
                            Text("Build Number:").bold()
                            Text(scanner.buildNumber)
                        }
                        GridRow {
                            Text("Platforms:").bold()
                            Text(scanner.platformSupport.joined(separator: ", "))
                            Text("Deployment Target:").bold()
                            Text(scanner.deploymentTargets.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
                        }
                        GridRow {
                            Text("Swift Version:").bold()
                            Text(scanner.swiftVersion)
                            Text("Active SDK:").bold()
                            Text(scanner.sdkVersion)
                        }
                    }
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            // Code statistics card
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("General Code Statistics", systemImage: "chart.pie.fill")
                        .font(.headline)
                        .foregroundColor(.orange)

                    Divider()

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 16) {
                        statBubble(title: "Total Files", val: "\(scanner.totalFiles)", icon: "doc.fill", color: .blue)
                        statBubble(title: "Total Folders", val: "\(scanner.totalFolders)", icon: "folder.fill", color: .yellow)
                        statBubble(title: "Swift Files", val: "\(scanner.totalSwiftFiles)", icon: "swift", color: .orange)
                        statBubble(title: "Assets & Media", val: "\(scanner.totalAssets)", icon: "photo.fill", color: .green)
                        statBubble(title: "Local Packages", val: "\(scanner.packageCount)", icon: "puzzlepiece.fill", color: .purple)
                        statBubble(title: "Frameworks", val: "\(scanner.frameworkCount)", icon: "shippingbox.fill", color: .cyan)
                    }
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            // AI Recommendations & Health Check Card
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("AI Recommendations & Health Checks", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundColor(.purple)

                    Divider()

                    ForEach(scanner.aiRecommendations, id: \.self) { rec in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.yellow)
                            Text(rec)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            // Recent Project Changes Card
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Recent Changes (Git History)", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.headline)
                        .foregroundColor(.green)

                    Divider()

                    ForEach(scanner.recentChanges, id: \.self) { change in
                        HStack {
                            Image(systemName: "arrow.triangle.branch")
                                .foregroundColor(.gray)
                            Text(change)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
        .padding(24)
    }

    private func statBubble(title: String, val: String, icon: String, color: Color) -> some View {
        HStack {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(val)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Analytics Tab View

    @ViewBuilder
    private func analyticsTab() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Modern Swift Syntax Usage Card
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Modern Swift Feature Usage", systemImage: "atom")
                        .font(.headline)
                        .foregroundColor(.blue)

                    Divider()

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 16) {
                        usageMetricBar(title: "SwiftUI View Declarations", count: scanner.swiftUIUsageCount, icon: "square.stack.3d.down.right.fill", color: .purple)
                        usageMetricBar(title: "UIKit Controller Usage", count: scanner.uikitUsageCount, icon: "apps.iphone", color: .green)
                        usageMetricBar(title: "AppKit Desktop Controls", count: scanner.appkitUsageCount, icon: "laptopcomputer", color: .cyan)
                        usageMetricBar(title: "Observation (@Observable)", count: scanner.observationUsageCount, icon: "brain.head.profile", color: .purple)
                        usageMetricBar(title: "Asynchronous Operations (async/await)", count: scanner.asyncUsageCount, icon: "clock.fill", color: .orange)
                        usageMetricBar(title: "Shared State Actors (actor)", count: scanner.actorUsageCount, icon: "shield.fill", color: .yellow)
                    }
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            // File sizes and line count analytics
            HStack(alignment: .top, spacing: 20) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Largest Files (on Disk)", systemImage: "doc.zippera")
                            .font(.headline)
                            .foregroundColor(.orange)

                        Divider()

                        ForEach(scanner.largestFiles) { file in
                            HStack {
                                Image(systemName: "doc.text")
                                    .foregroundColor(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.name).bold().font(.subheadline)
                                    Text(file.path).font(.caption).foregroundColor(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text(formatBytes(file.size))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Longest Swift Files (Line Count)", systemImage: "text.alignleft")
                            .font(.headline)
                            .foregroundColor(.purple)

                        Divider()

                        ForEach(scanner.longestSwiftFiles) { file in
                            HStack {
                                Image(systemName: "swift")
                                    .foregroundColor(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.name).bold().font(.subheadline)
                                    Text(file.path).font(.caption).foregroundColor(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text("\(file.lineCount) lines")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }

            // Largest directories card
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Largest Folders & Modules", systemImage: "folder.badge.gearshape")
                        .font(.headline)
                        .foregroundColor(.green)

                    Divider()

                    ForEach(scanner.largestFolders) { folder in
                        HStack {
                            Image(systemName: "folder")
                                .foregroundColor(.yellow)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder.name).bold().font(.subheadline)
                                Text(folder.path).font(.caption).foregroundColor(.secondary).lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(folder.fileCount) files").font(.caption).foregroundColor(.secondary)
                                Text(formatBytes(folder.totalSize)).font(.system(.caption, design: .monospaced)).foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
        .padding(24)
    }

    private func usageMetricBar(title: String, count: Int, icon: String, color: Color) -> some View {
        HStack {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(count) occurrences")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func formatBytes(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    // MARK: - AI Review Tab View

    @ViewBuilder
    private func aiReviewTab() -> some View {
        HSplitView {
            // Prompts Sidebar
            VStack(alignment: .leading, spacing: 12) {
                Text("AI Assistant Presets")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)

                let presets = [
                    "Explain this project.",
                    "Explain the architecture.",
                    "Find duplicated code.",
                    "Detect dead code.",
                    "Find improvements.",
                    "Suggest refactors.",
                    "Review dependencies.",
                    "Review security.",
                    "Explain project structure.",
                    "Generate architecture documentation.",
                    "Suggest performance improvements."
                ]

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(presets, id: \.self) { preset in
                            Button {
                                aiReviewPrompt = preset
                            } label: {
                                HStack {
                                    Image(systemName: "sparkles")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                    Text(preset)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Spacer()
                                }
                                .padding(8)
                                .background(aiReviewPrompt == preset ? Color.accentColor.opacity(0.12) : Color.clear)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .frame(width: 260)
            .background(Color(NSColor.windowBackgroundColor))

            // AI Chat Workspace
            VStack(spacing: 0) {
                // Prompt Bar
                HStack {
                    TextField("Enter your request here...", text: $aiReviewPrompt)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        runAIReview()
                    } label: {
                        HStack {
                            if isAIReviewRunning {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .padding(.trailing, 4)
                                Text("Analyzing...")
                            } else {
                                Image(systemName: "sparkles")
                                Text("Analyze")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isAIReviewRunning || aiReviewPrompt.isEmpty)
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                // Response View
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if isAIReviewRunning {
                            VStack(spacing: 20) {
                                ProgressView()
                                    .controlSize(.large)
                                Text("AI Project Inspector is analyzing code patterns, layers, and dependencies...")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 40)
                            .frame(maxWidth: .infinity)
                        } else if aiReviewResult.isEmpty {
                            ContentUnavailableView("Project AI Intelligence", systemImage: "sparkles", description: Text("Select a preset on the left or type your own analysis request above to consult the AI inspector."))
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "sparkles")
                                        .foregroundColor(.orange)
                                    Text("AI Analysis Result")
                                        .font(.headline)
                                }

                                Text(aiReviewResult)
                                    .font(.body)
                                    .lineSpacing(4)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding()
                            .background(Color.secondary.opacity(0.04))
                            .cornerRadius(10)
                        }
                    }
                    .padding(24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func runAIReview() {
        guard !aiReviewPrompt.isEmpty else { return }
        isAIReviewRunning = true
        aiReviewResult = ""

        let projectSummary = """
Project Analysis Context:
- Project Name: \(scanner.projectName)
- Total Files: \(scanner.totalFiles), Total Folders: \(scanner.totalFolders)
- Swift Source Files: \(scanner.totalSwiftFiles)
- SwiftUI Views: \(scanner.swiftUIUsageCount)
- UIKit Controllers: \(scanner.uikitUsageCount)
- AppKit Views: \(scanner.appkitUsageCount)
- @Observable Usage: \(scanner.observationUsageCount)
- Async/Await Operations: \(scanner.asyncUsageCount)
- Concurrency Actors: \(scanner.actorUsageCount)
- Active Local Swift Packages: \(scanner.packageCount)
- Image Assets: \(scanner.imageCount)
- Localization Files: \(scanner.localizationCount)

Prompt: \(aiReviewPrompt)
"""

        Task {
            do {
                let response = try await LLMService.shared.generateResponse(prompt: projectSummary, useContext: true)
                aiReviewResult = response
            } catch {
                aiReviewResult = "Analysis Failed: \(error.localizedDescription)"
            }
            isAIReviewRunning = false
        }
    }

    // MARK: - Actions Tab View

    @ViewBuilder
    private func actionsTab() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Export Project Metrics Reports", systemImage: "doc.badge.plus")
                        .font(.headline)
                        .foregroundColor(.blue)

                    Divider()

                    Text("Generate high-quality documentation files outlining your application's file statistics, health score, and layout modules in Markdown or JSON schema formats.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Button("Export Markdown Report...") {
                            exportMarkdownReport()
                        }
                        .buttonStyle(.bordered)

                        Button("Export JSON Metrics...") {
                            exportJSONMetrics()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 6)
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Scanner Cache Control", systemImage: "archivebox.fill")
                        .font(.headline)
                        .foregroundColor(.orange)

                    Divider()

                    Text("The Project Inspector caches file statistics and metadata locally to support instantaneous incremental rescans without re-reading intact Swift files.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("Clear Cache & Full Recalculation") {
                        UserDefaults.standard.removeObject(forKey: "com.swiftcode.projectscanner.cache")
                        Task {
                            await scanner.scan()
                            alertMessage = "Cache cleared. Completed a fresh, fully parsed project scan."
                            showingAlert = true
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
        .padding(24)
    }

    private func exportMarkdownReport() {
        let markdown = """
# Project Inspector Analysis Report: \(scanner.projectName)
Generated: \(Date().description)

## Overview
- Project Name: \(scanner.projectName)
- Bundle Identifier: \(scanner.bundleIdentifier)
- Version: \(scanner.version)
- Build Number: \(scanner.buildNumber)
- Platforms Support: \(scanner.platformSupport.joined(separator: ", "))
- Swift Version: \(scanner.swiftVersion)
- Health Score: \(scanner.projectHealthScore)/100

## Codebase Statistics
- Total Files: \(scanner.totalFiles)
- Total Folders: \(scanner.totalFolders)
- Swift Files: \(scanner.totalSwiftFiles)
- Assets & Media count: \(scanner.totalAssets)
- Swift Packages: \(scanner.packageCount)
- Frameworks: \(scanner.frameworkCount)

## Modern Swift Features Usage
- SwiftUI views: \(scanner.swiftUIUsageCount)
- UIKit Controller usages: \(scanner.uikitUsageCount)
- AppKit desktop components: \(scanner.appkitUsageCount)
- Modern @Observable usage: \(scanner.observationUsageCount)
- async/await async blocks: \(scanner.asyncUsageCount)
- Isolated concurrency actors: \(scanner.actorUsageCount)

## AI Architecture Recommendations
\(scanner.aiRecommendations.map { "- \($0)" }.joined(separator: "\n"))
"""

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.markdown]
        panel.nameFieldStringValue = "ProjectInspectorReport.md"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                alertMessage = "Markdown analysis report successfully exported to \(url.lastPathComponent)!"
            } catch {
                alertMessage = "Failed to export report: \(error.localizedDescription)"
            }
            showingAlert = true
        }
    }

    private func exportJSONMetrics() {
        struct JSONReport: Codable {
            let projectName: String
            let totalFiles: Int
            let totalFolders: Int
            let totalSwiftFiles: Int
            let totalAssets: Int
            let packageCount: Int
            let frameworkCount: Int
            let swiftUIUsageCount: Int
            let uikitUsageCount: Int
            let appkitUsageCount: Int
            let observationUsageCount: Int
            let asyncUsageCount: Int
            let actorUsageCount: Int
            let healthScore: Int
            let recommendations: [String]
        }

        let report = JSONReport(
            projectName: scanner.projectName,
            totalFiles: scanner.totalFiles,
            totalFolders: scanner.totalFolders,
            totalSwiftFiles: scanner.totalSwiftFiles,
            totalAssets: scanner.totalAssets,
            packageCount: scanner.packageCount,
            frameworkCount: scanner.frameworkCount,
            swiftUIUsageCount: scanner.swiftUIUsageCount,
            uikitUsageCount: scanner.uikitUsageCount,
            appkitUsageCount: scanner.appkitUsageCount,
            observationUsageCount: scanner.observationUsageCount,
            asyncUsageCount: scanner.asyncUsageCount,
            actorUsageCount: scanner.actorUsageCount,
            healthScore: scanner.projectHealthScore,
            recommendations: scanner.aiRecommendations
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        if let data = try? encoder.encode(report),
           let jsonString = String(data: data, encoding: .utf8) {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "ProjectMetrics.json"

            if panel.runModal() == .OK, let url = panel.url {
                do {
                    try jsonString.write(to: url, atomically: true, encoding: .utf8)
                    alertMessage = "JSON metrics file successfully saved!"
                } catch {
                    alertMessage = "Failed to save JSON: \(error.localizedDescription)"
                }
                showingAlert = true
            }
        }
    }
}
