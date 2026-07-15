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

// MARK: - Prompt Template Definition

struct PromptTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let basePrompt: String
}

// MARK: - DesignerDevTool View Model

@Observable
@MainActor
final class DesignerDevToolViewModel {
    // URL Reverse Engineering States
    var urlString: String = ""
    var isAnalyzing: Bool = false
    var result: DesignSnapshot?
    var errorMessage: String?

    // Design Studio Workspace States
    var selectedWorkspaceTab: Int = 0 // 0 = DESIGN.md, 1 = SwiftUI Tokens, 2 = SwiftUI Components, 3 = Live Sandbox Preview, 4 = URL Analyzer
    var userConcept: String = ""
    var selectedTemplateId: String = "saas"

    // Prompt Variables
    var accentColorHex: String = "#007AFF"
    var secondaryColorHex: String = "#5856D6"
    var typographyStyle: String = "Inter, Sans-serif"
    var spacingScale: String = "8px, 16px, 24px, 32px"
    var containerRadii: String = "8px, 12px, 16px"
    var themeMode: String = "Dark"

    // Prompt History & Previews
    var promptHistory: [String] = []
    var optimizedPrompt: String = ""
    var showOptimizationComparison: Bool = false
    var isOptimizingPrompt: Bool = false
    var isGeneratingWorkspace: Bool = false

    // Generated Workspace Outputs
    var designDoc: String = ""
    var swiftUITokens: String = ""
    var swiftUIComponents: String = ""

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "DesignerDevTool")
    private let analyzeURL = URL(string: "http://50.21.181.105:4000/analyze")!

    // Pre-defined Design System Templates
    let templates: [PromptTemplate] = [
        PromptTemplate(
            id: "saas",
            name: "SaaS Analytics Dashboard",
            description: "A data-rich metrics board featuring charts, progress rings, and multi-column widgets.",
            basePrompt: "Build a sleek desktop SaaS analytics dashboard for tracking engineering velocity, build statuses, and deployment health."
        ),
        PromptTemplate(
            id: "fintech",
            name: "Fintech Mobile Interface",
            description: "Clean card layouts, interactive sliders, transactions history, and neon-glass accents.",
            basePrompt: "Design a high-fidelity fintech personal banking interface with transaction streams, investment cards, and custom transfer forms."
        ),
        PromptTemplate(
            id: "developer",
            name: "Developer Logging System",
            description: "Command line dark palettes, diagnostic terminal windows, status pills, and monospaced typography.",
            basePrompt: "Create a technical developer logging dashboard displaying system telemetry, real-time process heaps, and database query latencies."
        )
    ]

    func loadTemplate() {
        if let template = templates.first(where: { $0.id == selectedTemplateId }) {
            userConcept = template.basePrompt
        }
    }

    func optimizePrompt() async {
        guard !userConcept.isEmpty else { return }
        isOptimizingPrompt = true
        showOptimizationComparison = true

        let promptText = """
        Rewrite and expand the following simple design concept into a highly detailed, professional engineering prompt.
        Specify target platform guidelines, precise accessibility contracts, strict color systems, typography scale, container corner radii, and interactions.

        Simple Concept: \(userConcept)
        Accent Color: \(accentColorHex)
        Secondary Color: \(secondaryColorHex)
        Typography: \(typographyStyle)
        Theme Mode: \(themeMode)
        Spacing: \(spacingScale)
        Corner Radii: \(containerRadii)
        """

        let systemPrompt = "You are a senior Design Systems Architect. Optimize the provided concept into a gorgeous, extensive system prompt that forces highly-scalable, accessible AppKit & SwiftUI interfaces."

        // Call OpenRouter / local fallback
        if let apiKey = KeychainService.shared.get(forKey: KeychainService.openRouterAPIKey), !apiKey.isEmpty {
            do {
                let response = try await OpenRouterService.shared.chat(
                    messages: [AIMessage(role: .user, content: promptText)],
                    model: "meta-llama/llama-3-8b-instruct:free",
                    systemPrompt: systemPrompt
                )
                if !response.isEmpty {
                    optimizedPrompt = response
                    isOptimizingPrompt = false
                    return
                }
            } catch {
                logger.error("OpenRouter optimization failed: \(error.localizedDescription)")
            }
        }

        // Local fallback
        optimizedPrompt = """
        [Optimized Design Prompts]
        SYSTEM DIRECTIVE: Engineer a multi-platform SwiftUI design environment optimized primarily for macOS desktop screens.
        - THEME: \(themeMode) mode.
        - PRIMARY PALETTE: Main Accent (\(accentColorHex)), Secondary Highlights (\(secondaryColorHex)).
        - TYPOGRAPHY SCALE: \(typographyStyle) featuring high visual hierarchy (Bold titles, structured regular body scales).
        - ACCESSIBILITY: Full VoiceOver labels, contrast ratio matching WCAG AAA, and high-visibility keyboard focus borders.
        - CONTAINERS: GroupBox configurations applying corner radii values (\(containerRadii)) with soft shadow depth buffers.
        - ARCHITECTURE: Strict downward flow (Core -> Backend -> ViewModel -> View) using SwiftUI 6 @Observable.
        - COMPONENT FOCUS: Navigation sidebars, responsive metric grids, and custom forms with robust validation.
        """
        isOptimizingPrompt = false
    }

    func generateWorkspace() async {
        isGeneratingWorkspace = true
        let activePrompt = optimizedPrompt.isEmpty ? userConcept : optimizedPrompt

        // ENFORCED DESIGN.md system prompt
        let designDocSystemPrompt = """
        You are a principal designer and engineering lead. You must reverse-engineer the provided prompt into a comprehensive, production-ready specification document named DESIGN.md.
        The output MUST cover all of the following exact sections with outstanding structure:
        1. Executive Summary
        2. Goals & Success Criteria
        3. User Experience & User Stories
        4. Navigation architecture
        5. Window Hierarchy
        6. View Hierarchy
        7. Components (Interactive buttons, text inputs, metric charts, modern GroupBoxes)
        8. Layout Behavior & Responsive Scaling
        9. States & Interactive Transitions
        10. Animations & Vibrancy Curves
        11. Accessibility Contract (VoiceOver labels, AA/AAA contrast guidelines, dynamic font support)
        12. Style Tokens (Colors, Typography scale, Spacing scale, Icons, SF Symbols)
        13. Data Flow & MainActor State Management
        14. Architecture & SwiftUI/AppKit integration notes
        15. Performance Considerations, Edge Cases, and Interaction Patterns.

        Output ONLY the Markdown document. Do not add conversational intro/outro texts.
        """

        let tokensSystemPrompt = """
        You are an expert design systems engineer. Analyze the design criteria and generate compile-safe, production-ready SwiftUI extensions for Color, Font, and CGFloat holding the visual tokens.
        Output ONLY the SwiftUI code block with no extra conversational text.
        """

        let componentsSystemPrompt = """
        You are a senior SwiftUI developer. Generate a set of beautifully styled, reusable SwiftUI component views (such as CardView, CustomButton, FormField, ModernHeader) styled according to the design specifications.
        Use strict Swift 6 and @Observable state models. Output ONLY the code block.
        """

        // 1. Generate DESIGN.md
        if let apiKey = KeychainService.shared.get(forKey: KeychainService.openRouterAPIKey), !apiKey.isEmpty {
            do {
                designDoc = try await OpenRouterService.shared.chat(
                    messages: [AIMessage(role: .user, content: activePrompt)],
                    model: "meta-llama/llama-3-8b-instruct:free",
                    systemPrompt: designDocSystemPrompt
                )
                swiftUITokens = try await OpenRouterService.shared.chat(
                    messages: [AIMessage(role: .user, content: activePrompt)],
                    model: "meta-llama/llama-3-8b-instruct:free",
                    systemPrompt: tokensSystemPrompt
                )
                swiftUIComponents = try await OpenRouterService.shared.chat(
                    messages: [AIMessage(role: .user, content: activePrompt)],
                    model: "meta-llama/llama-3-8b-instruct:free",
                    systemPrompt: componentsSystemPrompt
                )

                // Add to history
                if !promptHistory.contains(userConcept) {
                    promptHistory.insert(userConcept, at: 0)
                }
                isGeneratingWorkspace = false
                return
            } catch {
                logger.error("OpenRouter generation failed: \(error.localizedDescription)")
            }
        }

        // Fallbacks
        designDoc = """
        # DESIGN.md - Custom Design Specification

        ## 1. Executive Summary
        A professional, premium \(themeMode) mode workspace layout custom engineered for \(userConcept.prefix(30)).

        ## 2. Goals & Success Criteria
        - Establish a high-fidelity visual standard with unified style tokens.
        - Optimize rendering layout speeds for desktop-first monitors.
        - Implement cohesive SwiftUI components that comply with platform accessibility requirements.

        ## 3. User Experience & Navigation
        A Native split sidebar structure enabling smooth transitions between lists and primary canvas views.

        ## 4. Window & View Hierarchy
        - Main Application Window (resizable, min size 1000x700).
        - Split View Pane 1: Sidebar Category List.
        - Split View Pane 2: Interactive metrics and detail editors.

        ## 5. Style Tokens
        - Accent Highlight Color: \(accentColorHex)
        - Secondary Highlight Color: \(secondaryColorHex)
        - Typography Scale: \(typographyStyle)
        - Spacing Hierarchy: \(spacingScale)
        - Corner Radii: \(containerRadii)

        ## 6. SwiftUI Implementation & AppKit Integration Notes
        - Host views cleanly in `NSHostingController` instances with `sizingOptions = []`.
        - Fully isolated `@MainActor` state management models using SwiftUI 6 `@Observable` frameworks.
        """

        swiftUITokens = """
        import SwiftUI

        extension Color {
            enum StudioTokens {
                static let accent = Color(hex: "\(accentColorHex)")
                static let secondaryAccent = Color(hex: "\(secondaryColorHex)")
                static let background = Color(hex: "#1A1A1E")
                static let cardBg = Color(hex: "#25252A")
            }
        }

        extension Font {
            enum StudioTokens {
                static func titleFont(size: CGFloat = 20) -> Font {
                    .custom("System", size: size).bold()
                }
                static func bodyFont(size: CGFloat = 13) -> Font {
                    .custom("System", size: size)
                }
            }
        }
        """

        swiftUIComponents = """
        import SwiftUI

        struct CustomCardView<Content: View>: View {
            let title: String
            let content: Content

            init(title: String, @ViewBuilder content: () -> Content) {
                self.title = title
                self.content = content()
            }

            var body: some View {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(title, systemImage: "sparkles")
                            .font(.headline)
                            .foregroundStyle(Color.StudioTokens.accent)
                        Spacer()
                    }
                    content
                }
                .padding()
                .background(Color.StudioTokens.cardBg)
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
            }
        }
        """

        if !promptHistory.contains(userConcept) {
            promptHistory.insert(userConcept, at: 0)
        }
        isGeneratingWorkspace = false
    }

    // URL Reverse Engineering API Action
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

                // Load reverse-engineered parameters as default workspace tokens
                if !snapshot.colors.isEmpty {
                    accentColorHex = snapshot.colors[0]
                    if snapshot.colors.count > 1 {
                        secondaryColorHex = snapshot.colors[1]
                    }
                }
                if !snapshot.fonts.isEmpty {
                    typographyStyle = snapshot.fonts.joined(separator: ", ")
                }
                if !snapshot.radii.isEmpty {
                    containerRadii = snapshot.radii.joined(separator: ", ")
                }

                // Auto transition workspace tab
                selectedWorkspaceTab = 0

                logger.info("Successfully analyzed and loaded design tokens for: \(snapshot.title)")
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
}

// MARK: - DesignerDevToolView

public struct DesignerDevToolView: View {
    @State private var viewModel = DesignerDevToolViewModel()
    @Namespace private var workspaceAnimation

    public init() {}

    public var body: some View {
        HSplitView {
            // Left Column: Prompt Architect & Variable Configurator
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("Design System Architect", systemImage: "wand.and.stars")
                        .font(.title2.bold())
                        .foregroundStyle(Color.accentColor)

                    Text("Reverse-engineer existing websites or leverage advanced prompt variables to compile high-fidelity SwiftUI & AppKit designs.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Divider()

                    // Template Chooser
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CHOOSE DESIGN ARCHETYPE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)

                        Picker("", selection: $viewModel.selectedTemplateId) {
                            ForEach(viewModel.templates) { t in
                                Text(t.name).tag(t.id)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: viewModel.selectedTemplateId) {
                            viewModel.loadTemplate()
                        }

                        if let currentT = viewModel.templates.first(where: { $0.id == viewModel.selectedTemplateId }) {
                            Text(currentT.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                        }
                    }

                    // Prompt Concept Editor
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CREATIVE DESIGN CONCEPT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)

                        TextEditor(text: $viewModel.userConcept)
                            .font(.system(size: 12))
                            .frame(height: 80)
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                    }

                    // Variable Overrides
                    VStack(alignment: .leading, spacing: 14) {
                        Text("DESIGN TOKEN VARIABLE OVERRIDES")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Accent color:")
                                    .font(.caption)
                                Spacer()
                                TextField("#007AFF", text: $viewModel.accentColorHex)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 120)
                            }

                            HStack {
                                Text("Secondary color:")
                                    .font(.caption)
                                Spacer()
                                TextField("#5856D6", text: $viewModel.secondaryColorHex)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 120)
                            }

                            HStack {
                                Text("Typography Style:")
                                    .font(.caption)
                                Spacer()
                                TextField("Inter, Sans-serif", text: $viewModel.typographyStyle)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 120)
                            }

                            HStack {
                                Text("Spacing scale:")
                                    .font(.caption)
                                Spacer()
                                TextField("8px, 16px, 24px", text: $viewModel.spacingScale)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 120)
                            }

                            HStack {
                                Text("Theme mode:")
                                    .font(.caption)
                                Spacer()
                                Picker("", selection: $viewModel.themeMode) {
                                    Text("Dark").tag("Dark")
                                    Text("Light").tag("Light")
                                    Text("Vibrant Glass").tag("Glass")
                                }
                                .pickerStyle(.menu)
                                .frame(width: 120)
                            }
                        }
                        .padding(12)
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(10)
                    }

                    // Optimize Prompt Button
                    Button {
                        Task {
                            await viewModel.optimizePrompt()
                        }
                    } label: {
                        HStack {
                            if viewModel.isOptimizingPrompt {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "wand.and.rays")
                                Text("AI Optimize Prompt Configuration")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(viewModel.userConcept.isEmpty || viewModel.isOptimizingPrompt)

                    // Prompt comparison
                    if viewModel.showOptimizationComparison {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("AI Optimized Output Prompt Preview:")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            TextEditor(text: $viewModel.optimizedPrompt)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(height: 120)
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                        }
                        .transition(.slide)
                    }

                    // Main Generation Trigger Button
                    Button {
                        Task {
                            await viewModel.generateWorkspace()
                        }
                    } label: {
                        HStack {
                            if viewModel.isGeneratingWorkspace {
                                ProgressView().controlSize(.small)
                                Text("Compiling Design Workspace...")
                            } else {
                                Image(systemName: "sparkles")
                                Text("Generate Full Design System")
                            }
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(viewModel.userConcept.isEmpty ? Color.gray : Color.accentColor)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.userConcept.isEmpty || viewModel.isGeneratingWorkspace)

                    // History Section (if non-empty)
                    if !viewModel.promptHistory.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("DESIGN PROMPT HISTORY")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)

                            ForEach(viewModel.promptHistory, id: \.self) { concept in
                                Button {
                                    viewModel.userConcept = concept
                                } label: {
                                    HStack {
                                        Image(systemName: "clock.fill")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(concept)
                                            .font(.caption)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(6)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .frame(minWidth: 320, maxWidth: 450)
            .background(Color(NSColor.windowBackgroundColor))

            // Right Column: Professional Tabbed Design Studio Workspace
            VStack(spacing: 0) {
                // Modern Tabbed Headers
                HStack(spacing: 16) {
                    ForEach(["DESIGN.md", "SwiftUI Tokens", "Components", "Live Preview", "URL Analyzer"].indices, id: \.self) { idx in
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                viewModel.selectedWorkspaceTab = idx
                            }
                        } label: {
                            VStack(spacing: 8) {
                                Text(["DESIGN.md", "SwiftUI Tokens", "Components", "Live Preview", "URL Analyzer"][idx])
                                    .font(.subheadline.weight(viewModel.selectedWorkspaceTab == idx ? .bold : .medium))
                                    .foregroundStyle(viewModel.selectedWorkspaceTab == idx ? Color.primary : Color.secondary)

                                if viewModel.selectedWorkspaceTab == idx {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.accentColor)
                                        .frame(height: 2)
                                        .matchedGeometryEffect(id: "activeTabLine", in: workspaceAnimation)
                                } else {
                                    Color.clear.frame(height: 2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .background(.ultraThinMaterial)

                Divider()

                // Active Workspace Tab Render
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch viewModel.selectedWorkspaceTab {
                        case 0:
                            designMarkdownWorkspace()
                        case 1:
                            designTokensWorkspace()
                        case 2:
                            designComponentsWorkspace()
                        case 3:
                            interactiveLiveSandboxPreview()
                        default:
                            urlReverseEngineeringAnalyzer()
                        }
                    }
                    .padding(24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
            }
            .frame(minWidth: 500)
        }
    }

    // MARK: - Workspace Subview: DESIGN.md Spec Sheet

    @ViewBuilder
    private func designMarkdownWorkspace() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("DESIGN.md Specification", systemImage: "doc.text.fill")
                    .font(.title3.bold())
                Spacer()
                if !viewModel.designDoc.isEmpty {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(viewModel.designDoc, forType: .string)
                    }) {
                        Label("Copy DESIGN.md", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if viewModel.designDoc.isEmpty {
                emptyWorkspacePlaceholder(title: "No Design Specification Generated Yet", description: "Use the prompt configurator on the left to trigger 'Generate Full Design System' and produce your fully-detailed DESIGN.md document.")
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Text(viewModel.designDoc)
                        .font(.system(size: 12, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.15))
                        .cornerRadius(10)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Workspace Subview: SwiftUI Tokens Sheet

    @ViewBuilder
    private func designTokensWorkspace() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("SwiftUI Design Tokens", systemImage: "curlybraces")
                    .font(.title3.bold())
                Spacer()
                if !viewModel.swiftUITokens.isEmpty {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(viewModel.swiftUITokens, forType: .string)
                    }) {
                        Label("Copy Tokens Code", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if viewModel.swiftUITokens.isEmpty {
                emptyWorkspacePlaceholder(title: "No SwiftUI Tokens Compiled", description: "Trigger the Design generation on the left to compile theme Color and Font tokens.")
            } else {
                Text(viewModel.swiftUITokens)
                    .font(.system(size: 12, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.15))
                    .cornerRadius(10)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Workspace Subview: SwiftUI Components Sheet

    @ViewBuilder
    private func designComponentsWorkspace() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("SwiftUI Reusable Components", systemImage: "cube.fill")
                    .font(.title3.bold())
                Spacer()
                if !viewModel.swiftUIComponents.isEmpty {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(viewModel.swiftUIComponents, forType: .string)
                    }) {
                        Label("Copy Components Code", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if viewModel.swiftUIComponents.isEmpty {
                emptyWorkspacePlaceholder(title: "No Reusable Components Compiled", description: "Design components are produced upon full studio workspace generation.")
            } else {
                Text(viewModel.swiftUIComponents)
                    .font(.system(size: 12, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.15))
                    .cornerRadius(10)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Workspace Subview: Interactive Live Sandbox Preview

    @ViewBuilder
    private func interactiveLiveSandboxPreview() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Interactive Sandbox Preview", systemImage: "play.circle.fill")
                .font(.title3.bold())

            Text("This live sandbox lets you interact with widgets colored in your customized variables and generated design styles.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            let mainColor = Color(hex: viewModel.accentColorHex)
            let secondColor = Color(hex: viewModel.secondaryColorHex)

            VStack(spacing: 16) {
                // Interactive Banner
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.yellow)
                        Text("Active Theme Sandbox")
                            .font(.headline)
                        Spacer()
                    }
                    Text("Interactive visual components rendering live using primary color hex \(viewModel.accentColorHex) and secondary color hex \(viewModel.secondaryColorHex).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(mainColor.opacity(0.12))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(mainColor.opacity(0.3), lineWidth: 1.5))

                // Structured Layout Widgets Row
                HStack(spacing: 16) {
                    // Card 1
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Visual Card", systemImage: "photo.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(mainColor)

                        Text("Sleek dynamic rounded container satisfying container corner radii scale.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Button("Primary Action") {}
                            .buttonStyle(.borderedProminent)
                            .tint(mainColor)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.1), radius: 4)

                    // Card 2
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Analytical Card", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.subheadline.bold())
                            .foregroundStyle(secondColor)

                        Text("Interactive visual indicators reflecting the theme structure.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Button("Secondary Action") {}
                            .buttonStyle(.bordered)
                            .tint(secondColor)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.1), radius: 4)
                }
            }
            .padding()
            .background(Color.black.opacity(0.2))
            .cornerRadius(16)
        }
    }

    // MARK: - Workspace Subview: URL Reverse Engineering Analyzer

    @ViewBuilder
    private func urlReverseEngineeringAnalyzer() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("URL Reverse Engineering Analyzer", systemImage: "network")
                .font(.title3.bold())

            Text("Enter a fully-formed HTTPS / HTTP URL on the left or top input to extract and analyze its design details (Color systems, typography selection, corner radii scale, and styling).")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "globe")
                        .foregroundStyle(.secondary)
                    TextField("https://apple.com", text: $viewModel.urlString)
                        .autocorrectionDisabled()
                        .onSubmit {
                            Task { await viewModel.analyze() }
                        }
                }
                .padding(10)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1), lineWidth: 1))

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
                            Text("Reverse-Engineer URL")
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(viewModel.urlString.isEmpty ? Color.gray : Color.accentColor)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.urlString.isEmpty || viewModel.isAnalyzing)
            }

            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let snapshot = viewModel.result {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Successfully Analyzed: \(snapshot.title)")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Divider()

                    // Color palette chips
                    Text("EXTRACTED COLORS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)

                    FlowLayout(snapshot.colors, spacing: 10) { colorHex in
                        VStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(hex: colorHex))
                                .frame(width: 44, height: 44)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2), lineWidth: 1))

                            Text(colorHex.uppercased())
                                .font(.system(size: 8, design: .monospaced))
                        }
                    }

                    Divider()

                    // Extracted fonts
                    Text("EXTRACTED TYPOGRAPHY")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)

                    ForEach(snapshot.fonts, id: \.self) { fontName in
                        HStack {
                            Image(systemName: "textformat")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                            Text(fontName)
                                .font(.caption)
                        }
                        .padding(6)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(6)
                    }
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - General Utility Views

    @ViewBuilder
    private func emptyWorkspacePlaceholder(title: String, description: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.text.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.5))
            Text(title)
                .font(.headline)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }
}
