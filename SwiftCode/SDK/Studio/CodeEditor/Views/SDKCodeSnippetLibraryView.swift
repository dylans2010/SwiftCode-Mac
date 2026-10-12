import AppKit
import SwiftUI

// MARK: - SDKSnippet
//
// One entry in the SDK snippet library. Decoded from the bundled
// `snippets.json` resource against the documented shape
// `{id, title, description, capabilityId, tags}` — decoding is tolerant
// (missing keys fall back to sane defaults) so a partially-populated file
// still loads instead of failing wholesale.
//
// INTEGRATION: a sibling task emits `snippets.json` from the TypeScript
// package. Until that file is present in the SDK bundle resources, the
// library honestly reports its absence (see `SDKSnippetLoadOutcome.absent`)
// rather than fabricating entries.

public struct SDKSnippet: Identifiable, Sendable, Hashable, Codable {
    public let id: String
    public let title: String
    public let description: String
    public let capabilityId: String?
    public let tags: [String]

    public init(
        id: String,
        title: String,
        description: String = "",
        capabilityId: String? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.capabilityId = capabilityId
        self.tags = tags
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, description, capabilityId, tags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled Snippet"
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        capabilityId = try container.decodeIfPresent(String.self, forKey: .capabilityId)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}

// MARK: - SDKSnippetLoadOutcome
//
// Honest load result: `.absent` and `.unreadable` are first-class outcomes
// with their own empty states in the library view — a missing or corrupt
// `snippets.json` is reported, never papered over.

public enum SDKSnippetLoadOutcome: Sendable {
    /// No `snippets.json` resource in the SDK bundle.
    case absent
    /// The file exists but could not be decoded; carries the reason.
    case unreadable(reason: String)
    /// Decoded snippets (possibly empty).
    case loaded([SDKSnippet])
}

// MARK: - SDKSnippetStore
//
// Reads `snippets.json` from the SDK bundle resources. Pure and
// synchronous — the file is small and read once per presentation.

public enum SDKSnippetStore {
    /// `snippets.json` must be registered as a resource of the app target
    /// for this to resolve (a packaging step, not code).
    public static func bundledSnippetsURL() -> URL? {
        if let url = Bundle.main.url(forResource: "snippets", withExtension: "json") {
            return url
        }
        return Bundle(for: SDKSnippetBundleAnchor.self)
            .url(forResource: "snippets", withExtension: "json")
    }

    public static func load() -> SDKSnippetLoadOutcome {
        guard let url = bundledSnippetsURL() else {
            return .absent
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            if let snippets = try? decoder.decode([SDKSnippet].self, from: data) {
                return .loaded(snippets)
            }
            // Tolerate a wrapped top-level object: { "snippets": [...] }.
            struct Wrapped: Decodable { let snippets: [SDKSnippet] }
            let wrapped = try decoder.decode(Wrapped.self, from: data)
            return .loaded(wrapped.snippets)
        } catch {
            return .unreadable(reason: error.localizedDescription)
        }
    }

    /// Anchor class so `Bundle(for:)` can locate the SDK's bundle without
    /// hardcoding a bundle identifier.
    private final class SDKSnippetBundleAnchor: NSObject {}
}

// MARK: - SDKCodeSnippetLibraryView
//
// The snippet browser, presented from the editor shell's "Snippets"
// toolbar button. Searchable list over the decoded `snippets.json`;
// each row's Copy button places a text summary on the pasteboard (real
// action). Absent/unreadable/empty files each get an honest empty state.

@MainActor
public struct SDKCodeSnippetLibraryView: View {
    @EnvironmentObject private var editorState: SDKCodeEditorState

    @State private var outcome: SDKSnippetLoadOutcome?
    @State private var query = ""

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search snippets", text: $query)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(8)
            Divider()
            libraryBody
        }
        .navigationTitle("Snippets")
        .task {
            outcome = SDKSnippetStore.load()
        }
    }

    @ViewBuilder
    private var libraryBody: some View {
        switch outcome {
        case .none:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .absent:
            ContentUnavailableView(
                "No Snippets",
                systemImage: "text.quote",
                description: Text(
                    "The SDK bundle does not contain a snippets.json resource yet. " +
                    "The TypeScript package emits this file (sibling task); until it lands, " +
                    "this library is empty."
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unreadable(let reason):
            ContentUnavailableView(
                "Snippets Unreadable",
                systemImage: "exclamationmark.triangle",
                description: Text("snippets.json could not be decoded: \(reason)")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let snippets):
            if snippets.isEmpty {
                ContentUnavailableView(
                    "No Snippets",
                    systemImage: "text.quote",
                    description: Text("snippets.json is present but contains no snippets.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                snippetList(snippets)
            }
        }
    }

    private func snippetList(_ snippets: [SDKSnippet]) -> some View {
        let filtered = filteredSnippets(snippets)
        return Group {
            if filtered.isEmpty {
                ContentUnavailableView(
                    "No Matches",
                    systemImage: "magnifyingglass",
                    description: Text("No snippets match \"\(query)\".")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { snippet in
                    snippetRow(snippet)
                }
                .listStyle(.plain)
            }
        }
    }

    private func snippetRow(_ snippet: SDKSnippet) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snippet.title)
                    .font(.headline)
                if !snippet.description.isEmpty {
                    Text(snippet.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    if let capabilityId = snippet.capabilityId {
                        Label(capabilityId, systemImage: "key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(snippet.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(Capsule())
                    }
                }
            }
            Spacer()
            Button("Copy") {
                copySummary(of: snippet)
            }
            .help("Copy snippet summary to the pasteboard")
        }
        .padding(.vertical, 4)
    }

    private func filteredSnippets(_ snippets: [SDKSnippet]) -> [SDKSnippet] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return snippets }
        let needle = trimmed.localizedLowercase
        return snippets.filter { snippet in
            snippet.title.localizedLowercase.contains(needle)
                || snippet.description.localizedLowercase.contains(needle)
                || snippet.tags.contains(where: { $0.localizedLowercase.contains(needle) })
                || (snippet.capabilityId?.localizedLowercase.contains(needle) ?? false)
        }
    }

    /// Copies a plain-text summary of the snippet. The documented snippet
    /// shape carries metadata (no code payload), so the summary — not a
    /// fabricated code block — is what gets copied.
    private func copySummary(of snippet: SDKSnippet) {
        var lines = ["Snippet: \(snippet.title)"]
        if !snippet.description.isEmpty {
            lines.append(snippet.description)
        }
        if let capabilityId = snippet.capabilityId {
            lines.append("Capability: \(capabilityId)")
        }
        if !snippet.tags.isEmpty {
            lines.append("Tags: \(snippet.tags.joined(separator: ", "))")
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
        editorState.appendConsole(.system("Copied snippet summary: \(snippet.title)"))
    }
}
