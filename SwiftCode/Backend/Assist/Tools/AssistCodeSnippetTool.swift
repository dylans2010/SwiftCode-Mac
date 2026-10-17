import Foundation

public struct AssistCodeSnippetTool: AssistTool {
    public let id = "code_snippet_manager"
    public let name = "Code Snippet & Architecture Template Manager"
    public let description = "Retrieves and injects battle-tested Swift architecture templates (SwiftUI MVVM, AsyncStream, Actor isolation, Keychain wrapper)."

    public init() {}

    public var capability: ToolCapability { .general }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Retrieve standardized Swift 6 templates and architecture patterns.",
            properties: [
                "templateId": JSONSchema(type: "string", description: "Template identifier: 'observable_viewmodel', 'async_stream', 'keychain_helper', 'swiftui_glass_card', 'actor_service'."),
                "targetName": JSONSchema(type: "string", description: "Name of the type or feature to substitute in the template.")
            ],
            required: ["templateId"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let templateId = input["templateId"] as? String else {
            return .failure("Missing required parameter: templateId")
        }

        let name = (input["targetName"] as? String) ?? "Feature"

        switch templateId.lowercased() {
        case "observable_viewmodel":
            let snippet = """
            import SwiftUI
            import Observation

            @Observable
            @MainActor
            public final class \(name)ViewModel {
                public var items: [String] = []
                public var isLoading: Bool = false
                public var errorMessage: String? = nil

                public init() {}

                public func loadData() async {
                    isLoading = true
                    defer { isLoading = false }
                    do {
                        // Implement async data fetch
                        try await Task.sleep(nanoseconds: 500_000_000)
                        self.items = ["Sample 1", "Sample 2"]
                    } catch {
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
            """
            return .success("Swift 6 @Observable ViewModel Template:\n\n```swift\n\(snippet)\n```")

        case "async_stream":
            let snippet = """
            import Foundation

            public func make\(name)Stream() -> AsyncStream<String> {
                AsyncStream { continuation in
                    Task {
                        // Produce stream items
                        continuation.yield("Connected")
                        continuation.finish()
                    }
                }
            }
            """
            return .success("AsyncStream Template:\n\n```swift\n\(snippet)\n```")

        case "actor_service":
            let snippet = """
            import Foundation

            public actor \(name)Service {
                private var cache: [String: Data] = [:]

                public init() {}

                public func store(data: Data, for key: String) {
                    cache[key] = data
                }

                public func retrieve(for key: String) -> Data? {
                    return cache[key]
                }

                public func clear() {
                    cache.removeAll()
                }
            }
            """
            return .success("Thread-Safe Actor Service Template:\n\n```swift\n\(snippet)\n```")

        case "swiftui_glass_card":
            let snippet = """
            import SwiftUI

            public struct \(name)CardView: View {
                public var body: some View {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(name)")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text("Glassmorphic native component layout.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                }
            }
            """
            return .success("SwiftUI Glassmorphic Card Template:\n\n```swift\n\(snippet)\n```")

        default:
            return .failure("Unknown templateId '\(templateId)'. Available: observable_viewmodel, async_stream, actor_service, swiftui_glass_card")
        }
    }
}
