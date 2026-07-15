import SwiftUI

@MainActor
struct HomeProjectCardView: View {
    let project: Project
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                    Image(systemName: "swift")
                        .font(.title2)
                        .foregroundStyle(.orange)
                }
                .frame(width: 44, height: 44)

                Spacer()

                if isHovered {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.body)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                    .help("Delete Project")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Text(project.description.isEmpty ? "No description" : project.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            HStack {
                Label {
                    Text(project.lastOpened, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if project.githubRepo != nil {
                    Image(systemName: "network")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding()
        .frame(width: 180, height: 150)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(isHovered ? 0.4 : 0.1), lineWidth: 1)
        )
        .onHover { isHovered = $0 }
        .onTapGesture {
            onSelect()
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.3), value: isHovered)
    }
}
