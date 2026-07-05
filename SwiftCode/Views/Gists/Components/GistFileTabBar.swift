import SwiftUI

struct GistFileTabBar: View {
    let files: [GistFile]
    @Binding var selectedFileID: UUID?
    var isEditing: Bool
    var onRemoveFile: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(files) { file in
                    Button {
                        selectedFileID = file.id
                    } label: {
                        HStack(spacing: 6) {
                            Text(file.filename.isEmpty ? "Untitled" : file.filename)
                                .font(.system(size: 13, weight: selectedFileID == file.id ? .semibold : .regular))
                                .foregroundStyle(selectedFileID == file.id ? .white : .secondary)

                            if isEditing && files.count > 1 {
                                Button {
                                    onRemoveFile(file.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary.opacity(0.6))
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedFileID == file.id ? Color.white.opacity(0.1) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedFileID == file.id ? Color.white.opacity(0.1) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(red: 0.10, green: 0.10, blue: 0.13))
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}
