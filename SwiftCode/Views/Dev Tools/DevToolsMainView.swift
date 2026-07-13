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
            DevTool(name: "Password Strength Meter", description: "Audit security entropy of generated strings", icon: "key.fill", category: "Diagnostics", destination: AnyView(PasswordStrengthMeterView())),
            DevTool(name: "Battery Status", description: "Inspect macOS battery power sources", icon: "battery.100", category: "Diagnostics", destination: AnyView(BatteryStatusDevToolView())),
            DevTool(name: "Biometric Auth Sim", description: "Simulate LocalAuthentication FaceID/TouchID prompt responses", icon: "faceid", category: "Diagnostics", destination: AnyView(BiometricAuthSimDevToolView())),

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
            DevTool(name: "Bundle Size Analyzer Tool", description: "Analyze compiled application bundle footprints", icon: "chart.pie", category: "Build System", destination: AnyView(BundleSizeAnalyzerDevToolView())),
            DevTool(name: "Environment Variable Inspector", description: "Search and inspect active process environment variables", icon: "chevron.left.forwardslash.chevron.right", category: "Build System", destination: AnyView(EnvVarInspectorDevToolView())),

            // UI Design
            DevTool(name: "Designer", description: "Reverse-engineer website visual identities into SwiftUI", icon: "wand.and.stars", category: "UI Design", destination: AnyView(DesignerDevToolView())),
            DevTool(name: "Aspect Ratio Calculator", description: "Compute dimensions preserving photo proportions", icon: "aspectratio", category: "UI Design", destination: AnyView(AspectRatioCalculatorView())),
            DevTool(name: "CSS Border Radius Generator", description: "Generate beautiful container corner radius syntax", icon: "square.dashed", category: "UI Design", destination: AnyView(CSSBorderRadiusGeneratorView())),
            DevTool(name: "CSS Shadow Generator", description: "Design multi-layered drop shadow effects visually", icon: "shadow", category: "UI Design", destination: AnyView(CSSShadowGeneratorView())),
            DevTool(name: "Color Gradient Generator", description: "Construct smooth multi-stop color gradients", icon: "paintbrush.fill", category: "UI Design", destination: AnyView(ColorGradientGeneratorView())),
            DevTool(name: "Color Inspector", description: "Color spectrum and conversions", icon: "paintpalette.fill", category: "UI Design", destination: AnyView(ColorInspectorView())),
            DevTool(name: "Font Browser", description: "Browse and preview native system fonts", icon: "textformat", category: "UI Design", destination: AnyView(FontBrowserView())),
            DevTool(name: "Image Metadata Viewer", description: "Read resolution and EXIF fields", icon: "photo.fill", category: "UI Design", destination: AnyView(ImageMetadataViewerView())),
            DevTool(name: "Accessibility Contrast Grid", description: "Readability test across backgrounds", icon: "eye", category: "UI Design", destination: AnyView(AccessibilityContrastGridDevToolView())),
            DevTool(name: "Bezier Curve Visualizer", description: "Visual curve control points editor", icon: "bezier", category: "UI Design", destination: AnyView(BezierCurveVisualizerDevToolView())),
            DevTool(name: "Bezier Path Code", description: "SwiftUI Path code compiler from vector details", icon: "chevron.left.forwardslash.chevron.right", category: "UI Design", destination: AnyView(BezierPathCodeDevToolView())),
            DevTool(name: "Color Blending", description: "Blend two colors with ratios", icon: "paintpalette", category: "UI Design", destination: AnyView(ColorBlendingDevToolView())),
            DevTool(name: "Color Mixer", description: "RGB channel mixer and adjuster", icon: "slider.horizontal.3", category: "UI Design", destination: AnyView(ColorMixerDevToolView())),
            DevTool(name: "Color Palette Generator", description: "Build harmonious color variations", icon: "paintpalette.fill", category: "UI Design", destination: AnyView(ColorPaletteGeneratorDevToolView())),
            DevTool(name: "Contrast Checker", description: "WCAG contrast compliance test", icon: "eye.fill", category: "UI Design", destination: AnyView(ContrastCheckerDevToolView())),

            // Conversion
            DevTool(name: "CSV to JSON", description: "Translate structured CSV schemas to JSON data", icon: "doc.text", category: "Conversion", destination: AnyView(CSVToJSONView())),
            DevTool(name: "JSON to CSV", description: "Convert JSON array keys to tabular CSV file layouts", icon: "table", category: "Conversion", destination: AnyView(JSONToCSVView())),
            DevTool(name: "JSON to C#", description: "Generate structural C# models from raw JSON responses", icon: "chevron.left.forwardslash.chevron.right", category: "Conversion", destination: AnyView(JSONToCSharpView())),
            DevTool(name: "JSON to Dart", description: "Build Dart entities with serialization keys from JSON", icon: "arrow.triangle.2.circlepath", category: "Conversion", destination: AnyView(JSONToDartView())),
            DevTool(name: "JSON to Go", description: "Create strongly-typed Go struct schemas from JSON input", icon: "curlybraces", category: "Conversion", destination: AnyView(JSONToGoView())),
            DevTool(name: "JSON to Java", description: "Generate Java POJO properties from JSON data formats", icon: "square.grid.3x3.topleft.filled", category: "Conversion", destination: AnyView(JSONToJavaView())),
            DevTool(name: "JSON to Kotlin", description: "Create Kotlin data classes with parsing keys", icon: "pencil", category: "Conversion", destination: AnyView(JSONToKotlinView())),
            DevTool(name: "JSON to PHP", description: "Convert raw JSON into structured PHP associative arrays", icon: "doc.plaintext", category: "Conversion", destination: AnyView(JSONToPHPView())),
            DevTool(name: "JSON to Python", description: "Construct Python type-hinted dictionary models", icon: "terminal", category: "Conversion", destination: AnyView(JSONToPythonView())),
            DevTool(name: "JSON to Rust", description: "Generate safe, serializable Rust structs from JSON data", icon: "gear", category: "Conversion", destination: AnyView(JSONToRustView())),
            DevTool(name: "JSON to Swift", description: "Generate native Swift Codable structs from JSON API payloads", icon: "swift", category: "Conversion", destination: AnyView(JSONToSwiftView())),
            DevTool(name: "JSON to TOML", description: "Format standard JSON objects into clean TOML syntax", icon: "slider.horizontal.below.rectangle", category: "Conversion", destination: AnyView(JSONToTOMLView())),
            DevTool(name: "JSON to TS", description: "Convert API JSON to TypeScript interface structures", icon: "curlybraces", category: "Conversion", destination: AnyView(JSONToTSView())),
            DevTool(name: "TOML to JSON", description: "Convert declarative TOML configurations to JSON schemas", icon: "chevron.right.square", category: "Conversion", destination: AnyView(TOMLToJSONView())),
            DevTool(name: "XML to JSON", description: "Parse nested legacy XML structures into readable JSON", icon: "arrow.left.and.right", category: "Conversion", destination: AnyView(XMLToJSONView())),
            DevTool(name: "YAML to JSON", description: "JSON to YAML converter", icon: "doc.text", category: "Conversion", destination: AnyView(YAMLConverterView())),
            DevTool(name: "YAML to JSON Parser", description: "Convert YAML configs to parsed JSON objects", icon: "doc.plaintext", category: "Conversion", destination: AnyView(YAMLToJSONView())),
            DevTool(name: "ASCII Hex Converter", description: "Bidirectional ASCII to Hex converter", icon: "arrow.left.and.right.square", category: "Conversion", destination: AnyView(ASCIIHexConverterDevToolView())),
            DevTool(name: "Base32 Converter", description: "RFC 4648 Base32 encoder and decoder", icon: "number", category: "Conversion", destination: AnyView(Base32ConverterDevToolView())),
            DevTool(name: "Base64 Decoder", description: "Safe Base64 string decoding tool", icon: "lock.open", category: "Conversion", destination: AnyView(Base64DecoderDevToolView())),
            DevTool(name: "Base64 Encoder", description: "Encode standard strings to Base64 formats", icon: "lock", category: "Conversion", destination: AnyView(Base64EncoderDevToolView())),
            DevTool(name: "Binary Hex Converter", description: "Translate binary stream to hexadecimal bytes", icon: "01.square", category: "Conversion", destination: AnyView(BinaryHexConverterDevToolView())),
            DevTool(name: "Base64 File Converter", description: "Decode/Encode file binary payloads as Base64", icon: "doc.on.doc.fill", category: "Conversion", destination: AnyView(Base64FileConverterView())),
            DevTool(name: "Base64 Converter", description: "Encode/Decode Base64", icon: "arrow.left.and.right.square", category: "Conversion", destination: AnyView(Base64ConverterView())),
            DevTool(name: "Binary Converter", description: "Decimal to Binary", icon: "01.square", category: "Conversion", destination: AnyView(BinaryConverterView())),
            DevTool(name: "Hex Converter", description: "Hex to Decimal", icon: "h.square", category: "Conversion", destination: AnyView(HexDecimalConverterView())),
            DevTool(name: "Timestamp Converter", description: "Unix epoch to date", icon: "clock", category: "Conversion", destination: AnyView(TimestampConverterView())),
            DevTool(name: "Epoch Converter", description: "Seconds to readable UTC timestamp conversion", icon: "calendar.badge.clock", category: "Conversion", destination: AnyView(EpochConverterDevToolView())),

            // Cryptography
            DevTool(name: "AES Encryption", description: "Symmetric key AES-256 GCM cryptor", icon: "key.fill", category: "Cryptography", destination: AnyView(AESEncryptionDevToolView())),
            DevTool(name: "Bcrypt Hash Generator", description: "Generate Bcrypt salt verification hashes", icon: "lock.circle", category: "Cryptography", destination: AnyView(BcryptHashGeneratorView())),
            DevTool(name: "HMAC Calculator", description: "Generate secure digests with secret keys", icon: "shield", category: "Cryptography", destination: AnyView(HMACCalculatorDevToolView())),
            DevTool(name: "RSA Key Gen", description: "Generate RSA key pairs", icon: "key.fill", category: "Cryptography", destination: AnyView(RSAKeyGeneratorView())),
            DevTool(name: "Hash Generator", description: "MD5, SHA1, SHA256, SHA512", icon: "number.square", category: "Cryptography", destination: AnyView(HashGeneratorView())),
            DevTool(name: "HMAC Generator", description: "Hash-based message auth", icon: "shield", category: "Cryptography", destination: AnyView(HMACGeneratorView())),
            DevTool(name: "CSRF Token Generator", description: "Anti-forgery secure session key builder", icon: "lock.shield", category: "Cryptography", destination: AnyView(CSRFTokenDevToolView())),
            DevTool(name: "Encryption Hash Tool", description: "Multi-algorithm secure data digest calculator", icon: "lock.rotation", category: "Cryptography", destination: AnyView(EncryptionToolDevToolView())),
            DevTool(name: "App Receipt Inspector", description: "Analyze local sandbox store receipts", icon: "doc.plaintext", category: "Cryptography", destination: AnyView(AppReceiptInspectorDevToolView())),

            // Network
            DevTool(name: "API Response Viewer", description: "Fetch and pretty-print JSON response bodies", icon: "network", category: "Network", destination: AnyView(APIResponseViewerDevToolView())),
            DevTool(name: "cURL Converter", description: "Compile cURL bash terminal strings into Swift", icon: "terminal", category: "Network", destination: AnyView(CURLConverterDevToolView())),
            DevTool(name: "cURL Generator", description: "Construct console cURL commands from properties", icon: "chevron.right", category: "Network", destination: AnyView(CURLGeneratorDevToolView())),
            DevTool(name: "Deep Link Tester", description: "Dispatch and test custom URL routing schemes", icon: "link", category: "Network", destination: AnyView(DeepLinkTesterDevToolView())),
            DevTool(name: "Network Reachability", description: "Track active network status loop interfaces", icon: "wifi", category: "Network", destination: AnyView(NetworkReachabilityDevToolView())),
            DevTool(name: "API Tester", description: "Send REST API requests", icon: "bolt.fill", category: "Network", destination: AnyView(APITesterView())),
            DevTool(name: "Webhook Tester", description: "Test incoming webhooks", icon: "link", category: "Network", destination: AnyView(WebhookTesterView())),
            DevTool(name: "Port Lookup", description: "Common network ports", icon: "number", category: "Network", destination: AnyView(PortLookupView())),
            DevTool(name: "Port Scanner", description: "Locate active local/network interface ports", icon: "magnifyingglass.circle", category: "Network", destination: AnyView(PortScannerView())),
            DevTool(name: "DNS Lookup", description: "Query DNS records", icon: "magnifyingglass", category: "Network", destination: AnyView(DNSLookupView())),
            DevTool(name: "IP Address Info", description: "GeoIP and network info", icon: "info.circle", category: "Network", destination: AnyView(IPAddressInfoView())),
            DevTool(name: "SSL Checker", description: "Verify SSL certificates", icon: "checkmark.seal", category: "Network", destination: AnyView(SSLCheckerView())),
            DevTool(name: "Whois Lookup", description: "Domain registration info", icon: "person.text.rectangle", category: "Network", destination: AnyView(WhoisLookupView())),

            // Utilities
            DevTool(name: "Advanced Regex Debugger", description: "Debug, test, and analyze regular expressions", icon: "checklist", category: "Utilities", destination: AnyView(AdvancedRegexDebuggerDevToolView())),
            DevTool(name: "App Sandbox Explorer", description: "Navigate container application documents", icon: "folder", category: "Utilities", destination: AnyView(AppSandboxExplorerDevToolView())),
            DevTool(name: "App State Inspector", description: "Audit foreground/background active state logs", icon: "timer", category: "Utilities", destination: AnyView(AppStateInspectorDevToolView())),
            DevTool(name: "Barcode Generator", description: "Create Code 128 / Code 39 visual code lines", icon: "barcode", category: "Utilities", destination: AnyView(BarcodeGeneratorDevToolView())),
            DevTool(name: "Breakpoint Manager", description: "Toggle active LLDB debugger break lines", icon: "circle.fill", category: "Utilities", destination: AnyView(BreakpointManagerDevToolView())),
            DevTool(name: "CPU Thread Monitor", description: "Track core load metrics", icon: "speedometer", category: "Utilities", destination: AnyView(CPUMonitorDevToolView())),
            DevTool(name: "CSV Parser", description: "Grid view of comma-separated tabular files", icon: "table", category: "Utilities", destination: AnyView(CSVParserDevToolView())),
            DevTool(name: "Cache Viewer", description: "Inspect local caches and URL buffers", icon: "shippingbox", category: "Utilities", destination: AnyView(CacheViewerDevToolView())),
            DevTool(name: "Character Escaper", description: "Escape quote and code characters", icon: "chevron.left", category: "Utilities", destination: AnyView(CharacterEscaperDevToolView())),
            DevTool(name: "Clipboard Inspector", description: "Live clipboard UTI format inspector", icon: "doc.on.clipboard", category: "Utilities", destination: AnyView(ClipboardInspectorDevToolView())),
            DevTool(name: "Database Schema Builder", description: "Outline SQLite tables and CREATE TABLE commands", icon: "database", category: "Utilities", destination: AnyView(DatabaseCreateDevToolView())),
            DevTool(name: "Date Formatter", description: "Validate and format ISO dates with custom patterns", icon: "calendar", category: "Utilities", destination: AnyView(DateFormatterDevToolView())),
            DevTool(name: "Disk Usage Analyzer", description: "Calculate path sizes for DerivedData caches", icon: "internaldrive", category: "Utilities", destination: AnyView(DiskUsageAnalyzerDevToolView())),
            DevTool(name: "Energy Impact Monitor", description: "Estimate system core drawing power rates", icon: "bolt", category: "Utilities", destination: AnyView(EnergyImpactMonitorDevToolView())),
            DevTool(name: "FPS Performance Monitor", description: "Track layout animation loop update rates", icon: "gauge", category: "Utilities", destination: AnyView(FPSMonitorDevToolView())),
            DevTool(name: "CSS Minifier", description: "Reduce stylesheet footprint metrics", icon: "doc.plaintext", category: "Utilities", destination: AnyView(CSSMinifierView())),
            DevTool(name: "Cookie Parser", description: "Audit key/value web header cookies", icon: "circle.grid.hex", category: "Utilities", destination: AnyView(CookieParserView())),
            DevTool(name: "Cron Generator", description: "Build scheduled crontab cron expressions", icon: "timer.square", category: "Utilities", destination: AnyView(CronGeneratorView())),
            DevTool(name: "Gzip Compressor", description: "Compress string buffers into GZIP binary", icon: "square.and.arrow.down", category: "Utilities", destination: AnyView(GzipCompressorView())),
            DevTool(name: "HTML Minifier", description: "Optimize layout documents footprint", icon: "tag.fill", category: "Utilities", destination: AnyView(HTMLMinifierView())),
            DevTool(name: "HTTP Header Parser", description: "Query custom response/request network headers", icon: "list.bullet", category: "Utilities", destination: AnyView(HTTPHeaderParserView())),
            DevTool(name: "JSON Schema Generator", description: "Construct JSON schemas from input instances", icon: "curlybraces.square", category: "Utilities", destination: AnyView(JSONSchemaGeneratorView())),
            DevTool(name: "Length Converter", description: "Convert pixels to millimeter bounds", icon: "ruler.fill", category: "Utilities", destination: AnyView(LengthConverterView())),
            DevTool(name: "MAC Address Generator", description: "Create mock hardware network interfaces", icon: "wifi.square", category: "Utilities", destination: AnyView(MACAddressGeneratorView())),
            DevTool(name: "MIME Type Lookup", description: "Resolve file extensions to MIME keys", icon: "doc.plaintext", category: "Utilities", destination: AnyView(MIMETypeLookupView())),
            DevTool(name: "Percentage Calculator", description: "Evaluate proportion ratios", icon: "percent", category: "Utilities", destination: AnyView(PercentageCalculatorView())),
            DevTool(name: "Random String Generator", description: "Generate strong keys with character filters", icon: "abc", category: "Utilities", destination: AnyView(RandomStringGeneratorView())),
            DevTool(name: "SVG Minifier", description: "Optimize vector graphics layout text", icon: "photo.circle", category: "Utilities", destination: AnyView(SVGMinifierView())),
            DevTool(name: "SemVer Checker", description: "Validate software tag release ranges", icon: "tag.circle", category: "Utilities", destination: AnyView(SemVerCheckerView())),
            DevTool(name: "String Escaper", description: "Escape string literals", icon: "quote.bubble", category: "Utilities", destination: AnyView(StringEscaperView())),
            DevTool(name: "String Length Counter", description: "Words, characters, and bytes sizes details", icon: "character.textbox", category: "Utilities", destination: AnyView(StringLengthCounterView())),
            DevTool(name: "Subnet Calculator", description: "IP Subnet CIDR range mapping lookup", icon: "network.badge.shield.half.filled", category: "Utilities", destination: AnyView(SubnetCalculatorView())),
            DevTool(name: "Temperature Converter", description: "Translate Kelvin, Fahrenheit, Celsius bounds", icon: "thermometer.medium", category: "Utilities", destination: AnyView(TemperatureConverterView())),
            DevTool(name: "Text Case Swapper", description: "Toggle uppercase, lowercase, and title structures", icon: "textformat.size.smaller", category: "Utilities", destination: AnyView(TextCaseSwapperView())),
            DevTool(name: "Text Deduplicator", description: "Remove redundant words from plain list blocks", icon: "doc.on.doc.fill", category: "Utilities", destination: AnyView(TextDeduplicatorView())),
            DevTool(name: "Text Line Remover", description: "Filter out empty lines or containing patterns", icon: "line.horizontal.3.decrease.circle", category: "Utilities", destination: AnyView(TextLineRemoverView())),
            DevTool(name: "Timezone Converter", description: "Check UTC offsets across global cities", icon: "globe.badge.chevron.backward", category: "Utilities", destination: AnyView(TimezoneConverterView())),
            DevTool(name: "URL Decomposer", description: "Separate queries, paths, and domains structures", icon: "link.badge.plus", category: "Utilities", destination: AnyView(URLDecomposerView())),
            DevTool(name: "URL Slug Generator", description: "Build SEO-friendly dashed lowercase paths", icon: "textformat.abc", category: "Utilities", destination: AnyView(URLSlugGeneratorView())),
            DevTool(name: "User Agent Parser", description: "Retrieve browser, platform, and model keys", icon: "personalhotspot", category: "Utilities", destination: AnyView(UserAgentParserView())),
            DevTool(name: "Weight Converter", description: "Convert pounds, ounces, grams and kilograms bounds", icon: "scalemass", category: "Utilities", destination: AnyView(WeightConverterView())),
            DevTool(name: "HTTP Status", description: "Reference for HTTP response codes", icon: "network", category: "Utilities", destination: AnyView(HTTPStatusView())),
            DevTool(name: "Git Cheatsheet", description: "Common Git commands", icon: "terminal", category: "Utilities", destination: AnyView(GitCheatsheetView())),
            DevTool(name: "JWT Decoder", description: "Decode JSON Web Tokens", icon: "lock.shield", category: "Utilities", destination: AnyView(JWTDecoderView())),
            DevTool(name: "Certificate Decoder", description: "Decode PEM certificates", icon: "doc.plaintext", category: "Utilities", destination: AnyView(CertificateDecoderView())),
            DevTool(name: "JSON Formatter", description: "Pretty print or minify JSON", icon: "curlybraces", category: "Utilities", destination: AnyView(JSONFormatterView())),
            DevTool(name: "URL Encoder", description: "Percent encoding for URLs", icon: "link.badge.plus", category: "Utilities", destination: AnyView(URLEncoderView())),
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
            DevTool(name: "Password Gen", description: "Secure password generator", icon: "key", category: "Utilities", destination: AnyView(PasswordGeneratorView())),
            DevTool(name: "Text Counter", description: "Words, chars, lines count", icon: "list.number", category: "Utilities", destination: AnyView(TextCounterView())),
            DevTool(name: "ASCII Art", description: "Text to ASCII art", icon: "textformat.size", category: "Utilities", destination: AnyView(ASCIIArtGeneratorView())),
            DevTool(name: "Device Info", description: "System and hardware info", icon: "desktopcomputer", category: "Utilities", destination: AnyView(DeviceInfoView())),
            DevTool(name: "Property List Viewer", description: "Inspect standard XML property lists", icon: "list.bullet.rectangle", category: "Utilities", destination: AnyView(PlistViewerView()))
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
            VStack(spacing: 0) {
                // High-density Search Header Panel
                HStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Search developer tools, category, description...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)

                Divider()

                // Desktop compact list layout
                List {
                    // Favorites Group
                    if !favorites.isEmpty && searchText.isEmpty {
                        Section(header: Text("FAVORITE TOOLS").font(.system(size: 10, weight: .bold)).foregroundStyle(.orange)) {
                            ForEach(tools.filter { favorites.contains($0.name) }) { tool in
                                toolRow(for: tool)
                            }
                        }
                    }

                    // Recents Group
                    if !recents.isEmpty && searchText.isEmpty {
                        Section(header: Text("RECENTLY USED").font(.system(size: 10, weight: .bold)).foregroundStyle(.blue)) {
                            ForEach(recents.compactMap { name in tools.first(where: { $0.name == name }) }) { tool in
                                toolRow(for: tool)
                            }
                        }
                    }

                    // Collapsible Category Sections with Compact Rows
                    ForEach(categories, id: \.self) { category in
                        let catTools = filteredTools.filter { $0.category == category }
                        if !catTools.isEmpty {
                            Section(header: Text(category.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)) {
                                ForEach(catTools) { tool in
                                    toolRow(for: tool)
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .navigationTitle("Developer Tools Hub")
        }
        .frame(minWidth: 450, idealWidth: 550, minHeight: 480, idealHeight: 650)
    }

    @ViewBuilder
    private func toolRow(for tool: DevTool) -> some View {
        NavigationLink(destination: tool.destination.onAppear { recordRecent(tool.name) }) {
            HStack(spacing: 12) {
                // Colored SF Icon Background
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 24, height: 24)
                    Image(systemName: tool.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.orange)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(tool.name)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)

                    Text(tool.description)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Hover Favorite Button
                Button {
                    toggleFavorite(tool.name)
                } label: {
                    Image(systemName: favorites.contains(tool.name) ? "star.fill" : "star")
                        .font(.system(size: 11))
                        .foregroundColor(favorites.contains(tool.name) ? .orange : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
        }
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
        let trimmed = Array(list.prefix(6))
        recentToolNames = trimmed.joined(separator: ",")
    }
}
