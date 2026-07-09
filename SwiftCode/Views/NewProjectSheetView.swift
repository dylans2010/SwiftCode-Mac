import SwiftUI
import UniformTypeIdentifiers

struct NewProjectSheetView: View {
    @Bindable var viewModel: HomeViewModel
    @Environment(\.dismiss) var dismiss

    @State private var mode: SelectionMode = .create

    enum SelectionMode: String, CaseIterable, Identifiable {
        case create = "New"
        case importFolder = "Import"
        case clone = "Clone"
        case xcodeproj = "Xcode"
        case scproj = ".scproj"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .create: return "plus.square.fill"
            case .importFolder: return "folder.badge.plus"
            case .clone: return "arrow.triangle.pull"
            case .xcodeproj: return "app.badge"
            case .scproj: return "shippingbox.fill"
            }
        }
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                // Sidebar
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(SelectionMode.allCases) { item in
                        Button {
                            mode = item
                        } label: {
                            HStack {
                                Image(systemName: item.icon)
                                    .frame(width: 20)
                                Text(item.rawValue)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(mode == item ? Color.accentColor : Color.clear)
                            .foregroundColor(mode == item ? .white : .primary)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .frame(width: 150)
                .padding()
                .background(Color(NSColor.windowBackgroundColor).opacity(0.5))

                Divider()

                // Content Area
                VStack(spacing: 0) {
                    ScrollView {
                        contentView
                            .padding(30)
                    }

                    Divider()

                    HStack {
                        Button("Cancel") { dismiss() }
                        Spacer()
                    }
                    .padding()
                }
            }
            .navigationTitle(title)
        }
        .frame(width: 750, height: 600)
    }

    @ViewBuilder
    private var contentView: some View {
        switch mode {
        case .create:
            VStack(spacing: 30) {
                VStack(spacing: 15) {
                    Image(systemName: "plus.square.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.accentColor)
                        .shadow(radius: 5)

                    Text("Create a new project from a template.")
                        .font(.title2.bold())

                    Text("Select from various application types and library templates to get started quickly.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                NavigationLink(destination: TemplatePickerView(viewModel: viewModel)) {
                    HStack {
                        Text("Choose Template...")
                        Image(systemName: "chevron.right")
                    }
                    .frame(width: 200)
                    .padding()
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)

        case .clone:
            GitCloneSheetView(viewModel: viewModel)

        case .importFolder:
            VStack(spacing: 25) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 70))
                    .foregroundColor(.accentColor)

                Text("Import Folder")
                    .font(.title2.bold())

                Text("Select an existing folder on your disk to manage it as a SwiftCode project.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button("Select Folder...") {
                    importFolder()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity)

        case .xcodeproj:
            VStack(spacing: 25) {
                Image(systemName: "app.badge")
                    .font(.system(size: 70))
                    .foregroundColor(.accentColor)

                Text("Import Xcode Project")
                    .font(.title2.bold())

                Text("Open an existing .xcodeproj file to work with it in SwiftCode.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button("Select .xcodeproj...") {
                    importXcodeProject()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity)

        case .scproj:
            ImportProjView()
        }
    }

    private var title: String {
        switch mode {
        case .create: return "Create New Project"
        case .importFolder: return "Import Folder"
        case .clone: return "Clone Repository"
        case .xcodeproj: return "Import Xcode Project"
        case .scproj: return "Import .scproj File"
        }
    }

    private func importFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do {
                    let project = try await ProjectManager.shared.importProject(from: url)
                    try await ProjectManager.shared.openProject(project)
                    dismiss()
                } catch {
                    LoggingTool.error("Failed to import folder: \(error)")
                }
            }
        }
    }

    private func importXcodeProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "xcodeproj")].compactMap { $0 }
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do {
                    let project = try await ProjectManager.shared.importProject(from: url.deletingLastPathComponent())
                    try await ProjectManager.shared.openProject(project)
                    dismiss()
                } catch {
                    LoggingTool.error("Failed to import Xcode project: \(error)")
                }
            }
        }
    }
}
