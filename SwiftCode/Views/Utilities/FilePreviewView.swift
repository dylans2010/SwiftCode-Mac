import SwiftUI

// MARK: - File Preview View

struct FilePreviewView: View {
    @EnvironmentObject private var projectManager: ProjectManager

    @State private var previewContent: PreviewContent = .loading
    @State private var selectedTab: PreviewTab = .preview

    enum PreviewTab: String, CaseIterable {
        case preview = "Preview"
        case raw     = "Raw"
        case info    = "Info"
    }

    enum PreviewContent {
        case loading
        case image(UIImage)
        case markdown(String)
        case json(String)
        case plist(String)
        case text(String)
        case unsupported(String)
        case error(String)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.12).ignoresSafeArea()
                content
            }
            .navigationTitle(projectManager.activeFileNode?.name ?? "Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Picker("Tab", selection: $selectedTab) {
                        ForEach(PreviewTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { loadPreview() }
        .onChange(of: projectManager.activeFileNode) { _, _ in loadPreview() }
    }

    // MARK: - Content Router

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .preview:  previewView
        case .raw:      rawView
        case .info:     infoView
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewView: some View {
        switch previewContent {
        case .loading:
            ProgressView("Loading…").tint(.orange)

        case .image(let image):
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
            }

        case .markdown(let text):
            ScrollView {
                Text(parseMarkdown(text))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .json(let text):
            jsonPreview(text)

        case .plist(let text):
            ScrollView {
                Text(text)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color(red: 0.85, green: 0.85, blue: 0.85))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .text(let text):
            ScrollView {
                Text(text)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color(red: 0.85, green: 0.85, blue: 0.85))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

        case .unsupported(let ext):
            VStack(spacing: 16) {
                Image(systemName: "doc.questionmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Preview Not Available")
                    .font(.headline).foregroundStyle(.white)
                Text(".\(ext) files cannot be previewed here.")
                    .font(.caption).foregroundStyle(.secondary)
            }

        case .error(let msg):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 44)).foregroundStyle(.red.opacity(0.7))
                Text("Load Error").font(.headline).foregroundStyle(.white)
                Text(msg).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
            }
        }
    }

    // MARK: - Raw View

    private var rawView: some View {
        ScrollView {
            Text(rawText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(red: 0.85, green: 0.85, blue: 0.85))
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private var rawText: String {
        switch previewContent {
        case .markdown(let t), .json(let t), .plist(let t), .text(let t): return t
        case .image: return "(Binary Image Data)"
        case .loading: return "Loading…"
        case .unsupported(let e): return "No raw preview for .\(e) files"
        case .error(let e): return "Error: \(e)"
        }
    }

    // MARK: - Info View

    private var infoView: some View {
        List {
            if let node = projectManager.activeFileNode {
                Section("File") {
                    infoRow(label: "Name",      value: node.name)
                    infoRow(label: "Path",      value: node.path)
                    infoRow(label: "Extension", value: node.name.components(separatedBy: ".").last ?? "—")
                }
            }
            Section("Content") {
                let size = rawText.count
                infoRow(label: "Characters", value: "\(size)")
                infoRow(label: "Lines",      value: "\(rawText.components(separatedBy: "\n").count)")
                infoRow(label: "Words",      value: "\(rawText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count)")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(.primary).lineLimit(1)
        }
        .font(.callout)
    }

    // MARK: - JSON Preview

    private func jsonPreview(_ text: String) -> some View {
        ScrollView {
            Text(prettyJSON(text))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(red: 0.85, green: 0.90, blue: 0.85))
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    // MARK: - Load Logic

    private func loadPreview() {
        guard let node = projectManager.activeFileNode else {
            previewContent = .unsupported("")
            return
        }
        previewContent = .loading

        let content = projectManager.activeFileContent
        let ext = (node.name as NSString).pathExtension.lowercased()

        switch ext {
        case "png", "jpg", "jpeg", "gif", "webp", "heic":
            if let project = projectManager.activeProject,
               let data = try? Data(contentsOf: project.directoryURL.appendingPathComponent(node.path)),
               let image = UIImage(data: data) {
                previewContent = .image(image)
            } else {
                previewContent = .error("Could not load image data.")
            }

        case "md", "markdown":
            previewContent = .markdown(content)

        case "json":
            previewContent = .json(content)

        case "plist":
            previewContent = .plist(content)

        case "swift", "txt", "sh", "yml", "yaml", "xml", "html", "css", "js", "ts", "py", "rb", "go":
            previewContent = .text(content)

        default:
            previewContent = .unsupported(ext)
        }
    }

    // MARK: - Markdown Renderer

    private func parseMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    // MARK: - Pretty JSON

    private func prettyJSON(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
              let result = String(data: pretty, encoding: .utf8) else {
            return text
        }
        return result
    }
}
