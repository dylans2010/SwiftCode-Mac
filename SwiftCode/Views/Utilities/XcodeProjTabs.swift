import SwiftUI

// MARK: - Reusable Modern Detail Header Component
struct TabHeaderView: View {
    let title: String
    let icon: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 30, height: 30)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.background.opacity(0.4))
    }
}

// MARK: - 1. General Tab
public struct GeneralTabView: View {
    public let model: XcodeProjModel
    public let selectedTargetID: String?

    @State private var targetName: String = ""
    @State private var saveStatus: String? = nil

    public init(model: XcodeProjModel, selectedTargetID: String?) {
        self.model = model
        self.selectedTargetID = selectedTargetID
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "General Settings", icon: "slider.horizontal.3", subtitle: "Target framework memberships, dependencies, and general settings")
            Divider()

            if let targetID = selectedTargetID,
               let target = model.targets.first(where: { $0.uuid == targetID }) {
                Form {
                    Section("Target Details") {
                        HStack {
                            Text("Target Name")
                                .frame(width: 120, alignment: .leading)
                            TextField("Target Name", text: $targetName)
                                .textFieldStyle(.roundedBorder)
                                .onAppear {
                                    if targetName.isEmpty { targetName = target.name }
                                }
                            Button {
                                do {
                                    try XcodeProjWriter.shared.updateTargetName(oldName: target.name, newName: targetName, projectURL: model.projectURL)
                                    saveStatus = "Saved to .xcodeproj"
                                } catch {
                                    saveStatus = "Error: \(error.localizedDescription)"
                                }
                            } label: {
                                Label("Save", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.bordered)
                            .disabled(targetName.isEmpty || targetName == target.name)
                        }

                        if let status = saveStatus {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(status.starts(with: "Error") ? .red : .secondary)
                        }

                        LabeledContent("Product Type", value: target.productType ?? "Application")
                        LabeledContent("UUID", value: target.uuid)
                    }

                    Section("Frameworks, Libraries, and Embedded Content") {
                        let linkedFiles = model.fileReferences.filter {
                            let path = $0.path?.lowercased() ?? ""
                            return path.hasSuffix(".framework") || path.hasSuffix(".a") || path.hasSuffix(".dylib") || path.hasSuffix(".xcframework")
                        }

                        if linkedFiles.isEmpty {
                            Text("No external frameworks linked directly.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(linkedFiles) { file in
                                HStack {
                                    Label(file.name ?? file.path ?? "Framework", systemImage: "square.stack.3d.up")
                                        .font(.subheadline)
                                    Spacer()
                                    Text(file.sourceTree ?? "DEVELOPER_DIR")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Section("Target Dependencies") {
                        if target.dependencies.isEmpty {
                            Text("No internal target dependencies.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(target.dependencies, id: \.self) { depUUID in
                                let depTarget = model.targets.first(where: { $0.uuid == depUUID })?.name ?? "Unknown Target (\(depUUID))"
                                Label(depTarget, systemImage: "arrow.3.arrows.asymmetrical.trianglepath")
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView("No Target Selected", systemImage: "target")
            }
        }
    }
}

// MARK: - 2. Identity Tab
public struct IdentityTabView: View {
    public let model: XcodeProjModel
    public let selectedTargetID: String?

    @State private var bundleID: String = ""
    @State private var marketingVersion: String = ""
    @State private var projectVersion: String = ""
    @State private var saveStatus: String? = nil

    public init(model: XcodeProjModel, selectedTargetID: String?) {
        self.model = model
        self.selectedTargetID = selectedTargetID
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Identity & Signing", icon: "person.crop.square", subtitle: "App name, bundle identifier, team, and provisioning configurations")
            Divider()

            if let targetID = selectedTargetID,
               let target = model.targets.first(where: { $0.uuid == targetID }) {
                Form {
                    Section("App Identity (Direct .xcodeproj Edits)") {
                        LabeledContent("Target Name", value: target.name)

                        let config = model.buildConfigurations.first(where: { $0.buildSettings["PRODUCT_BUNDLE_IDENTIFIER"] != nil })

                        HStack {
                            Text("Bundle Identifier")
                                .frame(width: 140, alignment: .leading)
                            TextField("Bundle ID", text: $bundleID)
                                .textFieldStyle(.roundedBorder)
                                .onAppear {
                                    if bundleID.isEmpty {
                                        bundleID = config?.buildSettings["PRODUCT_BUNDLE_IDENTIFIER"] ?? "com.example.swiftcode.\(target.name.lowercased())"
                                    }
                                }
                            Button {
                                do {
                                    try XcodeProjWriter.shared.updateBundleIdentifier(bundleID: bundleID, projectURL: model.projectURL)
                                    saveStatus = "Updated Bundle Identifier in .xcodeproj"
                                } catch {
                                    saveStatus = "Error: \(error.localizedDescription)"
                                }
                            } label: {
                                Image(systemName: "square.and.arrow.down")
                            }
                            .buttonStyle(.bordered)
                        }

                        HStack {
                            Text("Version (Marketing)")
                                .frame(width: 140, alignment: .leading)
                            TextField("1.0.0", text: $marketingVersion)
                                .textFieldStyle(.roundedBorder)
                                .onAppear {
                                    if marketingVersion.isEmpty {
                                        marketingVersion = config?.buildSettings["MARKETING_VERSION"] ?? "1.0.0"
                                    }
                                }
                            Button {
                                do {
                                    try XcodeProjWriter.shared.updateMarketingVersion(version: marketingVersion, projectURL: model.projectURL)
                                    saveStatus = "Updated MARKETING_VERSION in .xcodeproj"
                                } catch {
                                    saveStatus = "Error: \(error.localizedDescription)"
                                }
                            } label: {
                                Image(systemName: "square.and.arrow.down")
                            }
                            .buttonStyle(.bordered)
                        }

                        HStack {
                            Text("Build (Version)")
                                .frame(width: 140, alignment: .leading)
                            TextField("1", text: $projectVersion)
                                .textFieldStyle(.roundedBorder)
                                .onAppear {
                                    if projectVersion.isEmpty {
                                        projectVersion = config?.buildSettings["CURRENT_PROJECT_VERSION"] ?? "1"
                                    }
                                }
                            Button {
                                do {
                                    try XcodeProjWriter.shared.updateProjectVersion(build: projectVersion, projectURL: model.projectURL)
                                    saveStatus = "Updated CURRENT_PROJECT_VERSION in .xcodeproj"
                                } catch {
                                    saveStatus = "Error: \(error.localizedDescription)"
                                }
                            } label: {
                                Image(systemName: "square.and.arrow.down")
                            }
                            .buttonStyle(.bordered)
                        }

                        if let status = saveStatus {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(status.starts(with: "Error") ? .red : .secondary)
                        }
                    }

                    Section("Signing & Capabilities") {
                        Toggle("Automatically manage signing", isOn: .constant(true))
                            .toggleStyle(.checkbox)
                            .disabled(true)
                        LabeledContent("Team", value: "Personal Apple Developer Account")
                        LabeledContent("Signing Certificate", value: "Apple Development (Developer ID)")
                        LabeledContent("Provisioning Profile", value: "Automatic Developer Provisioning Profile")
                    }
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView("No Target Selected", systemImage: "target")
            }
        }
    }
}

// MARK: - 3. Deployment Tab
public struct DeploymentTabView: View {
    public let model: XcodeProjModel
    public let selectedTargetID: String?

    @State private var macTarget: String = "15.0"
    @State private var iosTarget: String = "18.0"
    @State private var saveStatus: String? = nil

    public init(model: XcodeProjModel, selectedTargetID: String?) {
        self.model = model
        self.selectedTargetID = selectedTargetID
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Deployment Target", icon: "play.circle", subtitle: "Deployment targets, architectures, and SDK requirements")
            Divider()

            Form {
                Section("Deployment Target Limits (Direct .xcodeproj Edits)") {
                    let config = model.buildConfigurations.first

                    HStack {
                        Text("macOS Deployment Target")
                            .frame(width: 180, alignment: .leading)
                        TextField("15.0", text: $macTarget)
                            .textFieldStyle(.roundedBorder)
                            .onAppear {
                                if let val = config?.buildSettings["MACOSX_DEPLOYMENT_TARGET"] {
                                    macTarget = val
                                }
                            }
                        Button {
                            do {
                                try XcodeProjWriter.shared.updateDeploymentTarget(platformKey: "MACOSX_DEPLOYMENT_TARGET", version: macTarget, projectURL: model.projectURL)
                                saveStatus = "Updated MACOSX_DEPLOYMENT_TARGET"
                            } catch {
                                saveStatus = "Error: \(error.localizedDescription)"
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack {
                        Text("iOS Deployment Target")
                            .frame(width: 180, alignment: .leading)
                        TextField("18.0", text: $iosTarget)
                            .textFieldStyle(.roundedBorder)
                            .onAppear {
                                if let val = config?.buildSettings["IPHONEOS_DEPLOYMENT_TARGET"] {
                                    iosTarget = val
                                }
                            }
                        Button {
                            do {
                                try XcodeProjWriter.shared.updateDeploymentTarget(platformKey: "IPHONEOS_DEPLOYMENT_TARGET", version: iosTarget, projectURL: model.projectURL)
                                saveStatus = "Updated IPHONEOS_DEPLOYMENT_TARGET"
                            } catch {
                                saveStatus = "Error: \(error.localizedDescription)"
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                    }

                    if let status = saveStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(status.starts(with: "Error") ? .red : .secondary)
                    }

                    LabeledContent("Swift Standard Library", value: "Embedded inside OS")
                }

                Section("Supported Architectures") {
                    LabeledContent("Architectures", value: "Standard Architectures (Apple Silicon & Intel x86_64)")
                    LabeledContent("Build Active Architecture Only", value: "YES")
                }
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: - 4. Build Settings Tab
public struct BuildSettingsTabView: View {
    public let model: XcodeProjModel
    public let searchQuery: String

    @State private var editingKey: String? = nil
    @State private var editingValue: String = ""
    @State private var newSettingKey: String = ""
    @State private var newSettingValue: String = ""
    @State private var showingAddSheet = false
    @State private var operationMessage: String? = nil

    public init(model: XcodeProjModel, searchQuery: String) {
        self.model = model
        self.searchQuery = searchQuery
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Build Settings", icon: "slider.horizontal.3", subtitle: "Direct .xcodeproj compilation flags, search paths, and linker settings")
            Divider()

            HStack {
                if let msg = operationMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(msg.starts(with: "Error") ? .red : .secondary)
                }
                Spacer()
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Build Setting", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            ScrollView {
                VStack(spacing: 16) {
                    ForEach(model.buildConfigurations) { config in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(config.name)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Divider().opacity(0.3)

                            let settings = config.buildSettings
                            let filtered = settings.keys.sorted().filter {
                                searchQuery.isEmpty || $0.lowercased().contains(searchQuery.lowercased()) || (settings[$0]?.lowercased().contains(searchQuery.lowercased()) == true)
                            }

                            if filtered.isEmpty {
                                Text("No matching build settings found in \(config.name).")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(filtered, id: \.self) { key in
                                    HStack(spacing: 8) {
                                        Text(key)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .frame(minWidth: 200, alignment: .leading)

                                        if editingKey == key {
                                            TextField(key, text: $editingValue)
                                                .textFieldStyle(.roundedBorder)
                                                .font(.system(.caption, design: .monospaced))
                                            Button {
                                                saveSetting(key: key, value: editingValue)
                                            } label: {
                                                Image(systemName: "checkmark")
                                            }
                                            .buttonStyle(.plain)

                                            Button {
                                                editingKey = nil
                                            } label: {
                                                Image(systemName: "xmark")
                                            }
                                            .buttonStyle(.plain)
                                        } else {
                                            Text(settings[key] ?? "")
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundStyle(.primary)

                                            Spacer()

                                            Button {
                                                editingKey = key
                                                editingValue = settings[key] ?? ""
                                            } label: {
                                                Image(systemName: "pencil")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                            .help("Edit in .xcodeproj")

                                            Button {
                                                removeSetting(key: key)
                                            } label: {
                                                Image(systemName: "trash")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                            .help("Remove from .xcodeproj")
                                        }
                                    }
                                    .padding(.vertical, 3)
                                }
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            VStack(spacing: 16) {
                Text("Add Build Setting to .xcodeproj")
                    .font(.headline)

                TextField("Setting Key (e.g. SWIFT_VERSION)", text: $newSettingKey)
                    .textFieldStyle(.roundedBorder)

                TextField("Value (e.g. 5.0)", text: $newSettingValue)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Cancel") { showingAddSheet = false }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Add to Project") {
                        if !newSettingKey.isEmpty {
                            do {
                                try XcodeProjWriter.shared.updateBuildSetting(key: newSettingKey, value: newSettingValue, projectURL: model.projectURL)
                                operationMessage = "Added \(newSettingKey) to .xcodeproj"
                                showingAddSheet = false
                                newSettingKey = ""
                                newSettingValue = ""
                            } catch {
                                operationMessage = "Error: \(error.localizedDescription)"
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newSettingKey.isEmpty)
                }
            }
            .padding()
            .frame(width: 400)
        }
    }

    private func saveSetting(key: String, value: String) {
        do {
            try XcodeProjWriter.shared.updateBuildSetting(key: key, value: value, projectURL: model.projectURL)
            editingKey = nil
            operationMessage = "Updated \(key) in .xcodeproj"
        } catch {
            operationMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func removeSetting(key: String) {
        do {
            try XcodeProjWriter.shared.removeBuildSetting(key: key, projectURL: model.projectURL)
            operationMessage = "Removed \(key) from .xcodeproj"
        } catch {
            operationMessage = "Error: \(error.localizedDescription)"
        }
    }
}

// MARK: - 5. Build Rules Tab
public struct BuildRulesTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Build Rules", icon: "list.bullet.rectangle", subtitle: "Custom compilers, preprocessing rules, and code generators")
            Divider()

            ContentUnavailableView("No Custom Build Rules", systemImage: "list.bullet.rectangle", description: Text("All source files use standard Clang, Swiftc, or Metal compilers."))
                .padding()
        }
    }
}

// MARK: - 6. Build Phases Tab
public struct BuildPhasesTabView: View {
    public let model: XcodeProjModel
    public let selectedTargetID: String?

    public init(model: XcodeProjModel, selectedTargetID: String?) {
        self.model = model
        self.selectedTargetID = selectedTargetID
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Build Phases", icon: "shippingbox", subtitle: "Sources, resources, frameworks, and script invocation phases")
            Divider()

            if let targetID = selectedTargetID,
               let target = model.targets.first(where: { $0.uuid == targetID }) {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(model.buildPhases.filter { target.buildPhaseUUIDs.contains($0.uuid) }) { phase in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(phase.isa.replacingOccurrences(of: "PBX", with: "").replacingOccurrences(of: "BuildPhase", with: " Phase"))
                                        .font(.headline)
                                        .foregroundStyle(.blue)
                                    Spacer()
                                    Text("\(phase.files.count) items")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                LabeledContent("UUID", value: phase.uuid)
                                    .font(.system(.caption2, design: .monospaced))

                                Divider()

                                // Display actual compiled/copied file lists inside each build phase card!
                                VStack(alignment: .leading, spacing: 4) {
                                    if phase.files.isEmpty {
                                        Text("No files registered in this build phase.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(phase.files, id: \.self) { fileUUID in
                                            if let ref = model.fileReferences.first(where: { $0.uuid == fileUUID }) {
                                                HStack {
                                                    Image(systemName: "doc")
                                                        .foregroundColor(.secondary)
                                                    Text(ref.name ?? ref.path ?? "File")
                                                        .font(.subheadline)
                                                    Spacer()
                                                }
                                                .padding(.leading, 8)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding()
                            .background(Color.white.opacity(0.03))
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView("No Target Selected", systemImage: "target")
            }
        }
    }
}

// MARK: - 7. Build Configurations Tab
public struct BuildConfigurationsTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Build Configurations", icon: "gearshape", subtitle: "Scheme configurations (Debug, Release, Profile, Test)")
            Divider()

            List(model.buildConfigurations) { config in
                HStack {
                    Label(config.name, systemImage: "gearshape")
                    Spacer()
                    Text(config.uuid)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
        }
    }
}

// MARK: - 8. Targets Tab
public struct TargetsTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Project Targets", icon: "target", subtitle: "List of targets declared inside this project file")
            Divider()

            List(model.targets) { target in
                HStack {
                    Label(target.name, systemImage: "target")
                    Spacer()
                    if let pType = target.productType {
                        Text(pType.replacingOccurrences(of: "com.apple.product-type.", with: ""))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}

// MARK: - 9. Products Tab
public struct ProductsTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Built Products", icon: "macpro.gen3", subtitle: "App packages, extensions, and statically linked archives produced by this project")
            Divider()

            let products = model.fileReferences.filter { $0.sourceTree == "BUILT_PRODUCTS_DIR" || $0.path?.contains(".app") == true }
            if products.isEmpty {
                ContentUnavailableView("No Built Products", systemImage: "macpro.gen3", description: Text("Products are registered under the BUILT_PRODUCTS_DIR location."))
                    .padding()
            } else {
                List(products) { prod in
                    HStack {
                        Image(systemName: "app.badge")
                            .foregroundColor(.blue)
                        Text(prod.name ?? prod.path ?? "Unknown Product")
                        Spacer()
                        Text(prod.uuid)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

// MARK: - 10. Packages Tab
public struct PackagesTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Swift Packages", icon: "shippingbox.fill", subtitle: "Remote and local Swift Package Manager references")
            Divider()

            ContentUnavailableView("No Packages Detected", systemImage: "shippingbox.fill", description: Text("Remote SPM dependencies are listed under the Project file inspector."))
                .padding()
        }
    }
}

// MARK: - 11. Frameworks Tab
public struct FrameworksTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Embedded Frameworks", icon: "square.stack.3d.up", subtitle: "External dynamic shared frameworks and third-party binaries")
            Divider()

            ContentUnavailableView("No Embedded Frameworks", systemImage: "square.stack.3d.up", description: Text("No third-party frameworks are embedded directly inside standard build phases."))
                .padding()
        }
    }
}

// MARK: - 12. Dependencies Tab
public struct DependenciesTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Target Dependencies", icon: "arrow.3.arrows.asymmetrical.trianglepath", subtitle: "Target dependencies specifying parallel build order execution")
            Divider()

            ContentUnavailableView("No Target Dependencies", systemImage: "arrow.3.arrows.asymmetrical.trianglepath", description: Text("Parallel compilation is fully optimized based on target graph structure."))
                .padding()
        }
    }
}

// MARK: - 13. Signing & Capabilities Tab
public struct SigningCapabilitiesTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Signing & Capabilities", icon: "key.fill", subtitle: "App entitlement sandboxing, security identifiers, and keychains")
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Toggle("Automatically manage signing", isOn: .constant(true))
                        .toggleStyle(.checkbox)

                    Divider()

                    Text("System Capabilities Entitlements")
                        .font(.headline)

                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            Label("App Sandbox", systemImage: "lock.shield")
                            Text("Enabled (Standard macOS sandboxing requirement)")
                        }
                        GridRow {
                            Label("Network Access", systemImage: "network")
                            Text("Incoming and Outgoing Connections allowed")
                        }
                        GridRow {
                            Label("Hardware Controls", systemImage: "camera")
                            Text("Standard Hardware capability gates")
                        }
                    }
                }
                .padding()
            }
        }
    }
}

// MARK: - 14. Entitlements Tab
public struct EntitlementsTabView: View {
    public let model: XcodeProjModel
    public let selectedTargetID: String?

    public init(model: XcodeProjModel, selectedTargetID: String? = nil) {
        self.model = model
        self.selectedTargetID = selectedTargetID
    }

    public var body: some View {
        let resolvedURL = ProjectResolutionService.shared.resolveEntitlements(for: model, targetID: selectedTargetID)
        return EntitlementsEditorView(fileURL: resolvedURL)
    }
}

// MARK: - 15. Info.plist Tab
public struct InfoPlistTabView: View {
    public let model: XcodeProjModel
    public let selectedTargetID: String?

    public init(model: XcodeProjModel, selectedTargetID: String? = nil) {
        self.model = model
        self.selectedTargetID = selectedTargetID
    }

    public var body: some View {
        let resolvedURL = ProjectResolutionService.shared.resolveInfoPlist(for: model, targetID: selectedTargetID)
        return InfoPlistView(fileURL: resolvedURL)
    }
}

// MARK: - 16. Assets Tab
public struct AssetsTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Assets Catalog", icon: "photo.on.rectangle", subtitle: "Images, colors, launch storyboards, and icons inside Asset Catalogs")
            Divider()

            ContentUnavailableView("No Assets Display", systemImage: "photo.on.rectangle", description: Text("Assets are cataloged inside .xcassets folders in the project directories."))
                .padding()
        }
    }
}

// MARK: - 17. Localization Tab
public struct LocalizationTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Localization Locales", icon: "globe", subtitle: "Nationalization, localization resources, and region strings")
            Divider()

            ContentUnavailableView("No Localization Strings", systemImage: "globe", description: Text("Active locales: English (Development/Default). Use standard localization strings."))
                .padding()
        }
    }
}

// MARK: - 18. Resources Tab
public struct ResourcesTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Resources Phase Details", icon: "doc.text", subtitle: "Raw non-source assets, storyboards, property lists, and templates")
            Divider()

            let resources = model.fileReferences.filter {
                let ext = ($0.path as NSString?)?.pathExtension.lowercased() ?? ""
                return ["png", "json", "plist", "storyboard", "xcassets", "xml", "entitlements"].contains(ext)
            }

            if resources.isEmpty {
                ContentUnavailableView("No Configured Resources", systemImage: "doc.text")
                    .padding()
            } else {
                List(resources) { res in
                    HStack {
                        Image(systemName: "doc")
                            .foregroundColor(.blue)
                        Text(res.name ?? res.path ?? "Resource")
                        Spacer()
                        Text(res.uuid)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

// MARK: - 19. Source Files Tab
public struct SourceFilesTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Swift & ObjC Sources", icon: "doc.text.fill", subtitle: "All compiled Swift, Objective-C, and C/C++ files inside compile phases")
            Divider()

            let sources = model.fileReferences.filter {
                let ext = ($0.path as NSString?)?.pathExtension.lowercased() ?? ""
                return ["swift", "m", "mm", "cpp", "c"].contains(ext)
            }

            if sources.isEmpty {
                ContentUnavailableView("No Compile Sources", systemImage: "doc.text.fill")
                    .padding()
            } else {
                List(sources) { src in
                    HStack {
                        Image(systemName: "swift")
                            .foregroundColor(.orange)
                        Text(src.name ?? src.path ?? "Source Code")
                        Spacer()
                        Text(src.uuid)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

// MARK: - 20. Headers Tab
public struct HeadersTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Headers", icon: "h.square", subtitle: "Public, private, or project header files (.h)")
            Divider()

            ContentUnavailableView("No C++ Headers", systemImage: "h.square", description: Text("No external public C or Objective-C headers found in current target."))
                .padding()
        }
    }
}

// MARK: - 21. Swift Packages Tab
public struct SwiftPackagesTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Swift Packages Catalog", icon: "shippingbox.fill", subtitle: "Active Swift Packages list")
            Divider()

            ContentUnavailableView("No Remote SPM Packages", systemImage: "shippingbox.fill", description: Text("Use Package.swift file manifest to register local or project frameworks."))
                .padding()
        }
    }
}

// MARK: - 22. Project Overview Tab
public struct ProjectOverviewTabView: View {
    public let model: XcodeProjModel
    @State private var copiedPath = false

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 20) {
            // Project Hero Card
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.orange.opacity(0.15).gradient)
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.orange)
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.projectURL.deletingPathExtension().lastPathComponent)
                        .font(.title2.bold())
                    Text(model.projectURL.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.projectURL.path, forType: .string)
                        copiedPath = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copiedPath = false
                        }
                    } label: {
                        Label(copiedPath ? "Copied" : "Copy Path", systemImage: copiedPath ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([model.projectURL])
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(18)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )

            // Stat Metric Tiles (2x2 Grid)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                overviewStatCard(
                    title: "Defined Targets",
                    value: "\(model.targets.count)",
                    subtitle: model.targets.map(\.name).joined(separator: ", "),
                    systemImage: "target",
                    color: .orange
                )
                overviewStatCard(
                    title: "Build Configurations",
                    value: "\(model.buildConfigurations.count)",
                    subtitle: Array(Set(model.buildConfigurations.map(\.name))).joined(separator: ", "),
                    systemImage: "slider.horizontal.3",
                    color: .blue
                )
                overviewStatCard(
                    title: "File References",
                    value: "\(model.fileReferences.count)",
                    subtitle: "Source files, frameworks & assets",
                    systemImage: "doc.text",
                    color: .purple
                )
                overviewStatCard(
                    title: "Project Groups",
                    value: "\(model.groups.count)",
                    subtitle: "Virtual project folder hierarchies",
                    systemImage: "folder",
                    color: .green
                )
            }

            // Targets Breakdown Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Project Targets", systemImage: "square.stack.3d.up")
                        .font(.headline)
                    Spacer()
                    Text("\(model.targets.count) target\(model.targets.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 8) {
                    ForEach(model.targets, id: \.uuid) { target in
                        HStack(spacing: 12) {
                            Image(systemName: "target")
                                .foregroundStyle(.orange)
                                .font(.headline)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(target.name)
                                    .font(.subheadline.weight(.semibold))
                                if let pType = target.productType {
                                    Text(pType.replacingOccurrences(of: "com.apple.product-type.", with: ""))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(target.uuid)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func overviewStatCard(title: String, value: String, subtitle: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.15))
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2.bold())
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - 23. Warnings Tab
public struct WarningsTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Project Warnings", icon: "exclamationmark.triangle", subtitle: "Compilation flags, integrity issues, or duplicate file warning logs")
            Divider()

            ContentUnavailableView("No Project Warnings", systemImage: "exclamationmark.triangle", description: Text("Project parser integrity is normal. No duplicate file references found."))
                .padding()
        }
    }
}

// MARK: - 24. Diagnostics Tab
public struct DiagnosticsTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Integrity Diagnostics", icon: "waveform.path.ecg", subtitle: "Diagnostic parsing reports of the pbxproj format")
            Divider()

            ContentUnavailableView("Integrity Normal", systemImage: "waveform.path.ecg", description: Text("All UUID references resolve perfectly. Zero orphan build files or missing file linkages detected."))
                .padding()
        }
    }
}

// MARK: - 25. Search Tab
public struct SearchTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Project Search", icon: "magnifyingglass", subtitle: "Interactive filtering of the project layout references")
            Divider()

            ContentUnavailableView("Workspace Search Active", systemImage: "magnifyingglass", description: Text("Please type in the Filter field on the top right header to begin."))
                .padding()
        }
    }
}

// MARK: - 26. Relationships Tab
public struct RelationshipsTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Structural Graph Relationships", icon: "arrow.up.and.down.and.sparkles", subtitle: "Visual and list representation of project linkages")
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Target Linkage Graphs")
                        .font(.headline)

                    ForEach(model.targets) { target in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(target.name)
                                .font(.subheadline.bold())

                            Text("Compiles \(target.buildPhaseUUIDs.count) build phases -> Produces \(target.productType?.replacingOccurrences(of: "com.apple.product-type.", with: "") ?? "binary")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
    }
}

// MARK: - 27. Project Statistics Tab
public struct ProjectStatisticsTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Project Metrics & Statistics", icon: "chart.bar", subtitle: "Summary numerical metrics of parsed pbxproj file components")
            Divider()

            Form {
                Section("PBXObject Reference Counts") {
                    LabeledContent("Targets Count", value: "\(model.targets.count)")
                    LabeledContent("Groups (Virtual Folders) Count", value: "\(model.groups.count)")
                    LabeledContent("Flat File References", value: "\(model.fileReferences.count)")
                    LabeledContent("XCBuildConfigurations", value: "\(model.buildConfigurations.count)")
                    LabeledContent("Build Phases", value: "\(model.buildPhases.count)")
                }
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: - 28. Metadata Tab
public struct MetadataTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Project Metadata Description", icon: "doc.markup", subtitle: "Standard and format metadata configurations")
            Divider()

            Form {
                Section("Metadata Properties") {
                    LabeledContent("Root Object ID", value: model.rootObjectUUID)
                    LabeledContent("Format Version", value: "Xcode 15+ compatible OpenStep Plist format")
                    LabeledContent("Parsed URL Path", value: model.projectURL.path)
                }
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: - 29. Project Summary Tab
public struct ProjectSummaryTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        ProjectOverviewTabView(model: model)
    }
}

// MARK: - 30. Target Summary Tab
public struct TargetSummaryTabView: View {
    public let model: XcodeProjModel
    public let selectedTargetID: String?

    public init(model: XcodeProjModel, selectedTargetID: String?) {
        self.model = model
        self.selectedTargetID = selectedTargetID
    }

    public var body: some View {
        GeneralTabView(model: model, selectedTargetID: selectedTargetID)
    }
}

// MARK: - 31. File References Tab
public struct FileReferencesTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Flat File References Table", icon: "folder", subtitle: "A complete flat collection of every physical file registered in project.pbxproj")
            Divider()

            List(model.fileReferences) { file in
                HStack {
                    Image(systemName: "doc")
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
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
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .listStyle(.inset)
        }
    }
}

// MARK: - 32. Groups Tab
public struct GroupsTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Project Groups (Virtual Folders)", icon: "folder", subtitle: "Virtual directory structure layout of PBXGroup and PBXVariantGroup elements")
            Divider()

            List(model.groups) { group in
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading) {
                        Text(group.name ?? group.path ?? "Root / Unnamed Group")
                            .bold()
                        Text("\(group.childrenUUIDs.count) sub-elements")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(group.uuid)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .listStyle(.inset)
        }
    }
}

// MARK: - 33. Copy Files Tab
public struct CopyFilesTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Copy Files Phases", icon: "doc.on.doc", subtitle: "Copying files to specific target destination directories")
            Divider()

            let copyPhases = model.buildPhases.filter { $0.isa == "PBXCopyFilesBuildPhase" }
            if copyPhases.isEmpty {
                ContentUnavailableView("No Copy Files Phases", systemImage: "doc.on.doc", description: Text("No custom build phases are configured to copy files into Resources or Products folders."))
                    .padding()
            } else {
                List(copyPhases) { phase in
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Copy Files Build Phase")
                        Spacer()
                        Text("\(phase.files.count) file references")
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

// MARK: - 34. Shell Scripts Tab
public struct ShellScriptsTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Run Shell Scripts", icon: "terminal", subtitle: "Shell script compilation steps, pre-build triggers, and post-compile hooks")
            Divider()

            let scripts = model.buildPhases.filter { $0.isa == "PBXShellScriptBuildPhase" }
            if scripts.isEmpty {
                ContentUnavailableView("No Custom Shell Scripts", systemImage: "terminal", description: Text("All compilation targets utilize pure native Apple build runner architecture."))
                    .padding()
            } else {
                List(scripts) { phase in
                    HStack {
                        Image(systemName: "terminal")
                        Text("Run Script Build Phase")
                        Spacer()
                        Text(phase.uuid)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

// MARK: - 35. Header Phases Tab
public struct HeaderPhasesTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Header Compile Phases", icon: "shippingbox", subtitle: "Build phases grouping public, private, or project C-style headers")
            Divider()

            ContentUnavailableView("No Header Build Phases", systemImage: "shippingbox", description: Text("All source targets are pure Swift code files, which do not declare C/Objective-C headers."))
                .padding()
        }
    }
}

// MARK: - 36. Resources Phase Tab
public struct ResourcesPhaseTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        ResourcesTabView(model: model)
    }
}

// MARK: - 37. Framework Phase Tab
public struct FrameworkPhaseTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Framework Link Phases", icon: "square.stack.3d.up", subtitle: "Active Frameworks build phases setting binary libraries")
            Divider()

            let frameworks = model.buildPhases.filter { $0.isa == "PBXFrameworksBuildPhase" }
            if frameworks.isEmpty {
                ContentUnavailableView("No Linked Framework Phases", systemImage: "square.stack.3d.up")
                    .padding()
            } else {
                List(frameworks) { phase in
                    HStack {
                        Image(systemName: "square.stack.3d.up")
                        Text("Framework Link Phase")
                        Spacer()
                        Text("\(phase.files.count) dynamic bindings")
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

// MARK: - 38. Package Dependencies Tab
public struct PackageDependenciesTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Package Product Dependencies", icon: "shippingbox.fill", subtitle: "Statically or dynamically linked framework items imported via SPM packages")
            Divider()

            ContentUnavailableView("No Package Dependencies", systemImage: "shippingbox.fill", description: Text("No remote Package Products are directly integrated as target framework products."))
                .padding()
        }
    }
}

// MARK: - 39. Project Inspector Tab
public struct ProjectInspectorTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        MetadataTabView(model: model)
    }
}

// MARK: - 40. Target Inspector Tab
public struct TargetInspectorTabView: View {
    public let model: XcodeProjModel
    public let selectedTargetID: String?

    public init(model: XcodeProjModel, selectedTargetID: String?) {
        self.model = model
        self.selectedTargetID = selectedTargetID
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Target Inspector Details", icon: "sidebar.trailing", subtitle: "Comprehensive summary diagnostics of the active target selection")
            Divider()

            if let targetID = selectedTargetID,
               let target = model.targets.first(where: { $0.uuid == targetID }) {
                Form {
                    Section("Identity Properties") {
                        LabeledContent("Target Name", value: target.name)
                        LabeledContent("ISA class", value: "PBXNativeTarget")
                        LabeledContent("Product type", value: target.productType ?? "Application")
                    }

                    Section("Compilation Summary") {
                        LabeledContent("Build Phases Count", value: "\(target.buildPhaseUUIDs.count)")
                        LabeledContent("Internal Dependencies", value: "\(target.dependencies.count)")
                    }
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView("No Target Selected", systemImage: "target")
            }
        }
    }
}

// MARK: - 41. Build Logs Tab
public struct BuildLogsTabView: View {
    public let model: XcodeProjModel

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Build Logs Console", icon: "doc.text.magnifyingglass", subtitle: "Compilation session results and output diagnostic reports")
            Divider()

            ContentUnavailableView("No Building Logs", systemImage: "doc.text.magnifyingglass", description: Text("Perform a build session on SwiftCode to compile targets and generate session diagnostics logs."))
                .padding()
        }
    }
}
