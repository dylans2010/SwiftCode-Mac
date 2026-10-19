import SwiftUI

// MARK: - Info.plist Structured Sections
//
// UI-only editors for the well-known Info.plist domains (identity, icons,
// orientations, App Transport Security, URL types, document types, UTI
// declarations, background modes, device capabilities, privacy descriptions).
// Every control reads and writes the real InfoPlistEditor model — there is no
// raw text/XML editing anywhere in this file.

/// The sidebar sections of the Info.plist editor.
public enum PlistSidebarSection: String, CaseIterable, Identifiable {
    case identity = "Identity"
    case privacy = "Privacy & Permissions"
    case iconsLaunch = "Icons & Launch"
    case orientations = "Interface Orientations"
    case appTransportSecurity = "App Transport Security"
    case urlTypes = "URL Types"
    case documentTypes = "Document Types"
    case typeDeclarations = "Type Declarations"
    case backgroundModes = "Background Modes"
    case deviceCapabilities = "Device Capabilities"
    case allKeys = "All Keys"

    public var id: String { rawValue }
    public var title: String { rawValue }

    public var symbol: String {
        switch self {
        case .identity: return "app.badge"
        case .privacy: return "hand.raised"
        case .iconsLaunch: return "app.dashed"
        case .orientations: return "crop.rotate"
        case .appTransportSecurity: return "lock.shield"
        case .urlTypes: return "link"
        case .documentTypes: return "doc"
        case .typeDeclarations: return "tag"
        case .backgroundModes: return "moon"
        case .deviceCapabilities: return "cpu"
        case .allKeys: return "list.bullet.rectangle"
        }
    }
}

// MARK: - Shared Binding Helpers

/// String binding for a top-level key. Reads "" when the key is absent so the
/// field stays empty without creating the key until the user commits a value.
func plistTopLevelString(_ editor: InfoPlistEditor, key: String) -> Binding<String> {
    Binding(
        get: { editor.entries[key] as? String ?? "" },
        set: { editor.set(key: key, value: $0) }
    )
}

/// String-array binding for a top-level key. Tolerates the [Any] bridging form
/// that PropertyListSerialization produces.
func plistTopLevelStringArray(_ editor: InfoPlistEditor, key: String) -> Binding<[String]> {
    Binding(
        get: { (editor.entries[key] as? [Any])?.compactMap { $0 as? String } ?? [] },
        set: { editor.set(key: key, value: $0) }
    )
}

/// String binding into a nested dictionary binding.
func nestedPlistString(_ dict: Binding<[String: Any]>, key: String) -> Binding<String> {
    Binding(
        get: { dict.wrappedValue[key] as? String ?? "" },
        set: { var d = dict.wrappedValue; d[key] = $0; dict.wrappedValue = d }
    )
}

/// String-array binding into a nested dictionary binding.
func nestedPlistStringArray(_ dict: Binding<[String: Any]>, key: String) -> Binding<[String]> {
    Binding(
        get: { (dict.wrappedValue[key] as? [Any])?.compactMap { $0 as? String } ?? [] },
        set: { var d = dict.wrappedValue; d[key] = $0; dict.wrappedValue = d }
    )
}

/// Boolean binding into a nested dictionary binding.
private func plistDictBool(_ dict: Binding<[String: Any]>, key: String) -> Binding<Bool> {
    Binding(
        get: { dict.wrappedValue[key] as? Bool ?? false },
        set: { var d = dict.wrappedValue; d[key] = $0; dict.wrappedValue = d }
    )
}

// MARK: - Shared Section Primitives

/// Text field that edits a local draft and commits to the model on Return or
/// focus loss, so typing does not flood the editor's undo stack with an entry
/// per keystroke. External model changes (undo/redo) sync back while unfocused.
struct PlistCommitTextField: View {
    @Binding var value: String
    var prompt: String = ""
    var font: Font = .body
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(prompt, text: $draft)
            .focused($isFocused)
            .font(font)
            .onAppear {
                if draft.isEmpty { draft = value }
            }
            .onChange(of: value) { _, newValue in
                if !isFocused && newValue != draft { draft = newValue }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused && draft != value { value = draft }
            }
            .onSubmit {
                if draft != value { value = draft }
            }
    }
}

/// Labeled row: icon + title/subtitle on the left, custom content on the right.
struct PlistLabeledRow<Content: View>: View {
    let symbol: String
    let title: String
    let subtitle: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
            }
            .frame(minWidth: 180, maxWidth: 260, alignment: .leading)
            Spacer()
            content()
        }
        .padding(.vertical, 2)
    }
}

/// A labeled text row bound to a top-level string key, with optional inline
/// validation and a remove (unset) affordance when the key is present.
struct PlistKeyTextRow: View {
    let editor: InfoPlistEditor
    let key: String
    let title: String
    let symbol: String
    var validation: ((String) -> String?)? = nil

    var body: some View {
        let present = editor.entries[key] != nil
        let current = editor.entries[key] as? String ?? ""
        VStack(alignment: .leading, spacing: 4) {
            PlistLabeledRow(symbol: symbol, title: title, subtitle: key) {
                HStack(spacing: 6) {
                    PlistCommitTextField(value: plistTopLevelString(editor, key: key), prompt: title)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(minWidth: 160, maxWidth: 320)
                    PlistRemoveKeyButton(editor: editor, key: key)
                }
            }
            if present, let validation, let message = validation(current) {
                PlistValidationNote(message: message)
            }
        }
    }
}

/// Icon-only button that removes a key (resets it to the unset state).
/// Renders nothing when the key is absent.
struct PlistRemoveKeyButton: View {
    let editor: InfoPlistEditor
    let key: String

    var body: some View {
        if editor.entries[key] != nil {
            Button {
                editor.remove(key: key)
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove \(key) (unset)")
        }
    }
}

/// Neutral validation note used across plist editors.
struct PlistValidationNote: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Editable list of strings bound to a string array.
struct PlistStringListEditor: View {
    @Binding var items: [String]
    var prompt: String = "Value"
    var addLabel: String = "Add Item"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if items.isEmpty {
                Text("No items. Add one below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(items.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    PlistCommitTextField(
                        value: Binding(
                            get: { items.indices.contains(index) ? items[index] : "" },
                            set: { var updated = items; if updated.indices.contains(index) { updated[index] = $0 }; items = updated }
                        ),
                        prompt: prompt,
                        font: .system(.body, design: .monospaced)
                    )
                    .textFieldStyle(.roundedBorder)
                    Button {
                        var updated = items
                        if updated.indices.contains(index) { updated.remove(at: index) }
                        items = updated
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove item")
                }
            }
            Button {
                var updated = items
                updated.append("")
                items = updated
            } label: {
                Label(addLabel, systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

/// Renders an "Add" button when the key is absent; otherwise the content plus a
/// remove affordance. Used for optional structured keys (ATS, orientations,
/// icon files, ...).
struct PlistOptionalKeyBlock<Content: View>: View {
    let editor: InfoPlistEditor
    let key: String
    let title: String
    let symbol: String
    let defaultValue: Any
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                if editor.entries[key] == nil {
                    Button("Add") { editor.set(key: key, value: defaultValue) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else {
                    PlistRemoveKeyButton(editor: editor, key: key)
                }
            }
            Text(key)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            if editor.entries[key] != nil {
                content()
            }
        }
        .padding(.vertical, 2)
    }
}

/// One toggleable string value in a PlistStringSetEditor.
struct PlistStringOption: Identifiable {
    let id: String
    let name: String
    let description: String
    let symbol: String
}

/// Toggle list bound to membership in a top-level string array. Toggling the
/// last option off removes the key entirely.
struct PlistStringSetEditor: View {
    let editor: InfoPlistEditor
    let key: String
    let options: [PlistStringOption]
    let removeTitle: String

    private var current: [String] {
        (editor.entries[key] as? [Any])?.compactMap { $0 as? String } ?? []
    }

    var body: some View {
        let values = current
        ForEach(options) { option in
            VStack(alignment: .leading, spacing: 2) {
                Toggle(isOn: Binding(
                    get: { values.contains(option.id) },
                    set: { isOn in
                        var updated = values
                        if isOn {
                            if !updated.contains(option.id) { updated.append(option.id) }
                        } else {
                            updated.removeAll { $0 == option.id }
                        }
                        if updated.isEmpty {
                            editor.remove(key: key)
                        } else {
                            editor.set(key: key, value: updated)
                        }
                    }
                )) {
                    Label(option.name, systemImage: option.symbol)
                }
                .toggleStyle(.switch)
                .tint(.gray)
                Text(option.id)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(option.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        if editor.entries[key] != nil {
            HStack {
                Spacer()
                Button(removeTitle) { editor.remove(key: key) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.top, 4)
        }
    }
}

/// Shell for editing a top-level array of dictionaries (URL types, document
/// types, UTI declarations). Preserves non-dictionary entries in the array.
struct PlistDictArrayEditor<Row: View>: View {
    let editor: InfoPlistEditor
    let key: String
    let title: String
    let symbol: String
    let itemName: String
    let newItem: [String: Any]
    let footer: String
    @ViewBuilder var row: (Binding<[Any]>, Int) -> Row

    private var items: Binding<[Any]> {
        Binding(
            get: { editor.entries[key] as? [Any] ?? [] },
            set: { editor.set(key: key, value: $0) }
        )
    }

    var body: some View {
        Section {
            if editor.entries[key] == nil {
                Button {
                    editor.set(key: key, value: [Any]())
                } label: {
                    Label("Add \(title)", systemImage: "plus")
                }
                Text(key)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                let itemsBinding = items
                ForEach(itemsBinding.wrappedValue.indices, id: \.self) { index in
                    row(itemsBinding, index)
                }
                HStack {
                    Button {
                        var updated = itemsBinding.wrappedValue
                        updated.append(newItem)
                        itemsBinding.wrappedValue = updated
                    } label: {
                        Label("Add \(itemName)", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Spacer()
                    PlistRemoveKeyButton(editor: editor, key: key)
                }
                Text(key)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label(title, systemImage: symbol)
        } footer: {
            Text(footer)
                .foregroundStyle(.secondary)
        }
    }
}

/// Card shell for one dictionary entry inside a PlistDictArrayEditor.
struct PlistDictRowCard<Content: View>: View {
    let items: Binding<[Any]>
    let index: Int
    let title: String
    let symbol: String
    @ViewBuilder let content: (Binding<[String: Any]>) -> Content

    private var entry: Binding<[String: Any]> {
        Binding(
            get: { (items.wrappedValue.indices.contains(index) ? items.wrappedValue[index] : nil) as? [String: Any] ?? [:] },
            set: { var updated = items.wrappedValue; if updated.indices.contains(index) { updated[index] = $0 }; items.wrappedValue = updated }
        )
    }

    private func removeItem() {
        var updated = items.wrappedValue
        if updated.indices.contains(index) { updated.remove(at: index) }
        items.wrappedValue = updated
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.body.weight(.medium))
                Spacer()
                Button(action: removeItem) {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove \(title.lowercased())")
            }
            content(entry)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - 1. Bundle Identity

struct IdentitySectionView: View {
    let editor: InfoPlistEditor

    var body: some View {
        Form {
            Section {
                PlistKeyTextRow(editor: editor, key: "CFBundleName", title: "Bundle Name", symbol: "app")
                PlistKeyTextRow(editor: editor, key: "CFBundleDisplayName", title: "Display Name", symbol: "tag")
                PlistKeyTextRow(editor: editor, key: "CFBundleIdentifier", title: "Bundle Identifier", symbol: "app.badge") { value in
                    if value.isEmpty { return "Bundle identifier is empty. Use reverse-DNS format, e.g. com.example.MyApp." }
                    if !editor.validateBundleIdentifier(value) { return "Invalid characters. Use only letters, numbers, dots, and hyphens." }
                    return nil
                }
                PlistKeyTextRow(editor: editor, key: "CFBundleShortVersionString", title: "Version", symbol: "number") { value in
                    if value.isEmpty { return "Version string is empty. Use dot-separated numbers, e.g. 1.0." }
                    if !editor.validateVersion(value) { return "Malformed version. Use dot-separated numbers, e.g. 1.0.2." }
                    return nil
                }
                PlistKeyTextRow(editor: editor, key: "CFBundleVersion", title: "Build Number", symbol: "hammer") { value in
                    if value.isEmpty { return "Build number is empty." }
                    if !editor.validateVersion(value) { return "Malformed build number. Use dot-separated numbers, e.g. 42." }
                    return nil
                }
                PlistKeyTextRow(editor: editor, key: "NSHumanReadableCopyright", title: "Copyright", symbol: "c.circle")
            } header: {
                Label("Bundle Identity", systemImage: "app.badge")
            } footer: {
                Text("Build-setting variables such as $(PRODUCT_BUNDLE_IDENTIFIER) are resolved by Xcode at build time.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 2. Icons & Launch

struct IconsLaunchSectionView: View {
    let editor: InfoPlistEditor

    var body: some View {
        Form {
            Section {
                PlistOptionalKeyBlock(editor: editor, key: "CFBundleIconFiles", title: "Icon Files", symbol: "photo.stack", defaultValue: [String]()) {
                    PlistStringListEditor(
                        items: plistTopLevelStringArray(editor, key: "CFBundleIconFiles"),
                        prompt: "Icon file name",
                        addLabel: "Add Icon File"
                    )
                }
                PlistKeyTextRow(editor: editor, key: "CFBundleIconName", title: "Icon Name", symbol: "app.dashed")
                PlistKeyTextRow(editor: editor, key: "UILaunchStoryboardName", title: "Launch Storyboard", symbol: "rocket")
                PlistKeyTextRow(editor: editor, key: "UIMainStoryboardFile", title: "Main Storyboard", symbol: "square.stack")
            } header: {
                Label("Icons & Launch", systemImage: "app.dashed")
            } footer: {
                Text("CFBundleIconName references an asset-catalog icon set; CFBundleIconFiles lists explicit icon files.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 3. Interface Orientations

struct OrientationsSectionView: View {
    let editor: InfoPlistEditor

    private struct DeviceFamily: Identifiable {
        let id: String
        let name: String
        let symbol: String
    }

    private struct Orientation: Identifiable {
        let id: String
        let name: String
        let symbol: String
    }

    private let families: [DeviceFamily] = [
        DeviceFamily(id: "UISupportedInterfaceOrientations", name: "All Devices", symbol: "rectangle.on.rectangle"),
        DeviceFamily(id: "UISupportedInterfaceOrientations~iphone", name: "iPhone", symbol: "iphone"),
        DeviceFamily(id: "UISupportedInterfaceOrientations~ipad", name: "iPad", symbol: "ipad"),
    ]

    private let orientations: [Orientation] = [
        Orientation(id: "UIInterfaceOrientationPortrait", name: "Portrait", symbol: "arrow.up"),
        Orientation(id: "UIInterfaceOrientationPortraitUpsideDown", name: "Portrait Upside Down", symbol: "arrow.down"),
        Orientation(id: "UIInterfaceOrientationLandscapeLeft", name: "Landscape Left", symbol: "arrow.left"),
        Orientation(id: "UIInterfaceOrientationLandscapeRight", name: "Landscape Right", symbol: "arrow.right"),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(families) { family in
                    PlistOptionalKeyBlock(editor: editor, key: family.id, title: family.name, symbol: family.symbol, defaultValue: [String]()) {
                        orientationToggles(for: family.id)
                    }
                }
            } header: {
                Label("Interface Orientations", systemImage: "crop.rotate")
            } footer: {
                Text("Supported orientations per device family, stored as the real UIInterfaceOrientation strings.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func orientationToggles(for key: String) -> some View {
        let current = (editor.entries[key] as? [Any])?.compactMap { $0 as? String } ?? []
        ForEach(orientations) { orientation in
            Toggle(isOn: Binding(
                get: { current.contains(orientation.id) },
                set: { isOn in
                    var updated = current
                    if isOn {
                        if !updated.contains(orientation.id) { updated.append(orientation.id) }
                    } else {
                        updated.removeAll { $0 == orientation.id }
                    }
                    if updated.isEmpty {
                        editor.remove(key: key)
                    } else {
                        editor.set(key: key, value: updated)
                    }
                }
            )) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(orientation.name)
                        Text(orientation.id)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: orientation.symbol)
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                }
            }
            .toggleStyle(.switch)
            .tint(.gray)
        }
    }
}

// MARK: - 4. App Transport Security

struct ATSSectionView: View {
    let editor: InfoPlistEditor

    var body: some View {
        Form {
            Section {
                PlistOptionalKeyBlock(
                    editor: editor,
                    key: "NSAppTransportSecurity",
                    title: "App Transport Security",
                    symbol: "lock.shield",
                    defaultValue: [String: Any]()
                ) {
                    atsContent
                }
            } footer: {
                Text("App Transport Security enforces secure connections. Prefer narrow per-domain exceptions over disabling ATS globally.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var atsContent: some View {
        let ats = Binding<[String: Any]>(
            get: { editor.entries["NSAppTransportSecurity"] as? [String: Any] ?? [:] },
            set: { editor.set(key: "NSAppTransportSecurity", value: $0) }
        )
        atsToggleRow(
            ats: ats,
            key: "NSAllowsArbitraryLoads",
            title: "Allow Arbitrary Loads",
            symbol: "lock.open",
            description: "Disables ATS for all connections. Requires justification during App Review."
        )
        atsToggleRow(
            ats: ats,
            key: "NSAllowsArbitraryLoadsInWebContent",
            title: "Allow Arbitrary Loads in Web Content",
            symbol: "safari",
            description: "Relaxes ATS inside web views while keeping it enforced elsewhere."
        )
        atsToggleRow(
            ats: ats,
            key: "NSAllowsLocalNetworking",
            title: "Allow Local Networking",
            symbol: "network",
            description: "Allows insecure loads for local hosts and Bonjour services."
        )
        ATSExceptionDomainsView(ats: ats)
    }

    @ViewBuilder
    private func atsToggleRow(ats: Binding<[String: Any]>, key: String, title: String, symbol: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: plistDictBool(ats, key: key)) {
                Label(title, systemImage: symbol)
            }
            .toggleStyle(.switch)
            .tint(.gray)
            Text(key)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct ATSExceptionDomainsView: View {
    @Binding var ats: [String: Any]
    @State private var newDomain = ""

    private var domains: Binding<[String: Any]> {
        Binding(
            get: { (ats["NSExceptionDomains"] as? [String: Any]) ?? [:] },
            set: { var a = ats; a["NSExceptionDomains"] = $0; ats = a }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Exception Domains", systemImage: "globe")
            Text("NSExceptionDomains")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            ForEach(domains.wrappedValue.keys.sorted(), id: \.self) { domain in
                ATSExceptionDomainRow(domains: domains, domain: domain)
            }
            HStack {
                TextField("Add domain, e.g. example.com", text: $newDomain)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Button("Add Domain") {
                    let trimmed = newDomain.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    var d = domains.wrappedValue
                    if d[trimmed] == nil { d[trimmed] = [String: Any]() }
                    domains.wrappedValue = d
                    newDomain = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(newDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ATSExceptionDomainRow: View {
    @Binding var domains: [String: Any]
    let domain: String

    private static let tlsVersions = ["TLSv1.0", "TLSv1.1", "TLSv1.2", "TLSv1.3"]

    private var config: Binding<[String: Any]> {
        Binding(
            get: { (domains[domain] as? [String: Any]) ?? [:] },
            set: { var d = domains; d[domain] = $0; domains = d }
        )
    }

    var body: some View {
        let cfg = config
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(domain, systemImage: "globe")
                    .font(.body.weight(.medium))
                Spacer()
                Button {
                    domains.removeValue(forKey: domain)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove domain")
            }
            exceptionToggle(config: cfg, key: "NSTemporaryExceptionAllowsInsecureHTTPLoads", title: "Allow Insecure HTTP Loads")
            exceptionToggle(config: cfg, key: "NSIncludesSubdomains", title: "Include Subdomains")
            exceptionToggle(config: cfg, key: "NSRequiresForwardSecrecy", title: "Require Forward Secrecy")
            HStack {
                Label("Minimum TLS Version", systemImage: "lock")
                Spacer()
                if cfg.wrappedValue["NSTemporaryExceptionMinimumTLSVersion"] == nil {
                    Button("Set") {
                        var c = cfg.wrappedValue
                        c["NSTemporaryExceptionMinimumTLSVersion"] = "TLSv1.2"
                        cfg.wrappedValue = c
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Picker("Minimum TLS Version", selection: Binding(
                        get: { cfg.wrappedValue["NSTemporaryExceptionMinimumTLSVersion"] as? String ?? "TLSv1.2" },
                        set: { var c = cfg.wrappedValue; c["NSTemporaryExceptionMinimumTLSVersion"] = $0; cfg.wrappedValue = c }
                    )) {
                        ForEach(Self.tlsVersions, id: \.self) { version in
                            Text(version).tag(version)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    Button {
                        var c = cfg.wrappedValue
                        c.removeValue(forKey: "NSTemporaryExceptionMinimumTLSVersion")
                        cfg.wrappedValue = c
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Unset TLS version")
                }
            }
            Text("NSTemporaryExceptionMinimumTLSVersion")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func exceptionToggle(config: Binding<[String: Any]>, key: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: plistDictBool(config, key: key))
                .toggleStyle(.switch)
                .tint(.gray)
            Text(key)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 5. URL Types

struct URLTypesSectionView: View {
    let editor: InfoPlistEditor

    var body: some View {
        Form {
            PlistDictArrayEditor(
                editor: editor,
                key: "CFBundleURLTypes",
                title: "URL Types",
                symbol: "link",
                itemName: "URL Type",
                newItem: ["CFBundleURLName": "", "CFBundleURLSchemes": [String]()],
                footer: "URL types register custom schemes your app can open, e.g. myapp://."
            ) { items, index in
                PlistDictRowCard(items: items, index: index, title: "URL Type \(index + 1)", symbol: "link") { entry in
                    PlistLabeledRow(symbol: "tag", title: "URL Name", subtitle: "CFBundleURLName") {
                        PlistCommitTextField(value: nestedPlistString(entry, key: "CFBundleURLName"), prompt: "e.g. com.example.myapp")
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Label("URL Schemes", systemImage: "list.bullet")
                        Text("CFBundleURLSchemes")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        PlistStringListEditor(
                            items: nestedPlistStringArray(entry, key: "CFBundleURLSchemes"),
                            prompt: "Scheme, e.g. myapp",
                            addLabel: "Add Scheme"
                        )
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 6. Document Types

struct DocumentTypesSectionView: View {
    let editor: InfoPlistEditor

    private let roles = ["Editor", "Viewer", "Shell", "QLGenerator", "None"]

    var body: some View {
        Form {
            PlistDictArrayEditor(
                editor: editor,
                key: "CFBundleDocumentTypes",
                title: "Document Types",
                symbol: "doc",
                itemName: "Document Type",
                newItem: ["CFBundleTypeName": ""],
                footer: "Declares the document types your app can open, with roles, content types, and icons."
            ) { items, index in
                PlistDictRowCard(items: items, index: index, title: "Document Type \(index + 1)", symbol: "doc") { entry in
                    self.documentFields(entry: entry)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func documentFields(entry: Binding<[String: Any]>) -> some View {
        PlistLabeledRow(symbol: "textformat", title: "Name", subtitle: "CFBundleTypeName") {
            PlistCommitTextField(value: nestedPlistString(entry, key: "CFBundleTypeName"), prompt: "Document type name")
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
        }
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Role", systemImage: "figure.stand")
                Spacer()
                Picker("Role", selection: Binding<String?>(
                    get: { entry.wrappedValue["CFBundleTypeRole"] as? String },
                    set: {
                        var d = entry.wrappedValue
                        if let v = $0 { d["CFBundleTypeRole"] = v } else { d.removeValue(forKey: "CFBundleTypeRole") }
                        entry.wrappedValue = d
                    }
                )) {
                    Text("Not Set").tag(nil as String?)
                    ForEach(roles, id: \.self) { role in
                        Text(role).tag(role as String?)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            Text("CFBundleTypeRole")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        VStack(alignment: .leading, spacing: 4) {
            Label("Content Types", systemImage: "list.bullet")
            Text("LSItemContentTypes")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            PlistStringListEditor(
                items: nestedPlistStringArray(entry, key: "LSItemContentTypes"),
                prompt: "UTI, e.g. public.plain-text",
                addLabel: "Add Content Type"
            )
        }
        VStack(alignment: .leading, spacing: 4) {
            Label("Icon Files", systemImage: "photo")
            Text("CFBundleTypeIconFiles")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            PlistStringListEditor(
                items: nestedPlistStringArray(entry, key: "CFBundleTypeIconFiles"),
                prompt: "Icon file name",
                addLabel: "Add Icon File"
            )
        }
    }
}

// MARK: - 7. Exported / Imported Type Declarations

struct TypeDeclarationsSectionView: View {
    let editor: InfoPlistEditor

    var body: some View {
        Form {
            PlistDictArrayEditor(
                editor: editor,
                key: "UTExportedTypeDeclarations",
                title: "Exported Type Declarations",
                symbol: "square.and.arrow.up",
                itemName: "Exported Type",
                newItem: ["UTTypeIdentifier": "", "UTTypeDescription": "", "UTTypeConformsTo": [String]()],
                footer: "Custom uniform type identifiers owned and defined by this app."
            ) { items, index in
                PlistDictRowCard(items: items, index: index, title: "Exported Type \(index + 1)", symbol: "square.and.arrow.up") { entry in
                    self.declarationFields(entry: entry)
                }
            }
            PlistDictArrayEditor(
                editor: editor,
                key: "UTImportedTypeDeclarations",
                title: "Imported Type Declarations",
                symbol: "square.and.arrow.down",
                itemName: "Imported Type",
                newItem: ["UTTypeIdentifier": "", "UTTypeDescription": "", "UTTypeConformsTo": [String]()],
                footer: "Third-party uniform type identifiers this app understands."
            ) { items, index in
                PlistDictRowCard(items: items, index: index, title: "Imported Type \(index + 1)", symbol: "square.and.arrow.down") { entry in
                    self.declarationFields(entry: entry)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func declarationFields(entry: Binding<[String: Any]>) -> some View {
        PlistLabeledRow(symbol: "tag", title: "Identifier", subtitle: "UTTypeIdentifier") {
            PlistCommitTextField(value: nestedPlistString(entry, key: "UTTypeIdentifier"), prompt: "e.g. com.example.myformat")
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
        }
        PlistLabeledRow(symbol: "textformat", title: "Description", subtitle: "UTTypeDescription") {
            PlistCommitTextField(value: nestedPlistString(entry, key: "UTTypeDescription"), prompt: "Human-readable description")
                .textFieldStyle(.roundedBorder)
        }
        VStack(alignment: .leading, spacing: 4) {
            Label("Conforms To", systemImage: "list.bullet")
            Text("UTTypeConformsTo")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            PlistStringListEditor(
                items: nestedPlistStringArray(entry, key: "UTTypeConformsTo"),
                prompt: "Parent UTI, e.g. public.data",
                addLabel: "Add Parent Type"
            )
        }
    }
}

// MARK: - 8. Background Modes

struct BackgroundModesSectionView: View {
    let editor: InfoPlistEditor

    static let modes: [PlistStringOption] = [
        PlistStringOption(id: "audio", name: "Audio", description: "Continue playing or recording audio in the background.", symbol: "speaker.wave.2.fill"),
        PlistStringOption(id: "location", name: "Location", description: "Receive location updates in the background.", symbol: "location.fill"),
        PlistStringOption(id: "voip", name: "Voice over IP", description: "Handle Voice-over-IP calls in the background.", symbol: "phone.fill"),
        PlistStringOption(id: "fetch", name: "Background Fetch", description: "Periodically download small content updates.", symbol: "arrow.clockwise"),
        PlistStringOption(id: "remote-notification", name: "Remote Notifications", description: "Wake from the suspended state for push notifications.", symbol: "bell.badge.fill"),
        PlistStringOption(id: "newsstand-content", name: "Newsstand Content", description: "Download Newsstand issues in the background.", symbol: "newspaper.fill"),
        PlistStringOption(id: "external-accessory", name: "External Accessory", description: "Communicate with external accessories in the background.", symbol: "cable.connector"),
        PlistStringOption(id: "bluetooth-central", name: "Bluetooth Central", description: "Act as a Bluetooth central and scan peripherals in the background.", symbol: "bluetooth"),
        PlistStringOption(id: "bluetooth-peripheral", name: "Bluetooth Peripheral", description: "Act as a Bluetooth peripheral in the background.", symbol: "antenna.radiowaves"),
        PlistStringOption(id: "processing", name: "Background Processing", description: "Run scheduled background processing tasks.", symbol: "cpu"),
        PlistStringOption(id: "push-to-talk", name: "Push to Talk", description: "Provide push-to-talk voice communication.", symbol: "megaphone.fill"),
    ]

    var body: some View {
        Form {
            Section {
                PlistStringSetEditor(
                    editor: editor,
                    key: "UIBackgroundModes",
                    options: Self.modes,
                    removeTitle: "Remove All Background Modes"
                )
            } header: {
                Label("Background Modes", systemImage: "moon")
            } footer: {
                Text("Declares background execution modes (UIBackgroundModes). Some modes also require matching capabilities or entitlements.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 9. Required Device Capabilities

struct DeviceCapabilitiesSectionView: View {
    let editor: InfoPlistEditor

    static let capabilities: [PlistStringOption] = [
        PlistStringOption(id: "accelerometer", name: "Accelerometer", description: "Requires an accelerometer for motion input.", symbol: "move.3d"),
        PlistStringOption(id: "armv7", name: "ARMv7", description: "Requires the 32-bit ARMv7 instruction set.", symbol: "cpu"),
        PlistStringOption(id: "arm64", name: "ARM64", description: "Requires the 64-bit ARM instruction set.", symbol: "cpu.fill"),
        PlistStringOption(id: "arm64e", name: "ARM64e", description: "Requires the ARM64e architecture.", symbol: "memorychip"),
        PlistStringOption(id: "arkit", name: "ARKit", description: "Requires ARKit augmented reality support.", symbol: "arkit"),
        PlistStringOption(id: "auto-focus-camera", name: "Auto-Focus Camera", description: "Requires a camera with auto-focus.", symbol: "camera.aperture"),
        PlistStringOption(id: "bluetooth-le", name: "Bluetooth LE", description: "Requires Bluetooth Low Energy.", symbol: "bluetooth"),
        PlistStringOption(id: "camera-flash", name: "Camera Flash", description: "Requires a camera flash (LED).", symbol: "bolt.fill"),
        PlistStringOption(id: "front-facing-camera", name: "Front-Facing Camera", description: "Requires a front-facing camera.", symbol: "camera"),
        PlistStringOption(id: "gamekit", name: "Game Kit", description: "Requires GameKit / Game Center support.", symbol: "gamecontroller.fill"),
        PlistStringOption(id: "gps", name: "GPS", description: "Requires GPS hardware for fine location.", symbol: "location.fill"),
        PlistStringOption(id: "gyroscope", name: "Gyroscope", description: "Requires a gyroscope.", symbol: "rotate.3d"),
        PlistStringOption(id: "healthkit", name: "HealthKit", description: "Requires HealthKit support.", symbol: "heart.fill"),
        PlistStringOption(id: "location-services", name: "Location Services", description: "Requires system location services.", symbol: "location"),
        PlistStringOption(id: "magnetometer", name: "Magnetometer", description: "Requires a magnetometer (digital compass).", symbol: "location.north"),
        PlistStringOption(id: "metal", name: "Metal", description: "Requires Metal graphics support.", symbol: "display"),
        PlistStringOption(id: "microphone", name: "Microphone", description: "Requires a built-in microphone.", symbol: "mic.fill"),
        PlistStringOption(id: "nfc", name: "NFC", description: "Requires Near Field Communication hardware.", symbol: "antenna.radiowaves"),
        PlistStringOption(id: "opengles-1", name: "OpenGL ES 1", description: "Requires OpenGL ES 1.1.", symbol: "cube"),
        PlistStringOption(id: "opengles-2", name: "OpenGL ES 2", description: "Requires OpenGL ES 2.0.", symbol: "cube.fill"),
        PlistStringOption(id: "opengles-3", name: "OpenGL ES 3", description: "Requires OpenGL ES 3.0.", symbol: "cube.transparent"),
        PlistStringOption(id: "peer-peer", name: "Peer-to-Peer", description: "Requires GameKit peer-to-peer networking.", symbol: "personalhotspot"),
        PlistStringOption(id: "sms", name: "SMS", description: "Requires SMS messaging capability.", symbol: "message.fill"),
        PlistStringOption(id: "still-camera", name: "Still Camera", description: "Requires a still camera.", symbol: "photo"),
        PlistStringOption(id: "telephony", name: "Telephony", description: "Requires phone call capability.", symbol: "phone.fill"),
        PlistStringOption(id: "video-camera", name: "Video Camera", description: "Requires a video camera.", symbol: "video.fill"),
        PlistStringOption(id: "wifi", name: "Wi-Fi", description: "Requires Wi-Fi networking.", symbol: "wifi"),
    ]

    var body: some View {
        Form {
            Section {
                if let dict = editor.entries["UIRequiredDeviceCapabilities"] as? [String: Any] {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Dictionary Form Detected", systemImage: "curlybraces")
                            .font(.body.weight(.medium))
                        Text("UIRequiredDeviceCapabilities is currently stored as a dictionary. This editor manages the array form.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Convert to Array Form") {
                            let array = dict.compactMap { (key, value) -> String? in
                                (value as? Bool) == true ? key : nil
                            }.sorted()
                            editor.set(key: "UIRequiredDeviceCapabilities", value: array)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Keeps capabilities set to true, drops the rest")
                    }
                    .padding(.vertical, 4)
                } else {
                    PlistStringSetEditor(
                        editor: editor,
                        key: "UIRequiredDeviceCapabilities",
                        options: Self.capabilities,
                        removeTitle: "Remove All Capabilities"
                    )
                }
            } header: {
                Label("Required Device Capabilities", systemImage: "cpu")
            } footer: {
                Text("Limits installation to devices with these capabilities. The App Store uses this list to filter supported devices.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 10. Privacy Usage Descriptions

struct PrivacySectionView: View {
    let editor: InfoPlistEditor

    private var groupedKeys: [(category: String, items: [InfoPlistNSString])] {
        var groups: [(String, [InfoPlistNSString])] = []
        for meta in InfoPlistNSStrings.all {
            if let index = groups.firstIndex(where: { $0.0 == meta.category }) {
                groups[index].1.append(meta)
            } else {
                groups.append((meta.category, [meta]))
            }
        }
        return groups
    }

    var body: some View {
        Form {
            ForEach(groupedKeys, id: \.0) { group in
                Section {
                    ForEach(group.1) { meta in
                        PrivacyKeyRow(editor: editor, meta: meta)
                    }
                } header: {
                    Label(group.0, systemImage: "hand.raised")
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct PrivacyKeyRow: View {
    let editor: InfoPlistEditor
    let meta: InfoPlistNSString

    var body: some View {
        let present = editor.entries[meta.key] != nil
        let current = editor.entries[meta.key] as? String ?? ""
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(meta.name)
                    .font(.body.weight(.medium))
            } icon: {
                Image(systemName: meta.sfSymbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
            }
            Text(meta.key)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                PlistCommitTextField(value: plistTopLevelString(editor, key: meta.key), prompt: meta.name)
                    .textFieldStyle(.roundedBorder)
                PlistRemoveKeyButton(editor: editor, key: meta.key)
            }
            Text(meta.description)
                .font(.caption)
                .foregroundStyle(.secondary)
            if present, let issue = editor.validatePrivacyKeys()[meta.key] {
                PlistValidationNote(message: issue)
            }
            if !meta.recommendedWording.isEmpty, current != meta.recommendedWording {
                Button("Use Recommended Wording") {
                    editor.set(key: meta.key, value: meta.recommendedWording)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(meta.recommendedWording)
            }
        }
        .padding(.vertical, 4)
    }
}
