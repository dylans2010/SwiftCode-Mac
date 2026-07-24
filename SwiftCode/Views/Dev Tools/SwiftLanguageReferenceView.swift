import SwiftUI

struct LanguageFeature: Identifiable {
    let id = UUID()
    let title: String
    let code: String
    let detail: String
}

public struct SwiftLanguageReferenceView: View {
    private let features = [
        LanguageFeature(
            title: "Control Flow & Pattern Matching",
            code: "switch value {\ncase .success(let model) where model.isValid:\n    print(\"Valid: \\(model)\")\ncase .failure(let err):\n    print(\"Failed: \\(err)\")\ndefault:\n    break\n}",
            detail: "Use value binding patterns inside switch statements to cleanly extract associative enum values on compile-time conditions."
        ),
        LanguageFeature(
            title: "Escaping Closures",
            code: "func executeQuery(completion: @escaping (Result<Data, Error>) -> Void) {\n    Task {\n        let res = await fetch()\n        completion(res)\n    }\n}",
            detail: "The @escaping keyword indicates that a closures parameter can escape the lifespan of the host function (e.g., executing asynchronously)."
        ),
        LanguageFeature(
            title: "Generics Constraints",
            code: "func parse<T: Codable & Identifiable>(item: T) -> [String: Any] {\n    let encoded = try? JSONEncoder().encode(item)\n    return (try? JSONSerialization.jsonObject(with: encoded ?? Data())) as? [String: Any] ?? [:]\n}",
            detail: "Define generic parameters with protocol composition constraints to safely accept types carrying native decodable and serializable properties."
        )
    ]

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Swift Language Reference Guide")
                        .font(.title.bold())
                    Text("Interactive, quick-reference guide for complex modern Swift language syntax features.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                ForEach(features) { item in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(item.title)
                                .font(.headline)
                                .foregroundColor(.orange)

                            Text(item.detail)
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
