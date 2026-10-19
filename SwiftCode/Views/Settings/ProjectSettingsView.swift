import SwiftUI

// MARK: - Discovery models (parsed from the real project on disk)

/// A Swift package dependency with its pinned version resolved from
/// Package.resolved when one exists on disk.
private struct DiscoveredPackage: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var url: String
    var version: String?
    var isLocal: Bool
    var source: String
}

/// A PBXShellScriptBuildPhase parsed from project.pbxproj.
private struct DiscoveredRunScript: Identifiable, Hashable {
    let id: String
    var name: String
    var targetName: String?
    var shell: String
    var lineCount: Int
    var hasInlineScript: Bool
}

@MainActor
struct ProjectSettingsView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var scanner = InspectorProjectScanner.shared

    // MARK: - Identity
    @State private var projectName = ""
    @State private var organizationName = ""
    @State private var bundleIdentifier = ""
    @State private var projectDescription = ""
    @State private var githubRepo = ""

    // MARK: - Versioning
    @State private var marketingVersion = "1.0.0"
    @State private var buildNumber = "1"
    @State private var autoIncrementBuild = false

    // MARK: - Team / platform / toolchain
    @State private var developmentTeam = ""
    @State private var deploymentPlatform = "macOS"
    @State private var deploymentVersion = "15.0"
    @State private var swiftLanguageVersion = "6.0"

    // MARK: - Persisted build-metadata state
    @State private var xcodeSettings: [String: String] = [:]
    @State private var targetBundleIDOverrides: [String: String] = [:]
    @State private var infoPlistPath = ""
    @State private var entitlementsPath = ""
    @State private var codeSignStyle = "Automatic"
    @State private var codeSignIdentity = ""
    @State private var provisioningProfileSpecifier = ""

    // MARK: - Build configurations (persisted overrides)
    @State private var configurations: [String] = []
    @State private var configsCustomized = false
    @State private var newConfigName = ""
    @State private var renamingConfig: String?
    @State private var renameText = ""

    // MARK: - Discovered project info (real, from disk)
    @State private var resolvedPackages: [DiscoveredPackage] = []
    @State private var runScripts: [DiscoveredRunScript] = []
    @State private var testPlans: [String] = []
    @State private var shellScripts: [String] = []
    @State private var infoPlistExists: Bool?
    @State private var infoPlistResolvedPath: String?
    @State private var entitlementsExists: Bool?
    @State private var entitlementsResolvedPath: String?
    @State private var didScan = false

    @State private var errorMessage: String?
    @State private var showError = false

    private let macOSDeploymentTargets = ["13.0", "14.0", "15.0", "26.0"]
    private let iOSDeploymentTargets = ["16.0", "17.0", "18.0"]
    private let swiftVersions = ["5.0", "5.9", "5.10", "6.0", "6.1", "6.2"]
    private let optimizationLevels = ["-Onone", "-O", "-Osize"]
    private let concurrencyModes = ["minimal", "targeted", "complete"]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                versionSection
                teamSection
                deploymentSection
                swiftLanguageSection
                configurationsSection
                targetsSection
                buildSettingsSection
                schemesSection
                packagesSection
                propertyListsSection
                buildPhasesSection

                if let project = sessionStore.activeProject {
                    statisticsSection(project)
                    storageSection(project)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Project Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveSettings() }
                }
            }
            .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
                Button("OK") {}
            } message: { msg in Text(msg) }
            .onAppear { loadSettings() }
            .task(id: sessionStore.activeProject?.id) {
                await refreshProjectDiscovery()
            }
        }
    }

    // MARK: - Sections

    private var identitySection: some View {
        Section {
            LabeledContent {
                TextField("My App", text: $projectName)
                    .multilineTextAlignment(.trailing)
                    .disabled(nameFieldLocked)
            } label: {
                Label("Name", systemImage: "tag")
            }
            if nameFieldLocked {
                Label("Renaming is unavailable: this project was opened from an absolute path, so its name is tied to that path.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LabeledContent {
                TextField("Organization", text: $organizationName)
                    .multilineTextAlignment(.trailing)
            } label: {
                Label("Organization", systemImage: "building.2")
            }

            LabeledContent {
                TextField("com.example.MyApp", text: $bundleIdentifier)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } label: {
                Label("Bundle Identifier", systemImage: "app.badge")
            }
            if !bundleIdentifier.isEmpty, !isValidBundleID(bundleIdentifier) {
                Label("Bundle identifier should be reverse-DNS, e.g. com.example.MyApp.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let detected = detectedSetting("PRODUCT_BUNDLE_IDENTIFIER"), xcodeSettings["PRODUCT_BUNDLE_IDENTIFIER"] == nil {
                Label("Detected in project: \(detected)", systemImage: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            TextField("Description", text: $projectDescription, axis: .vertical)
                .lineLimit(3)
            Label("Description", systemImage: "text.alignleft")
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent {
                TextField("Owner/Repo", text: $githubRepo)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } label: {
                Label("GitHub Repository", systemImage: "link")
            }
        } header: {
            Label("Project Identity", systemImage: "app.badge")
        }
    }

    private var versionSection: some View {
        Section {
            LabeledContent {
                TextField("1.0.0", text: $marketingVersion)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            } label: {
                Label("Version", systemImage: "tag")
            }
            if !isValidVersion(marketingVersion) {
                Label("Version must be numeric x.y.z, e.g. 1.0.0.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LabeledContent {
                TextField("1", text: $buildNumber)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            } label: {
                Label("Build", systemImage: "number")
            }
            if !isValidBuildNumber(buildNumber) {
                Label("Build must be a non-empty numeric string, e.g. 42.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: $autoIncrementBuild) {
                Label("Auto-increment build number", systemImage: "arrow.triangle.2.circlepath")
            }
            .toggleStyle(.switch)
            Label("When on, saving settings increases the build number by 1.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Label("Version & Build", systemImage: "number.circle")
        }
    }

    private var teamSection: some View {
        Section {
            Picker(selection: $developmentTeam) {
                Text("Not Set").tag("")
                ForEach(teamOptions, id: \.self) { team in
                    Text(team).tag(team)
                }
            } label: {
                Label("Development Team", systemImage: "person.2")
            }
            .pickerStyle(.menu)

            Button {
                detectDevelopmentTeam()
            } label: {
                Label("Detect from Project", systemImage: "magnifyingglass")
            }
            .buttonStyle(.plain)

            if detectedSettingValues("DEVELOPMENT_TEAM").isEmpty {
                Label("No DEVELOPMENT_TEAM value is set in this project's build settings.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Teams found in this project's build settings are offered above.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label("Development Team", systemImage: "key")
        }
    }

    private var deploymentSection: some View {
        Section {
            Picker(selection: $deploymentPlatform) {
                Text("macOS").tag("macOS")
                Text("iOS").tag("iOS")
            } label: {
                Label("Platform", systemImage: "desktopcomputer")
            }
            .pickerStyle(.segmented)
            .onChange(of: deploymentPlatform) { _, new in
                let options = new == "macOS" ? macOSDeploymentTargets : iOSDeploymentTargets
                if !options.contains(deploymentVersion) {
                    deploymentVersion = options.last ?? deploymentVersion
                }
            }

            Picker(selection: $deploymentVersion) {
                ForEach(deploymentVersionOptions, id: \.self) { v in
                    Text("\(deploymentPlatform) \(v)").tag(v)
                }
            } label: {
                Label("Deployment Target", systemImage: "iphone")
            }
            .pickerStyle(.menu)

            if let detected = detectedDeploymentTarget {
                Label("Detected in project: \(detected)", systemImage: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        } header: {
            Label("Deployment", systemImage: "tray.and.arrow.down")
        }
    }

    private var swiftLanguageSection: some View {
        Section {
            Picker(selection: $swiftLanguageVersion) {
                ForEach(swiftLanguageVersionOptions, id: \.self) { v in
                    Text("Swift \(v)").tag(v)
                }
            } label: {
                Label("Swift Language Version", systemImage: "swift")
            }
            .pickerStyle(.menu)

            if let detected = detectedSetting("SWIFT_VERSION") {
                Label("Detected in project: Swift \(detected)", systemImage: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Label("Stored per project. Applying it to the .xcodeproj requires a build-settings write, which is not performed here.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Label("Swift Language", systemImage: "swift")
        }
    }

    private var configurationsSection: some View {
        Section {
            if effectiveConfigurations.isEmpty {
                Label("No build configurations found. Add one below, or rescan the project.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(effectiveConfigurations, id: \.self) { config in
                HStack {
                    if renamingConfig == config {
                        TextField("Configuration", text: $renameText)
                            .autocorrectionDisabled()
                        Button("Done") { commitRename() }
                            .buttonStyle(.plain)
                    } else {
                        Label(config, systemImage: "square.stack.3d.up")
                        Spacer()
                        Button {
                            duplicateConfiguration(config)
                        } label: {
                            Label("Duplicate", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .labelStyle(.iconOnly)
                        Button {
                            renamingConfig = config
                            renameText = config
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .buttonStyle(.plain)
                        .labelStyle(.iconOnly)
                        Button(role: .destructive) {
                            deleteConfiguration(config)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(.plain)
                        .labelStyle(.iconOnly)
                    }
                }
            }

            HStack {
                TextField("New configuration", text: $newConfigName)
                    .autocorrectionDisabled()
                Button {
                    addConfiguration()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .disabled(newConfigName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if configsCustomized {
                Button("Reset to project configurations") {
                    configsCustomized = false
                    configurations = []
                }
                .buttonStyle(.plain)
                Label("Customized list stored with this project. Reset restores the configurations read from the .xcodeproj.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !scanner.xcodeProjectFound {
                Label("No .xcodeproj was found, so this list starts empty.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label("Build Configurations", systemImage: "square.stack.3d.up")
        }
    }

    private var targetsSection: some View {
        Section {
            if !scanner.xcodeProjectFound {
                Label("No .xcodeproj found in this project directory, so no targets are available.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if scanner.xcodeTargets.isEmpty {
                Label("No targets were parsed from the .xcodeproj.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(scanner.xcodeTargets) { target in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent {
                            TextField("Inherit from project", text: targetBundleIDBinding(for: target.name))
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } label: {
                            Label("Bundle ID Override", systemImage: "app.badge")
                        }
                        if let detected = targetDetectedBundleID(target), targetBundleIDOverrides[target.name] == nil {
                            Label("Detected: \(detected)", systemImage: "magnifyingglass")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        if let override = targetBundleIDOverrides[target.name], !override.isEmpty, !isValidBundleID(override) {
                            Label("Override should be reverse-DNS, e.g. com.example.MyApp.", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Label("Configurations: \(target.configurationNames.joined(separator: ", "))", systemImage: "square.stack.3d.up")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let team = targetDetectedSetting(target, "DEVELOPMENT_TEAM") {
                            Label("Team: \(team)", systemImage: "person.2")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Label("Bundle ID overrides are stored per project. They are not written into the .xcodeproj.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } label: {
                    HStack {
                        Label(target.name, systemImage: "target")
                        Spacer()
                        Text(target.productType)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Label("Targets", systemImage: "target")
        }
    }

    private var buildSettingsSection: some View {
        Section {
            DisclosureGroup {
                settingsGroupContent(for: swiftCompilerSettings)
            } label: {
                Label("Swift Compiler", systemImage: "swift")
            }
            DisclosureGroup {
                settingsGroupContent(for: clangSettings)
            } label: {
                Label("Apple Clang", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            DisclosureGroup {
                settingsGroupContent(for: linkingSettings)
            } label: {
                Label("Linking", systemImage: "link")
            }
            DisclosureGroup {
                settingsGroupContent(for: packagingSettings)
            } label: {
                Label("Packaging", systemImage: "shippingbox")
            }
            DisclosureGroup {
                settingsGroupContent(for: deploymentSettings)
            } label: {
                Label("Deployment", systemImage: "tray.and.arrow.down")
            }
            DisclosureGroup {
                codeSigningGroup
            } label: {
                Label("Code Signing", systemImage: "signature")
            }
            Label("Values you change are stored with this project as overrides. Unchanged rows show the value detected in the project's build settings, if any.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Label("Build Settings", systemImage: "gearshape.2")
        }
    }

    private var codeSigningGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(selection: $codeSignStyle) {
                Text("Automatic").tag("Automatic")
                Text("Manual").tag("Manual")
            } label: {
                Label("Code Sign Style", systemImage: "signature")
            }
            .pickerStyle(.segmented)

            Picker(selection: $codeSignIdentity) {
                Text("Not Set").tag("")
                ForEach(codeSignIdentityOptions, id: \.self) { identity in
                    Text(identity).tag(identity)
                }
            } label: {
                Label("Code Sign Identity", systemImage: "key")
            }
            .pickerStyle(.menu)
            if let detected = detectedSetting("CODE_SIGN_IDENTITY") {
                Label("Detected in project: \(detected)", systemImage: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            LabeledContent {
                TextField("Specifier", text: $provisioningProfileSpecifier)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            } label: {
                Label("Provisioning Profile", systemImage: "doc.badge.gearshape")
            }
            if let detected = detectedSetting("PROVISIONING_PROFILE_SPECIFIER") {
                Label("Detected in project: \(detected)", systemImage: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            LabeledContent {
                Text(developmentTeam.isEmpty ? "Not Set" : developmentTeam)
                    .foregroundStyle(.secondary)
            } label: {
                Label("Development Team", systemImage: "person.2")
            }

            Button("Reset signing overrides") {
                xcodeSettings.removeValue(forKey: "CODE_SIGN_IDENTITY")
                xcodeSettings.removeValue(forKey: "PROVISIONING_PROFILE_SPECIFIER")
                codeSignStyle = "Automatic"
                codeSignIdentity = ""
                provisioningProfileSpecifier = ""
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Build setting row builders

    private var swiftCompilerSettings: [BuildSettingRow] {
        [
            .picker(key: "SWIFT_OPTIMIZATION_LEVEL", title: "Optimization Level", icon: "gauge", options: optimizationLevels, fallback: "-Onone"),
            .picker(key: "SWIFT_STRICT_CONCURRENCY", title: "Strict Concurrency", icon: "exclamationmark.lock", options: concurrencyModes, fallback: "minimal"),
            .toggle(key: "SWIFT_TREAT_WARNINGS_AS_ERRORS", title: "Treat Warnings as Errors", icon: "exclamationmark.triangle", fallback: false),
        ]
    }

    private var clangSettings: [BuildSettingRow] {
        [
            .toggle(key: "GCC_WARN_INHIBIT_ALL_WARNINGS", title: "Inhibit All Warnings", icon: "speaker.slash", fallback: false),
            .toggle(key: "GCC_TREAT_WARNINGS_AS_ERRORS", title: "Treat Warnings as Errors", icon: "exclamationmark.triangle", fallback: false),
        ]
    }

    private var linkingSettings: [BuildSettingRow] {
        [
            .toggle(key: "DEAD_CODE_STRIPPING", title: "Dead Code Stripping", icon: "scissors", fallback: true),
            .text(key: "OTHER_LDFLAGS", title: "Other Linker Flags", icon: "link", placeholder: "-ObjC", fallback: ""),
        ]
    }

    private var packagingSettings: [BuildSettingRow] {
        [
            .text(key: "PRODUCT_NAME", title: "Product Name", icon: "shippingbox", placeholder: "$(TARGET_NAME)", fallback: ""),
        ]
    }

    private var deploymentSettings: [BuildSettingRow] {
        [
            .toggle(key: "SKIP_INSTALL", title: "Skip Install", icon: "tray.and.arrow.down", fallback: false),
            .toggle(key: "COPY_PHASE_STRIP", title: "Strip Debug Symbols During Copy", icon: "scissors.badge.ellipsis", fallback: false),
        ]
    }

    @ViewBuilder
    private func settingsGroupContent(for rows: [BuildSettingRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows) { row in
                settingRow(row)
                if xcodeSettings[row.key] == nil, let detected = detectedSetting(row.key) {
                    Label("Detected: \(detected)", systemImage: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Button("Reset group") {
                for row in rows { xcodeSettings.removeValue(forKey: row.key) }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func settingRow(_ row: BuildSettingRow) -> some View {
        switch row.kind {
        case .toggle:
            Toggle(isOn: boolSettingBinding(row.key, fallback: row.boolFallback)) {
                Label(row.title, systemImage: row.icon)
            }
            .toggleStyle(.switch)
        case .picker(let options):
            let effective = effectiveString(row.key, fallback: row.stringFallback)
            let allOptions = options.contains(effective) ? options : options + [effective]
            Picker(selection: stringSettingBinding(row.key, fallback: row.stringFallback)) {
                ForEach(allOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            } label: {
                Label(row.title, systemImage: row.icon)
            }
            .pickerStyle(.menu)
        case .text(let placeholder):
            LabeledContent {
                TextField(placeholder, text: stringSettingBinding(row.key, fallback: row.stringFallback))
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            } label: {
                Label(row.title, systemImage: row.icon)
            }
        }
    }

    // MARK: - Schemes / packages / files

    private var schemesSection: some View {
        Section {
            if !scanner.xcodeProjectFound {
                Label("No .xcodeproj found, so no schemes were discovered.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if scanner.xcodeSchemes.isEmpty {
                Label("No schemes tracked", systemImage: "play.circle")
                    .foregroundStyle(.secondary)
                Label("No .xcscheme files were found in this project's xcshareddata or xcuserdata.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(scanner.xcodeSchemes) { scheme in
                HStack {
                    Label(scheme.name, systemImage: "play.circle")
                    Spacer()
                    Text(scheme.isShared ? "Shared" : "User")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("Schemes", systemImage: "play.circle")
        }
    }

    private var packagesSection: some View {
        Section {
            if resolvedPackages.isEmpty {
                Label("No Swift package dependencies found", systemImage: "shippingbox")
                    .foregroundStyle(.secondary)
                Label("Checked the .xcodeproj package references and Package.resolved on disk.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(resolvedPackages) { package in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Label(package.name, systemImage: package.isLocal ? "folder" : "shippingbox")
                        Spacer()
                        if let version = package.version {
                            Text(version)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Unresolved")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(package.url)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(package.source)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Label("Swift Packages", systemImage: "shippingbox")
        }
    }

    private var propertyListsSection: some View {
        Section {
            LabeledContent {
                TextField("Relative path", text: $infoPlistPath)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } label: {
                Label("Info.plist Path", systemImage: "doc")
            }
            pathExistenceRow(resolvedPath: infoPlistResolvedPath, exists: infoPlistExists)

            LabeledContent {
                TextField("Relative path", text: $entitlementsPath)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } label: {
                Label("Entitlements Path", systemImage: "lock.doc")
            }
            pathExistenceRow(resolvedPath: entitlementsResolvedPath, exists: entitlementsExists)

            Label("Leave a path empty to use the value detected from the project's build settings, or the conventional location.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Label("Property Lists & Entitlements", systemImage: "list.bullet.rectangle")
        }
    }

    @ViewBuilder
    private func pathExistenceRow(resolvedPath: String?, exists: Bool?) -> some View {
        if let resolvedPath {
            HStack {
                if exists == true {
                    Label("Exists", systemImage: "checkmark.circle")
                } else if exists == false {
                    Label("Not found on disk", systemImage: "exclamationmark.triangle")
                } else {
                    Label("Checking…", systemImage: "hourglass")
                }
                Spacer()
                Text(resolvedPath)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if exists == true {
                Button {
                    NSWorkspace.shared.selectFile(resolvedPath, inFileViewerRootedAtPath: nil)
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var buildPhasesSection: some View {
        Section {
            if runScripts.isEmpty {
                Label("No run script phases found", systemImage: "hammer")
                    .foregroundStyle(.secondary)
            }
            ForEach(runScripts) { script in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Label(script.name, systemImage: "terminal")
                        Spacer()
                        Text("\(script.lineCount) lines")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text(script.shell)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if let target = script.targetName {
                            Text("· \(target)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if !script.hasInlineScript {
                            Text("· external")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            if !testPlans.isEmpty {
                Label("Test Plans", systemImage: "checklist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(testPlans, id: \.self) { plan in
                    Label(URL(fileURLWithPath: plan).lastPathComponent, systemImage: "checklist")
                        .font(.caption)
                }
            }

            if !shellScripts.isEmpty {
                Label("Shell Scripts in Project", systemImage: "terminal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(shellScripts.prefix(10), id: \.self) { script in
                    Label(URL(fileURLWithPath: script).lastPathComponent, systemImage: "doc.plaintext")
                        .font(.caption)
                }
                if shellScripts.count > 10 {
                    Text("+\(shellScripts.count - 10) more")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            if runScripts.isEmpty && testPlans.isEmpty && shellScripts.isEmpty {
                Label("Parsed from project.pbxproj and scanned for .xctestplan / .sh files on disk.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label("Build Phases", systemImage: "hammer")
        }
    }

    // MARK: - Statistics & storage

    private func statisticsSection(_ project: Project) -> some View {
        Section {
            LabeledContent {
                Text("\(project.fileCount)")
            } label: {
                Label("Files", systemImage: "doc")
            }
            LabeledContent {
                Text(project.createdAt, style: .date)
            } label: {
                Label("Created", systemImage: "calendar")
            }
            LabeledContent {
                Text(project.lastOpened, style: .date)
            } label: {
                Label("Last Opened", systemImage: "clock")
            }
        } header: {
            Label("Statistics", systemImage: "chart.bar")
        }
    }

    private func storageSection(_ project: Project) -> some View {
        Section {
            HStack {
                Label("Location", systemImage: "internaldrive")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(project.directoryURL.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Button {
                openProjectInFiles(project)
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            .buttonStyle(.plain)
        } header: {
            Label("Storage", systemImage: "internaldrive")
        }
    }

    // MARK: - Computed helpers

    private var nameFieldLocked: Bool {
        guard let project = sessionStore.activeProject else { return true }
        return project.customDirectoryPath == nil && project.name.hasPrefix("/")
    }

    private var effectiveConfigurations: [String] {
        configsCustomized ? configurations : scanner.buildConfigurations
    }

    private var teamOptions: [String] {
        detectedSettingValues("DEVELOPMENT_TEAM")
    }

    private var codeSignIdentityOptions: [String] {
        Array(Set(detectedSettingValues("CODE_SIGN_IDENTITY") + ["Apple Development", "Apple Distribution"])).sorted()
    }

    private var deploymentVersionOptions: [String] {
        deploymentPlatform == "macOS" ? macOSDeploymentTargets : iOSDeploymentTargets
    }

    private var swiftLanguageVersionOptions: [String] {
        if let detected = detectedSetting("SWIFT_VERSION"), !swiftVersions.contains(detected) {
            return swiftVersions + [detected]
        }
        return swiftVersions
    }

    private var detectedDeploymentTarget: String? {
        if let value = detectedSetting("MACOSX_DEPLOYMENT_TARGET") { return "macOS \(value)" }
        if let value = detectedSetting("IPHONEOS_DEPLOYMENT_TARGET") { return "iOS \(value)" }
        return nil
    }

    // MARK: - Setting bindings (persisted overrides over detected values)

    private func detectedSetting(_ key: String) -> String? {
        for target in scanner.xcodeTargets {
            if let value = targetDetectedSetting(target, key) { return value }
        }
        return nil
    }

    private func detectedSettingValues(_ key: String) -> [String] {
        var seen: [String] = []
        for target in scanner.xcodeTargets {
            for config in target.configurationNames {
                if let value = target.buildSettings[config]?[key], !value.isEmpty, !seen.contains(value) {
                    seen.append(value)
                }
            }
        }
        return seen.sorted()
    }

    private func targetDetectedSetting(_ target: InspectorTargetInfo, _ key: String) -> String? {
        for config in target.configurationNames {
            if let value = target.buildSettings[config]?[key], !value.isEmpty { return value }
        }
        return nil
    }

    private func targetDetectedBundleID(_ target: InspectorTargetInfo) -> String? {
        targetDetectedSetting(target, "PRODUCT_BUNDLE_IDENTIFIER")
    }

    private func effectiveString(_ key: String, fallback: String) -> String {
        xcodeSettings[key] ?? detectedSetting(key) ?? fallback
    }

    private func stringSettingBinding(_ key: String, fallback: String) -> Binding<String> {
        Binding(
            get: { self.effectiveString(key, fallback: fallback) },
            set: { self.xcodeSettings[key] = $0 }
        )
    }

    private func effectiveBool(_ key: String, fallback: Bool) -> Bool {
        if let value = xcodeSettings[key] { return value == "YES" }
        if let value = detectedSetting(key) { return value == "YES" }
        return fallback
    }

    private func boolSettingBinding(_ key: String, fallback: Bool) -> Binding<Bool> {
        Binding(
            get: { self.effectiveBool(key, fallback: fallback) },
            set: { self.xcodeSettings[key] = $0 ? "YES" : "NO" }
        )
    }

    private func targetBundleIDBinding(for targetName: String) -> Binding<String> {
        Binding(
            get: { self.targetBundleIDOverrides[targetName] ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    self.targetBundleIDOverrides.removeValue(forKey: targetName)
                } else {
                    self.targetBundleIDOverrides[targetName] = trimmed
                }
            }
        )
    }

    // MARK: - Validation

    private func isValidBundleID(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z][A-Za-z0-9_-]*(\\.[A-Za-z][A-Za-z0-9_-]*)+$", options: .regularExpression) != nil
    }

    private func isValidVersion(_ value: String) -> Bool {
        value.range(of: "^\\d+\\.\\d+\\.\\d+$", options: .regularExpression) != nil
    }

    private func isValidBuildNumber(_ value: String) -> Bool {
        !value.isEmpty && value.range(of: "^\\d+$", options: .regularExpression) != nil
    }

    private func defaultBundleID(projectName: String) -> String {
        func cleaned(_ s: String, lowercase: Bool) -> String {
            let parts = s.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
            let joined = parts.joined()
            return lowercase ? joined.lowercased() : joined
        }
        let org = cleaned(organizationName, lowercase: true)
        let name = cleaned(projectName, lowercase: false)
        return "com.\(org.isEmpty ? "swiftcode" : org).\(name.isEmpty ? "app" : name)"
    }

    // MARK: - Build configuration editing

    private func ensureConfigurationsCustomized() {
        if !configsCustomized {
            configurations = scanner.buildConfigurations
            configsCustomized = true
        }
    }

    private func addConfiguration() {
        let name = newConfigName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        ensureConfigurationsCustomized()
        if !configurations.contains(name) { configurations.append(name) }
        newConfigName = ""
    }

    private func duplicateConfiguration(_ config: String) {
        ensureConfigurationsCustomized()
        var copy = "\(config) copy"
        var counter = 2
        while configurations.contains(copy) {
            copy = "\(config) copy \(counter)"
            counter += 1
        }
        if let idx = configurations.firstIndex(of: config) {
            configurations.insert(copy, at: idx + 1)
        } else {
            configurations.append(copy)
        }
    }

    private func deleteConfiguration(_ config: String) {
        ensureConfigurationsCustomized()
        configurations.removeAll { $0 == config }
        if renamingConfig == config { renamingConfig = nil }
    }

    private func commitRename() {
        defer { renamingConfig = nil }
        guard let old = renamingConfig else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != old else { return }
        ensureConfigurationsCustomized()
        if let idx = configurations.firstIndex(of: old), !configurations.contains(trimmed) {
            configurations[idx] = trimmed
        }
    }

    private func detectDevelopmentTeam() {
        if let team = detectedSettingValues("DEVELOPMENT_TEAM").first {
            developmentTeam = team
        } else {
            errorMessage = "No DEVELOPMENT_TEAM value was found in this project's build settings. Set it in Xcode first, or type the team ID."
            showError = true
        }
    }

    // MARK: - Load / save

    private func loadSettings() {
        guard let project = sessionStore.activeProject else { return }
        let meta = project.buildSettings
        projectName = project.name
        organizationName = meta.organizationName
        let fallbackBundleID = defaultBundleID(projectName: project.name)
        bundleIdentifier = meta.bundleIdentifier.isEmpty
            ? (detectedSetting("PRODUCT_BUNDLE_IDENTIFIER") ?? fallbackBundleID)
            : meta.bundleIdentifier
        projectDescription = project.description
        githubRepo = project.githubRepo ?? ""
        marketingVersion = meta.marketingVersion
        buildNumber = meta.buildNumber
        autoIncrementBuild = meta.autoIncrementBuildNumber
        developmentTeam = meta.developmentTeam
        deploymentPlatform = meta.deploymentTargetPlatform
        deploymentVersion = meta.deploymentTargetVersion
        swiftLanguageVersion = meta.swiftLanguageVersion
        xcodeSettings = meta.xcodeSettings
        targetBundleIDOverrides = meta.targetBundleIDOverrides
        infoPlistPath = meta.infoPlistPath
        entitlementsPath = meta.entitlementsPath
        codeSignStyle = meta.codeSignStyle
        codeSignIdentity = meta.codeSignIdentity
        provisioningProfileSpecifier = meta.provisioningProfileSpecifier
        if let overrides = meta.buildConfigurationOverrides {
            configurations = overrides
            configsCustomized = true
        } else {
            configurations = []
            configsCustomized = false
        }
    }

    private func saveSettings() {
        guard let project = sessionStore.activeProject else { return }

        var problems: [String] = []
        let trimmedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty { problems.append("Project name cannot be empty.") }
        if !bundleIdentifier.isEmpty && !isValidBundleID(bundleIdentifier) {
            problems.append("Bundle identifier must be reverse-DNS (e.g. com.example.MyApp).")
        }
        if !isValidVersion(marketingVersion) {
            problems.append("Version must be numeric x.y.z (e.g. 1.0.0).")
        }
        if !isValidBuildNumber(buildNumber) {
            problems.append("Build must be a non-empty numeric string.")
        }
        for (target, override) in targetBundleIDOverrides where !override.isEmpty && !isValidBundleID(override) {
            problems.append("Bundle ID override for target \"\(target)\" must be reverse-DNS.")
        }
        if !problems.isEmpty {
            errorMessage = problems.joined(separator: "\n")
            showError = true
            return
        }

        // Rename. Default-root projects move their folder so the name keeps
        // resolving; custom-directory projects rename metadata only.
        if trimmedName != project.name {
            if project.customDirectoryPath != nil {
                sessionStore.updateProjectName(trimmedName, for: project)
            } else if !nameFieldLocked {
                let newURL = sessionStore.projectsDirectory.appendingPathComponent(trimmedName)
                if FileManager.default.fileExists(atPath: newURL.path) {
                    errorMessage = "A project named \"\(trimmedName)\" already exists."
                    showError = true
                    return
                }
                do {
                    try sessionStore.renameProject(project, to: trimmedName)
                } catch {
                    errorMessage = "Could not rename the project folder: \(error.localizedDescription)"
                    showError = true
                    return
                }
            }
        }

        let repo = githubRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        sessionStore.updateProjectSettings(description: projectDescription, githubRepo: repo.isEmpty ? nil : repo, for: project)

        var metadata = ProjectBuildSettings()
        metadata.organizationName = organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        metadata.bundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        metadata.marketingVersion = marketingVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        var finalBuild = buildNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if autoIncrementBuild, let number = Int(finalBuild) {
            finalBuild = String(number + 1)
            buildNumber = finalBuild
        }
        metadata.buildNumber = finalBuild
        metadata.autoIncrementBuildNumber = autoIncrementBuild
        metadata.developmentTeam = developmentTeam
        metadata.swiftLanguageVersion = swiftLanguageVersion
        metadata.deploymentTargetPlatform = deploymentPlatform
        metadata.deploymentTargetVersion = deploymentVersion
        metadata.buildConfigurationOverrides = configsCustomized ? configurations : nil
        metadata.targetBundleIDOverrides = targetBundleIDOverrides
        metadata.xcodeSettings = xcodeSettings
        metadata.infoPlistPath = infoPlistPath.trimmingCharacters(in: .whitespacesAndNewlines)
        metadata.entitlementsPath = entitlementsPath.trimmingCharacters(in: .whitespacesAndNewlines)
        metadata.codeSignStyle = codeSignStyle
        metadata.codeSignIdentity = codeSignIdentity
        metadata.provisioningProfileSpecifier = provisioningProfileSpecifier.trimmingCharacters(in: .whitespacesAndNewlines)
        sessionStore.updateProjectBuildMetadata(metadata, for: project)

        dismiss()
    }

    private func openProjectInFiles(_ project: Project) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.directoryURL.path)
    }

    // MARK: - Project discovery (real data from disk)

    private func refreshProjectDiscovery() async {
        guard let project = sessionStore.activeProject else { return }
        let dir = project.directoryURL
        if !didScan || scanner.projectDirectoryPath != dir.path {
            if !scanner.isScanning {
                await scanner.scan()
            }
            didScan = true
        }
        let targets = scanner.xcodeTargets
        let packages = scanner.packageDependencies
        let plistOverride = infoPlistPath
        let entOverride = entitlementsPath
        let result = await Task.detached(priority: .userInitiated) {
            ProjectSettingsView.discoverDetails(
                at: dir,
                targets: targets,
                scannerPackages: packages,
                infoPlistOverride: plistOverride,
                entitlementsOverride: entOverride
            )
        }.value
        resolvedPackages = result.packages
        runScripts = result.runScripts
        testPlans = result.testPlans
        shellScripts = result.shellScripts
        infoPlistResolvedPath = result.infoPlistPath
        infoPlistExists = result.infoPlistExists
        entitlementsResolvedPath = result.entitlementsPath
        entitlementsExists = result.entitlementsExists
    }

    private struct DiscoveryResult: Sendable {
        var packages: [DiscoveredPackage] = []
        var runScripts: [DiscoveredRunScript] = []
        var testPlans: [String] = []
        var shellScripts: [String] = []
        var infoPlistPath: String?
        var infoPlistExists = false
        var entitlementsPath: String?
        var entitlementsExists = false
    }

    nonisolated private static func discoverDetails(
        at dir: URL,
        targets: [InspectorTargetInfo],
        scannerPackages: [InspectorPackageInfo],
        infoPlistOverride: String,
        entitlementsOverride: String
    ) -> DiscoveryResult {
        var result = DiscoveryResult()
        result.packages = discoverPackages(at: dir, scannerPackages: scannerPackages)
        result.runScripts = discoverRunScripts(at: dir)
        result.testPlans = shallowFiles(at: dir, extensions: ["xctestplan"], maxDepth: 3)
        result.shellScripts = shallowFiles(at: dir, extensions: ["sh"], maxDepth: 3)
        let plist = resolveInfoPlist(at: dir, override: infoPlistOverride, targets: targets)
        result.infoPlistPath = plist.path
        result.infoPlistExists = plist.exists
        let entitlements = resolveEntitlements(at: dir, override: entitlementsOverride, targets: targets)
        result.entitlementsPath = entitlements.path
        result.entitlementsExists = entitlements.exists
        return result
    }

    nonisolated private static func discoverPackages(at dir: URL, scannerPackages: [InspectorPackageInfo]) -> [DiscoveredPackage] {
        var byURL: [String: DiscoveredPackage] = [:]
        for package in scannerPackages {
            byURL[normalizeRepoURL(package.url)] = DiscoveredPackage(
                name: package.name, url: package.url, version: nil,
                isLocal: package.isLocal, source: "Xcode project"
            )
        }
        for resolvedURL in packageResolvedCandidates(at: dir) {
            guard let data = try? Data(contentsOf: resolvedURL),
                  let file = try? JSONDecoder().decode(PackageResolvedFile.self, from: data) else { continue }
            let pins = file.pins ?? file.object?.pins ?? []
            for pin in pins {
                let name = pin.identity ?? pin.package ?? ""
                let url = pin.location ?? pin.repositoryURL ?? ""
                let version = pin.state?.version ?? pin.state?.branch
                let key = normalizeRepoURL(url)
                if var existing = byURL[key] {
                    existing.version = version
                    existing.source = "Xcode project · Package.resolved"
                    byURL[key] = existing
                } else if !name.isEmpty {
                    byURL[key] = DiscoveredPackage(
                        name: name, url: url, version: version,
                        isLocal: false, source: "Package.resolved"
                    )
                }
            }
        }
        return byURL.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    nonisolated private static func normalizeRepoURL(_ url: String) -> String {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        return s
    }

    nonisolated private static func packageResolvedCandidates(at dir: URL) -> [URL] {
        let fm = FileManager.default
        var urls: [URL] = []
        for direct in [dir.appendingPathComponent("Package.resolved"), dir.appendingPathComponent(".swiftpm/Package.resolved")] {
            if fm.fileExists(atPath: direct.path) { urls.append(direct) }
        }
        for found in shallowFiles(at: dir, extensions: ["resolved"], maxDepth: 4) where found.hasSuffix("Package.resolved") {
            let url = URL(fileURLWithPath: found)
            if !urls.contains(url) { urls.append(url) }
        }
        return urls
    }

    nonisolated private static func locatePbxproj(at dir: URL) -> URL? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        if let proj = contents.first(where: { $0.pathExtension == "xcodeproj" && $0.hasDirectoryPath }) {
            return proj.appendingPathComponent("project.pbxproj")
        }
        for sub in contents where sub.hasDirectoryPath {
            if let subContents = try? fm.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]),
               let proj = subContents.first(where: { $0.pathExtension == "xcodeproj" && $0.hasDirectoryPath }) {
                return proj.appendingPathComponent("project.pbxproj")
            }
        }
        return nil
    }

    nonisolated private static func discoverRunScripts(at dir: URL) -> [DiscoveredRunScript] {
        guard let pbxprojURL = locatePbxproj(at: dir),
              let data = try? Data(contentsOf: pbxprojURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let objects = plist["objects"] as? [String: Any] else { return [] }

        var phaseToTarget: [String: String] = [:]
        for (_, obj) in objects {
            guard let dict = obj as? [String: Any],
                  let isa = dict["isa"] as? String,
                  isa == "PBXNativeTarget" || isa == "PBXAggregateTarget",
                  let name = dict["name"] as? String,
                  let phases = dict["buildPhases"] as? [String] else { continue }
            for phaseID in phases { phaseToTarget[phaseID] = name }
        }

        var scripts: [DiscoveredRunScript] = []
        for (id, obj) in objects {
            guard let dict = obj as? [String: Any],
                  dict["isa"] as? String == "PBXShellScriptBuildPhase" else { continue }
            let name = dict["name"] as? String ?? "Run Script"
            let shell = dict["shellPath"] as? String ?? "/bin/sh"
            let inline = dict["shellScript"] as? String ?? ""
            scripts.append(DiscoveredRunScript(
                id: id,
                name: name,
                targetName: phaseToTarget[id],
                shell: shell,
                lineCount: inline.isEmpty ? 0 : inline.components(separatedBy: "\n").count,
                hasInlineScript: !inline.isEmpty
            ))
        }
        return scripts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    nonisolated private static func shallowFiles(at dir: URL, extensions: Set<String>, maxDepth: Int) -> [String] {
        let fm = FileManager.default
        var results: [String] = []
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        var depths: [URL: Int] = [dir: 0]
        for case let fileURL as URL in enumerator {
            let parent = fileURL.deletingLastPathComponent()
            let depth = (depths[parent] ?? maxDepth) + 1
            depths[fileURL] = depth
            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                if depth >= maxDepth { enumerator.skipDescendants() }
                continue
            }
            guard depth <= maxDepth else { continue }
            if extensions.contains(fileURL.pathExtension.lowercased()) {
                results.append(fileURL.path)
            }
        }
        return results.sorted()
    }

    nonisolated private static func resolveBuildPath(_ raw: String, projectDir: URL, targetName: String?) -> URL {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "$(SRCROOT)", with: projectDir.path)
        s = s.replacingOccurrences(of: "${SRCROOT}", with: projectDir.path)
        if let targetName {
            s = s.replacingOccurrences(of: "$(TARGET_NAME)", with: targetName)
            s = s.replacingOccurrences(of: "${TARGET_NAME}", with: targetName)
            s = s.replacingOccurrences(of: "$(PRODUCT_NAME)", with: targetName)
            s = s.replacingOccurrences(of: "${PRODUCT_NAME}", with: targetName)
        }
        let url = URL(fileURLWithPath: s)
        if url.path.hasPrefix("/") { return url }
        return projectDir.appendingPathComponent(s)
    }

    nonisolated private static func resolveInfoPlist(at dir: URL, override: String, targets: [InspectorTargetInfo]) -> (path: String?, exists: Bool) {
        let fm = FileManager.default
        let targetName = targets.first?.name
        var candidates: [String] = []
        let trimmed = override.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            candidates.append(resolveBuildPath(trimmed, projectDir: dir, targetName: targetName).path)
        } else {
            if let target = targets.first {
                for config in target.configurationNames {
                    if let raw = target.buildSettings[config]?["INFOPLIST_FILE"], !raw.isEmpty {
                        candidates.append(resolveBuildPath(raw, projectDir: dir, targetName: target.name).path)
                        break
                    }
                }
            }
            if let name = targetName {
                candidates.append(dir.appendingPathComponent("\(name)/Info.plist").path)
            }
            candidates.append(dir.appendingPathComponent("Info.plist").path)
        }
        for candidate in candidates where fm.fileExists(atPath: candidate) {
            return (candidate, true)
        }
        return (candidates.first, false)
    }

    nonisolated private static func resolveEntitlements(at dir: URL, override: String, targets: [InspectorTargetInfo]) -> (path: String?, exists: Bool) {
        let fm = FileManager.default
        let targetName = targets.first?.name
        var candidates: [String] = []
        let trimmed = override.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            candidates.append(resolveBuildPath(trimmed, projectDir: dir, targetName: targetName).path)
        } else {
            if let target = targets.first {
                for config in target.configurationNames {
                    if let raw = target.buildSettings[config]?["CODE_SIGN_ENTITLEMENTS"], !raw.isEmpty {
                        candidates.append(resolveBuildPath(raw, projectDir: dir, targetName: target.name).path)
                        break
                    }
                }
            }
            if let name = targetName {
                candidates.append(dir.appendingPathComponent("\(name)/\(name).entitlements").path)
            }
        }
        for candidate in candidates where fm.fileExists(atPath: candidate) {
            return (candidate, true)
        }
        return (candidates.first, false)
    }

    private struct PackageResolvedFile: Decodable {
        struct PinState: Decodable {
            let version: String?
            let branch: String?
            let revision: String?
        }
        struct Pin: Decodable {
            let identity: String?
            let package: String?
            let location: String?
            let repositoryURL: String?
            let state: PinState?
        }
        struct V1Object: Decodable {
            let pins: [Pin]?
        }
        let pins: [Pin]?
        let object: V1Object?
    }
}

// MARK: - Build setting row descriptor

private struct BuildSettingRow: Identifiable {
    enum Kind {
        case toggle
        case picker(options: [String])
        case text(placeholder: String)
    }

    let id = UUID()
    let key: String
    let title: String
    let icon: String
    let kind: Kind
    let stringFallback: String
    let boolFallback: Bool

    static func toggle(key: String, title: String, icon: String, fallback: Bool) -> BuildSettingRow {
        BuildSettingRow(key: key, title: title, icon: icon, kind: .toggle, stringFallback: "", boolFallback: fallback)
    }

    static func picker(key: String, title: String, icon: String, options: [String], fallback: String) -> BuildSettingRow {
        BuildSettingRow(key: key, title: title, icon: icon, kind: .picker(options: options), stringFallback: fallback, boolFallback: false)
    }

    static func text(key: String, title: String, icon: String, placeholder: String, fallback: String) -> BuildSettingRow {
        BuildSettingRow(key: key, title: title, icon: icon, kind: .text(placeholder: placeholder), stringFallback: fallback, boolFallback: false)
    }
}

extension DiscoveredPackage: Sendable {}
extension DiscoveredRunScript: Sendable {}
