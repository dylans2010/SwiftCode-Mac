import Foundation

// MARK: - Sample native plugin (compiles and runs)
//
// Register it from the app's startup path (or from ExtensionsHomeView's
// "Native Extensions" section via ExtV2Manager.registerSamplePlugin):
//   ExtV2NativePluginRegistry.shared.register(ExtV2SamplePlugin.self)
// It declares exactly the capabilities it uses (workspace reads) and
// registers one command that lists workspace files — a complete,
// minimal example of the SDK's lifecycle, manifest, and permission model.

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
        // The command handler is a closure over the context, so it can
        // only do what the context (and its permission checks) allow.
        context.registerCommand("extv2.sample.listWorkspace") { _ in
            guard let workspace = context.workspace else {
                return .string("No workspace is open.")
            }
            let files = try workspace.listFiles(extensionId: Self.manifest.id)
            let names = files.map(\.relativePath).sorted().prefix(50).joined(separator: "\n")
            return .string(names.isEmpty ? "Workspace is empty." : names)
        }
        // Activation itself does not need workspace access; the check
        // happens when the command actually runs, where it can fail
        // visibly instead of failing activation for a command the user
        // may never invoke.
    }
}
