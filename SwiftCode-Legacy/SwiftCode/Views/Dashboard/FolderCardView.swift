import SwiftUI

struct FolderCardView: View {
    let folder: ProjectFolder
    @EnvironmentObject private var folderManager: FolderManager
    @Environment(ProjectSessionStore.self) private var sessionStore
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
        .liquidGlass(style: .standard, cornerRadius: 12)
        .onHover { isHovered = $0 }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.3), value: isHovered)
    }
}
