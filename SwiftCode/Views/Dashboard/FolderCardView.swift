import SwiftUI

struct FolderCardView: View {
    let folder: ProjectFolder
    @EnvironmentObject private var folderManager: FolderManager
    @EnvironmentObject private var projectManager: ProjectManager
    @State private var isHovered = false

    private var projectCount: Int {
        folder.projectIdentifiers.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: folder.iconSymbol)
                    .font(.title2)
                    .foregroundStyle(Color(hex: folder.colorHex))

                Spacer()

                Text("\(projectCount)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: folder.colorHex).opacity(0.2))
                    .foregroundStyle(Color(hex: folder.colorHex))
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(folder.folderName)
                    .font(.headline)
                    .lineLimit(1)

                Text("\(projectCount) projects")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 160, height: 120)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(isHovered ? 0.4 : 0.1), lineWidth: 1)
        )
        .onHover { isHovered = $0 }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.3), value: isHovered)
    }
}
