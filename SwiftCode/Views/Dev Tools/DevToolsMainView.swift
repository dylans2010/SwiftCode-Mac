import SwiftUI

struct DevToolsMainView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedCategory: ToolCategory = .network

    @State private var favoriteToolNames: Set<String> = []
    @State private var recentToolNames: [String] = []

    enum ToolCategory: String, CaseIterable, Identifiable {
        case favorites = "Favorites"
        case recents = "Recents"
        case network = "Network & Web"
        case security = "Security & Keys"
        case generators = "Code Generators"
        case converters = "Data Formatters & Converters"
        case design = "Design & Math"
        case text = "Text Utilities"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .favorites: return "star.fill"
            case .recents: return "clock.fill"
            case .network: return "network"
            case .security: return "lock.shield"
            case .generators: return "swift"
            case .converters: return "curlybraces"
            case .design: return "paintpalette"
            case .text: return "textformat"
            }
        }
    }

    struct DevTool: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let description: String
        let icon: String
        let category: ToolCategory
        let destination: AnyView

        func hash(into hasher: inout Hasher) {
            hasher.combine(name)
        }

        static func == (lhs: DevTool, rhs: DevTool) -> Bool {
            lhs.name == rhs.name
        }
    }

    // Comprehensive list of Dev Tools mapped to categories
    var tools: [DevTool] {
        [
            // Network & Web
            DevTool(name: "HTTP Status", description: "Reference for HTTP response codes", icon: "network", category: .network, destination: AnyView(HTTPStatusView())),
            DevTool(name: "API Tester", description: "Send REST API requests", icon: "bolt.fill", category: .network, destination: AnyView(APITesterView())),
            DevTool(name: "Webhook Tester", description: "Test incoming webhooks", icon: "link", category: .network, destination: AnyView(WebhookTesterView())),
            DevTool(name: "Port Lookup", description: "Common network ports", icon: "number", category: .network, destination: AnyView(PortLookupView())),
            DevTool(name: "DNS Lookup", description: "Query DNS records", icon: "magnifyingglass", category: .network, destination: AnyView(DNSLookupView())),
            DevTool(name: "IP Address Info", description: "GeoIP and network info", icon: "info.circle", category: .network, destination: AnyView(IPAddressInfoView())),
            DevTool(name: "Subnet Calc", description: "IP range and mask calculator", icon: "network", category: .network, destination: AnyView(SubnetCalculatorView())),
            DevTool(name: "UA Parser", description: "Extract info from User Agent", icon: "person.text.rectangle", category: .network, destination: AnyView(UserAgentParserView())),
            DevTool(name: "MIME Lookup", description: "MIME type by extension", icon: "doc.questionmark", category: .network, destination: AnyView(MIMETypeLookupView())),
            DevTool(name: "Header Parser", description: "Parse HTTP headers", icon: "list.bullet", category: .network, destination: AnyView(HTTPHeaderParserView())),
            DevTool(name: "Cookie Parser", description: "Parse cookie strings", icon: "circle.grid.2x2", category: .network, destination: AnyView(CookieParserView())),
            DevTool(name: "Port Scanner", description: "Scan common ports", icon: "magnifyingglass", category: .network, destination: AnyView(PortScannerView())),

            // Security & Keys
            DevTool(name: "JWT Decoder", description: "Decode JSON Web Tokens", icon: "lock.shield", category: .security, destination: AnyView(JWTDecoderView())),
            DevTool(name: "Hash Generator", description: "MD5, SHA1, SHA256, SHA512", icon: "number.square", category: .security, destination: AnyView(HashGeneratorView())),
            DevTool(name: "Certificate Decoder", description: "Decode PEM certificates", icon: "doc.plaintext", category: .security, destination: AnyView(CertificateDecoderView())),
            DevTool(name: "HMAC Generator", description: "Hash-based message auth", icon: "shield", category: .security, destination: AnyView(HMACGeneratorView())),
            DevTool(name: "RSA Key Gen", description: "Generate RSA key pairs", icon: "key.fill", category: .security, destination: AnyView(RSAKeyGeneratorView())),
            DevTool(name: "SSL Checker", description: "Verify SSL certificates", icon: "checkmark.seal", category: .security, destination: AnyView(SSLCheckerView())),
            DevTool(name: "Whois Lookup", description: "Domain registration info", icon: "person.text.rectangle", category: .security, destination: AnyView(WhoisLookupView())),
            DevTool(name: "Password Gen", description: "Secure password generator", icon: "key", category: .security, destination: AnyView(PasswordGeneratorView())),
            DevTool(name: "Password Strength", description: "Check password security", icon: "lock.shield", category: .security, destination: AnyView(PasswordStrengthMeterView())),
            DevTool(name: "Bcrypt Hash", description: "Generate Bcrypt hashes", icon: "number", category: .security, destination: AnyView(BcryptHashGeneratorView())),

            // Code Generators
            DevTool(name: "JSON to Swift", description: "Generate Swift models from JSON", icon: "swift", category: .generators, destination: AnyView(JSONToSwiftView())),
            DevTool(name: "JSON to Kotlin", description: "Generate Kotlin data classes", icon: "j.square", category: .generators, destination: AnyView(JSONToKotlinView())),
            DevTool(name: "JSON to TypeScript", description: "Generate TS interfaces", icon: "t.square", category: .generators, destination: AnyView(JSONToTSView())),
            DevTool(name: "JSON to Go", description: "Generate Go structs", icon: "g.square", category: .generators, destination: AnyView(JSONToGoView())),
            DevTool(name: "JSON to Java", description: "Generate Java classes", icon: "j.circle", category: .generators, destination: AnyView(JSONToJavaView())),
            DevTool(name: "JSON to Python", description: "Generate Python dataclasses", icon: "p.square", category: .generators, destination: AnyView(JSONToPythonView())),
            DevTool(name: "JSON to C#", description: "Generate C# classes", icon: "c.square", category: .generators, destination: AnyView(JSONToCSharpView())),
            DevTool(name: "JSON to Rust", description: "Generate Rust structs", icon: "r.square", category: .generators, destination: AnyView(JSONToRustView())),
            DevTool(name: "JSON to Dart", description: "Generate Dart classes", icon: "d.square", category: .generators, destination: AnyView(JSONToDartView())),
            DevTool(name: "JSON to PHP", description: "Generate PHP classes", icon: "p.circle", category: .generators, destination: AnyView(JSONToPHPView())),

            // Data Formatters & Converters
            DevTool(name: "JSON Formatter", description: "Pretty print or minify JSON", icon: "curlybraces", category: .converters, destination: AnyView(JSONFormatterView())),
            DevTool(name: "Base64 Converter", description: "Encode/Decode Base64", icon: "arrow.left.and.right.square", category: .converters, destination: AnyView(Base64ConverterView())),
            DevTool(name: "URL Encoder", description: "Percent encoding for URLs", icon: "link.badge.plus", category: .converters, destination: AnyView(URLEncoderView())),
            DevTool(name: "Timestamp Converter", description: "Unix epoch to date", icon: "clock", category: .converters, destination: AnyView(TimestampConverterView())),
            DevTool(name: "SQL Formatter", description: "Format SQL queries", icon: "database", category: .converters, destination: AnyView(SQLFormatterView())),
            DevTool(name: "XML Formatter", description: "Format XML data", icon: "chevron.left.forwardslash.chevron.right", category: .converters, destination: AnyView(XMLFormatterView())),
            DevTool(name: "YAML Converter", description: "JSON to YAML converter", icon: "doc.text", category: .converters, destination: AnyView(YAMLConverterView())),
            DevTool(name: "CSV to JSON", description: "Convert CSV to JSON array", icon: "tablecells", category: .converters, destination: AnyView(CSVToJSONView())),
            DevTool(name: "JSON to CSV", description: "Convert JSON array to CSV", icon: "list.bullet.rectangle", category: .converters, destination: AnyView(JSONToCSVView())),
            DevTool(name: "XML to JSON", description: "Convert XML to JSON", icon: "chevron.left.slash.chevron.right", category: .converters, destination: AnyView(XMLToJSONView())),
            DevTool(name: "TOML to JSON", description: "Convert TOML to JSON", icon: "doc.text.fill", category: .converters, destination: AnyView(TOMLToJSONView())),
            DevTool(name: "JSON to TOML", description: "Convert JSON to TOML", icon: "doc.text", category: .converters, destination: AnyView(JSONToTOMLView())),
            DevTool(name: "YAML to JSON", description: "Convert YAML to JSON", icon: "doc.plaintext", category: .converters, destination: AnyView(YAMLToJSONView())),
            DevTool(name: "Base64 File", description: "Encode/Decode files to Base64", icon: "doc.on.clipboard", category: .converters, destination: AnyView(Base64FileConverterView())),
            DevTool(name: "Gzip Compressor", description: "Compress/Decompress text", icon: "archivebox", category: .converters, destination: AnyView(GzipCompressorView())),

            // Design & Math
            DevTool(name: "Color Converter", description: "Hex, RGB, HSL", icon: "paintpalette", category: .design, destination: AnyView(ColorConverterView())),
            DevTool(name: "QR Code Gen", description: "Generate QR codes", icon: "qrcode", category: .design, destination: AnyView(QRCodeGeneratorView())),
            DevTool(name: "Image Base64", description: "Image to Base64 data", icon: "photo", category: .design, destination: AnyView(ImageBase64View())),
            DevTool(name: "CSS Units", description: "PX to REM/EM converter", icon: "ruler", category: .design, destination: AnyView(CSSUnitConverterView())),
            DevTool(name: "Cron Generator", description: "Interactive cron builder", icon: "calendar.badge.clock", category: .design, destination: AnyView(CronGeneratorView())),
            DevTool(name: "Color Gradient", description: "CSS/SwiftUI gradients", icon: "paintpalette", category: .design, destination: AnyView(ColorGradientGeneratorView())),
            DevTool(name: "CSS Shadow", description: "Box-shadow generator", icon: "square.fill.on.square.fill", category: .design, destination: AnyView(CSSShadowGeneratorView())),
            DevTool(name: "CSS Border Radius", description: "Border-radius generator", icon: "square.dashed", category: .design, destination: AnyView(CSSBorderRadiusGeneratorView())),
            DevTool(name: "Length Conv", description: "Metric/Imperial length", icon: "ruler", category: .design, destination: AnyView(LengthConverterView())),
            DevTool(name: "Weight Conv", description: "Metric/Imperial weight", icon: "scalemass", category: .design, destination: AnyView(WeightConverterView())),
            DevTool(name: "Temp Conv", description: "C, F, K temperature", icon: "thermometer.medium", category: .design, destination: AnyView(TemperatureConverterView())),
            DevTool(name: "Timezone Conv", description: "Compare timezones", icon: "globe", category: .design, destination: AnyView(TimezoneConverterView())),
            DevTool(name: "Percentage Calc", description: "Percentage math", icon: "percent", category: .design, destination: AnyView(PercentageCalculatorView())),
            DevTool(name: "Aspect Ratio", description: "Aspect ratio calculator", icon: "aspectratio", category: .design, destination: AnyView(AspectRatioCalculatorView())),

            // Text Utilities
            DevTool(name: "Git Cheatsheet", description: "Common Git commands", icon: "terminal", category: .text, destination: AnyView(GitCheatsheetView())),
            DevTool(name: "UUID Generator", description: "Generate random UUIDs", icon: "barcode", category: .text, destination: AnyView(UUIDGeneratorView())),
            DevTool(name: "Lorem Ipsum", description: "Placeholder text generator", icon: "text.alignleft", category: .text, destination: AnyView(LoremIpsumGeneratorView())),
            DevTool(name: "Cron Parser", description: "Human readable cron", icon: "calendar.badge.clock", category: .text, destination: AnyView(CronParserView())),
            DevTool(name: "Markdown Preview", description: "Live markdown preview", icon: "doc.richtext", category: .text, destination: AnyView(MarkdownPreviewerView())),
            DevTool(name: "Regex Tester", description: "Test regular expressions", icon: "checklist", category: .text, destination: AnyView(RegexTesterView())),
            DevTool(name: "HTML Entities", description: "Encode/Decode HTML entities", icon: "tag", category: .text, destination: AnyView(HTMLEntityConverterView())),
            DevTool(name: "Case Converter", description: "camelCase, snake_case, etc.", icon: "textformat", category: .text, destination: AnyView(CaseConverterView())),
            DevTool(name: "Diff Checker", description: "Compare two text files", icon: "doc.on.doc", category: .text, destination: AnyView(DiffCheckerView())),
            DevTool(name: "JS Minifier", description: "Minify JavaScript code", icon: "script", category: .text, destination: AnyView(JSMinifierView())),
            DevTool(name: "Text Counter", description: "Words, chars, lines count", icon: "list.number", category: .text, destination: AnyView(TextCounterView())),
            DevTool(name: "ASCII Art", description: "Text to ASCII art", icon: "textformat.size", category: .text, destination: AnyView(ASCIIArtGeneratorView())),
            DevTool(name: "Binary Converter", description: "Decimal to Binary", icon: "01.square", category: .text, destination: AnyView(BinaryConverterView())),
            DevTool(name: "Hex Converter", description: "Hex to Decimal", icon: "h.square", category: .text, destination: AnyView(HexDecimalConverterView())),
            DevTool(name: "Device Info", description: "System and hardware info", icon: "desktopcomputer", category: .text, destination: AnyView(DeviceInfoView())),
            DevTool(name: "JSON Schema Gen", description: "Generate JSON Schema from JSON", icon: "schema", category: .text, destination: AnyView(JSONSchemaGeneratorView())),
            DevTool(name: "String Escaper", description: "Escape/Unescape strings", icon: "escape", category: .text, destination: AnyView(StringEscaperView())),
            DevTool(name: "Line Remover", description: "Remove empty/duplicate lines", icon: "line.horizontal.3.decrease", category: .text, destination: AnyView(TextLineRemoverView())),
            DevTool(name: "Text Deduplicator", description: "Remove duplicate words/lines", icon: "doc.on.doc", category: .text, destination: AnyView(TextDeduplicatorView())),
            DevTool(name: "Random String", description: "Generate random strings", icon: "dice", category: .text, destination: AnyView(RandomStringGeneratorView())),
            DevTool(name: "URL Slug Gen", description: "Generate URL-friendly slugs", icon: "link", category: .text, destination: AnyView(URLSlugGeneratorView())),
            DevTool(name: "HTML Minifier", description: "Minify HTML code", icon: "chevron.left.forwardslash.chevron.right", category: .text, destination: AnyView(HTMLMinifierView())),
            DevTool(name: "CSS Minifier", description: "Minify CSS code", icon: "paintbrush", category: .text, destination: AnyView(CSSMinifierView())),
            DevTool(name: "SVG Minifier", description: "Minify SVG code", icon: "square.stack.3d.down.right", category: .text, destination: AnyView(SVGMinifierView())),
            DevTool(name: "URL Decomposer", description: "Break down URL parts", icon: "link.badge.plus", category: .text, destination: AnyView(URLDecomposerView())),
            DevTool(name: "Case Swapper", description: "Toggle case of text", icon: "textformat.size", category: .text, destination: AnyView(TextCaseSwapperView())),
            DevTool(name: "Length Counter", description: "Count chars, words, lines", icon: "character.cursor.ibeam", category: .text, destination: AnyView(StringLengthCounterView())),
            DevTool(name: "SemVer Checker", description: "Validate SemVer strings", icon: "tag", category: .text, destination: AnyView(SemVerCheckerView()))
        ]
    }

    var filteredTools: [DevTool] {
        var baseTools: [DevTool] = []

        if !searchText.isEmpty {
            baseTools = tools.filter {
                $0.name.lowercased().contains(searchText.lowercased()) ||
                $0.description.lowercased().contains(searchText.lowercased())
            }
        } else {
            switch selectedCategory {
            case .favorites:
                baseTools = tools.filter { favoriteToolNames.contains($0.name) }
            case .recents:
                baseTools = recentToolNames.compactMap { name in tools.first { $0.name == name } }
            default:
                baseTools = tools.filter { $0.category == selectedCategory }
            }
        }

        return baseTools.sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar List of Categories
            List(selection: $selectedCategory) {
                Section("Personal") {
                    NavigationLink(value: ToolCategory.favorites) {
                        Label(ToolCategory.favorites.rawValue, systemImage: ToolCategory.favorites.icon)
                    }
                    NavigationLink(value: ToolCategory.recents) {
                        Label(ToolCategory.recents.rawValue, systemImage: ToolCategory.recents.icon)
                    }
                }

                Section("Categories") {
                    ForEach(ToolCategory.allCases.filter { $0 != .favorites && $0 != .recents }) { cat in
                        NavigationLink(value: cat) {
                            Label(cat.rawValue, systemImage: cat.icon)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Developer Suite")
            .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
        } detail: {
            VStack(spacing: 0) {
                // Search Bar Header
                HStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search all developer tools...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))

                    Button(action: { dismiss() }) {
                        Text("Done")
                            .fontWeight(.semibold)
                    }
                    .keyboardShortcut(.cancelAction)
                }
                .padding()
                .background(.ultraThinMaterial)

                Divider()

                // Content Grid Pane
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(searchText.isEmpty ? selectedCategory.rawValue : "Search Results")
                            .font(.title2.bold())
                            .foregroundStyle(.primary)

                        if filteredTools.isEmpty {
                            ContentUnavailableView(
                                "No Tools Available",
                                systemImage: "square.grid.2x2",
                                description: Text(searchText.isEmpty ? "No tools inside this category yet." : "No tools matched your search query.")
                            )
                            .padding(.top, 40)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 16)], spacing: 16) {
                                ForEach(filteredTools) { tool in
                                    NavigationLink(destination: tool.destination.onAppear { recordUsage(of: tool) }) {
                                        VStack(alignment: .leading, spacing: 12) {
                                            HStack {
                                                Image(systemName: tool.icon)
                                                    .font(.title2)
                                                    .foregroundStyle(.orange)
                                                    .frame(width: 32, height: 32)
                                                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                                                Spacer()

                                                Button(action: { toggleFavorite(tool) }) {
                                                    Image(systemName: favoriteToolNames.contains(tool.name) ? "star.fill" : "star")
                                                        .foregroundStyle(favoriteToolNames.contains(tool.name) ? .yellow : .secondary)
                                                }
                                                .buttonStyle(.plain)
                                            }

                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(tool.name)
                                                    .font(.headline)
                                                    .foregroundStyle(.primary)
                                                Text(tool.description)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                                    .multilineTextAlignment(.leading)
                                            }
                                        }
                                        .padding()
                                        .background(.ultraThinMaterial)
                                        .cornerRadius(12)
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(24)
                }
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .frame(minWidth: 950, minHeight: 650)
        .onAppear {
            loadFavoritesAndRecents()
        }
    }

    // MARK: - Usage Helpers

    private func toggleFavorite(_ tool: DevTool) {
        if favoriteToolNames.contains(tool.name) {
            favoriteToolNames.remove(tool.name)
        } else {
            favoriteToolNames.insert(tool.name)
        }
        saveFavoritesAndRecents()
    }

    private func recordUsage(of tool: DevTool) {
        recentToolNames.removeAll { $0 == tool.name }
        recentToolNames.insert(tool.name, at: 0)
        if recentToolNames.count > 12 {
            recentToolNames.removeLast()
        }
        saveFavoritesAndRecents()
    }

    private func saveFavoritesAndRecents() {
        UserDefaults.standard.set(Array(favoriteToolNames), forKey: "com.swiftcode.devTools.favorites")
        UserDefaults.standard.set(recentToolNames, forKey: "com.swiftcode.devTools.recents")
    }

    private func loadFavoritesAndRecents() {
        if let favs = UserDefaults.standard.stringArray(forKey: "com.swiftcode.devTools.favorites") {
            favoriteToolNames = Set(favs)
        }
        if let recs = UserDefaults.standard.stringArray(forKey: "com.swiftcode.devTools.recents") {
            recentToolNames = recs
        }
    }
}
