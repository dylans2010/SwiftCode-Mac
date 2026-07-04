import SwiftUI

struct NewProjectSheetView: View {
    @Bindable var viewModel: HomeViewModel
    @Environment(\.dismiss) var dismiss

    @State private var mode: SelectionMode = .create
    @State private var gitURL: String = ""

    enum SelectionMode {
        case create, importFolder, clone, xcodeproj
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
                            SectionView(title: "Git Repository URL") {
                                TextField("https://github.com/user/repo.git", text: $gitURL)
                                    .textFieldStyle(.roundedBorder)
                            }
                        } else if mode == .importFolder {
                            VStack(alignment: .center) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 50))
                                    .foregroundColor(.accentColor)
                                    .padding()
                                Text("Select a folder to import it as a SwiftCode project.")
                                    .foregroundColor(.secondary)
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
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                    }
                    .padding()
                }

                Divider()

                // Footer
                HStack {
                    Button("Cancel") { dismiss() }
                    Spacer()
                    if mode != .create {
                        Button(actionButtonTitle) {
                            handleAction()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            }
            .navigationTitle(title)
            .navigationBarHidden(true)
        }
        .frame(width: 500, height: 400)
    }

    private var title: String {
        switch mode {
        case .create: return "Create New Project"
        case .importFolder: return "Import Folder"
        case .clone: return "Clone Repository"
        case .xcodeproj: return "Import Xcode Project"
        }
    }

    private var actionButtonTitle: String {
        switch mode {
        case .create: return "Create Project"
        case .importFolder: return "Select Folder..."
        case .clone: return "Clone & Open"
        case .xcodeproj: return "Select .xcodeproj..."
        }
    }

    private func handleAction() {
        switch mode {
        case .create:
            break // Handled in TemplatePickerView
        case .importFolder:
            importFolder()
        case .clone:
            cloneRepo()
        case .xcodeproj:
            importXcodeProject()
        }
    }

    private func importFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await viewModel.importProject(url: url)
                dismiss()
            }
        }
    }

    private func cloneRepo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            let destinationURL = url.appendingPathComponent(URL(string: gitURL)?.lastPathComponent.replacingOccurrences(of: ".git", with: "") ?? "repo")
            Task {
                do {
                    guard let remoteURL = URL(string: gitURL) else {
                        throw AppError.validationError("Invalid Git URL")
                    }
                    try await GitService.shared.clone(remoteURL: remoteURL, destinationURL: destinationURL, token: nil)
                    await viewModel.importProject(url: destinationURL)
                    dismiss()
                } catch {
                    LoggingTool.error("Failed to clone repository: \(error)")
                }
            }
        }
    }

    private func importXcodeProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "xcodeproj")!]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await viewModel.importProject(url: url.deletingLastPathComponent())
                dismiss()
            }
        }
    }
}
