import SwiftUI
import UniformTypeIdentifiers

// MARK: - Plist Value Type Helpers

/// The plist value kinds a user can create/edit through the UI.
public enum PlistValueKind: String, CaseIterable {
    case string = "String"
    case boolean = "Boolean"
    case number = "Number"
    case date = "Date"
    case data = "Data"
    case array = "Array"
    case dictionary = "Dictionary"

    public var symbol: String {
        switch self {
        case .string: return "textformat"
        case .boolean: return "switch.2"
        case .number: return "number"
        case .date: return "calendar"
        case .data: return "externaldrive"
        case .array: return "square.stack"
        case .dictionary: return "curlybraces"
        }
    }
}

/// Detects the plist kind of an arbitrary value coming from the editor.
public func plistValueKind(of value: Any) -> PlistValueKind {
    if value is Bool { return .boolean }
    if value is NSNumber { return .number }
    if value is Date { return .date }
    if value is Data { return .data }
    if value is [Any] { return .array }
    if value is [String: Any] { return .dictionary }
    return .string
}

/// A sensible default value for a freshly created key of the given kind.
public func defaultPlistValue(for kind: PlistValueKind) -> Any {
    switch kind {
    case .string: return ""
    case .boolean: return false
    case .number: return NSNumber(value: 0)
    case .date: return Date()
    case .data: return Data()
    case .array: return [Any]()
    case .dictionary: return [String: Any]()
    }
}

// MARK: - Common Key Templates

/// A pre-built Info.plist key a user can add with one tap.
public struct InfoPlistTemplate: Identifiable {
    public var id: String { key }
    public let key: String
    public let name: String
    public let symbol: String
    public let category: String
    public let kind: PlistValueKind
    public let defaultValue: Any

    public init(key: String, name: String, symbol: String, category: String, kind: PlistValueKind, defaultValue: Any) {
        self.key = key
        self.name = name
        self.symbol = symbol
        self.category = category
        self.kind = kind
        self.defaultValue = defaultValue
    }
}

public enum InfoPlistTemplateCatalog {
    public static let categories = ["All", "Identity", "Display & Scene", "Network & Security", "Behavior & Lifecycle", "URL Types", "Orientations", "Privacy"]

    nonisolated(unsafe) public static let all: [InfoPlistTemplate] = {
        var list: [InfoPlistTemplate] = [
            // Identity
            InfoPlistTemplate(key: "CFBundleIdentifier", name: "Bundle Identifier", symbol: "app.badge", category: "Identity", kind: .string, defaultValue: "$(PRODUCT_BUNDLE_IDENTIFIER)"),
            InfoPlistTemplate(key: "CFBundleName", name: "Bundle Name", symbol: "app", category: "Identity", kind: .string, defaultValue: "$(PRODUCT_NAME)"),
            InfoPlistTemplate(key: "CFBundleDisplayName", name: "Display Name", symbol: "tag", category: "Identity", kind: .string, defaultValue: ""),
            InfoPlistTemplate(key: "CFBundleExecutable", name: "Executable File", symbol: "gearshape.2", category: "Identity", kind: .string, defaultValue: "$(EXECUTABLE_NAME)"),
            InfoPlistTemplate(key: "CFBundleShortVersionString", name: "Version String", symbol: "number", category: "Identity", kind: .string, defaultValue: "1.0"),
            InfoPlistTemplate(key: "CFBundleVersion", name: "Build Number", symbol: "hammer", category: "Identity", kind: .string, defaultValue: "1"),
            InfoPlistTemplate(key: "CFBundleDevelopmentRegion", name: "Development Region", symbol: "globe", category: "Identity", kind: .string, defaultValue: "en"),
            InfoPlistTemplate(key: "CFBundlePackageType", name: "Package Type", symbol: "archivebox", category: "Identity", kind: .string, defaultValue: "APPL"),
            InfoPlistTemplate(key: "CFBundleInfoDictionaryVersion", name: "Info Dictionary Version", symbol: "info.circle", category: "Identity", kind: .string, defaultValue: "6.0"),
            InfoPlistTemplate(key: "CFBundleSpokenName", name: "Spoken Name", symbol: "waveform", category: "Identity", kind: .string, defaultValue: ""),
            InfoPlistTemplate(key: "NSHumanReadableCopyright", name: "Copyright Notice", symbol: "c.circle", category: "Identity", kind: .string, defaultValue: ""),
            InfoPlistTemplate(key: "LSApplicationCategoryType", name: "App Category", symbol: "square.grid.2x2", category: "Identity", kind: .string, defaultValue: "public.app-category.developer-tools"),
            InfoPlistTemplate(key: "ITSAppUsesNonExemptEncryption", name: "App Uses Non-Exempt Encryption", symbol: "lock.shield", category: "Identity", kind: .boolean, defaultValue: false),
            InfoPlistTemplate(key: "LSHasLocalizedDisplayName", name: "Localized Display Name", symbol: "character.book.closed", category: "Identity", kind: .boolean, defaultValue: true),

            // Display & Scene
            InfoPlistTemplate(key: "CFBundleIconName", name: "Icon Name", symbol: "app.dashed", category: "Display & Scene", kind: .string, defaultValue: "AppIcon"),
            InfoPlistTemplate(key: "UILaunchStoryboardName", name: "Launch Storyboard Name", symbol: "play.rectangle", category: "Display & Scene", kind: .string, defaultValue: "LaunchScreen"),
            InfoPlistTemplate(key: "LSMinimumSystemVersion", name: "Minimum System Version", symbol: "desktopcomputer", category: "Display & Scene", kind: .string, defaultValue: "13.0"),
            InfoPlistTemplate(key: "NSPrincipalClass", name: "Principal Class", symbol: "pyramid", category: "Display & Scene", kind: .string, defaultValue: "NSApplication"),
            InfoPlistTemplate(key: "NSHighResolutionCapable", name: "High Resolution Capable", symbol: "sparkles", category: "Display & Scene", kind: .boolean, defaultValue: true),
            InfoPlistTemplate(key: "UIRequiresFullScreen", name: "Requires Full Screen", symbol: "arrow.up.left.and.arrow.down.right", category: "Display & Scene", kind: .boolean, defaultValue: true),
            InfoPlistTemplate(key: "UIStatusBarHidden", name: "Status Bar Initially Hidden", symbol: "eye.slash", category: "Display & Scene", kind: .boolean, defaultValue: false),
            InfoPlistTemplate(key: "UIViewControllerBasedStatusBarAppearance", name: "View Controller-based Status Bar", symbol: "slider.horizontal.2.rectangle", category: "Display & Scene", kind: .boolean, defaultValue: true),
            InfoPlistTemplate(key: "CADisableMinimumFrameDurationOnPhone", name: "Prefer 120Hz ProMotion Refresh Rate", symbol: "speedometer", category: "Display & Scene", kind: .boolean, defaultValue: true),
            InfoPlistTemplate(key: "UIUserInterfaceStyle", name: "User Interface Style Override", symbol: "circle.righthalf.filled", category: "Display & Scene", kind: .string, defaultValue: "Automatic"),
            InfoPlistTemplate(key: "UISupportsDocumentBrowser", name: "Supports Document Browser", symbol: "folder.badge.gearshape", category: "Display & Scene", kind: .boolean, defaultValue: false),
            InfoPlistTemplate(key: "NSApplicationCrashOnExceptions", name: "Crash on Exceptions", symbol: "exclamationmark.octagon", category: "Display & Scene", kind: .boolean, defaultValue: true),

            // Network & Security
            InfoPlistTemplate(key: "NSAppTransportSecurity", name: "App Transport Security Settings", symbol: "shield", category: "Network & Security", kind: .dictionary, defaultValue: ["NSAllowsArbitraryLoads": false] as [String: Any]),
            InfoPlistTemplate(key: "NSAllowsArbitraryLoads", name: "Allows Arbitrary Loads (ATS Bypass)", symbol: "lock.open", category: "Network & Security", kind: .boolean, defaultValue: true),
            InfoPlistTemplate(key: "NSAllowsLocalNetworking", name: "Allows Local Networking", symbol: "wifi.router", category: "Network & Security", kind: .boolean, defaultValue: true),
            InfoPlistTemplate(key: "NSLocalNetworkUsageDescription", name: "Local Network Usage Description", symbol: "network", category: "Network & Security", kind: .string, defaultValue: "This app requires access to the local network to discover companion devices."),
            InfoPlistTemplate(key: "NSBonjourServices", name: "Bonjour Services", symbol: "antenna.radiowaves.left.and.right", category: "Network & Security", kind: .array, defaultValue: ["_http._tcp"] as [Any]),

            // Behavior & Lifecycle
            InfoPlistTemplate(key: "LSUIElement", name: "Agent / Menu Bar App (No Dock Icon)", symbol: "eye.slash", category: "Behavior & Lifecycle", kind: .boolean, defaultValue: false),
            InfoPlistTemplate(key: "NSSupportsAutomaticTermination", name: "Supports Automatic Termination", symbol: "power", category: "Behavior & Lifecycle", kind: .boolean, defaultValue: false),
            InfoPlistTemplate(key: "NSSupportsSuddenTermination", name: "Supports Sudden Termination", symbol: "bolt", category: "Behavior & Lifecycle", kind: .boolean, defaultValue: false),
            InfoPlistTemplate(key: "CFBundleAllowMixedLocalizations", name: "Allow Mixed Localizations", symbol: "globe", category: "Behavior & Lifecycle", kind: .boolean, defaultValue: false),
            InfoPlistTemplate(key: "UIFileSharingEnabled", name: "Application Supports iTunes File Sharing", symbol: "externaldrive.badge.person.crop", category: "Behavior & Lifecycle", kind: .boolean, defaultValue: false),
            InfoPlistTemplate(key: "LSSupportsOpeningDocumentsInPlace", name: "Supports Opening Documents in Place", symbol: "doc.badge.arrow.up", category: "Behavior & Lifecycle", kind: .boolean, defaultValue: true),
            InfoPlistTemplate(key: "NSAppleScriptEnabled", name: "AppleScript Enabled", symbol: "applescript", category: "Behavior & Lifecycle", kind: .boolean, defaultValue: false),
            InfoPlistTemplate(key: "UIApplicationSupportsIndirectInputEvents", name: "Supports Indirect Input Events", symbol: "cursorarrow.rays", category: "Behavior & Lifecycle", kind: .boolean, defaultValue: true),
            InfoPlistTemplate(key: "UIBackgroundModes", name: "Background Modes", symbol: "arrow.triangle.2.circlepath", category: "Behavior & Lifecycle", kind: .array, defaultValue: ["fetch", "remote-notification"] as [Any]),
            InfoPlistTemplate(key: "BGTaskSchedulerPermittedIdentifiers", name: "Permitted Background Task IDs", symbol: "clock.badge.checkmark", category: "Behavior & Lifecycle", kind: .array, defaultValue: ["com.example.app.refresh"] as [Any]),

            // Orientations
            InfoPlistTemplate(key: "UISupportedInterfaceOrientations", name: "Supported Interface Orientations", symbol: "iphone", category: "Orientations", kind: .array, defaultValue: ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"] as [Any]),
            InfoPlistTemplate(key: "UISupportedInterfaceOrientations~ipad", name: "Supported Interface Orientations (iPad)", symbol: "ipad", category: "Orientations", kind: .array, defaultValue: ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"] as [Any]),

            // URL Types
            InfoPlistTemplate(key: "CFBundleURLTypes", name: "URL Types", symbol: "link", category: "URL Types", kind: .array, defaultValue: [["CFBundleURLName": "", "CFBundleURLSchemes": ["myapp"]]] as [Any]),
            InfoPlistTemplate(key: "LSApplicationQueriesSchemes", name: "Queried URL Schemes", symbol: "magnifyingglass", category: "URL Types", kind: .array, defaultValue: [String]() as [Any]),
            InfoPlistTemplate(key: "CFBundleDocumentTypes", name: "Document Types", symbol: "doc", category: "URL Types", kind: .array, defaultValue: [Any]()),
            InfoPlistTemplate(key: "UTExportedTypeDeclarations", name: "Exported Type Declarations", symbol: "arrow.up.doc", category: "URL Types", kind: .array, defaultValue: [Any]()),
            InfoPlistTemplate(key: "UTImportedTypeDeclarations", name: "Imported Type Declarations", symbol: "arrow.down.doc", category: "URL Types", kind: .array, defaultValue: [Any]()),
        ]
        // Privacy usage descriptions come from the curated metadata catalog.
        for meta in InfoPlistNSStrings.all {
            list.append(InfoPlistTemplate(
                key: meta.key,
                name: meta.name,
                symbol: meta.sfSymbol,
                category: "Privacy",
                kind: .string,
                defaultValue: meta.recommendedWording
            ))
        }
        return list
    }()

    public static func templates(in category: String) -> [InfoPlistTemplate] {
        if category == "All" {
            return all
        }
        return all.filter { $0.category == category }
    }
}

// MARK: - Validation Issues

/// One validation warning surfaced by the warnings panel.
struct PlistValidationIssue: Identifiable {
    let id = UUID()
    let symbol = "exclamationmark.triangle"
    let message: String
    let fixTitle: String?
    let fix: (() -> Void)?
}

/// Collects validation issues for the warnings panel. Shared by the panel and
/// the Validate toolbar action. Uses the editor's own validators.
@MainActor
func collectPlistValidationIssues(editor: InfoPlistEditor) -> [PlistValidationIssue] {
    var list: [PlistValidationIssue] = []

    // Missing required identity keys.
    for key in ["CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion"] {
        if editor.entries[key] == nil {
            list.append(PlistValidationIssue(
                message: "Missing required key \(key).",
                fixTitle: "Add Key",
                fix: { editor.addMissingKey(key) }
            ))
        }
    }

    // Malformed bundle identifier.
    if let identifier = editor.entries["CFBundleIdentifier"] as? String {
        if identifier.isEmpty {
            list.append(PlistValidationIssue(
                message: "CFBundleIdentifier is empty. Use reverse-DNS format, e.g. com.example.MyApp.",
                fixTitle: nil,
                fix: nil
            ))
        } else if !editor.validateBundleIdentifier(identifier) {
            list.append(PlistValidationIssue(
                message: "CFBundleIdentifier contains invalid characters. Use only letters, numbers, dots, and hyphens.",
                fixTitle: nil,
                fix: nil
            ))
        }
    }

    // Malformed version / build strings.
    for key in ["CFBundleShortVersionString", "CFBundleVersion"] {
        if let version = editor.entries[key] as? String {
            if version.isEmpty {
                list.append(PlistValidationIssue(
                    message: "\(key) is empty.",
                    fixTitle: nil,
                    fix: nil
                ))
            } else if !editor.validateVersion(version) {
                list.append(PlistValidationIssue(
                    message: "\(key) \"\(version)\" is malformed. Use dot-separated numbers, e.g. 1.0.2.",
                    fixTitle: nil,
                    fix: nil
                ))
            }
        }
    }

    // Privacy usage-description wording issues (under 10 characters).
    let privacyIssues = editor.validatePrivacyKeys()
    for key in privacyIssues.keys.sorted() {
        let detail = privacyIssues[key] ?? ""
        if let meta = InfoPlistNSStrings.all.first(where: { $0.key == key }) {
            list.append(PlistValidationIssue(
                message: "\(meta.name): \(detail)",
                fixTitle: "Use Recommended",
                fix: { editor.set(key: key, value: meta.recommendedWording) }
            ))
        } else {
            list.append(PlistValidationIssue(
                message: "\(key): \(detail)",
                fixTitle: nil,
                fix: nil
            ))
        }
    }

    return list
}

/// Collapsible warnings panel. Hidden entirely when there are no issues.
struct InfoPlistValidationPanel: View {
    let issues: [PlistValidationIssue]
    @Binding var isExpanded: Bool

    var body: some View {
        if !issues.isEmpty {
            VStack(spacing: 0) {
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(issues) { issue in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: issue.symbol)
                                    .foregroundStyle(.secondary)
                                Text(issue.message)
                                    .font(.callout)
                                Spacer()
                                if let fixTitle = issue.fixTitle, let fix = issue.fix {
                                    Button(fixTitle, action: fix)
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Label("\(issues.count) Validation Warning\(issues.count == 1 ? "" : "s")", systemImage: "exclamationmark.triangle")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                Divider()
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
}

// MARK: - Info.plist View

public struct InfoPlistView: View {
    private let fileURL: URL?
    @State private var editor: InfoPlistEditor
    @State private var searchQuery = ""
    @State private var selectedKey: String? = nil
    @State private var selectedSection: PlistSidebarSection? = .identity
    @State private var validationExpanded = true
    @State private var showingAddKeySheet = false
    @State private var newCustomKey = ""
    @State private var newCustomType: PlistValueKind = .string
    @State private var templateCategory = "All"
    @State private var addKeySearchQuery = ""
    @State private var showingInspectorSheet = false
    @State private var toolStatus: String? = nil

    @Environment(WorkspaceViewModel.self) private var workspaceViewModel
    @State private var isCreating = false
    @State private var creationError: String? = nil

    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let url = fileURL {
            _editor = State(initialValue: InfoPlistEditor(fileURL: url))
        } else {
            _editor = State(initialValue: InfoPlistEditor(fileURL: URL(fileURLWithPath: "/dev/null")))
        }
    }

    private func reloadFromDisk(url: URL? = nil) {
        let target = url ?? fileURL
        guard let validURL = target else { return }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: validURL.path, isDirectory: &isDir), !isDir.boolValue else { return }
        editor = InfoPlistEditor(fileURL: validURL)
        editor.load()
    }

    private func createInfoPlist() {
        guard let project = ProjectSessionStore.shared.activeProject else {
            creationError = "No active project found in session."
            return
        }

        isCreating = true
        creationError = nil

        let targetURL = project.directoryURL.appendingPathComponent("Info.plist")
        let defaultContent = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>$(DEVELOPMENT_LANGUAGE)</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
</dict>
</plist>
"""

        Task {
            do {
                try defaultContent.write(to: targetURL, atomically: true, encoding: .utf8)
                ProjectSessionStore.shared.refreshFileTree(for: project)
                await workspaceViewModel.editor.openFile(url: targetURL)
                await workspaceViewModel.editor.updateActiveConfigurationURLs(for: project)
                isCreating = false
            } catch {
                isCreating = false
                creationError = "Failed to create Info.plist: \(error.localizedDescription)"
            }
        }
    }

    /// Keys matching the global search across key names, values, types, and
    /// privacy metadata (names, descriptions, search keywords).
    private var searchFilteredKeys: [String] {
        guard fileURL != nil, !searchQuery.isEmpty else { return [] }
        let lowerQuery = searchQuery.lowercased()
        return editor.entries.keys.sorted().filter { key in
            let matchesKey = key.lowercased().contains(lowerQuery)
            let matchesVal = String(describing: editor.entries[key] ?? "").lowercased().contains(lowerQuery)
            let matchesType = plistValueKind(of: editor.entries[key] ?? "").rawValue.lowercased().contains(lowerQuery)
            let matchesMetadata = InfoPlistNSStrings.all.contains { meta in
                meta.key == key && (
                    meta.name.lowercased().contains(lowerQuery) ||
                    meta.description.lowercased().contains(lowerQuery) ||
                    meta.searchKeywords.contains(where: { $0.lowercased().contains(lowerQuery) })
                )
            }
            return matchesKey || matchesVal || matchesType || matchesMetadata
        }
    }

    private var filteredTemplates: [InfoPlistTemplate] {
        let base = InfoPlistTemplateCatalog.templates(in: templateCategory)
        guard !addKeySearchQuery.isEmpty else { return base }
        let query = addKeySearchQuery.lowercased()
        return base.filter {
            $0.name.lowercased().contains(query) ||
            $0.key.lowercased().contains(query) ||
            $0.category.lowercased().contains(query)
        }
    }

    /// Produces a copy key that cannot collide with an existing key.
    private func uniqueCopyKey(basedOn key: String) -> String {
        var candidate = "\(key) copy"
        var n = 2
        while editor.entries[candidate] != nil {
            candidate = "\(key) copy \(n)"
            n += 1
        }
        return candidate
    }

    private func savePlist() {
        guard let url = fileURL else {
            toolStatus = "Save failed: No file URL available."
            return
        }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            toolStatus = "Save failed: Path is a directory, not an Info.plist file."
            return
        }
        do {
            try editor.save()
            toolStatus = "Info.plist saved to disk successfully."
        } catch {
            toolStatus = "Save failed: \(error.localizedDescription)"
        }
    }

    private func validateStructure() {
        validationExpanded = true
        let count = collectPlistValidationIssues(editor: editor).count
        if count == 0 {
            toolStatus = "Info.plist validated successfully. Required identity keys are present."
        } else {
            toolStatus = "Validation found \(count) warning\(count == 1 ? "" : "s"). See the panel below the toolbar."
        }
    }

    public var body: some View {
        if fileURL == nil {
            VStack(spacing: 20) {
                ContentUnavailableView {
                    Label("No Info.plist Configured", systemImage: "info.circle")
                } description: {
                    Text("The currently selected target does not contain an Info.plist configuration file.\n\nYou can create a standard Info.plist file in your project workspace.")
                }

                if let error = creationError {
                    Text(error)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }

                Button {
                    createInfoPlist()
                } label: {
                    Label(isCreating ? "Creating..." : "Create Info.plist", systemImage: "plus")
                        .font(.headline)
                        .frame(minWidth: 160)
                }
                .buttonStyle(.bordered)
                .disabled(isCreating)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        } else {
            VStack(spacing: 0) {
                // Professional Header Toolbar with Tool Actions
                headerToolbar

                Divider()

                // Validation warnings panel (hidden when there are no issues)
                InfoPlistValidationPanel(
                    issues: collectPlistValidationIssues(editor: editor),
                    isExpanded: $validationExpanded
                )

                // Feedback status banner
                if let status = toolStatus {
                    HStack {
                        Image(systemName: "info.circle")
                            .font(.caption)
                        Text(status)
                            .font(.caption)
                        Spacer()
                        Button { toolStatus = nil } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.secondarySystemFill))
                    Divider()
                }

                // Sidebar navigation + section detail
                NavigationSplitView {
                    List(selection: $selectedSection) {
                        ForEach(PlistSidebarSection.allCases) { section in
                            Label(section.title, systemImage: section.symbol)
                                .tag(section)
                        }
                    }
                    .navigationTitle("Sections")
                    .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
                } detail: {
                    Group {
                        if !searchQuery.isEmpty {
                            searchResultsView
                        } else {
                            sectionDetailView
                        }
                    }
                    .navigationTitle(searchQuery.isEmpty ? (selectedSection?.title ?? "Info.plist") : "Search Results")
                }
            }
            .sheet(isPresented: $showingAddKeySheet) {
                addKeySheetView
            }
            .sheet(isPresented: $showingInspectorSheet) {
                inspectorSheetView
            }
            .onAppear {
                reloadFromDisk()
            }
            .onChange(of: fileURL) { _, newURL in
                reloadFromDisk(url: newURL)
            }
        }
    }

    // MARK: - Section Detail

    @ViewBuilder
    private var sectionDetailView: some View {
        switch selectedSection ?? .identity {
        case .identity:
            IdentitySectionView(editor: editor)
        case .privacy:
            PrivacySectionView(editor: editor)
        case .iconsLaunch:
            IconsLaunchSectionView(editor: editor)
        case .orientations:
            OrientationsSectionView(editor: editor)
        case .appTransportSecurity:
            ATSSectionView(editor: editor)
        case .urlTypes:
            URLTypesSectionView(editor: editor)
        case .documentTypes:
            DocumentTypesSectionView(editor: editor)
        case .typeDeclarations:
            TypeDeclarationsSectionView(editor: editor)
        case .backgroundModes:
            BackgroundModesSectionView(editor: editor)
        case .deviceCapabilities:
            DeviceCapabilitiesSectionView(editor: editor)
        case .allKeys:
            allKeysListView
        }
    }

    // MARK: - Header Toolbar
    private var headerToolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text(fileURL?.lastPathComponent ?? "Info.plist")
                    .font(.headline)
                Text("(\(editor.entries.count) properties)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if editor.isDirty {
                    Text("Unsaved changes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(NSColor.controlBackgroundColor), in: Capsule())
                }
            }

            Spacer()

            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search keys, values, or types...", text: $searchQuery)
                    .textFieldStyle(.plain)
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .frame(width: 220)

            // Undo / Redo
            HStack(spacing: 4) {
                Button {
                    editor.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .disabled(!editor.canUndo)
                .help("Undo")

                Button {
                    editor.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .buttonStyle(.bordered)
                .disabled(!editor.canRedo)
                .help("Redo")
            }

            // Save Tool
            Button {
                savePlist()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .disabled(!editor.isDirty)
            .keyboardShortcut("s", modifiers: .command)
            .help("Write changes to the Info.plist file")

            // Add Key
            Button {
                showingAddKeySheet = true
            } label: {
                Label("Add Key", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)

            // Actions Menu
            Menu {
                Button {
                    validateStructure()
                } label: {
                    Label("Validate Info.plist", systemImage: "checkmark.seal")
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(editor.generateRawXML(), forType: .string)
                    toolStatus = "Copied Raw XML to clipboard"
                } label: {
                    Label("Copy Raw XML", systemImage: "doc.on.doc")
                }

                Divider()

                Button {
                    reloadFromDisk()
                    toolStatus = "Reloaded Info.plist from disk."
                } label: {
                    Label("Reload from Disk", systemImage: "arrow.clockwise")
                }

                if let url = fileURL {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28, height: 28)
            .help("More Actions")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Key Rows

    private func keyRow(for key: String) -> some View {
        InfoPlistRow(
            key: key,
            value: editor.entries[key] ?? "",
            onSelect: {
                selectedKey = key
                showingInspectorSheet = true
            },
            onDuplicate: {
                let val = editor.entries[key] ?? ""
                let copyKey = uniqueCopyKey(basedOn: key)
                editor.set(key: copyKey, value: val)
                toolStatus = "Duplicated to \(copyKey)"
            },
            onDelete: {
                editor.remove(key: key)
                if selectedKey == key { selectedKey = nil }
            },
            onValueChange: { newVal in
                editor.set(key: key, value: newVal)
            }
        )
        .padding(.vertical, 2)
    }

    // MARK: - All Keys List View
    private var allKeysListView: some View {
        let keys = editor.entries.keys.sorted()
        return List {
            if keys.isEmpty {
                ContentUnavailableView(
                    "No Properties",
                    systemImage: "doc.text",
                    description: Text("Click 'Add Key' to add properties.")
                )
                .padding()
            } else {
                ForEach(keys, id: \.self) { key in
                    keyRow(for: key)
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Search Results View
    private var searchResultsView: some View {
        let keys = searchFilteredKeys
        return List {
            if keys.isEmpty {
                ContentUnavailableView(
                    "No Matches",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("No properties match '\(searchQuery)'.")
                )
                .padding()
            } else {
                ForEach(keys, id: \.self) { key in
                    keyRow(for: key)
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Add Key Sheet
    private var addKeySheetView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Info.plist Key")
                        .font(.headline)
                    Text("Select a standard Apple configuration key, privacy description, or define a custom property.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showingAddKeySheet = false
                    newCustomKey = ""
                    addKeySearchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search keys by name or identifier...", text: $addKeySearchQuery)
                    .textFieldStyle(.plain)
                if !addKeySearchQuery.isEmpty {
                    Button { addKeySearchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            // Category Filter Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(InfoPlistTemplateCatalog.categories, id: \.self) { category in
                        let isSelected = templateCategory == category
                        let count = category == "All" ? InfoPlistTemplateCatalog.all.count : InfoPlistTemplateCatalog.templates(in: category).count
                        Button {
                            templateCategory = category
                        } label: {
                            HStack(spacing: 4) {
                                Text(category)
                                Text("(\(count))")
                                    .font(.caption2)
                                    .opacity(isSelected ? 0.9 : 0.6)
                            }
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor),
                                in: Capsule()
                            )
                            .foregroundColor(isSelected ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("Standard Templates (\(filteredTemplates.count))")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            List(filteredTemplates) { template in
                let exists = editor.entries[template.key] != nil
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.12))
                        Image(systemName: template.symbol)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.name)
                            .font(.body.weight(.medium))
                        Text(template.key)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    PlistTypeBadge(kind: template.kind)
                    if exists {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                            Text("Added")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.controlBackgroundColor), in: Capsule())
                    } else {
                        Button("Add") {
                            editor.set(key: template.key, value: template.defaultValue)
                            toolStatus = "Added \(template.key)"
                            showingAddKeySheet = false
                            addKeySearchQuery = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            }
            .listStyle(.inset)
            .frame(minHeight: 220)

            Divider()

            // Custom Key Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Custom Key Definition")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField("Key name (e.g. MyCustomProperty)", text: $newCustomKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Picker("", selection: $newCustomType) {
                        ForEach(PlistValueKind.allCases, id: \.self) { kind in
                            Label(kind.rawValue, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)

                    let trimmedKey = newCustomKey.trimmingCharacters(in: .whitespaces)
                    let keyExists = !trimmedKey.isEmpty && editor.entries[trimmedKey] != nil

                    Button("Add Custom") {
                        editor.set(key: trimmedKey, value: defaultPlistValue(for: newCustomType))
                        toolStatus = "Added \(trimmedKey) (\(newCustomType.rawValue))"
                        showingAddKeySheet = false
                        newCustomKey = ""
                        addKeySearchQuery = ""
                    }
                    .buttonStyle(.bordered)
                    .disabled(trimmedKey.isEmpty || keyExists)
                }

                let trimmedKey = newCustomKey.trimmingCharacters(in: .whitespaces)
                let keyExists = !trimmedKey.isEmpty && editor.entries[trimmedKey] != nil
                if keyExists {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                        Text("A key named '\(trimmedKey)' already exists. Choose a different name.")
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }
        }
        .padding(18)
        .frame(width: 620, height: 600)
    }

    // MARK: - Inspector Sheet
    private var inspectorSheetView: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Property Inspector", systemImage: "info.circle")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    showingInspectorSheet = false
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if let key = selectedKey {
                let metadata = InfoPlistNSStrings.all.first(where: { $0.key == key })
                InfoPlistInspectorPanel(
                    key: key,
                    value: Binding(
                        get: { editor.entries[key] ?? "" },
                        set: { newVal in
                            editor.set(key: key, value: newVal)
                        }
                    ),
                    metadata: metadata,
                    editor: editor
                )
            } else {
                ContentUnavailableView("No Key Selected", systemImage: "info.circle")
            }
        }
        .frame(width: 540, height: 520)
    }
}

// MARK: - Type Badge

struct PlistTypeBadge: View {
    let kind: PlistValueKind

    var body: some View {
        Text(kind.rawValue)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(NSColor.controlBackgroundColor), in: Capsule())
    }
}

// MARK: - Inline Scalar Value Editor (used in rows)

/// Edits scalar plist values inline. Arrays, dictionaries, and data show a
/// summary — they are edited in the inspector panel instead.
struct PlistInlineScalarEditor: View {
    @Binding var value: Any

    var body: some View {
        Group {
            switch plistValueKind(of: value) {
            case .boolean:
                Toggle("", isOn: Binding(
                    get: { (value as? Bool) ?? false },
                    set: { value = $0 }
                ))
                .toggleStyle(.switch)
                .tint(.gray)
                .labelsHidden()
            case .number:
                TextField("", text: numberTextBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            case .date:
                DatePicker("", selection: Binding(
                    get: { (value as? Date) ?? Date() },
                    set: { value = $0 }
                ), displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
            case .string:
                TextField("", text: Binding(
                    get: { (value as? String) ?? String(describing: value) },
                    set: { value = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            case .data:
                Text("Data (\((value as? Data)?.count ?? 0) bytes)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
            case .array:
                Text("\((value as? [Any])?.count ?? 0) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
            case .dictionary:
                Text("Dictionary (\((value as? [String: Any])?.count ?? 0) keys)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private var numberTextBinding: Binding<String> {
        Binding(
            get: {
                guard let number = value as? NSNumber else { return "" }
                let d = number.doubleValue
                if d.truncatingRemainder(dividingBy: 1) == 0 && abs(d) < 9_007_199_254_740_992 {
                    return String(Int(d))
                }
                return String(d)
            },
            set: { text in
                if let d = Double(text) {
                    value = NSNumber(value: d)
                }
            }
        )
    }
}

// MARK: - Array Editor

struct PlistArrayEditorView: View {
    @Binding var items: [Any]
    @State private var newItemKind: PlistValueKind = .string

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if items.isEmpty {
                Text("Empty array. Add items below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(items.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    Text("\(index)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                    PlistTypeBadge(kind: plistValueKind(of: items[index]))
                    PlistInlineScalarEditor(value: Binding(
                        get: { items[index] },
                        set: { items[index] = $0 }
                    ))
                    Spacer()
                    Button {
                        items.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove item")
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Picker("New item type", selection: $newItemKind) {
                    ForEach(PlistValueKind.allCases, id: \.self) { kind in
                        Label(kind.rawValue, systemImage: kind.symbol).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Button("Add Item") {
                    items.append(defaultPlistValue(for: newItemKind))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer()
            }
        }
    }
}

// MARK: - Dictionary Editor

struct PlistDictionaryEditorView: View {
    @Binding var dict: [String: Any]
    @State private var newKey = ""
    @State private var newKind: PlistValueKind = .string
    @State private var keyExistsWarning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if dict.isEmpty {
                Text("Empty dictionary. Add entries below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(dict.keys.sorted(), id: \.self) { key in
                HStack(spacing: 8) {
                    Text(key)
                        .font(.system(.body, design: .monospaced))
                        .frame(minWidth: 110, alignment: .leading)
                        .lineLimit(1)
                    PlistTypeBadge(kind: plistValueKind(of: dict[key] ?? ""))
                    PlistInlineScalarEditor(value: Binding(
                        get: { dict[key] ?? "" },
                        set: { dict[key] = $0 }
                    ))
                    Spacer()
                    Button {
                        dict.removeValue(forKey: key)
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove entry")
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField("New key", text: $newKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Picker("Type", selection: $newKind) {
                        ForEach(PlistValueKind.allCases, id: \.self) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    Button("Add") {
                        let trimmed = newKey.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        guard dict[trimmed] == nil else {
                            keyExistsWarning = true
                            return
                        }
                        dict[trimmed] = defaultPlistValue(for: newKind)
                        newKey = ""
                        keyExistsWarning = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if keyExistsWarning {
                    Text("That key already exists in this dictionary.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: newKey) { _, _ in
            keyExistsWarning = false
        }
    }
}

// MARK: - Data (Hex) Editor

struct PlistDataEditorView: View {
    @Binding var data: Data
    @State private var hexText: String = ""
    @State private var hexError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(data.count) bytes")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Hex bytes, e.g. 0A1B2C", text: $hexText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onAppear {
                    hexText = data.map { String(format: "%02X", $0) }.joined()
                }
            if let error = hexError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Apply Hex") {
                if let parsed = Data(hexString: hexText) {
                    data = parsed
                    hexError = nil
                } else {
                    hexError = "Invalid hex. Use pairs of 0-9/A-F characters."
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

private extension Data {
    init?(hexString: String) {
        let cleaned = hexString
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
        guard !cleaned.isEmpty, cleaned.count % 2 == 0 else { return nil }
        var result = Data()
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            result.append(byte)
            index = next
        }
        self = result
    }
}

// MARK: - Clean Monochrome Row View
struct InfoPlistRow: View {
    let key: String
    let value: Any
    let onSelect: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onValueChange: (Any) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(key)
                        .font(.system(.body, design: .monospaced).weight(.medium))
                        .lineLimit(1)
                    PlistTypeBadge(kind: plistValueKind(of: value))
                }

                if let meta = InfoPlistNSStrings.all.first(where: { $0.key == key }) {
                    Text(meta.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 240, alignment: .leading)

            Spacer()

            // Value Editor (scalars inline; collections open in the inspector)
            PlistInlineScalarEditor(value: Binding(
                get: { value },
                set: onValueChange
            ))
            .frame(minWidth: 180, maxWidth: 320)

            // Inspect
            Button(action: onSelect) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Inspect Property")

            // Duplicate
            Button(action: onDuplicate) {
                Image(systemName: "plus.square.on.square")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Duplicate Property")

            // Delete
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete Property")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

// MARK: - Inspector Panel

struct InfoPlistInspectorPanel: View {
    let key: String
    @Binding var value: Any
    let metadata: InfoPlistNSString?
    let editor: InfoPlistEditor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(metadata?.name ?? key)
                            .font(.title3.bold())
                        Spacer()
                        PlistTypeBadge(kind: plistValueKind(of: value))
                    }
                    Text(key)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if let desc = metadata?.description {
                    Text(desc)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                validationHints

                Divider()

                Text("Value")
                    .font(.subheadline.bold())

                switch plistValueKind(of: value) {
                case .array:
                    PlistArrayEditorView(items: Binding(
                        get: { (value as? [Any]) ?? [] },
                        set: { value = $0 }
                    ))
                case .dictionary:
                    PlistDictionaryEditorView(dict: Binding(
                        get: { (value as? [String: Any]) ?? [:] },
                        set: { value = $0 }
                    ))
                case .data:
                    PlistDataEditorView(data: Binding(
                        get: { (value as? Data) ?? Data() },
                        set: { value = $0 }
                    ))
                default:
                    PlistInlineScalarEditor(value: $value)
                }

                if let meta = metadata {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Category: \(meta.category)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Expected Type: \(meta.valueType.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !meta.recommendedWording.isEmpty {
                            Text("Apple Recommendation: \(meta.recommendedWording)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private var validationHints: some View {
        if key == "CFBundleIdentifier", let s = value as? String, !editor.validateBundleIdentifier(s) {
            PlistValidationNote(message: "This bundle identifier contains invalid characters. Use only letters, numbers, dots, and hyphens.")
        }
        if key == "CFBundleShortVersionString", let s = value as? String, !editor.validateVersion(s) {
            PlistValidationNote(message: "Version strings should use dot-separated numbers, e.g. 1.0.2.")
        }
        if let issue = editor.validatePrivacyKeys()[key] {
            PlistValidationNote(message: issue)
        }
    }
}
