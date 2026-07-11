import SwiftUI

// MARK: - Extension Demo View

struct ExtensionDemoView: View {
    let ext: ExtensionManifest
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch ext.id {
                case "swiftformatter":
                    SwiftFormatterExtensionView()
                case "swiftlintrunner":
                    SwiftLintRunnerExtensionView()
                case "gitblame":
                    GitBlameExtensionView()
                case "colorpicker":
                    ColorPickerExtensionView()
                case "snippetlibrary":
                    SnippetLibraryExtensionView()
                case "markdownpreview":
                    MarkdownPreviewExtensionView()
                case "jsonformatter":
                    JSONFormatterExtensionView()
                case "regextester":
                    RegexTesterExtensionView()
                case "darkprotheme":
                    DarkProThemeExtensionView()
                case "nordtheme":
                    NordThemeExtensionView()
                case "gruvboxtheme":
                    GruvboxThemeExtensionView()
                case "kotlinsupport":
                    KotlinSupportExtensionView()
                case "typescriptsupport":
                    TypeScriptSupportExtensionView()
                case "pythonsupport":
                    PythonSupportExtensionView()
                case "rustsupport":
                    RustSupportExtensionView()
                case "gosupport":
                    GoSupportExtensionView()
                case "aidocgen":
                    AIDocGenExtensionView()
                case "airefactor":
                    AIRefactorExtensionView()
                case "unittestgen":
                    UnitTestGenExtensionView()
                case "xcodebuildtool":
                    XcodeBuildToolExtensionView()
                case "swiftpackagemanager":
                    SwiftPackageManagerExtensionView()
                case "doccgenerator":
                    DocCGeneratorExtensionView()
                case "todohighlighter":
                    TodoHighlighterExtensionView()
                case "multicursor":
                    MultiCursorExtensionView()
                case "codestats":
                    CodeStatsExtensionView()
                default:
                    genericFallbackView
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    private var genericFallbackView: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label(ext.name, systemImage: ext.category.icon)
                        .font(.title2.bold())
                    Text("v\(ext.version) · By \(ext.author)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(ext.description)
                        .font(.body)
                }
                .padding(.vertical, 8)
            } header: {
                Text("About")
            }

            Section {
                Text("EntryPoint: \(ext.entryPoint)")
                if !ext.capabilities.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Capabilities:")
                            .font(.headline)
                        ForEach(ext.capabilities, id: \.self) { capability in
                            Text("• \(capability.rawValue)")
                        }
                    }
                }
            } header: {
                Text("Technical Details")
            }
        }
        .navigationTitle(ext.name)
    }
}
