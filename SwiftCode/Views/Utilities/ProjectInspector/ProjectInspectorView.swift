import SwiftUI
import os

// MARK: - Small helpers for the Project tab

private struct InspectorSettingsGroup: Identifiable {
    var id: String { name }
    let name: String
    let pairs: [(key: String, value: String)]
}

private struct InspectorSigningRow: Identifiable {
    var id: String { config }
    let config: String
    let team: String
    let style: String
    let identity: String
}

struct ProjectInspectorView: View {
    @State private var scanner = InspectorProjectScanner.shared
    @State private var selectedTab = "Overview"
    @State private var aiReviewPrompt = "Explain this project."
    @State private var aiReviewResult = ""
    @State private var isAIReviewRunning = false
    @State private var alertMessage = ""
    @State private var showingAlert = false

    // Project tab state
    @State private var selectedSettingsTargetID = ""
    @State private var selectedSettingsConfig = ""
    @State private var settingsSearch = ""

    let tabs = ["Overview", "Project", "Structure", "Analytics", "AI Review", "Actions"]

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: "square.text.square")
                        .font(.title2)
                        .foregroundStyle(.secondary)
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

                // Project Tab
                ScrollView {
                    projectTab()
                }
                .tabItem {
                    Label("Project", systemImage: "hammer.fill")
                }
                .tag("Project")

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
        if scanner.projectHealthScore >= 65 { return .yellow }
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

                    Divider()

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 16) {
                        statTile(title: "Total Files", val: "\(scanner.totalFiles)", icon: "doc.fill")
                        statTile(title: "Total Folders", val: "\(scanner.totalFolders)", icon: "folder.fill")
                        statTile(title: "Swift Files", val: "\(scanner.totalSwiftFiles)", icon: "swift")
                        statTile(title: "Assets & Media", val: "\(scanner.totalAssets)", icon: "photo.fill")
                        statTile(title: "Local Packages", val: "\(scanner.packageCount)", icon: "puzzlepiece.fill")
                        statTile(title: "Frameworks", val: "\(scanner.frameworkCount)", icon: "shippingbox.fill")
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

                    Divider()

                    ForEach(scanner.aiRecommendations, id: \.self) { rec in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.secondary)
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

                    Divider()

                    ForEach(scanner.recentChanges, id: \.self) { change in
                        HStack {
                            Image(systemName: "arrow.triangle.branch")
                                .foregroundColor(.secondary)
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

    private func statTile(title: String, val: String, icon: String) -> some View {
        HStack {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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

    // MARK: - Project Tab View

    @ViewBuilder
    private func projectTab() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            projectSummaryCard()

            if scanner.xcodeProjectFound {
                targetsCard()
                schemesAndConfigsCard()
                signingSummaryCard()
                buildSettingsCard()
                dependenciesCard()
            } else {
                GroupBox {
                    ContentUnavailableView(
                        "No Xcode Project Found",
                        systemImage: "hammer",
                        description: Text("The scanner could not find a .xcodeproj at the project root, so target, scheme, signing, and build-setting details are unavailable.")
                    )
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }

            sourceFilesCard()
        }
        .padding(24)
    }

    @ViewBuilder
    private func projectSummaryCard() -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Project Summary", systemImage: "info.circle")
                    .font(.headline)

                Divider()

                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                    GridRow {
                        Text("Project Name:").bold()
                        Text(scanner.projectName)
                        Text("Xcode Project:").bold()
                        Text(scanner.xcodeProjectFound ? "Found" : "Not found")
                    }
                    GridRow {
                        Text("Targets:").bold()
                        Text("\(scanner.xcodeTargets.count)")
                        Text("Schemes:").bold()
                        Text("\(scanner.xcodeSchemes.count)")
                    }
                    GridRow {
                        Text("Configurations:").bold()
                        Text(scanner.buildConfigurations.isEmpty ? "—" : scanner.buildConfigurations.joined(separator: ", "))
                        Text("Package Dependencies:").bold()
                        Text("\(scanner.packageDependencies.count)")
                    }
                    GridRow {
                        Text("Project Path:").bold()
                        Text(scanner.projectDirectoryPath.isEmpty ? "—" : scanner.projectDirectoryPath)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                            .gridCellColumns(3)
                    }
                }
            }
            .padding()
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    @ViewBuilder
    private func targetsCard() -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Targets", systemImage: "square.stack.3d.up")
                    .font(.headline)

                Divider()

                ForEach(scanner.xcodeTargets) { target in
                    DisclosureGroup {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                            GridRow {
                                Text("Configuration").font(.caption).foregroundStyle(.secondary)
                                Text("Team").font(.caption).foregroundStyle(.secondary)
                                Text("Signing Style").font(.caption).foregroundStyle(.secondary)
                                Text("Identity").font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(signingRows(for: target)) { row in
                                GridRow {
                                    Text(row.config).font(.caption.weight(.medium))
                                    Text(row.team).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                                    Text(row.style).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                                    Text(row.identity).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        HStack {
                            Text(target.name)
                                .font(.body.weight(.medium))
                            productTypeBadge(target.productType)
                            Spacer()
                            Text("\(target.buildSettings.values.reduce(0) { $0 + $1.count }) settings")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    Divider().opacity(0.4)
                }
            }
            .padding()
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    private func productTypeBadge(_ type: String) -> some View {
        Text(type)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(NSColor.controlBackgroundColor), in: Capsule())
    }

    @ViewBuilder
    private func schemesAndConfigsCard() -> some View {
        HStack(alignment: .top, spacing: 20) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Schemes", systemImage: "play.square")
                        .font(.headline)

                    Divider()

                    if scanner.xcodeSchemes.isEmpty {
                        Text("No schemes found.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(scanner.xcodeSchemes) { scheme in
                            HStack {
                                Image(systemName: "play.circle")
                                    .foregroundStyle(.secondary)
                                Text(scheme.name)
                                    .font(.subheadline)
                                Spacer()
                                Text(scheme.isShared ? "Shared" : "Personal")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(NSColor.controlBackgroundColor), in: Capsule())
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Build Configurations", systemImage: "gearshape.2")
                        .font(.headline)

                    Divider()

                    if scanner.buildConfigurations.isEmpty {
                        Text("No configurations found.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ProjectInspectorFlowLayout(spacing: 8) {
                            ForEach(scanner.buildConfigurations, id: \.self) { config in
                                Text(config)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color(NSColor.controlBackgroundColor), in: Capsule())
                            }
                        }
                    }

                    Text("Each target below can override settings per configuration; use the Build Settings card to inspect them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
    }

    @ViewBuilder
    private func signingSummaryCard() -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Signing Summary", systemImage: "signature")
                    .font(.headline)

                Divider()

                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow {
                        Text("Target").font(.caption).foregroundStyle(.secondary)
                        Text("Team").font(.caption).foregroundStyle(.secondary)
                        Text("Signing Style").font(.caption).foregroundStyle(.secondary)
                        Text("Identity").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(scanner.xcodeTargets) { target in
                        let summary = preferredSigning(for: target)
                        GridRow {
                            Text(target.name).font(.subheadline.weight(.medium))
                            Text(summary.team).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                            Text(summary.style).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                Text(summary.identity).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                                if summary.varies {
                                    Text("varies by config")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Divider().opacity(0.3).gridCellUnsizedAxes(.horizontal)
                    }
                }
            }
            .padding()
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    private func signingRows(for target: InspectorTargetInfo) -> [InspectorSigningRow] {
        target.configurationNames.map { config in
            let settings = target.buildSettings[config] ?? [:]
            return InspectorSigningRow(
                config: config,
                team: settings["DEVELOPMENT_TEAM"] ?? "—",
                style: settings["CODE_SIGN_STYLE"] ?? "—",
                identity: settings["CODE_SIGN_IDENTITY"] ?? "—"
            )
        }
    }

    private func preferredSigning(for target: InspectorTargetInfo) -> (team: String, style: String, identity: String, varies: Bool) {
        let rows = signingRows(for: target)
        guard let first = rows.first else { return ("—", "—", "—", false) }
        let preferred = rows.first(where: { $0.config == "Release" }) ?? first
        let varies = rows.contains { $0.team != preferred.team || $0.style != preferred.style || $0.identity != preferred.identity }
        return (preferred.team, preferred.style, preferred.identity, varies)
    }

    // MARK: Build Settings browser

    private var effectiveSettingsTarget: InspectorTargetInfo? {
        scanner.xcodeTargets.first(where: { $0.id == selectedSettingsTargetID }) ?? scanner.xcodeTargets.first
    }

    private var effectiveConfigNames: [String] {
        effectiveSettingsTarget?.configurationNames ?? []
    }

    private var effectiveConfigName: String {
        let names = effectiveConfigNames
        if names.contains(selectedSettingsConfig) { return selectedSettingsConfig }
        return names.first ?? ""
    }

    private var groupedSettings: [InspectorSettingsGroup] {
        guard let target = effectiveSettingsTarget else { return [] }
        let settings = target.buildSettings[effectiveConfigName] ?? [:]
        let query = settingsSearch.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered: [String: String]
        if query.isEmpty {
            filtered = settings
        } else {
            filtered = settings.filter {
                $0.key.lowercased().contains(query) || $0.value.lowercased().contains(query)
            }
        }
        let grouped = Dictionary(grouping: filtered.keys, by: settingsGroupName)
        return grouped.keys.sorted().map { name in
            let pairs = (grouped[name] ?? []).sorted().map { key in
                (key: key, value: filtered[key] ?? "")
            }
            return InspectorSettingsGroup(name: name, pairs: pairs)
        }
    }

    private func settingsGroupName(for key: String) -> String {
        let upper = key.uppercased()
        if upper.hasPrefix("CODE_SIGN") || upper.contains("PROVISIONING") || upper == "DEVELOPMENT_TEAM" { return "Signing" }
        if upper.hasPrefix("SWIFT_") { return "Swift Compiler" }
        if upper.hasPrefix("GCC_") || upper.hasPrefix("CLANG_") || upper.hasPrefix("LLVM_") { return "Apple Clang" }
        if upper.hasPrefix("INFOPLIST_") { return "Info.plist" }
        if upper.hasPrefix("PRODUCT_") || upper.hasPrefix("EXECUTABLE_") || upper == "WRAPPER_EXTENSION" { return "Packaging" }
        if upper.hasPrefix("MARKETING_") { return "Versioning" }
        if upper.hasPrefix("ASSETCATALOG_") { return "Asset Catalog" }
        if upper.contains("SEARCH_PATHS") { return "Search Paths" }
        if upper.hasPrefix("LD_") || upper.contains("LINKER") { return "Linking" }
        if upper.hasSuffix("DEPLOYMENT_TARGET") || upper.hasPrefix("SUPPORTED_PLATFORMS") || upper.hasPrefix("TARGETED_DEVICE") { return "Deployment" }
        return "General"
    }

    @ViewBuilder
    private func buildSettingsCard() -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Build Settings", systemImage: "gearshape")
                    .font(.headline)

                Divider()

                if scanner.xcodeTargets.isEmpty {
                    Text("No targets available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Picker("Target", selection: $selectedSettingsTargetID) {
                            ForEach(scanner.xcodeTargets) { target in
                                Text(target.name).tag(target.id)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("Configuration", selection: $selectedSettingsConfig) {
                            ForEach(effectiveConfigNames, id: \.self) { config in
                                Text(config).tag(config)
                            }
                        }
                        .pickerStyle(.menu)

                        Spacer()

                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Search settings...", text: $settingsSearch)
                                .textFieldStyle(.plain)
                            if !settingsSearch.isEmpty {
                                Button { settingsSearch = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        .frame(width: 200)
                    }

                    let totalCount = groupedSettings.reduce(0) { $0 + $1.pairs.count }
                    Text("\(totalCount) settings grouped by area")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if groupedSettings.isEmpty {
                        Text(settingsSearch.isEmpty ? "No build settings recorded for this configuration." : "No settings match '\(settingsSearch)'.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(groupedSettings) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.name)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                ForEach(group.pairs.indices, id: \.self) { pairIndex in
                                    let pair = group.pairs[pairIndex]
                                    HStack(alignment: .top, spacing: 12) {
                                        Text(pair.key)
                                            .font(.system(.caption, design: .monospaced))
                                            .frame(minWidth: 230, alignment: .leading)
                                        Text(pair.value.isEmpty ? "—" : pair.value)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                        Spacer()
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    @ViewBuilder
    private func dependenciesCard() -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Dependencies & Packages", systemImage: "puzzlepiece")
                    .font(.headline)

                Divider()

                if scanner.packageDependencies.isEmpty {
                    Text("No Swift package dependencies referenced by the .xcodeproj.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(scanner.packageDependencies) { package in
                        HStack(spacing: 10) {
                            Image(systemName: package.isLocal ? "folder" : "cloud")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(package.name)
                                    .font(.subheadline.weight(.medium))
                                Text(package.url)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Text(package.isLocal ? "Local" : "Remote")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(NSColor.controlBackgroundColor), in: Capsule())
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding()
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    @ViewBuilder
    private func sourceFilesCard() -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Source File Counts", systemImage: "doc.on.doc")
                    .font(.headline)

                Divider()

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 16) {
                    statTile(title: "Swift", val: "\(scanner.totalSwiftFiles)", icon: "swift")
                    statTile(title: "JSON", val: "\(scanner.jsonCount)", icon: "curlybraces")
                    statTile(title: "YAML", val: "\(scanner.yamlCount)", icon: "list.bullet")
                    statTile(title: "Markdown", val: "\(scanner.markdownCount)", icon: "text.quote")
                    statTile(title: "Property Lists", val: "\(scanner.plistCount)", icon: "table")
                    statTile(title: "Localization Files", val: "\(scanner.localizationCount)", icon: "globe")
                    statTile(title: "Images", val: "\(scanner.imageCount)", icon: "photo")
                    statTile(title: "SQL", val: "\(scanner.sqlCount)", icon: "cylinder")
                }
            }
            .padding()
        }
        .groupBoxStyle(ModernGroupBoxStyle())
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

                    Divider()

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 16) {
                        usageMetricTile(title: "SwiftUI View Declarations", count: scanner.swiftUIUsageCount, icon: "square.stack.3d.down.right.fill")
                        usageMetricTile(title: "UIKit Controller Usage", count: scanner.uikitUsageCount, icon: "apps.iphone")
                        usageMetricTile(title: "AppKit Desktop Controls", count: scanner.appkitUsageCount, icon: "laptopcomputer")
                        usageMetricTile(title: "Observation (@Observable)", count: scanner.observationUsageCount, icon: "brain.head.profile")
                        usageMetricTile(title: "Asynchronous Operations (async/await)", count: scanner.asyncUsageCount, icon: "clock.fill")
                        usageMetricTile(title: "Shared State Actors (actor)", count: scanner.actorUsageCount, icon: "shield.fill")
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

                        Divider()

                        ForEach(scanner.longestSwiftFiles) { file in
                            HStack {
                                Image(systemName: "swift")
                                    .foregroundColor(.secondary)
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

                    Divider()

                    ForEach(scanner.largestFolders) { folder in
                        HStack {
                            Image(systemName: "folder")
                                .foregroundColor(.secondary)
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

    private func usageMetricTile(title: String, count: Int, icon: String) -> some View {
        HStack {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                                        .foregroundColor(.secondary)
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
                                        .foregroundColor(.secondary)
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

// MARK: - Adaptive flow layout for configuration chips

private struct ProjectInspectorFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * spacing
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var current = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !current.indices.isEmpty && current.width + spacing + size.width > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.indices.append(index)
            current.width += (current.indices.count > 1 ? spacing : 0) + size.width
            current.height = max(current.height, size.height)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
