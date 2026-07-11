import SwiftUI

struct WorkflowEditorView: View {
    @Binding var content: String
    let fileName: String
    let onSave: (String) -> Void

    @State private var snippetSearch = ""
    @State private var selectedCategory: SnippetCategory = .all
    @State private var validationMessage: String?
    @State private var validationStatus: ValidationStatus = .unchecked
    @State private var isValidating = false
    @State private var parsedJobs: [WorkflowJob] = []

    enum SnippetCategory: String, CaseIterable, Identifiable {
        case all = "All"
        case setup = "Setup"
        case build = "Build / Test"
        case deploy = "Deploy"
        case notifications = "Alerts"

        var id: String { rawValue }
    }

    enum ValidationStatus: Sendable {
        case unchecked
        case valid
        case warning
        case invalid
    }

    struct WorkflowJob: Identifiable, Sendable {
        let id = UUID()
        let name: String
        let steps: [String]
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Snippet search and category selector
                VStack(spacing: 8) {
                    TextField("Search Snippets", text: $snippetSearch)
                        .textFieldStyle(.roundedBorder)

                    Picker("Category", selection: $selectedCategory) {
                        ForEach(SnippetCategory.allCases) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding()

                snippetLibrary
            }
            .navigationTitle("Snippets")
            .frame(minWidth: 240)
        } detail: {
            HSplitView {
                // Left editor block
                VStack(spacing: 0) {
                    editorToolbar

                    if let msg = validationMessage {
                        HStack {
                            Image(systemName: validationIcon)
                                .foregroundStyle(validationColor)
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(validationColor)
                            Spacer()
                            Button { validationMessage = nil } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(validationColor.opacity(0.12))
                        .overlay(
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(validationColor.opacity(0.3)),
                            alignment: .bottom
                        )
                    }

                    TextEditor(text: $content)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .onChange(of: content) { _, newValue in
                            parseWorkflow(newValue)
                        }
                }
                .frame(minWidth: 350)

                // Right Live Visualizer Pane
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Label("Workflow Map (Live)", systemImage: "flowchart")
                            .font(.headline)
                        Spacer()
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))

                    Divider()

                    ScrollView {
                        if parsedJobs.isEmpty {
                            VStack(spacing: 16) {
                                Spacer()
                                Image(systemName: "circle.dashed")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.secondary)
                                Text("Define 'jobs:' in YAML to see live visual flowchart map")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                Spacer()
                            }
                            .padding()
                            .frame(maxWidth: .infinity, minHeight: 300)
                        } else {
                            VStack(alignment: .leading, spacing: 20) {
                                ForEach(parsedJobs) { job in
                                    VStack(alignment: .leading, spacing: 0) {
                                        // Job node header
                                        HStack {
                                            Image(systemName: "gearshape.2.fill")
                                                .foregroundStyle(.orange)
                                            Text(job.name)
                                                .font(.headline)
                                                .foregroundStyle(.white)
                                            Spacer()
                                            Text("job")
                                                .font(.caption2.monospaced())
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(.orange.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                                        }
                                        .padding()
                                        .background(Color.orange.opacity(0.15))

                                        // Steps flow list
                                        VStack(alignment: .leading, spacing: 12) {
                                            if job.steps.isEmpty {
                                                Text("No steps declared")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .padding()
                                            } else {
                                                ForEach(Array(job.steps.enumerated()), id: \.offset) { stepIndex, stepName in
                                                    HStack(alignment: .top, spacing: 10) {
                                                        ZStack {
                                                            Circle()
                                                                .fill(Color.orange.opacity(0.2))
                                                                .frame(width: 20, height: 20)
                                                            Text("\(stepIndex + 1)")
                                                                .font(.system(size: 10, weight: .bold))
                                                                .foregroundStyle(.orange)
                                                        }

                                                        VStack(alignment: .leading, spacing: 2) {
                                                            Text(stepName)
                                                                .font(.subheadline)
                                                                .foregroundStyle(.white)
                                                        }
                                                    }
                                                    .padding(.horizontal)

                                                    if stepIndex < job.steps.count - 1 {
                                                        LineConnector()
                                                            .stroke(style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [4]))
                                                            .foregroundStyle(.secondary.opacity(0.5))
                                                            .frame(height: 12)
                                                            .padding(.leading, 20)
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.vertical)
                                        .background(Color.secondary.opacity(0.08))
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                                    )
                                }
                            }
                            .padding()
                        }
                    }
                }
                .frame(minWidth: 280, maxWidth: 500)
            }
            .task {
                parseWorkflow(content)
            }
        }
    }

    private var editorToolbar: some View {
        HStack {
            Text(fileName)
                .font(.headline)
            Spacer()

            Button(action: {
                validateGitHubWorkflow()
            }) {
                Label(isValidating ? "Validating..." : "Validate Workflow", systemImage: "checkmark.shield")
            }
            .disabled(isValidating)

            Button("Save") {
                onSave(content)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var validationIcon: String {
        switch validationStatus {
        case .unchecked: return "questionmark.circle"
        case .valid: return "checkmark.seal.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .invalid: return "xmark.octagon.fill"
        }
    }

    private var validationColor: Color {
        switch validationStatus {
        case .unchecked: return .secondary
        case .valid: return .green
        case .warning: return .yellow
        case .invalid: return .red
        }
    }

    private var filteredSnippets: [(String, String, SnippetCategory)] {
        let all: [(String, String, SnippetCategory)] = [
            ("Checkout Code", "- uses: actions/checkout@v4", .setup),
            ("Setup Swift", "- name: Select Swift Version\n  uses: swift-actions/setup-swift@v2\n  with:\n    swift-version: '6.0'", .setup),
            ("Setup Xcode", "- name: Select Xcode Version\n  run: sudo xcode-select -s /Applications/Xcode_16.app", .setup),
            ("Swift Build", "- name: Swift Build\n  run: swift build -c release", .build),
            ("Swift Test", "- name: Run Suite\n  run: swift test --parallel", .build),
            ("Xcodebuild Archive", "- name: Xcode Archive\n  run: xcodebuild archive -workspace SwiftCode.xcworkspace -scheme SwiftCode -archivePath build/SwiftCode.xcarchive", .build),
            ("Deploy to App Store", "- name: App Store Upload\n  uses: apple-actions/upload-testflight-build@v1\n  with:\n    app-path: 'build/SwiftCode.ipa'\n    api-key-id: ${{ secrets.APP_STORE_CONNECT_API_KEY_ID }}", .deploy),
            ("Deploy to Netlify", "- name: Netlify Deploy\n  uses: nwtgck/actions-netlify@v3\n  with:\n    publish-dir: './dist'\n    production-deploy: true\n  env:\n    NETLIFY_AUTH_TOKEN: ${{ secrets.NETLIFY_AUTH_TOKEN }}", .deploy),
            ("Slack Notification", "- name: Slack Notification\n  uses: rtCamp/action-slack-notify@v2\n  env:\n    SLACK_WEBHOOK: ${{ secrets.SLACK_WEBHOOK }}\n    SLACK_MESSAGE: 'Build Succeeded!'", .notifications),
            ("Discord Notification", "- name: Discord Alert\n  uses: Ilshidur/action-discord@master\n  env:\n    DISCORD_WEBHOOK: ${{ secrets.DISCORD_WEBHOOK }}", .notifications)
        ]

        var result = all
        if selectedCategory != .all {
            result = result.filter { $0.2 == selectedCategory }
        }
        if !snippetSearch.isEmpty {
            result = result.filter { $0.0.localizedCaseInsensitiveContains(snippetSearch) }
        }
        return result
    }

    private var snippetLibrary: some View {
        List {
            ForEach(filteredSnippets, id: \.0) { snippet in
                SnippetRow(title: snippet.0, code: snippet.1)
            }
        }
    }

    // MARK: - YAML & Workflow Parsing

    private func parseWorkflow(_ text: String) {
        var jobsList: [WorkflowJob] = []

        let lines = text.components(separatedBy: .newlines)
        var currentJobName: String?
        var currentSteps: [String] = []
        var inJobsSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Detect section headers
            if line.hasPrefix("jobs:") {
                inJobsSection = true
                continue
            } else if inJobsSection && !line.hasPrefix(" ") && line.contains(":") {
                // Exited jobs section if we find a root level key other than jobs
                inJobsSection = false
            }

            if inJobsSection {
                // If a line is indented by exactly 2 spaces and ends with ':', it defines a Job name
                let spacesCount = line.prefix(while: { $0 == " " }).count
                if spacesCount == 2 && line.contains(":") {
                    if let previousJobName = currentJobName {
                        jobsList.append(WorkflowJob(name: previousJobName, steps: currentSteps))
                    }
                    currentJobName = line.replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    currentSteps.removeAll()
                } else if spacesCount > 2 && trimmed.hasPrefix("-") {
                    // Step element detected. Parse step name
                    if trimmed.contains("name:") {
                        if let nameRange = trimmed.range(of: "name:") {
                            let stepName = trimmed[nameRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                            currentSteps.append(stepName)
                        }
                    } else if trimmed.contains("uses:") {
                        if let usesRange = trimmed.range(of: "uses:") {
                            let actionName = trimmed[usesRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                            currentSteps.append("Action: \(actionName)")
                        }
                    } else if trimmed.contains("run:") {
                        if let runRange = trimmed.range(of: "run:") {
                            let runCmd = trimmed[runRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                            currentSteps.append("Cmd: \(runCmd)")
                        }
                    }
                }
            }
        }

        if let finalJobName = currentJobName {
            jobsList.append(WorkflowJob(name: finalJobName, steps: currentSteps))
        }

        self.parsedJobs = jobsList
    }

    private func validateGitHubWorkflow() {
        isValidating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let text = content
            if !text.contains(":") {
                validationStatus = .invalid
                validationMessage = "Error: Text does not contain valid YAML structure (missing ':')."
            } else if !text.contains("name:") {
                validationStatus = .warning
                validationMessage = "Recommendation: Add a 'name:' block to identify your workflow."
            } else if !text.contains("on:") {
                validationStatus = .invalid
                validationMessage = "Error: Missing triggers. Workflow requires an 'on:' trigger keyword."
            } else if !text.contains("jobs:") {
                validationStatus = .invalid
                validationMessage = "Error: Missing jobs. Workflow must declare at least one job under 'jobs:'."
            } else if parsedJobs.contains(where: { $0.steps.isEmpty }) {
                validationStatus = .warning
                validationMessage = "Warning: One or more declared jobs do not contain any steps."
            } else {
                validationStatus = .valid
                validationMessage = "Workflow structure is fully Valid! Live flowchart updated."
            }
            isValidating = false
        }
    }

    struct SnippetRow: View {
        let title: String
        let code: String
        var body: some View {
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(code).font(.caption.monospaced()).lineLimit(2).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .onTapGesture {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
            }
            .help("Click to copy snippet")
        }
    }
}

// Custom shape to draw step connector line
struct LineConnector: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}
