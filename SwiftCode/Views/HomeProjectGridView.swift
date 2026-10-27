import SwiftUI

struct HomeProjectGridView: View {
    let projects: [ProjectRegistryEntry]
    let onSelect: (ProjectRegistryEntry) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 20) {
                ForEach(projects) { project in
                    Button {
                        onSelect(project)
                    } label: {
                        LiquidGlassCard(cornerRadius: 12, style: .standard) {
                            VStack(spacing: 8) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 38))
                                    .foregroundStyle(Color.accentColor)
                                Text(project.name)
                                    .font(.headline)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
