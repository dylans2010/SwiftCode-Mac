import SwiftUI
import AppKit

public struct CreateNewAppCompletionView: View {
    public let config: CreateAppConfiguration
    public let createdAppPath: String
    public let builtAppPath: String?
    public let onDismiss: () -> Void

    @State private var moveStatusMessage: String?
    @State private var moveStatusIsError: Bool = false

    public var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            VStack(spacing: 6) {
                Text("\(config.appName) Created Successfully!")
                    .font(.title2.bold())
                Text("Version \(config.version) (\(config.build)) • Target Platform: \(config.platform.rawValue)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Project Directory:", value: createdAppPath)
                    .font(.caption)
                if let builtPath = builtAppPath {
                    LabeledContent("Built Application:", value: builtPath)
                        .font(.caption)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)

            if let message = moveStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(moveStatusIsError ? .red : .green)
            }

            HStack(spacing: 12) {
                Button("Open Project") {
                    var proj = Project(name: config.appName)
                    proj.customDirectoryPath = createdAppPath
                    Task {
                        await ProjectSessionStore.shared.openProject(proj)
                    }
                    onDismiss()
                }

                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: createdAppPath)
                }

                if let builtAppPath = builtAppPath, FileManager.default.fileExists(atPath: builtAppPath) {
                    Button("Open Built App") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: builtAppPath))
                    }
                }

                Button("Move to Applications") {
                    moveToApplications()
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding()
    }

    private func moveToApplications() {
        guard let builtAppPath = builtAppPath, FileManager.default.fileExists(atPath: builtAppPath) else {
            // Fallback to checking executable or directory bundle
            let appURL = URL(fileURLWithPath: createdAppPath)
            performMove(sourceURL: appURL)
            return
        }
        performMove(sourceURL: URL(fileURLWithPath: builtAppPath))
    }

    private func performMove(sourceURL: URL) {
        let appName = sourceURL.lastPathComponent
        let targetApplicationsURL = URL(fileURLWithPath: "/Applications/\(appName)")

        do {
            if FileManager.default.fileExists(atPath: targetApplicationsURL.path) {
                try FileManager.default.removeItem(at: targetApplicationsURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: targetApplicationsURL)
            moveStatusMessage = "Successfully moved \(appName) to /Applications!"
            moveStatusIsError = false
        } catch {
            moveStatusMessage = "Failed to move to /Applications: \(error.localizedDescription)"
            moveStatusIsError = true
        }
    }
}
