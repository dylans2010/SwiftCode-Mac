import SwiftUI
import UniformTypeIdentifiers

struct NewProjectSheetView: View {
    @Bindable var viewModel: HomeViewModel
    @Environment(\.dismiss) var dismiss

    @State private var mode: SelectionMode = .create

    enum SelectionMode {
        case create, importFolder, clone, xcodeproj, scproj
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text(title)
                        .font(.title2)
                        .bold()
                    Spacer()
                    Picker("", selection: $mode) {
                        Text("New").tag(SelectionMode.create)
                        Text("Import").tag(SelectionMode.importFolder)
                        Text("Clone").tag(SelectionMode.clone)
                        Text("Xcode").tag(SelectionMode.xcodeproj)
                        Text(".scproj").tag(SelectionMode.scproj)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if mode == .create {
                            VStack(alignment: .center, spacing: 20) {
                                Image(systemName: "plus.square.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(.accentColor)

                                Text("Create a new project from a template.")
                                    .font(.headline)

                                NavigationLink(destination: TemplatePickerView(viewModel: viewModel)) {
                                    Text("Choose Template...")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)

                        } else if mode == .clone {
                            GitCloneSheetView(viewModel: viewModel)
                                .frame(height: 450)
                        } else if mode == .importFolder {
                            VStack(alignment: .center) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 50))
                                    .foregroundColor(.accentColor)
                                    .padding()
                                Text("Select a folder to import it as a SwiftCode project.")
                                    .foregroundColor(.secondary)

                                Button("Select Folder...") {
                                    importFolder()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .padding()
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        } else if mode == .xcodeproj {
                            VStack(alignment: .center) {
                                Image(systemName: "app.badge")
                                    .font(.system(size: 50))
                                    .foregroundColor(.accentColor)
                                    .padding()
                                Text("Import an existing .xcodeproj file.")
                                    .foregroundColor(.secondary)

                                Button("Select .xcodeproj...") {
                                    importXcodeProject()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .padding()
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        } else if mode == .scproj {
                            ImportProjView()
                                .frame(height: 450)
                        }
                    }
                    .padding()
                }

                if mode == .create {
                    Divider()
                    // Footer
                    HStack {
                        Button("Cancel") { dismiss() }
                        Spacer()
                    }
                    .padding()
                }
            }
            .navigationTitle(title)
        }
        .frame(width: 600, height: 600)
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
                    await ProjectManager.shared.openProject(project)
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
                    await ProjectManager.shared.openProject(project)
                    dismiss()
                } catch {
                    LoggingTool.error("Failed to import Xcode project: \(error)")
                }
            }
        }
    }
}
