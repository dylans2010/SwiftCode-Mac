import SwiftUI

struct DevToolsMainView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    @AppStorage("com.swiftcode.devtools.favorites") private var favoriteToolNames: String = ""
    @AppStorage("com.swiftcode.devtools.recents") private var recentToolNames: String = ""

    struct DevTool: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let description: String
        let icon: String
        let category: String
        let destination: AnyView

        static func == (lhs: DevTool, rhs: DevTool) -> Bool {
            lhs.name == rhs.name
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(name)
        }
    }

    private var tools: [DevTool] {
        [
            // Diagnostics & Logs
            DevTool(name: "Entitlement Inspector", description: "Verify active app capability settings", icon: "shield", category: "Diagnostics", destination: AnyView(EntitlementInspectorView())),
            DevTool(name: "Provisioning Profile Viewer", description: "Inspect mobile provisioning profiles", icon: "key", category: "Diagnostics", destination: AnyView(ProvisioningProfileViewerView())),
            DevTool(name: "Signing Inspector", description: "Validate certificates, identities, and signatures", icon: "lock.shield", category: "Diagnostics", destination: AnyView(SigningInspectorView())),
            DevTool(name: "Crash Log Viewer", description: "De-symbolicate and view iOS/macOS crash logs", icon: "ant", category: "Diagnostics", destination: AnyView(CrashLogViewerView())),
            DevTool(name: "Console Viewer", description: "Real-time NSLog and stdout console viewer", icon: "terminal", category: "Diagnostics", destination: AnyView(ConsoleViewerView())),
            DevTool(name: "Device Log Viewer", description: "Inspect logs from connected simulators/devices", icon: "macbook.and.iphone", category: "Diagnostics", destination: AnyView(DeviceLogViewerView())),
            DevTool(name: "Code Metrics", description: "Calculate Lines of Code and file statistics", icon: "chart.xyaxis.line", category: "Diagnostics", destination: AnyView(CodeMetricsView())),
            DevTool(name: "Duplicate File Detector", description: "Identify redundant resource/source files", icon: "doc.on.doc", category: "Diagnostics", destination: AnyView(DuplicateFileDetectorView())),

            // Core Xcode & Build System
            DevTool(name: "Bundle Identifier Editor", description: "Read and rewrite project bundle ids", icon: "barcode", category: "Build System", destination: AnyView(BundleIdentifierEditorView())),
            DevTool(name: "Build Settings Explorer", description: "Explore PBX target settings", icon: "gearshape.2", category: "Build System", destination: AnyView(BuildSettingsExplorerView())),
            DevTool(name: "XCConfig Viewer", description: "Inspect active project .xcconfig configurations", icon: "doc.plaintext", category: "Build System", destination: AnyView(XCConfigViewerView())),
            DevTool(name: "Symbol Browser", description: "Browse classes, structs, and methods in project", icon: "list.bullet.indent", category: "Build System", destination: AnyView(SymbolBrowserView())),
            DevTool(name: "Asset Catalog Browser", description: "View app assets, images, and colors", icon: "photo.stack", category: "Build System", destination: AnyView(AssetCatalogBrowserView())),
            DevTool(name: "Localization Explorer", description: "Inspect localized .strings catalog files", icon: "globe", category: "Build System", destination: AnyView(LocalizationExplorerView())),
            DevTool(name: "Info.plist Editor", description: "Edit targets Info.plist configurations", icon: "list.bullet.rectangle", category: "Build System", destination: AnyView(InfoPlistEditorView())),
            DevTool(name: "Package Dependency Explorer", description: "Inspect project framework packages", icon: "shippingbox", category: "Build System", destination: AnyView(PackageDependencyExplorerView())),
            DevTool(name: "Swift Package Manager Inspector", description: "SPM diagnostics and cached package details", icon: "shippingbox.circle", category: "Build System", destination: AnyView(SPMInspectorView())),
            DevTool(name: "Binary Size Analyzer", description: "Explore application bundle sizes and footprints", icon: "chart.pie", category: "Build System", destination: AnyView(BinarySizeAnalyzerView())),
            DevTool(name: "Framework Inspector", description: "Review linked dynamically imported modules", icon: "square.stack.3d.up", category: "Build System", destination: AnyView(FrameworkInspectorView())),
            DevTool(name: "Simulator Manager", description: "Launch and manage iOS/watchOS simulators", icon: "iphone.circle", category: "Build System", destination: AnyView(SimulatorManagerView())),
            DevTool(name: "Certificate Manager", description: "Verify active Developer identities in Keychain", icon: "checkmark.seal", category: "Build System", destination: AnyView(CertificateManagerView())),
            DevTool(name: "Keychain Inspector", description: "Safely read developer environment Keychain entries", icon: "key.fill", category: "Build System", destination: AnyView(KeychainInspectorView())),
            DevTool(name: "Build Cache Manager", description: "Review and clear local build caches", icon: "folder", category: "Build System", destination: AnyView(BuildCacheManagerView())),
            DevTool(name: "Derived Data Manager", description: "Scan and clean project DerivedData directories", icon: "trash", category: "Build System", destination: AnyView(DerivedDataManagerView())),
            DevTool(name: "Environment Variable Editor", description: "Edit build process environment variables", icon: "chevron.left.forwardslash.chevron.right", category: "Build System", destination: AnyView(EnvVarEditorView())),

            // Legacy & Utilities
            DevTool(name: "HTTP Status", description: "Reference for HTTP response codes", icon: "network", category: "Utilities", destination: AnyView(HTTPStatusView())),
            DevTool(name: "API Tester", description: "Send REST API requests", icon: "bolt.fill", category: "Utilities", destination: AnyView(APITesterView())),
            DevTool(name: "Webhook Tester", description: "Test incoming webhooks", icon: "link", category: "Utilities", destination: AnyView(WebhookTesterView())),
            DevTool(name: "Git Cheatsheet", description: "Common Git commands", icon: "terminal", category: "Utilities", destination: AnyView(GitCheatsheetView())),
            DevTool(name: "Port Lookup", description: "Common network ports", icon: "number", category: "Utilities", destination: AnyView(PortLookupView())),
            DevTool(name: "JWT Decoder", description: "Decode JSON Web Tokens", icon: "lock.shield", category: "Utilities", destination: AnyView(JWTDecoderView())),
            DevTool(name: "Hash Generator", description: "MD5, SHA1, SHA256, SHA512", icon: "number.square", category: "Utilities", destination: AnyView(HashGeneratorView())),
            DevTool(name: "Certificate Decoder", description: "Decode PEM certificates", icon: "doc.plaintext", category: "Utilities", destination: AnyView(CertificateDecoderView())),
            DevTool(name: "JSON Formatter", description: "Pretty print or minify JSON", icon: "curlybraces", category: "Utilities", destination: AnyView(JSONFormatterView())),
            DevTool(name: "Base64 Converter", description: "Encode/Decode Base64", icon: "arrow.left.and.right.square", category: "Utilities", destination: AnyView(Base64ConverterView())),
            DevTool(name: "URL Encoder", description: "Percent encoding for URLs", icon: "link.badge.plus", category: "Utilities", destination: AnyView(URLEncoderView())),
            DevTool(name: "Timestamp Converter", description: "Unix epoch to date", icon: "clock", category: "Utilities", destination: AnyView(TimestampConverterView())),
            DevTool(name: "UUID Generator", description: "Generate random UUIDs", icon: "barcode", category: "Utilities", destination: AnyView(UUIDGeneratorView())),
            DevTool(name: "Lorem Ipsum", description: "Placeholder text generator", icon: "text.alignleft", category: "Utilities", destination: AnyView(LoremIpsumGeneratorView())),
            DevTool(name: "Cron Parser", description: "Human readable cron", icon: "calendar.badge.clock", category: "Utilities", destination: AnyView(CronParserView())),
            DevTool(name: "Color Converter", description: "Hex, RGB, HSL", icon: "paintpalette", category: "Utilities", destination: AnyView(ColorConverterView())),
            DevTool(name: "SQL Formatter", description: "Format SQL queries", icon: "database", category: "Utilities", destination: AnyView(SQLFormatterView())),
            DevTool(name: "XML Formatter", description: "Format XML data", icon: "chevron.left.forwardslash.chevron.right", category: "Utilities", destination: AnyView(XMLFormatterView())),
            DevTool(name: "YAML Converter", description: "JSON to YAML converter", icon: "doc.text", category: "Utilities", destination: AnyView(YAMLConverterView())),
            DevTool(name: "Markdown Preview", description: "Live markdown preview", icon: "doc.richtext", category: "Utilities", destination: AnyView(MarkdownPreviewerView())),
            DevTool(name: "Regex Tester", description: "Test regular expressions", icon: "checklist", category: "Utilities", destination: AnyView(RegexTesterView())),
            DevTool(name: "HTML Entities", description: "Encode/Decode HTML entities", icon: "tag", category: "Utilities", destination: AnyView(HTMLEntityConverterView())),
            DevTool(name: "Case Converter", description: "camelCase, snake_case, etc.", icon: "textformat", category: "Utilities", destination: AnyView(CaseConverterView())),
            DevTool(name: "Diff Checker", description: "Compare two text files", icon: "doc.on.doc", category: "Utilities", destination: AnyView(DiffCheckerView())),
            DevTool(name: "QR Code Gen", description: "Generate QR codes", icon: "qrcode", category: "Utilities", destination: AnyView(QRCodeGeneratorView())),
            DevTool(name: "Image Base64", description: "Image to Base64 data", icon: "photo", category: "Utilities", destination: AnyView(ImageBase64View())),
            DevTool(name: "CSS Units", description: "PX to REM/EM converter", icon: "ruler", category: "Utilities", destination: AnyView(CSSUnitConverterView())),
            DevTool(name: "JS Minifier", description: "Minify JavaScript code", icon: "script", category: "Utilities", destination: AnyView(JSMinifierView())),
            DevTool(name: "DNS Lookup", description: "Query DNS records", icon: "magnifyingglass", category: "Utilities", destination: AnyView(DNSLookupView())),
            DevTool(name: "IP Address Info", description: "GeoIP and network info", icon: "info.circle", category: "Utilities", destination: AnyView(IPAddressInfoView())),
            DevTool(name: "Password Gen", description: "Secure password generator", icon: "key", category: "Utilities", destination: AnyView(PasswordGeneratorView())),
            DevTool(name: "Text Counter", description: "Words, chars, lines count", icon: "list.number", category: "Utilities", destination: AnyView(TextCounterView())),
            DevTool(name: "ASCII Art", description: "Text to ASCII art", icon: "textformat.size", category: "Utilities", destination: AnyView(ASCIIArtGeneratorView())),
            DevTool(name: "Binary Converter", description: "Decimal to Binary", icon: "01.square", category: "Utilities", destination: AnyView(BinaryConverterView())),
            DevTool(name: "Hex Converter", description: "Hex to Decimal", icon: "h.square", category: "Utilities", destination: AnyView(HexDecimalConverterView())),
            DevTool(name: "HMAC Generator", description: "Hash-based message auth", icon: "shield", category: "Utilities", destination: AnyView(HMACGeneratorView())),
            DevTool(name: "RSA Key Gen", description: "Generate RSA key pairs", icon: "key.fill", category: "Utilities", destination: AnyView(RSAKeyGeneratorView())),
            DevTool(name: "SSL Checker", description: "Verify SSL certificates", icon: "checkmark.seal", category: "Utilities", destination: AnyView(SSLCheckerView())),
            DevTool(name: "Whois Lookup", description: "Domain registration info", icon: "person.text.rectangle", category: "Utilities", destination: AnyView(WhoisLookupView())),
            DevTool(name: "Device Info", description: "System and hardware info", icon: "desktopcomputer", category: "Utilities", destination: AnyView(DeviceInfoView())),
            DevTool(name: "Property List Viewer", description: "Inspect standard XML property lists", icon: "list.bullet.rectangle", category: "Utilities", destination: AnyView(PlistViewerView())),
            DevTool(name: "Color Inspector", description: "Color spectrum and conversions", icon: "paintpalette.fill", category: "Utilities", destination: AnyView(ColorInspectorView())),
            DevTool(name: "Font Browser", description: "Browse and preview native system fonts", icon: "textformat", category: "Utilities", destination: AnyView(FontBrowserView())),
            DevTool(name: "Image Metadata Viewer", description: "Read resolution and EXIF fields", icon: "photo.fill", category: "Utilities", destination: AnyView(ImageMetadataViewerView()))
        ]
    }

    private var favorites: Set<String> {
        Set(favoriteToolNames.split(separator: ",").map(String.init))
    }

    private var recents: [String] {
        recentToolNames.split(separator: ",").map(String.init)
    }

    var filteredTools: [DevTool] {
        let list = tools
        if searchText.isEmpty {
            return list
        } else {
            return list.filter {
                $0.name.lowercased().contains(searchText.lowercased()) ||
                $0.description.lowercased().contains(searchText.lowercased()) ||
                $0.category.lowercased().contains(searchText.lowercased())
            }
        }
    }

    private var categories: [String] {
        Array(Set(tools.map(\.category))).sorted()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // Search Bar Dashboard Header
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search developer tools, categories, diagnostics...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)

                    // Favorites Section
                    if !favorites.isEmpty && searchText.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label("Favorite Tools", systemImage: "star.fill")
                                        .font(.headline)
                                        .foregroundColor(.orange)
                                    Spacer()
                                }

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 12) {
                                    ForEach(tools.filter { favorites.contains($0.name) }) { tool in
                                        toolCard(for: tool)
                                    }
                                }
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                        .padding(.horizontal)
                    }

                    // Recents Section
                    if !recents.isEmpty && searchText.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label("Recent Tools", systemImage: "clock.fill")
                                        .font(.headline)
                                        .foregroundColor(.blue)
                                    Spacer()
                                }

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 12) {
                                    ForEach(recents.compactMap { name in tools.first(where: { $0.name == name }) }) { tool in
                                        toolCard(for: tool)
                                    }
                                }
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                        .padding(.horizontal)
                    }

                    // Categories Grid
                    ForEach(categories, id: \.self) { category in
                        let catTools = filteredTools.filter { $0.category == category }
                        if !catTools.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(category)
                                    .font(.title3.bold())
                                    .padding(.horizontal)

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 16) {
                                    ForEach(catTools) { tool in
                                        toolCard(for: tool)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Developer Tools Hub")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func toolCard(for tool: DevTool) -> some View {
        NavigationLink(destination: tool.destination.onAppear { recordRecent(tool.name) }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: tool.icon)
                        .font(.title2)
                        .foregroundColor(.orange)
                        .frame(width: 32, height: 32)
                        .background(Color.orange.opacity(0.12))
                        .cornerRadius(6)

                    Spacer()

                    Button {
                        toggleFavorite(tool.name)
                    } label: {
                        Image(systemName: favorites.contains(tool.name) ? "star.fill" : "star")
                            .foregroundColor(favorites.contains(tool.name) ? .orange : .secondary)
                    }
                    .buttonStyle(.plain)
                }

                Text(tool.name)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundColor(.primary)

                Text(tool.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 32, alignment: .top)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func toggleFavorite(_ name: String) {
        var favs = favorites
        if favs.contains(name) {
            favs.remove(name)
        } else {
            favs.insert(name)
        }
        favoriteToolNames = favs.joined(separator: ",")
    }

    private func recordRecent(_ name: String) {
        var list = recents.filter { $0 != name }
        list.insert(name, at: 0)
        // Keep up to 6 recents
        let trimmed = Array(list.prefix(6))
        recentToolNames = trimmed.joined(separator: ",")
    }
}
