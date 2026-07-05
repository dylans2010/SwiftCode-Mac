import UIKit

final class SyntaxHighlighter {
    static let shared = SyntaxHighlighter()
    private init() { buildAllPatterns() }

    // MARK: - Theme

    struct Theme {
        let background: UIColor
        let defaultText: UIColor
        let keyword: UIColor
        let string: UIColor
        let comment: UIColor
        let number: UIColor
        let type: UIColor
        let function: UIColor
        let attribute: UIColor
        let propertyWrapper: UIColor
        let swiftUIView: UIColor
        let modifier: UIColor
        let importModule: UIColor
        let controlFlow: UIColor
        let accessControl: UIColor
        let variableDecl: UIColor
        let preprocessor: UIColor
        let operatorColor: UIColor
        let interpolation: UIColor
        let placeholder: UIColor

        static let dark = Theme(
            background: UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1),
            defaultText: UIColor(red: 0.85, green: 0.85, blue: 0.87, alpha: 1),
            keyword: UIColor(red: 0.99, green: 0.37, blue: 0.53, alpha: 1),
            string: UIColor(red: 0.99, green: 0.41, blue: 0.36, alpha: 1),
            comment: UIColor(red: 0.42, green: 0.68, blue: 0.42, alpha: 1),
            number: UIColor(red: 0.82, green: 0.68, blue: 1.0, alpha: 1),
            type: UIColor(red: 0.35, green: 0.82, blue: 0.98, alpha: 1),
            function: UIColor(red: 0.67, green: 0.85, blue: 0.33, alpha: 1),
            attribute: UIColor(red: 0.99, green: 0.58, blue: 0.23, alpha: 1),
            propertyWrapper: UIColor(red: 0.80, green: 0.58, blue: 1.0, alpha: 1),
            swiftUIView: UIColor(red: 0.30, green: 0.78, blue: 0.95, alpha: 1),
            modifier: UIColor(red: 0.55, green: 0.80, blue: 0.95, alpha: 1),
            importModule: UIColor(red: 0.90, green: 0.55, blue: 0.95, alpha: 1),
            controlFlow: UIColor(red: 0.99, green: 0.37, blue: 0.53, alpha: 1),
            accessControl: UIColor(red: 0.99, green: 0.37, blue: 0.53, alpha: 1),
            variableDecl: UIColor(red: 0.99, green: 0.37, blue: 0.53, alpha: 1),
            preprocessor: UIColor(red: 0.99, green: 0.58, blue: 0.23, alpha: 1),
            operatorColor: UIColor(red: 0.85, green: 0.85, blue: 0.87, alpha: 1),
            interpolation: UIColor(red: 0.67, green: 0.85, blue: 0.33, alpha: 1),
            placeholder: UIColor(red: 0.55, green: 0.55, blue: 0.60, alpha: 1)
        )

        static let xcodeDark = Theme(
            background: UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1),
            defaultText: UIColor(red: 0.85, green: 0.85, blue: 0.87, alpha: 1),
            keyword: UIColor(red: 0.99, green: 0.23, blue: 0.51, alpha: 1),
            string: UIColor(red: 0.99, green: 0.38, blue: 0.32, alpha: 1),
            comment: UIColor(red: 0.42, green: 0.68, blue: 0.42, alpha: 1),
            number: UIColor(red: 0.82, green: 0.68, blue: 1.0, alpha: 1),
            type: UIColor(red: 0.36, green: 0.85, blue: 0.98, alpha: 1),
            function: UIColor(red: 0.40, green: 0.83, blue: 0.37, alpha: 1),
            attribute: UIColor(red: 0.99, green: 0.58, blue: 0.23, alpha: 1),
            propertyWrapper: UIColor(red: 0.75, green: 0.49, blue: 0.98, alpha: 1),
            swiftUIView: UIColor(red: 0.36, green: 0.85, blue: 0.98, alpha: 1),
            modifier: UIColor(red: 0.55, green: 0.80, blue: 0.95, alpha: 1),
            importModule: UIColor(red: 0.75, green: 0.49, blue: 0.98, alpha: 1),
            controlFlow: UIColor(red: 0.99, green: 0.23, blue: 0.51, alpha: 1),
            accessControl: UIColor(red: 0.99, green: 0.23, blue: 0.51, alpha: 1),
            variableDecl: UIColor(red: 0.99, green: 0.23, blue: 0.51, alpha: 1),
            preprocessor: UIColor(red: 0.68, green: 0.51, blue: 0.32, alpha: 1),
            operatorColor: UIColor(red: 0.85, green: 0.85, blue: 0.87, alpha: 1),
            interpolation: UIColor(red: 0.40, green: 0.83, blue: 0.37, alpha: 1),
            placeholder: UIColor(red: 0.55, green: 0.55, blue: 0.60, alpha: 1)
        )
    }

    // MARK: - Pattern Storage

    private typealias PatternEntry = (regex: NSRegularExpression,
                                      captureGroup: Int,
                                      color: (Theme) -> UIColor)

    private var swiftPatterns: [PatternEntry] = []
    private var shellPatterns: [PatternEntry] = []
    private var jsonPatterns: [PatternEntry] = []
    private var plistPatterns: [PatternEntry] = []
    private var markdownPatterns: [PatternEntry] = []

    // MARK: - Highlight (entry point)

    func highlight(_ source: String, fileExtension: String = "swift", theme: Theme = .dark) -> NSAttributedString {
        let patterns = patternsForExtension(fileExtension)
        return apply(patterns: patterns, to: source, theme: theme)
    }

    // MARK: - Apply Patterns

    private func apply(patterns: [PatternEntry], to source: String, theme: Theme) -> NSAttributedString {
        let font = TextLayoutEngine.editorFont()
        let paragraphStyle = TextLayoutEngine.paragraphStyle()
        let result = NSMutableAttributedString(string: source)
        let range = NSRange(source.startIndex..., in: source)

        result.addAttributes([
            .font: font,
            .foregroundColor: theme.defaultText,
            .paragraphStyle: paragraphStyle
        ], range: range)

        for entry in patterns {
            let matches = entry.regex.matches(in: source, range: range)
            for match in matches {
                let idx = match.numberOfRanges > entry.captureGroup ? entry.captureGroup : 0
                let matchRange = match.range(at: idx)
                guard matchRange.location != NSNotFound else { continue }
                result.addAttribute(.foregroundColor, value: entry.color(theme), range: matchRange)
            }
        }
        return result
    }

    // MARK: - Language Selection

    private func patternsForExtension(_ ext: String) -> [PatternEntry] {
        switch ext.lowercased() {
        case "sh", "bash", "zsh": return shellPatterns
        case "json": return jsonPatterns
        case "plist": return plistPatterns
        case "md", "markdown": return markdownPatterns
        default: return swiftPatterns
        }
    }

    // MARK: - Pattern Building

    private func buildAllPatterns() {
        buildSwiftPatterns()
        buildShellPatterns()
        buildJSONPatterns()
        buildPlistPatterns()
        buildMarkdownPatterns()
    }

    // MARK: Swift

    private func buildSwiftPatterns() {
        var p: [PatternEntry] = []

        add(#"(\/\/[^\n]*)"#, color: \.comment, to: &p)
        add(#"(\/\*[\s\S]*?\*\/)"#, color: \.comment, to: &p)

        add(#"("""[\s\S]*?""")"#, color: \.string, to: &p)
        add(#"("(?:[^"\\]|\\.)*")"#, color: \.string, to: &p)

        add(#"(\\(\())"#, color: \.interpolation, to: &p)

        add(#"\b(import)\s+([A-Za-z_][A-Za-z0-9_]*)"#, color: \.variableDecl, captureGroup: 1, to: &p)
        add(#"\bimport\s+([A-Za-z_][A-Za-z0-9_]*)"#, color: \.importModule, captureGroup: 1, to: &p)

        add(#"(#if|#else|#elseif|#endif|#available|#unavailable|#selector|#keyPath|#file|#line|#function|#column|#dsohandle|#warning|#error|#sourceLocation|#Preview)\b"#, color: \.preprocessor, to: &p)

        let swiftUIViews = [
            "Text", "Image", "Button", "Toggle", "Slider", "Stepper",
            "TextField", "TextEditor", "SecureField", "Label",
            "VStack", "HStack", "ZStack", "LazyVStack", "LazyHStack",
            "LazyVGrid", "LazyHGrid", "Grid", "GridRow",
            "List", "ForEach", "ScrollView", "Form", "Section",
            "NavigationStack", "NavigationLink", "NavigationSplitView",
            "TabView", "TabItem", "Sheet", "Popover",
            "Spacer", "Divider", "EmptyView", "AnyView",
            "Color", "Gradient", "LinearGradient", "RadialGradient", "AngularGradient",
            "Path", "Shape", "Circle", "Rectangle", "RoundedRectangle", "Capsule", "Ellipse",
            "GeometryReader", "Canvas", "TimelineView",
            "Alert", "ConfirmationDialog", "Menu", "ContextMenu",
            "ProgressView", "Gauge", "DatePicker", "ColorPicker",
            "Picker", "DisclosureGroup", "OutlineGroup",
            "Map", "MapAnnotation",
            "AsyncImage", "ShareLink", "PhotosPicker",
            "ContentView", "ToolbarItem", "ToolbarItemGroup",
            "GroupBox", "ControlGroup", "LabeledContent",
            "ViewThatFits", "AnyLayout",
            "ContentUnavailableView", "TipView"
        ]
        add("\\b(\(swiftUIViews.joined(separator: "|")))\\b", color: \.swiftUIView, to: &p)

        let modifiers = [
            "padding", "frame", "background", "foregroundColor", "foregroundStyle",
            "font", "fontWeight", "fontDesign", "opacity", "cornerRadius",
            "clipShape", "clipped", "mask", "overlay", "border",
            "shadow", "blur", "brightness", "contrast", "saturation",
            "scaleEffect", "rotationEffect", "rotation3DEffect",
            "offset", "position", "alignmentGuide",
            "onTapGesture", "onLongPressGesture", "gesture",
            "onAppear", "onDisappear", "onChange", "onReceive", "task",
            "sheet", "fullScreenCover", "popover", "alert", "confirmationDialog",
            "navigationTitle", "navigationBarTitleDisplayMode",
            "toolbar", "toolbarBackground", "toolbarColorScheme",
            "listStyle", "listRowBackground", "listRowSeparator",
            "buttonStyle", "toggleStyle", "pickerStyle", "textFieldStyle",
            "environment", "environmentObject",
            "preferredColorScheme", "tint", "accentColor",
            "disabled", "hidden", "redacted",
            "transition", "animation", "withAnimation",
            "matchedGeometryEffect", "contentTransition",
            "presentationDetents", "presentationDragIndicator",
            "scrollContentBackground", "scrollIndicators",
            "searchable", "refreshable", "swipeActions",
            "contextMenu", "menuStyle",
            "ignoresSafeArea", "safeAreaInset",
            "containerRelativeFrame", "contentShape",
            "accessibilityLabel", "accessibilityHint", "accessibilityValue",
            "tag", "id", "equatable",
            "lineLimit", "multilineTextAlignment", "truncationMode",
            "imageScale", "symbolRenderingMode", "renderingMode",
            "resizable", "scaledToFit", "scaledToFill", "aspectRatio",
            "bold", "italic", "underline", "strikethrough",
            "textCase", "kerning", "tracking",
            "keyboardShortcut", "focusable", "focused",
            "help", "badge",
            "interactiveDismissDisabled", "navigationDestination",
            "navigationBarBackButtonHidden",
            "sensoryFeedback", "typesettingLanguage",
            "defaultScrollAnchor", "scrollPosition",
            "containerBackground", "backgroundStyle",
            "inspector", "fileImporter", "fileExporter",
            "photosPickerStyle", "labelStyle",
            "tableStyle", "formStyle", "groupBoxStyle",
            "autocorrectionDisabled", "textInputAutocapitalization",
            "layoutPriority", "fixedSize", "geometryGroup"
        ]
        add("\\.(\(modifiers.joined(separator: "|")))\\b", color: \.modifier, captureGroup: 1, to: &p)

        add(#"(@[a-zA-Z_][a-zA-Z0-9_]*)"#, color: \.propertyWrapper, to: &p)

        let accessKw = ["public", "private", "internal", "fileprivate", "open"]
        add("\\b(\(accessKw.joined(separator: "|")))\\b", color: \.accessControl, to: &p)

        let controlKw = ["if", "else", "for", "while", "repeat", "switch", "case",
                         "default", "break", "continue", "fallthrough", "return",
                         "guard", "where", "do", "catch", "throw", "defer"]
        add("\\b(\(controlKw.joined(separator: "|")))\\b", color: \.controlFlow, to: &p)

        let declKw = ["struct", "class", "enum", "protocol", "extension",
                      "func", "init", "deinit", "subscript", "typealias",
                      "actor", "macro", "associatedtype"]
        add("\\b(\(declKw.joined(separator: "|")))\\b", color: \.keyword, to: &p)

        let varKw = ["var", "let"]
        add("\\b(\(varKw.joined(separator: "|")))\\b", color: \.variableDecl, to: &p)

        let otherKw = ["in", "is", "as", "try", "throws", "rethrows",
                       "async", "await", "get", "set", "willSet", "didSet",
                       "static", "final", "override", "required", "convenience",
                       "mutating", "nonmutating", "lazy", "weak", "unowned",
                       "true", "false", "nil", "self", "super",
                       "some", "any", "inout", "consuming", "borrowing",
                       "nonisolated", "isolated", "Sendable",
                       "preconcurrency", "dynamic", "optional",
                       "indirect", "prefix", "postfix", "infix",
                       "precedencegroup", "operator"]
        add("\\b(\(otherKw.joined(separator: "|")))\\b", color: \.keyword, to: &p)

        add(#"\b([A-Z][a-zA-Z0-9_]*)\b"#, color: \.type, to: &p)
        add(#"\bfunc\s+([a-zA-Z_][a-zA-Z0-9_]*)"#, color: \.function, captureGroup: 1, to: &p)
        add(#"\.([a-zA-Z_][a-zA-Z0-9_]*)\s*\("#, color: \.function, captureGroup: 1, to: &p)
        add(#"\b(\d+\.?\d*(?:e[+-]?\d+)?)\b"#, color: \.number, to: &p)
        add(#"\b(0x[0-9a-fA-F]+)\b"#, color: \.number, to: &p)
        add(#"\b(0b[01]+)\b"#, color: \.number, to: &p)
        add(#"\b(0o[0-7]+)\b"#, color: \.number, to: &p)

        add(#"(\?\?|\.\.\.|\.\.<)"#, color: \.operatorColor, to: &p)

        swiftPatterns = p
    }

    // MARK: Shell

    private func buildShellPatterns() {
        var p: [PatternEntry] = []
        add(#"(#[^\n]*)"#, color: \.comment, to: &p)
        add(#"("(?:[^"\\]|\\.)*")"#, color: \.string, to: &p)
        add(#"('(?:[^'\\]|\\.)*')"#, color: \.string, to: &p)
        let kw = ["if","then","else","elif","fi","for","while","do",
                  "done","case","esac","in","function","return","exit",
                  "local","export","source","true","false","echo","read"]
        add("\\b(\(kw.joined(separator: "|")))\\b", color: \.keyword, to: &p)
        let cmds = ["mkdir","cp","rm","cd","ls","cat","grep","sed","awk",
                    "chmod","chown","curl","wget","git","brew","swift","xcodebuild"]
        add("\\b(\(cmds.joined(separator: "|")))\\b", color: \.function, to: &p)
        add(#"(\$\{?[A-Za-z_][A-Za-z0-9_]*\}?)"#, color: \.attribute, to: &p)
        add(#"\b(\d+)\b"#, color: \.number, to: &p)
        shellPatterns = p
    }

    // MARK: JSON

    private func buildJSONPatterns() {
        var p: [PatternEntry] = []
        add(#"("(?:[^"\\]|\\.)*")\s*:"#, color: \.type, captureGroup: 1, to: &p)
        add(#":\s*("(?:[^"\\]|\\.)*")"#, color: \.string, captureGroup: 1, to: &p)
        add(#"\b(true|false|null)\b"#, color: \.keyword, to: &p)
        add(#"(-?\d+\.?\d*(?:[eE][+-]?\d+)?)"#, color: \.number, to: &p)
        jsonPatterns = p
    }

    // MARK: Plist

    private func buildPlistPatterns() {
        var p: [PatternEntry] = []
        add(#"(<!--[\s\S]*?-->)"#, color: \.comment, to: &p)
        add(#"(<[^>]+>)"#, color: \.keyword, to: &p)
        add(#">([^<]+)<"#, color: \.string, captureGroup: 1, to: &p)
        plistPatterns = p
    }

    // MARK: Markdown

    private func buildMarkdownPatterns() {
        var p: [PatternEntry] = []
        add(#"(^#{1,6}\s+[^\n]+)"#, color: \.keyword, to: &p, options: [.anchorsMatchLines])
        add(#"(\*\*[^\*]+\*\*|__[^_]+__)"#, color: \.type, to: &p)
        add(#"(\*[^\*\n]+\*|_[^_\n]+_)"#, color: \.function, to: &p)
        add(#"(`[^`\n]+`)"#, color: \.string, to: &p)
        add(#"(```[\s\S]*?```)"#, color: \.string, to: &p)
        add(#"(\[[^\]]+\]\([^\)]+\))"#, color: \.attribute, to: &p)
        add(#"(^>\s+[^\n]*)"#, color: \.comment, to: &p, options: [.anchorsMatchLines])
        markdownPatterns = p
    }

    // MARK: - Helper

    private func add(
        _ pattern: String,
        color: @escaping (Theme) -> UIColor,
        captureGroup: Int = 0,
        to list: inout [PatternEntry],
        options: NSRegularExpression.Options = [.dotMatchesLineSeparators]
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        list.append((regex: regex, captureGroup: captureGroup, color: color))
    }
}
