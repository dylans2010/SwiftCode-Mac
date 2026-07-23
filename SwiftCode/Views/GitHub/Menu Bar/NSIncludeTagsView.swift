import SwiftUI

public struct NSIncludeTagsView: View {
    @State private var includeTags = true
    @State private var successMsg = ""
    @State private var errorMsg = ""
    @State private var isLoading = false

    public init() {}

    public var body: some View {
        Group {
            if let _ = ProjectSessionStore.shared.activeProject {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Include Tags", systemImage: "tag.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)

                    Toggle("Push tags alongside commits (--tags)", isOn: $includeTags)
                        .toggleStyle(.checkbox)
                        .disabled(isLoading)

                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .padding(.vertical, 4)
                    }

                    if !successMsg.isEmpty {
                        Text(successMsg)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    if !errorMsg.isEmpty {
                        Text(errorMsg)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button("Execute Tag Push") {
                        Task {
                            isLoading = true
                            successMsg = ""
                            errorMsg = ""
                            do {
                                var args = ["push", "origin"]
                                if includeTags {
                                    args.append("--tags")
                                }
                                try await GitMenuBarCommandExecutor.runGit(args: args)
                                successMsg = "Tags push completed successfully."
                            } catch {
                                errorMsg = "Failed: \(error.localizedDescription)"
                            }
                            isLoading = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isLoading)
                }
            } else {
                NoActiveProjectView(title: "Include Tags")
            }
        }
        .padding()
        .frame(width: 280)
    }
}
