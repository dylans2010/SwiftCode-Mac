import SwiftUI

struct ConcurrencyItem: Identifiable {
    let id = UUID()
    let concept: String
    let code: String
    let summary: String
}

public struct SwiftConcurrencyCheatsheetView: View {
    private let concepts = [
        ConcurrencyItem(
            concept: "Actors & Thread Safety",
            code: "actor CacheManager {\n    private var cache: [String: Data] = [:]\n    func get(_ key: String) -> Data? { cache[key] }\n    func set(_ key: String, val: Data) { cache[key] = val }\n}",
            summary: "Actors ensure mutable state isolation, preventing simultaneous data access and compiler-enforced race conditions."
        ),
        ConcurrencyItem(
            concept: "Structured Task Groups",
            code: "try await withThrowingTaskGroup(of: Data.self) { group in\n    for url in urls {\n        group.addTask { try await fetchData(from: url) }\n    }\n    for try await data in group {\n        process(data)\n    }\n}",
            summary: "Task groups coordinate multiple concurrent child tasks, supporting parent-child propagation of cancellation signals."
        ),
        ConcurrencyItem(
            concept: "Async Let bindings",
            code: "async let userDetails = fetchUser()\nasync let imageDetails = fetchImage()\nlet profile = try await Profile(user: userDetails, img: imageDetails)",
            summary: "Concurrent sibling operations. Spawns tasks immediately and blocks only when resolving the values using try await."
        )
    ]

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Swift Structured Concurrency")
                        .font(.title.bold())
                    Text("A cheat sheet for high-performance, race-free modern Swift async-await concurrency patterns.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                ForEach(concepts) { item in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(item.concept)
                                .font(.headline)
                                .foregroundColor(.purple)

                            Text(item.summary)
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text(item.code)
                                .font(.system(.body, design: .monospaced))
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.25))
                                .cornerRadius(8)
                        }
                        .padding(10)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}
