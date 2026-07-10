import SwiftUI

struct DevToolsMainView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    struct DevTool: Identifiable {
        let id = UUID()
        let name: String
        let description: String
        let icon: String
        let destination: AnyView
    }

    let tools: [DevTool] = [
        DevTool(name: "HTTP Status", description: "Reference for HTTP response codes", icon: "network", destination: AnyView(HTTPStatusView())),
        DevTool(name: "API Tester", description: "Send REST API requests", icon: "bolt.fill", destination: AnyView(APITesterView())),
        DevTool(name: "Webhook Tester", description: "Test incoming webhooks", icon: "link", destination: AnyView(WebhookTesterView())),
        DevTool(name: "Git Cheatsheet", description: "Common Git commands", icon: "terminal", destination: AnyView(GitCheatsheetView())),
        DevTool(name: "Port Lookup", description: "Common network ports", icon: "number", destination: AnyView(PortLookupView())),
        DevTool(name: "JWT Decoder", description: "Decode JSON Web Tokens", icon: "lock.shield", destination: AnyView(JWTDecoderView())),
        DevTool(name: "Hash Generator", description: "MD5, SHA1, SHA256, SHA512", icon: "number.square", destination: AnyView(HashGeneratorView())),
        DevTool(name: "Certificate Decoder", description: "Decode PEM certificates", icon: "doc.plaintext", destination: AnyView(CertificateDecoderView())),
        DevTool(name: "JSON Formatter", description: "Pretty print or minify JSON", icon: "curlybraces", destination: AnyView(JSONFormatterView())),
        DevTool(name: "Base64 Converter", description: "Encode/Decode Base64", icon: "arrow.left.and.right.square", destination: AnyView(Base64ConverterView())),
        DevTool(name: "URL Encoder", description: "Percent encoding for URLs", icon: "link.badge.plus", destination: AnyView(URLEncoderView())),
        DevTool(name: "Timestamp Converter", description: "Unix epoch to date", icon: "clock", destination: AnyView(TimestampConverterView())),
        DevTool(name: "UUID Generator", description: "Generate random UUIDs", icon: "barcode", destination: AnyView(UUIDGeneratorView())),
        DevTool(name: "Lorem Ipsum", description: "Placeholder text generator", icon: "text.alignleft", destination: AnyView(LoremIpsumGeneratorView())),
        DevTool(name: "Cron Parser", description: "Human readable cron", icon: "calendar.badge.clock", destination: AnyView(CronParserView())),
        DevTool(name: "Color Converter", description: "Hex, RGB, HSL", icon: "paintpalette", destination: AnyView(ColorConverterView())),
        DevTool(name: "SQL Formatter", description: "Format SQL queries", icon: "database", destination: AnyView(SQLFormatterView())),
        DevTool(name: "XML Formatter", description: "Format XML data", icon: "chevron.left.forwardslash.chevron.right", destination: AnyView(XMLFormatterView())),
        DevTool(name: "YAML Converter", description: "JSON to YAML converter", icon: "doc.text", destination: AnyView(YAMLConverterView())),
        DevTool(name: "Markdown Preview", description: "Live markdown preview", icon: "doc.richtext", destination: AnyView(MarkdownPreviewerView())),
        DevTool(name: "Regex Tester", description: "Test regular expressions", icon: "checklist", destination: AnyView(RegexTesterView())),
        DevTool(name: "HTML Entities", description: "Encode/Decode HTML entities", icon: "tag", destination: AnyView(HTMLEntityConverterView())),
        DevTool(name: "Case Converter", description: "camelCase, snake_case, etc.", icon: "textformat", destination: AnyView(CaseConverterView())),
        DevTool(name: "Diff Checker", description: "Compare two text files", icon: "doc.on.doc", destination: AnyView(DiffCheckerView())),
        DevTool(name: "QR Code Gen", description: "Generate QR codes", icon: "qrcode", destination: AnyView(QRCodeGeneratorView())),
        DevTool(name: "Image Base64", description: "Image to Base64 data", icon: "photo", destination: AnyView(ImageBase64View())),
        DevTool(name: "CSS Units", description: "PX to REM/EM converter", icon: "ruler", destination: AnyView(CSSUnitConverterView())),
        DevTool(name: "JS Minifier", description: "Minify JavaScript code", icon: "script", destination: AnyView(JSMinifierView())),
        DevTool(name: "DNS Lookup", description: "Query DNS records", icon: "magnifyingglass", destination: AnyView(DNSLookupView())),
        DevTool(name: "IP Address Info", description: "GeoIP and network info", icon: "info.circle", destination: AnyView(IPAddressInfoView())),
        DevTool(name: "Password Gen", description: "Secure password generator", icon: "key", destination: AnyView(PasswordGeneratorView())),
        DevTool(name: "Text Counter", description: "Words, chars, lines count", icon: "list.number", destination: AnyView(TextCounterView())),
        DevTool(name: "ASCII Art", description: "Text to ASCII art", icon: "textformat.size", destination: AnyView(ASCIIArtGeneratorView())),
        DevTool(name: "Binary Converter", description: "Decimal to Binary", icon: "01.square", destination: AnyView(BinaryConverterView())),
        DevTool(name: "Hex Converter", description: "Hex to Decimal", icon: "h.square", destination: AnyView(HexDecimalConverterView())),
        DevTool(name: "HMAC Generator", description: "Hash-based message auth", icon: "shield", destination: AnyView(HMACGeneratorView())),
        DevTool(name: "RSA Key Gen", description: "Generate RSA key pairs", icon: "key.fill", destination: AnyView(RSAKeyGeneratorView())),
        DevTool(name: "SSL Checker", description: "Verify SSL certificates", icon: "checkmark.seal", destination: AnyView(SSLCheckerView())),
        DevTool(name: "Whois Lookup", description: "Domain registration info", icon: "person.text.rectangle", destination: AnyView(WhoisLookupView())),
        DevTool(name: "Device Info", description: "System and hardware info", icon: "desktopcomputer", destination: AnyView(DeviceInfoView())),
        // Code Generators
        DevTool(name: "JSON to Swift", description: "Generate Swift models from JSON", icon: "swift", destination: AnyView(JSONToSwiftView())),
        DevTool(name: "JSON to Kotlin", description: "Generate Kotlin data classes", icon: "j.square", destination: AnyView(JSONToKotlinView())),
        DevTool(name: "JSON to TypeScript", description: "Generate TS interfaces", icon: "t.square", destination: AnyView(JSONToTSView())),
        DevTool(name: "JSON to Go", description: "Generate Go structs", icon: "g.square", destination: AnyView(JSONToGoView())),
        DevTool(name: "JSON to Java", description: "Generate Java classes", icon: "j.circle", destination: AnyView(JSONToJavaView())),
        DevTool(name: "JSON to Python", description: "Generate Python dataclasses", icon: "p.square", destination: AnyView(JSONToPythonView())),
        DevTool(name: "JSON to C#", description: "Generate C# classes", icon: "c.square", destination: AnyView(JSONToCSharpView())),
        DevTool(name: "JSON to Rust", description: "Generate Rust structs", icon: "r.square", destination: AnyView(JSONToRustView())),
        DevTool(name: "JSON to Dart", description: "Generate Dart classes", icon: "d.square", destination: AnyView(JSONToDartView())),
        DevTool(name: "JSON to PHP", description: "Generate PHP classes", icon: "p.circle", destination: AnyView(JSONToPHPView())),
        // Data Converters
        DevTool(name: "CSV to JSON", description: "Convert CSV to JSON array", icon: "tablecells", destination: AnyView(CSVToJSONView())),
        DevTool(name: "JSON to CSV", description: "Convert JSON array to CSV", icon: "list.bullet.rectangle", destination: AnyView(JSONToCSVView())),
        DevTool(name: "XML to JSON", description: "Convert XML to JSON", icon: "chevron.left.slash.chevron.right", destination: AnyView(XMLToJSONView())),
        DevTool(name: "TOML to JSON", description: "Convert TOML to JSON", icon: "doc.text.fill", destination: AnyView(TOMLToJSONView())),
        DevTool(name: "JSON to TOML", description: "Convert JSON to TOML", icon: "doc.text", destination: AnyView(JSONToTOMLView())),
        DevTool(name: "JSON Schema Gen", description: "Generate JSON Schema from JSON", icon: "schema", destination: AnyView(JSONSchemaGeneratorView())),
        DevTool(name: "String Escaper", description: "Escape/Unescape strings", icon: "escape", destination: AnyView(StringEscaperView())),
        DevTool(name: "Line Remover", description: "Remove empty/duplicate lines", icon: "line.horizontal.3.decrease", destination: AnyView(TextLineRemoverView())),
        DevTool(name: "Text Deduplicator", description: "Remove duplicate words/lines", icon: "doc.on.doc", destination: AnyView(TextDeduplicatorView())),
        DevTool(name: "YAML to JSON", description: "Convert YAML to JSON", icon: "doc.plaintext", destination: AnyView(YAMLToJSONView())),
        // Text & Security
        DevTool(name: "Random String", description: "Generate random strings", icon: "dice", destination: AnyView(RandomStringGeneratorView())),
        DevTool(name: "Password Strength", description: "Check password security", icon: "lock.shield", destination: AnyView(PasswordStrengthMeterView())),
        DevTool(name: "Bcrypt Hash", description: "Generate Bcrypt hashes", icon: "number", destination: AnyView(BcryptHashGeneratorView())),
        DevTool(name: "URL Slug Gen", description: "Generate URL-friendly slugs", icon: "link", destination: AnyView(URLSlugGeneratorView())),
        DevTool(name: "HTML Minifier", description: "Minify HTML code", icon: "chevron.left.forwardslash.chevron.right", destination: AnyView(HTMLMinifierView())),
        DevTool(name: "CSS Minifier", description: "Minify CSS code", icon: "paintbrush", destination: AnyView(CSSMinifierView())),
        DevTool(name: "SVG Minifier", description: "Minify SVG code", icon: "square.stack.3d.down.right", destination: AnyView(SVGMinifierView())),
        DevTool(name: "URL Decomposer", description: "Break down URL parts", icon: "link.badge.plus", destination: AnyView(URLDecomposerView())),
        DevTool(name: "Case Swapper", description: "Toggle case of text", icon: "textformat.size", destination: AnyView(TextCaseSwapperView())),
        DevTool(name: "Length Counter", description: "Count chars, words, lines", icon: "character.cursor.ibeam", destination: AnyView(StringLengthCounterView())),
        // Network & Web
        DevTool(name: "Subnet Calc", description: "IP range and mask calculator", icon: "network", destination: AnyView(SubnetCalculatorView())),
        DevTool(name: "UA Parser", description: "Extract info from User Agent", icon: "person.text.rectangle", destination: AnyView(UserAgentParserView())),
        DevTool(name: "MIME Lookup", description: "MIME type by extension", icon: "doc.questionmark", destination: AnyView(MIMETypeLookupView())),
        DevTool(name: "Header Parser", description: "Parse HTTP headers", icon: "list.bullet", destination: AnyView(HTTPHeaderParserView())),
        DevTool(name: "Cookie Parser", description: "Parse cookie strings", icon: "circle.grid.2x2", destination: AnyView(CookieParserView())),
        DevTool(name: "Base64 File", description: "Encode/Decode files to Base64", icon: "doc.on.clipboard", destination: AnyView(Base64FileConverterView())),
        DevTool(name: "Gzip Compressor", description: "Compress/Decompress text", icon: "archivebox", destination: AnyView(GzipCompressorView())),
        DevTool(name: "MAC Address Gen", description: "Generate MAC addresses", icon: "barcode", destination: AnyView(MACAddressGeneratorView())),
        DevTool(name: "Port Scanner", description: "Scan common ports", icon: "magnifyingglass", destination: AnyView(PortScannerView())),
        DevTool(name: "SemVer Checker", description: "Validate SemVer strings", icon: "tag", destination: AnyView(SemVerCheckerView())),
        // Design & Math
        DevTool(name: "Cron Generator", description: "Interactive cron builder", icon: "calendar.badge.clock", destination: AnyView(CronGeneratorView())),
        DevTool(name: "Color Gradient", description: "CSS/SwiftUI gradients", icon: "paintpalette", destination: AnyView(ColorGradientGeneratorView())),
        DevTool(name: "CSS Shadow", description: "Box-shadow generator", icon: "square.fill.on.square.fill", destination: AnyView(CSSShadowGeneratorView())),
        DevTool(name: "CSS Border Radius", description: "Border-radius generator", icon: "square.dashed", destination: AnyView(CSSBorderRadiusGeneratorView())),
        DevTool(name: "Length Conv", description: "Metric/Imperial length", icon: "ruler", destination: AnyView(LengthConverterView())),
        DevTool(name: "Weight Conv", description: "Metric/Imperial weight", icon: "scalemass", destination: AnyView(WeightConverterView())),
        DevTool(name: "Temp Conv", description: "C, F, K temperature", icon: "thermometer.medium", destination: AnyView(TemperatureConverterView())),
        DevTool(name: "Timezone Conv", description: "Compare timezones", icon: "globe", destination: AnyView(TimezoneConverterView())),
        DevTool(name: "Percentage Calc", description: "Percentage math", icon: "percent", destination: AnyView(PercentageCalculatorView())),
        DevTool(name: "Aspect Ratio", description: "Aspect ratio calculator", icon: "aspectratio", destination: AnyView(AspectRatioCalculatorView()))
    ]

    var filteredTools: [DevTool] {
        if searchText.isEmpty {
            return tools
        } else {
            return tools.filter {
                $0.name.lowercased().contains(searchText.lowercased()) ||
                $0.description.lowercased().contains(searchText.lowercased())
            }
        }
    }

    var body: some View {
        List(filteredTools) { tool in
            NavigationLink(destination: tool.destination) {
                HStack(spacing: 15) {
                    Image(systemName: tool.icon)
                        .font(.title2)
                        .foregroundColor(.accentColor)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(tool.name)
                            .font(.headline)
                        Text(tool.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search developer tools")
        .navigationTitle("Developer Tools")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Close") {
                    dismiss()
                }
            }
        }
    }
}
