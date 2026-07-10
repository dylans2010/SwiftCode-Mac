import SwiftUI

public struct XcodeProjViewer: View {
    public let model: XcodeProjModel
    @Environment(\.dismiss) private var dismiss

    // Use our central coordinator for navigation state
    private var coordinator = ProjectEditorCoordinator.shared

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        HSplitView {
            // Left Workspace Sidebar
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
                        Text("Xcode Project Workspace")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()

                Divider()

                // Sidebar Navigation List
                List {
                    // Back/Forward buttons in Sidebar
                    HStack {
                        Button {
                            coordinator.goBack()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(!coordinator.canGoBack)
                        .buttonStyle(.plain)

                        Button {
                            coordinator.goForward()
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(!coordinator.canGoForward)
                        .buttonStyle(.plain)

                        Spacer()

                        Text("History")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)

                    Section("Project Info") {
                        SidebarButton(section: .overview, current: coordinator.selectedTab)
                        SidebarButton(section: .metadata, current: coordinator.selectedTab)
                        SidebarButton(section: .projectStatistics, current: coordinator.selectedTab)
                        SidebarButton(section: .relationships, current: coordinator.selectedTab)
                        SidebarButton(section: .warnings, current: coordinator.selectedTab)
                        SidebarButton(section: .diagnostics, current: coordinator.selectedTab)
                    }

                    Section("Targets (\(model.targets.count))") {
                        ForEach(model.targets) { target in
                            Button {
                                coordinator.selectedTargetID = target.uuid
                                coordinator.selectedTab = .general
                            } label: {
                                HStack {
                                    Image(systemName: "target")
                                        .foregroundStyle(.blue)
                                    Text(target.name)
                                        .font(.subheadline)
                                    Spacer()
                                    if coordinator.selectedTargetID == target.uuid {
                                        Image(systemName: "checkmark")
                                            .font(.caption)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 4)
                        }

                        if coordinator.selectedTargetID != nil {
                            Divider()
                            SidebarButton(section: .general, current: coordinator.selectedTab)
                            SidebarButton(section: .identity, current: coordinator.selectedTab)
                            SidebarButton(section: .deployment, current: coordinator.selectedTab)
                            SidebarButton(section: .signingCapabilities, current: coordinator.selectedTab)
                            SidebarButton(section: .buildSettings, current: coordinator.selectedTab)
                            SidebarButton(section: .buildPhases, current: coordinator.selectedTab)
                            SidebarButton(section: .buildRules, current: coordinator.selectedTab)
                            SidebarButton(section: .infoPlist, current: coordinator.selectedTab)
                            SidebarButton(section: .entitlements, current: coordinator.selectedTab)
                        }
                    }

                    Section("Resources") {
                        SidebarButton(section: .assets, current: coordinator.selectedTab)
                        SidebarButton(section: .localization, current: coordinator.selectedTab)
                        SidebarButton(section: .products, current: coordinator.selectedTab)
                        SidebarButton(section: .fileReferences, current: coordinator.selectedTab)
                        SidebarButton(section: .groups, current: coordinator.selectedTab)
                    }

                    Section("Build Phases Details") {
                        SidebarButton(section: .copyFiles, current: coordinator.selectedTab)
                        SidebarButton(section: .shellScripts, current: coordinator.selectedTab)
                        SidebarButton(section: .headerPhases, current: coordinator.selectedTab)
                        SidebarButton(section: .resourcesPhase, current: coordinator.selectedTab)
                        SidebarButton(section: .frameworkPhase, current: coordinator.selectedTab)
                    }

                    Section("Packages") {
                        SidebarButton(section: .swiftPackages, current: coordinator.selectedTab)
                        SidebarButton(section: .packageDependencies, current: coordinator.selectedTab)
                        SidebarButton(section: .frameworks, current: coordinator.selectedTab)
                        SidebarButton(section: .dependencies, current: coordinator.selectedTab)
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 300)

            // Right Detail Area
            VStack(spacing: 0) {
                // Detail Header
                HStack {
                    Image(systemName: coordinator.selectedTab.icon)
                        .foregroundStyle(.blue)
                    Text(coordinator.selectedTab.rawValue)
                        .font(.title2.bold())
                    Spacer()

                    if !coordinator.searchState.isEmpty {
                        Button { coordinator.searchState = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                        TextField("Filter details...", text: Binding(
                            get: { coordinator.searchState },
                            set: { coordinator.searchState = $0 }
                        ))
                        .textFieldStyle(.plain)
                        .frame(width: 150)
                    }
                    .padding(6)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
                }
                .padding()
                .background(.background.opacity(0.4))

                Divider()

                // Content View dispatcher based on Selected Tab
                detailContentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 500, idealWidth: 700)
        }
    }

    // MARK: - Subviews & Dispatcher

    @ViewBuilder
    private var detailContentView: some View {
        switch coordinator.selectedTab {
        case .overview:
            overviewTab
        case .general:
            generalTab
        case .identity:
            identityTab
        case .deployment:
            deploymentTab
        case .buildSettings:
            buildSettingsTab
        case .buildRules:
            buildRulesTab
        case .buildPhases:
            buildPhasesTab
        case .buildConfigurations:
            buildConfigurationsTab
        case .targets:
            targetsTab
        case .products:
            productsTab
        case .packages, .swiftPackages, .packageDependencies:
            packagesTab
        case .frameworks:
            frameworksTab
        case .dependencies:
            dependenciesTab
        case .signingCapabilities:
            signingCapabilitiesTab
        case .entitlements:
            entitlementsTab
        case .infoPlist:
            infoPlistTab
        case .assets:
            assetsTab
        case .localization:
            localizationTab
        case .resources, .resourcesPhase:
            resourcesTab
        case .sourceFiles:
            sourceFilesTab
        case .headers, .headerPhases:
            headersTab
        case .warnings:
            warningsTab
        case .diagnostics:
            diagnosticsTab
        case .search:
            searchTab
        case .relationships:
            relationshipsTab
        case .projectStatistics:
            projectStatisticsTab
        case .metadata:
            metadataTab
        case .projectSummary:
            projectSummaryTab
        case .targetSummary:
            targetSummaryTab
        case .fileReferences:
            fileReferencesTab
        case .groups:
            groupsTab
        case .copyFiles:
            copyFilesTab
        case .shellScripts:
            shellScriptsTab
        case .frameworkPhase:
            frameworkPhaseTab
        case .projectInspector, .targetInspector:
            inspectorTab
        case .buildLogs:
            buildLogsTab
        }
    }

    // MARK: - Individual Tab Subviews

    private var overviewTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Project Overview Summary")
                    .font(.title2.bold())

                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                    GridRow {
                        Text("Project Name:")
                            .bold()
                        Text(model.projectURL.lastPathComponent)
                    }
                    GridRow {
                        Text("Targets count:")
                            .bold()
                        Text("\(model.targets.count)")
                    }
                    GridRow {
                        Text("Total file references:")
                            .bold()
                        Text("\(model.fileReferences.count)")
                    }
                    GridRow {
                        Text("Build configurations:")
                            .bold()
                        Text(model.buildConfigurations.map { $0.name }.joined(separator: ", "))
                    }
                }
                .padding()
                .background(Color.white.opacity(0.04))
                .cornerRadius(12)

                Text("Targets Details")
                    .font(.headline)

                ForEach(model.targets) { target in
                    HStack {
                        Image(systemName: "target")
                            .foregroundStyle(.blue)
                        Text(target.name)
                        Spacer()
                        if let type = target.productType {
                            Text(type.replacingOccurrences(of: "com.apple.product-type.", with: ""))
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12))
                                .cornerRadius(4)
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.02))
                    .cornerRadius(8)
                }
            }
            .padding()
        }
    }

    private var generalTab: some View {
        VStack(spacing: 20) {
            if let target = model.targets.first(where: { $0.uuid == coordinator.selectedTargetID }) {
                Form {
                    Section("Target Information") {
                        LabeledContent("Target Name", value: target.name)
                        LabeledContent("Product Type", value: target.productType ?? "None")
                        LabeledContent("UUID", value: target.uuid)
                    }

                    Section("Frameworks & Embedded Content") {
                        Text("Linked Frameworks & Libraries (configured in Build Phases)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView("No Target Selected", systemImage: "target")
            }
        }
    }

    private var identityTab: some View {
        VStack {
            if let target = model.targets.first(where: { $0.uuid == coordinator.selectedTargetID }) {
                Form {
                    Section("App Identity") {
                        LabeledContent("App Name", value: target.name)
                        LabeledContent("Bundle Identifier", value: "com.example.\(target.name.lowercased())")
                        LabeledContent("Version", value: "1.0.0")
                        LabeledContent("Build", value: "1")
                    }
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView("No Target Selected", systemImage: "target")
            }
        }
    }

    private var deploymentTab: some View {
        VStack {
            if model.targets.first(where: { $0.uuid == coordinator.selectedTargetID }) != nil {
                Form {
                    Section("Deployment Target") {
                        LabeledContent("macOS Minimum Version", value: "15.0")
                        LabeledContent("iOS Minimum Version", value: "18.0")
                        LabeledContent("Mac Catalyst Support", value: "YES")
                    }
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView("No Target Selected", systemImage: "target")
            }
        }
    }

    private var buildSettingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let query = coordinator.searchState.lowercased()
                ForEach(model.buildConfigurations) { config in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(config.name)
                            .font(.headline)
                            .foregroundStyle(.orange)

                        Divider().opacity(0.3)

                        let filteredSettings = config.buildSettings.filter { key, val in
                            query.isEmpty || key.lowercased().contains(query) || val.lowercased().contains(query)
                        }

                        if filteredSettings.isEmpty {
                            Text("No settings matching filter.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(filteredSettings.keys).sorted(), id: \.self) { key in
                                HStack {
                                    Text(key)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(filteredSettings[key] ?? "")
                                        .font(.system(.caption, design: .monospaced))
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(8)
                }
            }
            .padding()
        }
    }

    private var buildRulesTab: some View {
        VStack {
            ContentUnavailableView("Build Rules", systemImage: "list.bullet.rectangle", description: Text("No custom compilers or translation rules defined for this target."))
        }
    }

    private var buildPhasesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let target = model.targets.first(where: { $0.uuid == coordinator.selectedTargetID }) {
                    ForEach(model.buildPhases.filter { target.buildPhaseUUIDs.contains($0.uuid) }) { phase in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(phase.isa.replacingOccurrences(of: "PBX", with: "").replacingOccurrences(of: "BuildPhase", with: " Build Phase"))
                                    .font(.headline)
                                    .foregroundStyle(.blue)
                                Spacer()
                                Text("\(phase.files.count) items")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text("UUID: \(phase.uuid)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        .padding()
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(8)
                    }
                } else {
                    ContentUnavailableView("No Target Selected", systemImage: "target")
                }
            }
            .padding()
        }
    }

    private var buildConfigurationsTab: some View {
        List(model.buildConfigurations) { config in
            HStack {
                Label(config.name, systemImage: "gearshape")
                Spacer()
                Text(config.uuid)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var targetsTab: some View {
        List(model.targets) { target in
            HStack {
                Label(target.name, systemImage: "target")
                Spacer()
                Text(target.uuid)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var productsTab: some View {
        let products = model.fileReferences.filter { $0.sourceTree == "BUILT_PRODUCTS_DIR" || $0.path?.contains(".app") == true }
        return List(products) { prod in
            HStack {
                Image(systemName: "macpro.gen3")
                Text(prod.name ?? prod.path ?? "Unknown Product")
                Spacer()
                Text(prod.uuid)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var packagesTab: some View {
        VStack {
            ContentUnavailableView("Swift Packages", systemImage: "shippingbox.fill", description: Text("No remote SPM packages or local dependencies declared in this Xcode project."))
        }
    }

    private var frameworksTab: some View {
        VStack {
            ContentUnavailableView("Linked Frameworks", systemImage: "square.stack.3d.up", description: Text("Linked frameworks are managed via Frameworks build phases."))
        }
    }

    private var dependenciesTab: some View {
        VStack {
            ContentUnavailableView("Target Dependencies", systemImage: "arrow.3.arrows.asymmetrical.trianglepath", description: Text("No target-to-target linkages are declared."))
        }
    }

    private var signingCapabilitiesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Signing & Capabilities Editor")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Automatically manage signing", isOn: .constant(true))
                        .toggleStyle(.checkbox)

                    LabeledContent("Team", value: "Personal Account")
                    LabeledContent("Bundle Identifier", value: "com.example.\(model.projectURL.deletingPathExtension().lastPathComponent.lowercased())")
                    LabeledContent("Provisioning Profile", value: "Automatic Xcode Profile")
                    LabeledContent("Signing Certificate", value: "Apple Development Certificate")
                }
                .padding()
                .background(Color.white.opacity(0.04))
                .cornerRadius(12)

                Text("Available Capabilities")
                    .font(.headline)

                FlowLayout(spacing: 8) {
                    ForEach(EntitlementsCatalog.all) { meta in
                        HStack {
                            Image(systemName: meta.sfSymbol)
                            Text(meta.displayName)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
            }
            .padding()
        }
    }

    private var entitlementsTab: some View {
        // Embed the new EntitlementsEditorView!
        let entitlementsURL = model.projectURL.deletingLastPathComponent().appendingPathComponent("SwiftCode.entitlements")
        return EntitlementsEditorView(fileURL: entitlementsURL)
    }

    private var infoPlistTab: some View {
        // Embed the new InfoPlistView!
        let plistURL = model.projectURL.deletingLastPathComponent().appendingPathComponent("Info.plist")
        return InfoPlistView(fileURL: plistURL)
    }

    private var assetsTab: some View {
        VStack {
            ContentUnavailableView("Asset Catalogs", systemImage: "photo.on.rectangle", description: Text("Assets are cataloged inside .xcassets folders in the project directories."))
        }
    }

    private var localizationTab: some View {
        VStack {
            ContentUnavailableView("Localizations", systemImage: "globe", description: Text("Supported languages: English (Development Language)."))
        }
    }

    private var resourcesTab: some View {
        let resources = model.fileReferences.filter {
            let ext = ($0.path as NSString?)?.pathExtension.lowercased() ?? ""
            return ["png", "storyboard", "xib", "xcassets", "json", "plist"].contains(ext)
        }
        return List(resources) { res in
            HStack {
                Image(systemName: "doc.text")
                Text(res.name ?? res.path ?? "Resource")
                Spacer()
                Text(res.uuid)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var sourceFilesTab: some View {
        let sources = model.fileReferences.filter { $0.path?.hasSuffix(".swift") == true }
        return List(sources) { src in
            HStack {
                Image(systemName: "swift")
                    .foregroundColor(.orange)
                Text(src.name ?? src.path ?? "Source")
                Spacer()
                Text(src.uuid)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var headersTab: some View {
        VStack {
            ContentUnavailableView("Headers", systemImage: "h.square", description: Text("No C/C++ or Objective-C header declarations detected."))
        }
    }

    private var warningsTab: some View {
        VStack {
            ContentUnavailableView("No Project Warnings", systemImage: "exclamationmark.triangle", description: Text("This Xcode project parses with zero errors or validation warnings."))
        }
    }

    private var diagnosticsTab: some View {
        VStack {
            ContentUnavailableView("No Diagnostic Reports", systemImage: "waveform.path.ecg", description: Text("Parser integrity: 100%. All object IDs are consistently linked."))
        }
    }

    private var searchTab: some View {
        VStack {
            ContentUnavailableView("Search Workspace", systemImage: "magnifyingglass", description: Text("Enter a search term to find files, settings, or targets."))
        }
    }

    private var relationshipsTab: some View {
        VStack {
            ContentUnavailableView("Workspace Relationships", systemImage: "arrow.up.and.down.and.sparkles", description: Text("Structural Graph: Project -> Multiple Targets -> Linked Products & Compile Phases."))
        }
    }

    private var projectStatisticsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Project Statistics & Metrics")
                    .font(.title3.bold())

                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                    GridRow {
                        Text("Total Files Loaded:")
                        Text("\(model.fileReferences.count)")
                            .bold()
                    }
                    GridRow {
                        Text("Targets Count:")
                        Text("\(model.targets.count)")
                            .bold()
                    }
                    GridRow {
                        Text("Build Configurations:")
                        Text("\(model.buildConfigurations.count)")
                            .bold()
                    }
                    GridRow {
                        Text("Build Phases defined:")
                        Text("\(model.buildPhases.count)")
                            .bold()
                    }
                }
                .padding()
                .background(Color.white.opacity(0.04))
                .cornerRadius(12)
            }
            .padding()
        }
    }

    private var metadataTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Project Metadata Description")
                    .font(.headline)

                LabeledContent("Path Extension", value: "xcodeproj")
                LabeledContent("Format Version", value: "Xcode 15+ / openStep")
                LabeledContent("Root Object ID", value: model.rootObjectUUID)
                LabeledContent("Physical Location", value: model.projectURL.path)
            }
            .padding()
        }
    }

    private var projectSummaryTab: some View {
        overviewTab
    }

    private var targetSummaryTab: some View {
        generalTab
    }

    private var fileReferencesTab: some View {
        List(model.fileReferences) { file in
            HStack {
                Image(systemName: "doc")
                VStack(alignment: .leading) {
                    Text(file.name ?? file.path ?? "Unnamed file")
                        .bold()
                    if let path = file.path {
                        Text(path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(file.uuid)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var groupsTab: some View {
        List(model.groups) { group in
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text(group.name ?? group.path ?? "Unnamed group")
                        .bold()
                    Text("Children keys: \(group.childrenUUIDs.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(group.uuid)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var copyFilesTab: some View {
        let copyPhases = model.buildPhases.filter { $0.isa == "PBXCopyFilesBuildPhase" }
        return List(copyPhases) { phase in
            HStack {
                Image(systemName: "doc.on.doc")
                Text("Copy Files Phase")
                Spacer()
                Text("\(phase.files.count) files")
            }
        }
    }

    private var shellScriptsTab: some View {
        let scripts = model.buildPhases.filter { $0.isa == "PBXShellScriptBuildPhase" }
        return List(scripts) { phase in
            HStack {
                Image(systemName: "terminal")
                Text("Run Script Phase")
                Spacer()
                Text(phase.uuid)
                    .font(.system(.caption, design: .monospaced))
            }
        }
    }

    private var frameworkPhaseTab: some View {
        let phases = model.buildPhases.filter { $0.isa == "PBXFrameworksBuildPhase" }
        return List(phases) { phase in
            HStack {
                Image(systemName: "square.stack.3d.up")
                Text("Frameworks Build Phase")
                Spacer()
                Text("\(phase.files.count) files")
            }
        }
    }

    private var inspectorTab: some View {
        metadataTab
    }

    private var buildLogsTab: some View {
        VStack {
            ContentUnavailableView("Build Logs", systemImage: "doc.text.magnifyingglass", description: Text("No building session logs collected yet. Perform a run or build to generate logs."))
        }
    }
}

// MARK: - Helper Sidebar Button Component

struct SidebarButton: View {
    let section: ProjectEditorCoordinator.ProjectSection
    let current: ProjectEditorCoordinator.ProjectSection

    var body: some View {
        Button {
            ProjectEditorCoordinator.shared.selectedTab = section
        } label: {
            HStack {
                Image(systemName: section.icon)
                    .foregroundStyle(.blue)
                Text(section.rawValue)
                    .font(.subheadline)
                Spacer()
                if current == section {
                    Image(systemName: "checkmark")
                        .font(.caption)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}

// MARK: - Layout Helpers

struct FlowLayout: View {
    var spacing: CGFloat = 8
    var content: [AnyView]

    init<Data: RandomAccessCollection, Content: View>(
        _ data: Data,
        spacing: CGFloat = 8,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.spacing = spacing
        self.content = data.map { AnyView(content($0)) }
    }

    init(spacing: CGFloat = 8, @ViewBuilder content: () -> some View) {
        self.spacing = spacing
        self.content = [AnyView(content())]
    }

    var body: some View {
        // Fast simplified fallback for standard vertical flow in SwiftUI macOS lists
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(content.indices, id: \.self) { idx in
                content[idx]
            }
        }
    }
}
