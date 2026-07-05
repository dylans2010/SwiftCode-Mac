import SwiftUI

struct GistRowView: View {
    let gist: GistResponse
    var isStarred: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(gist.description ?? gist.files.keys.first ?? "Untitled Gist")
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.white)

                Spacer()

                if isStarred {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }

                if !gist.public {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                if let language = primaryLanguage {
                    Text(language)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(languageColor.opacity(0.2))
                        .foregroundStyle(languageColor)
                        .clipShape(Capsule())
                }

                Text(gist.public ? "Public" : "Secret")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(gist.updatedAt, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var primaryLanguage: String? {
        gist.files.values.first?.language
    }

    private var languageColor: Color {
        guard let lang = primaryLanguage?.lowercased() else { return .gray }
        switch lang {
        case "swift": return .orange
        case "javascript", "js": return .yellow
        case "python": return .blue
        case "html": return .red
        case "css": return .indigo
        case "json": return .yellow
        case "markdown": return .green
        default: return .gray
        }
    }
}
