import SwiftUI
import UIKit

// MARK: - Code Editor View (SwiftUI wrapper)

struct CodeEditorView: View {
    @EnvironmentObject private var projectManager: ProjectManager
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var toolbarSettings: ToolbarSettings
    @EnvironmentObject private var suggestionsManager: CodeSuggestionsML
    @State private var searchQuery = ""
    @State private var replaceText = ""
    @State private var showFileLoadError = false
    @State private var showSuggestionToast = false
    @State private var showSuggestionsView = false
    @State private var showGistComposer = false
    @State private var showAssist = false
    @AppStorage("minimapEnabled") private var minimapEnabled = true

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
            if !projectManager.openFileTabs.isEmpty {
                fileTabsBar
            }

            if projectManager.activeFileNode != nil {
                editorActionBar
            }

            Button("") {
                projectManager.saveCurrentFile(content: projectManager.activeFileContent)
            }
            .keyboardShortcut("s", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)

            if toolbarSettings.showSearchBar {
                searchBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if projectManager.activeFileNode != nil {
                HStack(spacing: 0) {
                    TextEditorRepresentable(
                        text: Binding(
                            get: { projectManager.activeFileContent },
                            set: { newValue in
                                projectManager.activeFileContent = newValue
                                if settings.autoSave {
                                    scheduleAutoSave(content: newValue)
                                }
                            }
                        ),
                        wordWrap: toolbarSettings.wordWrap,
                        searchQuery: toolbarSettings.showSearchBar ? searchQuery : "",
                        fileExtension: projectManager.activeFileNode?.name.components(separatedBy: ".").last ?? "swift"
                    )
                    .background(Color(red: 0.11, green: 0.11, blue: 0.14))
                    .id(projectManager.activeFileNode?.id)

                    if minimapEnabled {
                        MinimapView(content: projectManager.activeFileContent)
                    }
                }
            } else {
                editorPlaceholder
            }
        }

        if showSuggestionToast {
            Button {
                showSuggestionToast = false
                showSuggestionsView = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "lightbulb.max.fill")
                        .foregroundStyle(.yellow)
                    Text("Code Suggestions has reviewed your code, tap here to see.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.black.opacity(0.8), in: Capsule())
            }
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        }
        .background(Color(red: 0.11, green: 0.11, blue: 0.14))
        .sheet(isPresented: $showFileLoadError) {
            fileLoadErrorSheet
        }
        .sheet(isPresented: $showSuggestionsView) {
            CodeSuggestionsView()
                .environmentObject(suggestionsManager)
        }
        .sheet(isPresented: $showGistComposer) {
            CreateGistView(
                initialFilename: projectManager.activeFileNode?.name,
                initialContent: projectManager.activeFileContent
            )
        }
        .sheet(isPresented: $showAssist) {
            AssistMainView()
        }
        .onChange(of: projectManager.fileLoadError) {
            if projectManager.fileLoadError != nil {
                showFileLoadError = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .codeSuggestionsReady)) { _ in
            guard settings.codeSuggestionsEnabled else { return }
            withAnimation {
                showSuggestionToast = true
            }
        }
    }

    // MARK: - File Tabs Bar

    private var fileTabsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 1) {
                ForEach(projectManager.openFileTabs) { tab in
                    fileTab(tab)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
    }

    private func fileTab(_ node: FileNode) -> some View {
        let isActive = projectManager.activeFileNode?.id == node.id
        return HStack(spacing: 6) {
            Image(systemName: node.icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(node.iconColor)
            Text(node.name)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular, design: .default))
                .foregroundStyle(isActive ? .white : .secondary)
                .lineLimit(1)
            Button {
                projectManager.closeTab(node)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(isActive ? .white.opacity(0.6) : .secondary.opacity(0.5))
                    .padding(2)
                    .background(
                        Circle()
                            .fill(isActive ? Color.white.opacity(0.1) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive
                      ? Color(red: 0.16, green: 0.16, blue: 0.20)
                      : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Color.white.opacity(0.08) : Color.clear, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            projectManager.openFile(node)
        }
    }

    // MARK: - Editor Action Bar (Breadcrumb + Format)

    private var editorActionBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    if let project = projectManager.activeProject {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.blue.opacity(0.7))
                            Text(project.name)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let node = projectManager.activeFileNode {
                        let components = node.path.components(separatedBy: "/")
                        ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                            Image(systemName: "chevron.right")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.quaternary)
                            Text(component)
                                .font(.system(size: 11, weight: index == components.count - 1 ? .semibold : .regular, design: .monospaced))
                                .foregroundStyle(index == components.count - 1 ? .orange : .secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            Spacer()

            Button {
                formatCode()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Format")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(red: 0.22, green: 0.22, blue: 0.28))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)

            Button {
                showGistComposer = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.doc")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Gist")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.orange.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)

            Button {
                showAssist = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Assist")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.purple.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
        }
        .background(Color(red: 0.10, green: 0.10, blue: 0.13))
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.04))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    // MARK: - Subviews

    private var searchBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                    TextField("Find In File", text: $searchQuery)
                        .font(.system(size: 13, design: .monospaced))
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        toolbarSettings.showSearchBar = false
                    }
                } label: {
                    Text("Done")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                    TextField("Replace With", text: $replaceText)
                        .font(.system(size: 13, design: .monospaced))
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )

                Button {
                    replaceAll()
                } label: {
                    Text("Replace")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(red: 0.10, green: 0.10, blue: 0.13))
    }

    private var editorPlaceholder: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.03))
                    .frame(width: 100, height: 100)
                Image(systemName: "curlybraces")
                    .font(.system(size: 36, weight: .thin))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue.opacity(0.6), .purple.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            VStack(spacing: 6) {
                Text("No File Open")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Select a file from the navigator to begin editing")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fileLoadErrorSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.1))
                        .frame(width: 72, height: 72)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.red)
                }
                Text("File Load Error")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text(projectManager.fileLoadError ?? "Unknown Error")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                Spacer()
            }
            .padding(.top, 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.10, green: 0.10, blue: 0.14))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Dismiss") {
                        projectManager.fileLoadError = nil
                        showFileLoadError = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    @State private var pendingSaveTask: Task<Void, Never>?

    private func scheduleAutoSave(content: String) {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                projectManager.saveCurrentFile(content: content)
            }
        }
    }

    private func replaceAll() {
        guard !searchQuery.isEmpty else { return }
        let updated = projectManager.activeFileContent.replacingOccurrences(of: searchQuery, with: replaceText)
        projectManager.saveCurrentFile(content: updated)
    }

    private func formatCode() {
        let ext = projectManager.activeFileNode?.name.components(separatedBy: ".").last ?? "swift"
        let formatted = EditorCodeFormatter.shared.format(projectManager.activeFileContent, fileExtension: ext)
        projectManager.activeFileContent = formatted
        projectManager.saveCurrentFile(content: formatted)
    }
}

private final class EditorCodeFormatter {
    static let shared = EditorCodeFormatter()

    private init() {}

    func format(_ code: String, fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "json":
            return formatJSON(code)
        default:
            return code
        }
    }

    private func formatJSON(_ code: String) -> String {
        guard let data = code.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let formattedData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let formatted = String(data: formattedData, encoding: .utf8) else {
            return code
        }

        return formatted
    }
}

// MARK: - Minimap View

struct MinimapView: View {
    let content: String
    @AppStorage("minimapWidth") private var minimapWidth: Double = 60
    @AppStorage("minimapOpacity") private var minimapOpacity: Double = 0.6

    var body: some View {
        GeometryReader { geo in
            let lines = content.components(separatedBy: "\n")
            let lineHeight: CGFloat = 2
            let totalHeight = CGFloat(lines.count) * lineHeight

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.prefix(2000).enumerated()), id: \.offset) { _, line in
                        let width = min(CGFloat(line.count) * 0.5, minimapWidth - 4)
                        RoundedRectangle(cornerRadius: 0.5)
                            .fill(minimapColor(for: line))
                            .frame(width: max(width, 0), height: lineHeight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
                .frame(height: max(totalHeight, geo.size.height))
            }
        }
        .frame(width: minimapWidth)
        .background(Color(red: 0.10, green: 0.10, blue: 0.13))
        .opacity(minimapOpacity)
    }

    private func minimapColor(for line: String) -> Color {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") {
            return .green.opacity(0.4)
        }
        if trimmed.hasPrefix("import ") {
            return .purple.opacity(0.5)
        }
        if trimmed.hasPrefix("func ") {
            return Color(red: 0.40, green: 0.83, blue: 0.37).opacity(0.5)
        }
        if trimmed.hasPrefix("struct ") || trimmed.hasPrefix("class ") || trimmed.hasPrefix("enum ") {
            return .cyan.opacity(0.5)
        }
        if trimmed.hasPrefix("@") {
            return Color(red: 0.75, green: 0.49, blue: 0.98).opacity(0.5)
        }
        if trimmed.hasPrefix("var ") || trimmed.hasPrefix("let ") {
            return Color(red: 0.99, green: 0.37, blue: 0.53).opacity(0.3)
        }
        if trimmed.isEmpty {
            return .clear
        }
        return .white.opacity(0.2)
    }
}

// MARK: - UITextView Representable

struct TextEditorRepresentable: UIViewRepresentable {
    @Binding var text: String
    var wordWrap: Bool
    var searchQuery: String
    var fileExtension: String = "swift"

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = UIColor(red: 0.11, green: 0.11, blue: 0.14, alpha: 1)
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = true

        let container = UIView()
        container.backgroundColor = .clear
        scrollView.addSubview(container)

        let lineNumbers = LineNumberView()
        context.coordinator.lineNumberView = lineNumbers

        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.textColor = UIColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1)
        textView.font = TextLayoutEngine.editorFont()


        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.spellCheckingType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.isEditable = true
        textView.isScrollEnabled = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.delegate = context.coordinator
        textView.textContainerInset = TextLayoutEngine.textContainerInset()

        container.addSubview(lineNumbers)
        container.addSubview(textView)

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.containerView = container
        context.coordinator.fileExtension = fileExtension

        scrollView.delegate = context.coordinator

        let highlighted = SyntaxHighlighter.shared.highlight(text, fileExtension: fileExtension)
        textView.attributedText = highlighted

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        context.coordinator.fileExtension = fileExtension

        if textView.attributedText.string != text {
            let highlighted = SyntaxHighlighter.shared.highlight(text, fileExtension: fileExtension)
            let savedRange = textView.selectedRange
            textView.attributedText = highlighted
            let clampedLocation = min(savedRange.location, max(0, text.count))
            textView.selectedRange = NSRange(location: clampedLocation, length: 0)
        }

        if wordWrap {
            textView.textContainer.lineBreakMode = .byWordWrapping
            textView.textContainer.widthTracksTextView = true
            textView.textContainer.size = CGSize(
                width: TextLayoutEngine.codeColumnWidth(totalWidth: scrollView.bounds.width),
                height: .greatestFiniteMagnitude
            )
        } else {
            textView.textContainer.lineBreakMode = .byClipping
            textView.textContainer.widthTracksTextView = false
            textView.textContainer.size = CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: .greatestFiniteMagnitude
            )
        }

        context.coordinator.updateLayout()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIScrollViewDelegate {
        var text: Binding<String>
        var fileExtension: String = "swift"
        weak var textView: UITextView?
        weak var scrollView: UIScrollView?
        weak var containerView: UIView?
        weak var lineNumberView: LineNumberView?

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func showAllTools() {
            NotificationCenter.default.post(name: NSNotification.Name("ShowAllToolsPanel"), object: nil)
        }

        @objc func dismissKeyboard() {
            textView?.resignFirstResponder()
        }

        @objc func undoAction() {
            textView?.undoManager?.undo()
        }

        @objc func redoAction() {
            textView?.undoManager?.redo()
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
            let highlighted = SyntaxHighlighter.shared.highlight(textView.text, fileExtension: fileExtension)
            let savedRange = textView.selectedRange
            textView.attributedText = highlighted
            let clampedLocation = min(savedRange.location, max(0, textView.text.count))
            textView.selectedRange = NSRange(location: clampedLocation, length: 0)
            updateLayout()
        }

        func updateLayout() {
            guard let textView, let scrollView, let container = containerView,
                  let lineNumbers = lineNumberView else { return }

            let gutterWidth = TextLayoutEngine.lineNumberColumnWidth
            let availableWidth = TextLayoutEngine.codeColumnWidth(totalWidth: scrollView.bounds.width)

            let textSize = textView.sizeThatFits(CGSize(
                width: availableWidth,
                height: .greatestFiniteMagnitude
            ))

            let contentWidth = max(textSize.width + gutterWidth, scrollView.bounds.width)
            let contentHeight = max(textSize.height, scrollView.bounds.height)

            container.frame = CGRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
            scrollView.contentSize = container.frame.size

            lineNumbers.frame = CGRect(x: 0, y: 0, width: gutterWidth, height: contentHeight)
            textView.frame = CGRect(x: gutterWidth, y: 0,
                                    width: contentWidth - gutterWidth,
                                    height: contentHeight)

            let font = textView.font ?? TextLayoutEngine.editorFont()
            lineNumbers.lineHeight = font.lineHeight
            lineNumbers.topInset = textView.textContainerInset.top
            lineNumbers.lineCount = textView.text.components(separatedBy: "\n").count
            lineNumbers.setNeedsDisplay()
        }
    }
}

// MARK: - Line Number View

final class LineNumberView: UIView {
    var lineCount: Int = 1
    var lineHeight: CGFloat = TextLayoutEngine.lineHeight()
    var topInset: CGFloat = TextLayoutEngine.textContainerInset().top

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.10, green: 0.10, blue: 0.13, alpha: 1)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        let font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let activeAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white.withAlphaComponent(0.4)
        ]
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.gray.withAlphaComponent(0.35)
        ]

        let separatorX = bounds.width - 0.5
        UIColor.white.withAlphaComponent(0.05).setFill()
        UIRectFill(CGRect(x: separatorX, y: 0, width: 0.5, height: bounds.height))

        let count = max(1, lineCount)
        for i in 1...count {
            let label = "\(i)"
            let useAttrs = (i % 5 == 0 || i == 1) ? activeAttrs : attrs
            let labelSize = label.size(withAttributes: useAttrs)
            let x = bounds.width - labelSize.width - 8
            // Align baseline with the code line: topInset + (line-1) * lineHeight
            // Drawing with `draw(at:)` places top-left of the glyph at the given point.
            // Shift down by (lineHeight - labelSize.height) / 2 to vertically centre.
            let codeLine_y = topInset + CGFloat(i - 1) * lineHeight
            let y = codeLine_y + (lineHeight - labelSize.height) / 2
            label.draw(at: CGPoint(x: x, y: y), withAttributes: useAttrs)
        }
    }
}
