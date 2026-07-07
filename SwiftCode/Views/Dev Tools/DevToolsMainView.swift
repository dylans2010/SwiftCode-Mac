import SwiftUI

struct DevToolsMainView: View {
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
        DevTool(name: "Device Info", description: "System and hardware info", icon: "desktopcomputer", destination: AnyView(DeviceInfoView()))
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
    }
}
