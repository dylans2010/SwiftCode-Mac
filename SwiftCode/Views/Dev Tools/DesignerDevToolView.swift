import SwiftUI
import os.log

// MARK: - Models

struct APIResponse: Codable {
    let success: Bool
    let data: DesignData?
    let error: String?
}

struct DesignData: Codable {
    let title: String
    let colors: [String]
    let fonts: [String]
    let radii: [String]
    let screenshot: String
}

struct DesignSnapshot: Codable {
    let title: String
    let colors: [String]
    let fonts: [String]
    let radii: [String]
    let screenshotBase64: String
    let isValid: Bool

    init(from data: DesignData) {
        self.title = data.title
        self.screenshotBase64 = data.screenshot

        // Normalize Colors: Remove duplicates, filter transparent, limit to 50
        let cleanedColors = data.colors
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.lowercased() != "rgba(0, 0, 0, 0)" && $0.lowercased() != "rgba(0,0,0,0)" && !$0.isEmpty }

        var seenColors = Set<String>()
        var uniqueColors: [String] = []
        for color in cleanedColors {
            if !seenColors.contains(color) {
                uniqueColors.append(color)
                seenColors.insert(color)
            }
            if uniqueColors.count >= 50 { break }
        }
        self.colors = uniqueColors

        // Normalize Fonts: Split stacks, trim, deduplicate
        var uniqueFonts: [String] = []
        var seenFonts = Set<String>()
        for fontStack in data.fonts {
            let parts = fontStack.components(separatedBy: ",")
            for part in parts {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                if !trimmed.isEmpty && !seenFonts.contains(trimmed) {
                    uniqueFonts.append(trimmed)
                    seenFonts.insert(trimmed)
                }
            }
        }
        self.fonts = uniqueFonts

        // Normalize Radii: Remove "0px", deduplicate
        var uniqueRadii: [String] = []
        var seenRadii = Set<String>()
        for radius in data.radii {
            let trimmed = radius.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != "0px" && trimmed != "0" && !trimmed.isEmpty && !seenRadii.contains(trimmed) {
                uniqueRadii.append(trimmed)
                seenRadii.insert(trimmed)
            }
        }
        self.radii = uniqueRadii

        self.isValid = true
    }

    static var empty: DesignSnapshot {
        DesignSnapshot(title: "", colors: [], fonts: [], radii: [], screenshotBase64: "", isValid: false)
    }

    private init(title: String, colors: [String], fonts: [String], radii: [String], screenshotBase64: String, isValid: Bool) {
        self.title = title
        self.colors = colors
        self.fonts = fonts
        self.radii = radii
        self.screenshotBase64 = screenshotBase64
        self.isValid = isValid
    }
}

// MARK: - View Model

@Observable
@MainActor
final class DesignerDevToolViewModel {
    var urlString: String = ""
    var isAnalyzing: Bool = false
    var result: DesignSnapshot?
    var errorMessage: String?
    var designDoc: String = ""
    var swiftUITokens: String = ""
    var selectedTab: Int = 0

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "DesignerDevTool")

    // FORCE-UNWRAP JUSTIFICATION: The analyzeURL string is a well-formed constant URL known at compile time.
    private let analyzeURL = URL(string: "http://50.21.181.105:4000/analyze")!

    func analyze() async {
        guard let url = URL(string: urlString), url.scheme != nil else {
            errorMessage = "Please enter a valid URL."
            return
        }

        isAnalyzing = true
        errorMessage = nil
        result = nil

        do {
            var request = URLRequest(url: analyzeURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body = ["url": urlString]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)

            if apiResponse.success, let designData = apiResponse.data {
                let snapshot = DesignSnapshot(from: designData)
                self.result = snapshot

                // Generate design doc content
                self.designDoc = await generateDesignMarkdown(from: snapshot)

                // Generate SwiftUI tokens
                await generateSwiftUITokens(from: snapshot)

                logger.info("Successfully analyzed and generated design tokens for: \(snapshot.title)")
            } else {
                errorMessage = apiResponse.error ?? "Analysis failed without an error message."
                logger.error("Analysis failed: \(apiResponse.error ?? "No error details")")
            }

        } catch {
            errorMessage = "Analysis failed: \(error.localizedDescription)"
            logger.error("API call error: \(error.localizedDescription)")
        }

        isAnalyzing = false
    }

    private func generateDesignMarkdown(from snapshot: DesignSnapshot) async -> String {
        let title = snapshot.title.isEmpty ? "System" : snapshot.title
        let prompt = """
        Analyze the following extracted website design data and generate a professional, extensive DESIGN.md document.

        Extracted Data:
        Title: \(title)
        Colors: \(snapshot.colors.joined(separator: ", "))
        Fonts: \(snapshot.fonts.joined(separator: ", "))
        Corner Radii: \(snapshot.radii.joined(separator: ", "))

        Output a comprehensive specification detailing theme styles, typographic scale, spacing hierarchy, and container patterns. Use markdown format.
        """

        // 1. Try OpenRouter if API key is present
        if let apiKey = KeychainService.shared.get(forKey: KeychainService.openRouterAPIKey), !apiKey.isEmpty {
            do {
                let response = try await OpenRouterService.shared.chat(
                    messages: [AIMessage(role: .user, content: prompt)],
                    model: "meta-llama/llama-3-8b-instruct:free",
                    systemPrompt: "You are an expert design systems engineer. Output a beautifully organized, comprehensive markdown document."
                )
                if !response.isEmpty {
                    return response
                }
            } catch {
                logger.error("OpenRouter markdown generation failed: \(error.localizedDescription)")
            }
        }

        // 2. Try OnDeviceAIManager if available
        do {
            let response = try await OnDeviceAIManager.shared.sendPrompt(prompt, task: .textGeneration)
            if !response.isEmpty {
                return response
            }
        } catch {
            logger.error("On-device markdown generation failed: \(error.localizedDescription)")
        }

        // 3. Robust local fallback generator
        return generateLocalDesignMarkdown(from: snapshot)
    }

    private func generateSwiftUITokens(from snapshot: DesignSnapshot) async {
        let title = snapshot.title.isEmpty ? "System" : snapshot.title
        let prompt = """
        Analyze the following extracted website design data and generate a SwiftUI extension on Color and Font containing these tokens.

        Extracted Data:
        Title: \(title)
        Colors: \(snapshot.colors.joined(separator: ", "))
        Fonts: \(snapshot.fonts.joined(separator: ", "))
        Corner Radii: \(snapshot.radii.joined(separator: ", "))

        Return ONLY the SwiftUI code block.
        """

        // 1. Try OpenRouter if API key is present
        if let apiKey = KeychainService.shared.get(forKey: KeychainService.openRouterAPIKey), !apiKey.isEmpty {
            do {
                let response = try await OpenRouterService.shared.chat(
                    messages: [AIMessage(role: .user, content: prompt)],
                    model: "meta-llama/llama-3-8b-instruct:free",
                    systemPrompt: "You are an expert design systems engineer. Output only a complete, compile-safe SwiftUI extension with no extra text."
                )
                if !response.isEmpty {
                    self.swiftUITokens = response
                    return
                }
            } catch {
                logger.error("OpenRouter token generation failed: \(error.localizedDescription)")
            }
        }

        // 2. Try OnDeviceAIManager if available
        do {
            let response = try await OnDeviceAIManager.shared.sendPrompt(prompt, task: .codeAssist)
            if !response.isEmpty {
                self.swiftUITokens = response
                return
            }
        } catch {
            logger.error("On-device token generation failed: \(error.localizedDescription)")
        }

        // 3. Robust local fallback generator
        self.swiftUITokens = generateLocalSwiftUITokens(from: snapshot)
    }

    private func generateLocalDesignMarkdown(from snapshot: DesignSnapshot) -> String {
        let title = snapshot.title.isEmpty ? "System" : snapshot.title
        var content = """
        # Design Tokens for \(title)

        ## Typography Styles
        """

        if snapshot.fonts.isEmpty {
            content += "\n- Default system font families\n"
        } else {
            for font in snapshot.fonts {
                content += "\n- \(font) (Primary scale: 32px, Body: 14px)"
            }
        }

        content += """


        ## Spacing Scale
        - Compact: 8px
        - Medium: 16px
        - Large: 24px
        - Extra Large: 32px

        ## Corner Radii Scale
        """

        if snapshot.radii.isEmpty {
            content += "\n- Default: 8px\n"
        } else {
            for radius in snapshot.radii {
                content += "\n- Corner Radius: \(radius)"
            }
        }

        return content
    }

    private func generateLocalSwiftUITokens(from snapshot: DesignSnapshot) -> String {
        let title = snapshot.title.isEmpty ? "System" : snapshot.title.replacingOccurrences(of: " ", with: "")
        let safeTitle = title.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()

        var colorLines = ""
        for (index, color) in snapshot.colors.prefix(15).enumerated() {
            colorLines += "        static let color\(index + 1) = Color(hex: \"\(color)\")\n"
        }
        if colorLines.isEmpty {
            colorLines = "        static let background = Color(hex: \"#1A1A1A\")\n        static let foreground = Color(hex: \"#FFFFFF\")\n"
        }

        var fontLines = ""
        for (index, font) in snapshot.fonts.prefix(10).enumerated() {
            fontLines += "        static func font\(index + 1)(size: CGFloat) -> Font {\n            .custom(\"\(font)\", size: size)\n        }\n"
        }
        if fontLines.isEmpty {
            fontLines = "        static func header(size: CGFloat = 32) -> Font {\n            .system(size: size, weight: .bold)\n        }\n"
        }

        var radiusLines = ""
        for (index, radius) in snapshot.radii.prefix(10).enumerated() {
            let numStr = radius.replacingOccurrences(of: "px", "")
            let num = Double(numStr) ?? 8.0
            radiusLines += "        static let radius\(index + 1): CGFloat = \(num)\n"
        }
        if radiusLines.isEmpty {
            radiusLines = "        static let standardRadius: CGFloat = 8.0\n"
        }

        return """
        import SwiftUI

        extension Color {
            enum \(safeTitle)Tokens {
        \(colorLines)    }
        }

        extension Font {
            enum \(safeTitle)Tokens {
        \(fontLines)    }
        }

        extension CGFloat {
            enum \(safeTitle)Tokens {
        \(radiusLines)    }
        }
        """
    }
}

// MARK: - UI

struct DesignerDevToolView: View {
    @State private var viewModel = DesignerDevToolViewModel()
    @Namespace private var animation

    var body: some View {
        ZStack {
            // Modern Background
            Color(NSColor.windowBackgroundColor).ignoresSafeArea()

            LinearGradient(colors: [Color.accentColor.opacity(0.05), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Modern Header Input
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        HStack {
                            Image(systemName: "globe")
                                .foregroundStyle(.secondary)
                            TextField("https://apple.com", text: $viewModel.urlString)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        .padding(12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1), lineWidth: 1))

                        Button(action: {
                            Task {
                                await viewModel.analyze()
                            }
                        }) {
                            HStack {
                                if viewModel.isAnalyzing {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "sparkles")
                                    Text("Analyze")
                                }
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(viewModel.urlString.isEmpty ? Color.gray : Color.accentColor)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.urlString.isEmpty || viewModel.isAnalyzing)
                    }

                    if let error = viewModel.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)

                if let result = viewModel.result {
                    // Modern Tab Picker
                    HStack(spacing: 20) {
                        ForEach(["System", "DESIGN.md", "SwiftUI"].indices, id: \.self) { index in
                            Button(action: { withAnimation(.spring()) { viewModel.selectedTab = index } }) {
                                VStack(spacing: 8) {
                                    Text(["System", "DESIGN.md", "SwiftUI"][index])
                                        .font(.subheadline.weight(viewModel.selectedTab == index ? .bold : .medium))
                                        .foregroundStyle(viewModel.selectedTab == index ? Color.primary : Color.secondary)

                                    if viewModel.selectedTab == index {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.accentColor)
                                            .frame(height: 2)
                                            .matchedGeometryEffect(id: "tab", in: animation)
                                    } else {
                                        Color.clear.frame(height: 2)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if viewModel.selectedTab == 0 {
                                designSummary(result)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                            } else if viewModel.selectedTab == 1 {
                                codeView(viewModel.designDoc)
                                    .transition(.opacity)
                            } else {
                                codeView(viewModel.swiftUITokens)
                                    .transition(.opacity)
                            }
                        }
                        .padding()
                    }
                } else if !viewModel.isAnalyzing {
                    VStack(spacing: 24) {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.1))
                                .frame(width: 120, height: 120)
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 50))
                                .foregroundStyle(LinearGradient(colors: [.accentColor, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        }

                        VStack(spacing: 8) {
                            Text("Engine Your Design")
                                .font(.title2.bold())
                            Text("Enter a URL to reverse-engineer its visual identity into a production-ready design system.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        Spacer()
                    }
                } else {
                    VStack(spacing: 20) {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Extracting Design DNA...")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Analyzing colors, typography and spacing patterns")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .navigationTitle("Designer Dev Tool")
    }

    @ViewBuilder
    private func designSummary(_ data: DesignSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            // Colors Section
            sectionHeader(title: "Color Palette", icon: "paintpalette.fill")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 12) {
                ForEach(data.colors, id: \.self) { colorHex in
                    VStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(hex: colorHex))
                                .frame(width: 70, height: 70)
                                .shadow(color: Color(hex: colorHex).opacity(0.3), radius: 4, x: 0, y: 2)

                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                .frame(width: 70, height: 70)
                        }

                        VStack(spacing: 2) {
                            Text(colorHex.uppercased())
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(16)
                }
            }

            // Typography Section
            sectionHeader(title: "Typography", icon: "textformat")

            VStack(spacing: 12) {
                ForEach(data.fonts, id: \.self) { fontName in
                    HStack(spacing: 16) {
                        Text("Aa")
                            .font(.system(size: 24, weight: .medium))
                            .frame(width: 44)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(fontName)
                                .font(.subheadline.bold())
                        }

                        Spacer()
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(16)
                }
            }

            // Radius Section
            sectionHeader(title: "Radius Scale", icon: "square.dashed")

            HStack(spacing: 16) {
                if data.radii.isEmpty {
                    Text("none detected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(16)
                } else {
                    ForEach(data.radii, id: \.self) { r in
                        VStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.accentColor.opacity(0.1))
                                    .frame(width: 50, height: 50)

                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.accentColor, lineWidth: 1.5)
                                    .frame(width: 50, height: 50)
                            }

                            Text(r)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                        }
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(16)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .font(.headline)
            Text(title)
                .font(.headline)
            Spacer()
        }
    }

    @ViewBuilder
    private func codeView(_ content: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Generated Implementation", systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.subheadline.bold())
                Spacer()
                Button(action: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(content, forType: .string)
                }) {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Copy")
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                Text(content)
                    .font(.system(size: 12, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.05))
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1), lineWidth: 1))
            }
            .frame(maxHeight: 400)
            .textSelection(.enabled)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}