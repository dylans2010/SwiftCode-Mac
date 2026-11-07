import Foundation

public struct ExtV2SamplePlugin: ExtV2NativePlugin {
    public static let manifest = ExtV2NativePluginManifest(
        id: "sample.workspace-lister",
        name: "Workspace Lister (Sample)",
        version: "1.0.0",
        description: "Sample SwiftCode-native plugin: lists files in the current workspace.",
        commands: [ExtV2ContributionCommand(command: "extv2.sample.listWorkspace", title: "Sample: List Workspace Files")],
        capabilities: [.workspaceRead]
    )

    public init() {}

    public func activate(context: ExtV2NativePluginContext) async throws {
        context.registerCommand("extv2.sample.listWorkspace") { _ in
            guard let workspace = context.workspace else {
                return .string("No workspace is open.")
            }
            let files = try workspace.listFiles(extensionId: Self.manifest.id)
            let names = files.map(\.relativePath).sorted().prefix(50).joined(separator: "\n")
            return .string(names.isEmpty ? "Workspace is empty." : names)
        }
    }
}
